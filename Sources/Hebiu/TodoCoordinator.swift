import AppKit
import CoreGraphics
import HebiuKit

/// 桌宠这边的待办总管：持有存储和收件箱，监听文件变化，把结果告诉桌宠（说句话、做个动作）
final class TodoCoordinator {
    let store: TodoStore
    private let inbox: TodoInbox
    private var inboxWatchers: [DirectoryWatcher] = []
    private var fileWatcher: FileWatcher?
    private var timer: DispatchSourceTimer?
    private var pendingProcess = false

    /// 桌宠要说的话、要做的动作；sticky：台词一直挂着直到点她
    var react: ((_ event: String, _ line: String?, _ sticky: Bool) -> Void)?
    var isQuiet: () -> Bool = { false }
    var config: Config?
    let notifier = Notifier()
    private var reminderTimer: DispatchSourceTimer?
    private var state = ReminderState.load()
    /// 列表变了（窗口刷新、菜单计数）
    var onChange: (() -> Void)?
    /// 命令行 hebiu say 的话交给 AI 大脑
    var onSay: ((String) -> Void)?
    var onNote: ((String) -> Void)?
    /// 早报里加的一句（天气提醒）；nil 就不加
    var morningExtra: (() -> String?)?
    /// AI 结合今天的事说一句（打开 AI 大脑时），nil 时用固定台词
    var compose: ((_ task: String, _ completion: @escaping (String?) -> Void) -> Void)?

    init() {
        store = TodoStore()
        inbox = TodoInbox(store: store)
        store.onChange = { [weak self] in self?.onChange?() }
    }

    func start() {
        store.ensureFile()
        store.purgeOldDone()
        processInbox()
        inboxWatchers = [Paths.inbox, Paths.inbox.appendingPathComponent("sources")].map {
            DirectoryWatcher(url: $0) { [weak self] in self?.scheduleProcess() }
        }
        fileWatcher = FileWatcher(url: Paths.todo) { [weak self] in self?.store.reloadIfChangedOnDisk() }
        // 兜底：每分钟扫一次收件箱，顺便清理过期的已完成
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            self?.processInbox()
            self?.store.purgeOldDone()
        }
        t.resume()
        timer = t

        // 提醒：每 20 秒看一次，到点误差不超过半分钟
        let r = DispatchSource.makeTimerSource(queue: .main)
        r.schedule(deadline: .now() + 3, repeating: 20, leeway: .seconds(2))
        r.setEventHandler { [weak self] in self?.checkReminders() }
        r.resume()
        reminderTimer = r
    }

    // MARK: - 提醒

    /// 最近 2 分钟动过键盘鼠标，算「在用电脑」
    private var userActive: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) < 120
    }

    func checkReminders(now: Date = Date()) {
        let settings = config?.settings ?? Config.Settings()
        let items = store.items

        let due = ReminderPlanner.dueNow(items, now: now)
        if !due.isEmpty {
            store.markReminded(due.map(\.id), at: now)
            let line = ReminderPlanner.dueLine(due)
            Log.write("todo due: \(due.map(\.id))")
            react?("remind", line, true)
            if settings.notify {
                notifier.post(title: "⏰ \(due[0].title)", body: due.count > 1 ? "还有 \(due.count - 1) 件也到点了" : "到点啦，点开看看待办")
            }
            return                      // 一次只说一件事
        }
        guard !isQuiet() else { return }

        let active = userActive
        let extra = morningExtra?()
        if let today = ReminderPlanner.morningSummary(items, now: now, state: state, enabled: settings.morningSummary, userActive: active,
                                                      alsoWhenEmpty: extra != nil) {
            state.morningDay = ReminderState.day(now)
            state.save()
            Log.write("todo morning summary: \(today.count)")
            let fallback = today.isEmpty ? "早上好～" + (extra ?? "") : ReminderPlanner.morningLine(today, now: now) + (extra.map { "，" + $0 } ?? "")
            if let compose {
                compose("早上\(Config.he)第一次打开电脑。打个招呼当早报：有天气就提一句（要带伞、多穿就提醒），看看今天的待办告诉\(Config.he)先做哪件，快到的重要日子和今天的习惯顺口提一下。两三句话，不要列清单。") { [weak self] text in
                    self?.react?("hello", text ?? fallback, false)
                }
            } else {
                react?("hello", fallback, false)
            }
            return
        }
        if let left = ReminderPlanner.eveningReminder(items, now: now, state: state, at: settings.eveningReminder, userActive: active) {
            state.eveningDay = ReminderState.day(now)
            state.save()
            Log.write("todo evening reminder: \(left.count)")
            let fallback = ReminderPlanner.eveningLine(left)
            if let compose {
                compose("快下班了，\(Config.he)今天还有 \(left.count) 件待办没做完。提醒\(Config.he)，语气别凶，可以撒娇。") { [weak self] text in
                    self?.react?("pout", text ?? fallback, false)
                }
            } else {
                react?("pout", fallback, false)
            }
        }
    }

    /// 文件刚放进来时可能一次来好几个事件，合并成一次处理
    private func scheduleProcess() {
        guard !pendingProcess else { return }
        pendingProcess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.pendingProcess = false
            self?.processInbox()
        }
    }

    private func processInbox() {
        for outcome in inbox.process() {
            switch outcome {
            case .added(let item):
                Log.write("todo added via inbox: \(item.id)")
                react?("pat", "记下啦：\(item.title)", false)
            case .completed(let item):
                Log.write("todo done via inbox: \(item.id)")
                celebrate(item)
            case .reopened(let item):
                Log.write("todo reopened via inbox: \(item.id)")
            case .deleted(let title):
                Log.write("todo deleted via inbox: \(title)")
            case let .synced(source, added, updated, removed):
                Log.write("todo synced \(source): +\(added) ~\(updated) -\(removed)")
                if added > 0 { react?("think", "\(TodoSource.displayName(source))来了 \(added) 件新待办", false) }
            case .say(let text):
                onSay?(text)
            case .note(let text):
                onNote?(text)
            case .failed(let reason):
                Log.write("todo inbox failed: \(reason)")
            }
        }
    }

    // MARK: - 窗口里的操作

    func add(text: String) {
        guard let item = store.add(text: text) else { return }
        Log.write("todo added: \(item.id)")
    }

    func toggle(_ id: String) {
        guard let item = store.item(id) else { return }
        if item.isDone {
            store.uncomplete(id)
        } else {
            store.complete(id)
            celebrate(item)
        }
    }

    private func celebrate(_ item: TodoItem) {
        let left = store.items.filter { !$0.isDone }.count
        react?("done", left == 0 ? "全部搞定啦！奖励一杯奶茶" : "又搞定一件！还剩 \(left) 件", false)
    }
}
