import EventKit
import Foundation
import HebiuKit

/// 定时运行打开了的数据来源，结果写进收件箱（inbox/sources/<名字>.json），由 TodoCoordinator 对账进待办。
/// 失败时什么都不写，已有的待办保持不变
final class SourceScheduler {
    struct Status: Equatable {
        var lastRun: Date?
        var count = 0
        var error: String?
        var running = false
    }

    private let config: Config
    private var timer: DispatchSourceTimer?
    private lazy var eventStore = EKEventStore()     // 打开日历或提醒事项来源时才创建
    private let queue = DispatchQueue(label: "hebiu.sources", qos: .utility)
    private(set) var status: [String: Status] = [:]
    var onStatusChange: (() -> Void)?

    init(config: Config) {
        self.config = config
    }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 10, repeating: 60, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.runDue() }
        t.resume()
        timer = t
    }

    /// 能用的来源：内置的 + ~/.hebiu/sources/ 里的脚本
    func available() -> [(name: String, title: String, detail: String, installed: Bool)] {
        let scripts = ScriptSource.installed()
        var out = SourceCatalog.known.map { e in
            (e.name, e.title, e.detail, e.builtIn || scripts[e.name] != nil)
        }
        for name in scripts.keys.sorted() where SourceCatalog.entry(name) == nil {
            out.append((name, name, "自己写的来源脚本", true))
        }
        return out
    }

    private func runDue() {
        let now = Date()
        for (name, minutes) in config.settings.sources where minutes > 0 {
            let s = status[name] ?? Status()
            guard !s.running else { continue }
            if let last = s.lastRun, now.timeIntervalSince(last) < Double(minutes) * 60 - 5 { continue }
            run(name)
        }
    }

    /// 立刻同步一次（设置页「立即同步」也用这个）
    func run(_ name: String) {
        var s = status[name] ?? Status()
        guard !s.running else { return }
        s.running = true
        status[name] = s
        onStatusChange?()
        let finish: (Result<[SourceItem], Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async { self?.finish(name, result) }
        }
        switch name {
        case "calendar": fetchCalendar(finish)
        case "reminders": fetchReminders(finish)
        default:
            guard let url = ScriptSource.installed()[name] else {
                finish(.failure(SourceError.message("~/.hebiu/sources/ 里没有 \(name) 这个脚本")))
                return
            }
            queue.async { finish(Result { try ScriptSource.run(url, name: name) }) }
        }
    }

    /// 关掉来源时调用：它带进来、还没完成的待办一起清掉（已完成的留着）
    func clear(_ name: String) {
        try? TodoInbox.publish(.init(source: name, items: []))
        status[name] = nil
        onStatusChange?()
    }

    private func finish(_ name: String, _ result: Result<[SourceItem], Error>) {
        var s = status[name] ?? Status()
        s.running = false
        s.lastRun = Date()
        switch result {
        case .success(let items):
            do {
                try TodoInbox.publish(.init(source: name, items: items))
                s.count = items.count
                s.error = nil
            } catch {
                s.error = "写入失败：\(error)"
            }
        case .failure(let error):
            s.error = "\(error)"
            Log.write("source \(name) failed: \(error)")
        }
        status[name] = s
        onStatusChange?()
    }

    // MARK: - Mac 日历

    /// 今天和明天还没结束的会议（全天的不算），开始前 5 分钟提醒
    private func fetchCalendar(_ done: @escaping (Result<[SourceItem], Error>) -> Void) {
        withAccess(to: .event) { [eventStore] granted in
            guard granted else { return done(.failure(SourceError.noAccess("日历"))) }
            let cal = Calendar.current
            let now = Date()
            let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
            let predicate = eventStore.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            let items = eventStore.events(matching: predicate)
                .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
                .map { e -> SourceItem in
                    var note = "\(f.string(from: e.startDate))–\(f.string(from: e.endDate))"
                    if let place = e.location, !place.isEmpty { note += " · \(place)" }
                    return SourceItem(id: "\(e.calendarItemIdentifier)@\(Int(e.startDate.timeIntervalSince1970))",
                                      title: "\(e.title ?? "会议") \(f.string(from: e.startDate)) 开始",
                                      due: e.startDate.addingTimeInterval(-5 * 60), dueHasTime: true,
                                      note: note, link: e.url?.absoluteString)
                }
            done(.success(items))
        }
    }

    // MARK: - Mac 提醒事项

    /// 没完成的提醒：没有日期的、7 天内到期的
    private func fetchReminders(_ done: @escaping (Result<[SourceItem], Error>) -> Void) {
        withAccess(to: .reminder) { [eventStore] granted in
            guard granted else { return done(.failure(SourceError.noAccess("提醒事项"))) }
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            eventStore.fetchReminders(matching: predicate) { reminders in
                let limit = Date().addingTimeInterval(7 * 86400)
                let items = (reminders ?? []).compactMap { r -> SourceItem? in
                    let comps = r.dueDateComponents
                    let due = comps.flatMap { Calendar.current.date(from: $0) }
                    if let due, due > limit { return nil }
                    return SourceItem(id: r.calendarItemIdentifier, title: r.title ?? "提醒", due: due,
                                      dueHasTime: comps?.hour != nil, note: r.notes, link: r.url?.absoluteString)
                }
                done(.success(items))
            }
        }
    }

    /// 没问过就问；问过了直接给结果
    private func withAccess(to type: EKEntityType, _ body: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return body(true) }
            if status != .notDetermined { return body(false) }
            if type == .event {
                eventStore.requestFullAccessToEvents { granted, _ in body(granted) }
            } else {
                eventStore.requestFullAccessToReminders { granted, _ in body(granted) }
            }
        } else {
            if status == .authorized { return body(true) }
            if status != .notDetermined { return body(false) }
            eventStore.requestAccess(to: type) { granted, _ in body(granted) }
        }
    }
}

enum SourceError: Error, CustomStringConvertible {
    case noAccess(String)
    case message(String)

    var description: String {
        switch self {
        case .noAccess(let what): return "没有\(what)权限：系统设置 → 隐私与安全性 → \(what)，打开 Hebiu"
        case .message(let m): return m
        }
    }
}
