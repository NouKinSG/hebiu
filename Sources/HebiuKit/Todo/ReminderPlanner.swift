import Foundation

/// 该不该提醒、提醒什么：纯规则，不碰界面，方便测试
public enum ReminderPlanner {
    /// 到点该喊的：有钟点、时间到了、还没喊过、没完成；过期超过 6 小时的不再补喊（比如电脑合盖一晚上）
    public static func dueNow(_ items: [TodoItem], now: Date) -> [TodoItem] {
        TodoQuery.sorted(items.filter {
            guard !$0.isDone, $0.dueHasTime, $0.remindedAt == nil, let due = $0.due else { return false }
            return due <= now && due > now.addingTimeInterval(-6 * 3600)
        })
    }

    /// 每天第一次在用电脑（6 点以后）时说一次今天要做的；今天没有待办就不说
    /// alsoWhenEmpty：没有待办也说（比如有天气可以讲）
    public static func morningSummary(_ items: [TodoItem], now: Date, state: ReminderState, enabled: Bool,
                                      userActive: Bool, alsoWhenEmpty: Bool = false, calendar cal: Calendar = .current) -> [TodoItem]? {
        guard enabled, userActive, cal.component(.hour, from: now) >= 6,
              state.morningDay != ReminderState.day(now, cal) else { return nil }
        let today = TodoQuery.sections(items, now: now, calendar: cal).today
        return today.isEmpty && !alsoWhenEmpty ? nil : today
    }

    /// 到了设定时间（比如 18:00）还有今天的没做完，提醒一次
    public static func eveningReminder(_ items: [TodoItem], now: Date, state: ReminderState, at time: DateComponents?,
                                       userActive: Bool, calendar cal: Calendar = .current) -> [TodoItem]? {
        guard let time, userActive, state.eveningDay != ReminderState.day(now, cal),
              let start = cal.date(bySettingHour: time.hour ?? 18, minute: time.minute ?? 0, second: 0, of: now),
              now >= start else { return nil }
        let today = TodoQuery.sections(items, now: now, calendar: cal).today
        return today.isEmpty ? nil : today
    }

    // MARK: - 说什么

    public static func dueLine(_ due: [TodoItem]) -> String {
        guard let first = due.first else { return "" }
        let time = first.due.map { TodoFormat.describe($0, hasTime: true).components(separatedBy: " ").last ?? "" } ?? ""
        let more = due.count > 1 ? "还有 \(due.count - 1) 件也到点了" : ""
        return "⏰ \(time) \(first.title)，到点啦！\(more)"
    }

    public static func morningLine(_ today: [TodoItem], now: Date) -> String {
        let overdue = today.filter { TodoQuery.isOverdue($0, now: now) }.count
        let names = titles(today)
        let tail = overdue > 0 ? "（有 \(overdue) 件已经过期了哦）" : ""
        return "早呀～今天有 \(today.count) 件事：\(names)\(tail)"
    }

    public static func eveningLine(_ left: [TodoItem]) -> String {
        "快下班啦，还有 \(left.count) 件没做：\(titles(left))"
    }

    /// 最多列 3 个标题，多的说「等」
    static func titles(_ items: [TodoItem]) -> String {
        let names = items.prefix(3).map(\.title).joined(separator: "、")
        return items.count > 3 ? names + " 等" : names
    }
}

/// 今天早上、下班提醒说过没有；存在 ~/.hebiu/state.json，重启程序也不会重复说
public struct ReminderState: Codable, Equatable {
    public var morningDay: String?
    public var eveningDay: String?

    public init(morningDay: String? = nil, eveningDay: String? = nil) {
        self.morningDay = morningDay
        self.eveningDay = eveningDay
    }

    public static func day(_ date: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func load(url: URL = Paths.state) -> ReminderState {
        guard let data = try? Data(contentsOf: url) else { return ReminderState() }
        return (try? JSONDecoder().decode(ReminderState.self, from: data)) ?? ReminderState()
    }

    public func save(url: URL = Paths.state) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
