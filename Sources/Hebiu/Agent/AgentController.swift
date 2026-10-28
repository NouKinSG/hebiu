import AppKit
import HebiuKit

/// 桌宠这边的 AI 大脑：持有会话，给浮窗和聊天页提供状态，回答时让她做表情、说话
final class AgentController: ObservableObject {
    @Published private(set) var lines: [AgentChatLog.Line] = []
    @Published private(set) var thinking = false
    /// 最近一句的回答和改动（浮窗显示、撤销用）
    @Published private(set) var lastReply: AgentSession.Reply?
    @Published private(set) var undone: Set<Int> = []
    /// 她提出的删除：你点了删除为 true，点了算了为 false
    @Published private(set) var deleteDecisions: [String: Bool] = [:]
    @Published var draft = ""
    @Published private(set) var monthSpent: Decimal = 0
    @Published private(set) var week: [AgentLedger.DaySpend] = []
    @Published private(set) var balance: String?
    @Published private(set) var keyMasked = AgentSecrets.masked(nil)
    @Published private(set) var linesDay: String?
    @Published private(set) var writingLines = false
    private let linesStore = AgentLinesStore()
    private var linesTimer: Timer?
    /// 她的记忆（「她记得的事」页显示）
    let memory = AgentMemory()
    @Published private(set) var facts: [String] = []
    @Published private(set) var diaries: [AgentMemory.Entry] = []
    @Published private(set) var summaries: [AgentMemory.Entry] = []
    @Published private(set) var consolidating = false
    @Published private(set) var memoryMessage: String?

    private let config: Config
    private let chatLog = AgentChatLog()
    private let ledger = AgentLedger()
    private lazy var session = AgentSession(store: store, ledger: ledger, chatLog: chatLog,
                                            budget: { [config] in config.settings.agentBudget },
                                            memory: memory,
                                            memoryEnabled: { [config] in config.settings.agentMemory },
                                            activityEnabled: { [config] in config.settings.agentActivity },
                                            dates: dates, extraDates: { [config] in ImportantDate.builtIns(config.settings) },
                                            habits: habits, notes: notes, moods: moods,
                                            weather: { [weak self] in self?.weatherText() }, tasks: tasks)
    private let store: TodoStore
    /// 让她做动作、说话
    var react: ((_ event: String, _ line: String?) -> Void)?
    var onChange: (() -> Void)?
    /// 今天的天气（AppDelegate 提供）
    var weatherText: () -> String? = { nil }
    /// 说话输入：边说边填进输入框，停顿后自动发送
    lazy var voice: VoiceInput = {
        let v = VoiceInput()
        v.onText = { [weak self] text in self?.draft = text }
        v.onFinish = { [weak self] text in
            self?.draft = text
            self?.send()
        }
        return v
    }()
    /// 跟她说了一句（小统计用）
    var onSent: (() -> Void)?

    private let dates: ImportantDateStore
    private let habits: HabitStore
    private let notes: NoteStore
    private let moods: MoodStore
    /// 定时让她做的事
    let tasks = ScheduledTaskStore()

    init(config: Config, store: TodoStore, dates: ImportantDateStore, habits: HabitStore, notes: NoteStore, moods: MoodStore) {
        self.moods = moods
        self.notes = notes
        self.config = config
        self.store = store
        self.dates = dates
        self.habits = habits
        reload()
        applyLines()
        // 每小时看一次：今天还没写过台词就写一批；昨天的日记没写就补上（都是一天一次）
        linesTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.writeLinesIfNeeded()
            self?.consolidateIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.writeLinesIfNeeded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.consolidateIfNeeded() }
    }

    // MARK: - 记忆

    var memoryOn: Bool { enabled && config.settings.agentMemory }

    func reloadMemory() {
        facts = memory.facts()
        diaries = memory.entries(.diary)
        summaries = memory.entries(.monthly) + memory.entries(.weekly)
    }

    /// 补写没写的日记、该压的周记月记；没有要做的就不请求
    func consolidateIfNeeded() {
        guard memoryOn, !consolidating else { return }
        consolidating = true
        memoryMessage = nil
        Task {
            let result = await session.consolidate()
            await MainActor.run {
                self.consolidating = false
                self.memoryMessage = result.failed ? "这次没整理完（网络或额度），过一会儿会再试"
                    : result.wroteSomething ? "整理好了：" + ([result.diaries.isEmpty ? nil : "\(result.diaries.count) 篇日记",
                                                          result.weekly.map { _ in "1 篇周记" },
                                                          result.monthly.map { _ in "1 篇月记" }].compactMap { $0 }.joined(separator: "、"))
                    : "都整理过了"
                if result.wroteSomething { Log.write("memory consolidated: \(result.diaries) \(result.weekly ?? "") \(result.monthly ?? "")") }
                self.reloadMemory()
                self.reload()
            }
        }
    }

    func writeTodayDiary() {
        guard memoryOn, !consolidating else { return }
        consolidating = true
        memoryMessage = nil
        Task {
            let ok = await session.writeTodayDiary()
            await MainActor.run {
                self.consolidating = false
                self.memoryMessage = ok == nil ? "今天还没聊什么，晚点再写吧" : ok! ? "今天的日记写好了，明天\(Her.she)会按一整天重写一遍" : "没写成（网络或额度），等会儿再试"
                self.reloadMemory()
                self.reload()
            }
        }
    }

    func writeWeekReview(_ review: WeekReview, completion: @escaping (String?) -> Void) {
        guard enabled else { completion(nil); return }
        Task {
            let text = await session.writeWeekReview(review)
            await MainActor.run {
                self.reload()
                completion(text)
            }
        }
    }

    /// 定时任务到点了：她去做，结果交给 completion（失败为 nil）
    func runTask(_ task: ScheduledTask, completion: @escaping (String?) -> Void) {
        guard enabled else { completion(nil); return }
        Task {
            let text = await session.compose("这是\(Config.he)设好的定时任务，现在到点了：\(task.prompt)。结合现在的情况去做，直接说结果。", maxChars: 150)
            await MainActor.run {
                self.reload()
                completion(text)
            }
        }
    }

    func addFact(_ text: String) {
        memory.remember(text)
        reloadMemory()
    }

    func updateFact(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        var all = memory.facts()
        guard let i = all.firstIndex(of: old) else { return }
        if trimmed.isEmpty { all.remove(at: i) } else { all[i] = trimmed }
        memory.saveFacts(all)
        reloadMemory()
    }

    func forgetFact(_ fact: String) {
        memory.forget(fact)
        reloadMemory()
    }

    func deleteEntry(_ entry: AgentMemory.Entry) {
        memory.delete(entry.kind, entry.key)
        reloadMemory()
    }

    // MARK: - 主动说话、AI 写台词

    var proactive: Bool { enabled && config.settings.agentProactive }

    /// 让 AI 结合今天的事说一句；没打开或失败时返回 nil，调用方用固定台词
    func compose(_ task: String, maxChars: Int = 40, completion: @escaping (String?) -> Void) {
        guard proactive else { completion(nil); return }
        Task {
            let text = await session.compose(task, maxChars: maxChars)
            await MainActor.run {
                if text != nil { self.reload() }
                completion(text)
            }
        }
    }

    /// 把已经写好的 AI 台词交给配置；开关关掉时清空
    func applyLines() {
        let body = linesStore.load()
        linesDay = body?.day
        config.setAILines(enabled && config.settings.agentLines ? body?.lines ?? [:] : [:])
    }

    func writeLinesIfNeeded(force: Bool = false) {
        guard enabled, config.settings.agentLines, !writingLines, force || !linesStore.isFresh() else { return }
        writingLines = true
        let events = lineEvents.map { (key: $0.key, when: $0.when) }
        Task {
            let lines = await session.writeLines(for: events)
            await MainActor.run {
                self.writingLines = false
                if let lines {
                    self.linesStore.save(.init(day: ReminderState.day(Date()), lines: lines))
                    Log.write("agent wrote lines for \(lines.count) events")
                }
                self.applyLines()
                self.reload()
            }
        }
    }

    var enabled: Bool { config.settings.agentEnabled }
    var hotkeyText: String { config.settings.agentHotkey }

    func reload() {
        lines = chatLog.all().suffix(200)
        monthSpent = ledger.total(monthOf: Date())
        week = ledger.daily(last: 7)
        DispatchQueue.global().async {
            let masked = AgentSecrets.masked(AgentSecrets.shared.load())
            DispatchQueue.main.async { self.keyMasked = masked }
        }
    }

    /// 命令行或别处直接说一句
    func say(_ text: String) {
        draft = text
        send()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        guard enabled else {
            let message = "AI 大脑还没打开，去「连接 → AI 大脑」里打开吧"
            lastReply = .init(text: message, expression: "pout", changes: [], failure: .noKey)
            chatLog.append(.init(time: Date(), role: "error", content: message))
            reload()
            return
        }
        draft = ""
        onSent?()
        thinking = true
        lastReply = nil
        undone = []
        deleteDecisions = [:]
        react?("think", nil)
        lines.append(.init(time: Date(), role: "user", content: text))
        Task {
            let reply = await session.send(text)
            await MainActor.run {
                self.thinking = false
                self.lastReply = reply
                if reply.failure == .network || reply.failure == .overBudget || reply.failure == .noKey { self.draft = text }
                self.react?(reply.expression ?? "pat", reply.text)
                if reply.changes.contains(where: { if case .remembered = $0 { return true }; return false }) { self.reloadMemory() }
                self.reload()
                self.onChange?()
            }
        }
    }

    func decideDelete(_ pending: AgentTools.PendingDelete, delete: Bool) {
        guard deleteDecisions[pending.id] == nil else { return }
        deleteDecisions[pending.id] = delete
        guard delete else { return }
        Task {
            await session.confirmDelete(pending)
            await MainActor.run {
                self.reload()
                self.onChange?()
            }
        }
    }

    func undo(_ index: Int) {
        guard let change = lastReply?.changes[safe: index], !undone.contains(index) else { return }
        undone.insert(index)
        Task {
            await session.undo(change)
            await MainActor.run {
                self.reloadMemory()
                self.reload()
                self.onChange?()
            }
        }
    }

    // MARK: - 设置页

    func saveKey(_ key: String) -> Bool {
        let ok = AgentSecrets.shared.save(key)
        reload()
        return ok
    }

    func deleteKey() {
        AgentSecrets.shared.delete()
        balance = nil
        reload()
    }

    func refreshBalance() {
        guard let key = AgentSecrets.shared.load() else { balance = nil; return }
        Task {
            let b = await DeepSeekClient().balance(key: key)
            await MainActor.run { self.balance = b }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
