import Foundation

/// 给模型用的工具：查、加、打勾、改时间、做表情；打开记忆时多两个：记下一件事、翻日记。
/// 只认 list_todos 返回过（或这次加的）待办 id；每个改动都能撤销；不提供删除和对外发送
public final class AgentTools {
    /// 一次改动，用来撤销
    public enum Change: Equatable {
        case added(id: String, title: String)
        case modified(before: TodoItem, summary: String)
        case remembered(fact: String)
        case addedDate(id: String, title: String)
        case checkedHabit(id: String, title: String)
        case savedNote(id: String, text: String)
        case loggedMood(day: String, before: Mood?, summary: String)
        case scheduled(id: String, summary: String)
        case addedHabit(id: String, title: String)

        public var summary: String {
            switch self {
            case let .added(_, title): return "加了「\(title)」"
            case let .modified(_, summary): return summary
            case let .remembered(fact): return "记住了：\(fact)"
            case let .addedDate(_, title): return "记下了重要日子「\(title)」"
            case let .checkedHabit(_, title): return "「\(title)」打卡"
            case let .loggedMood(_, _, summary): return summary
            case let .scheduled(_, summary): return summary
            case let .savedNote(_, text): return "记进随手记：\(text.prefix(20))\(text.count > 20 ? "…" : "")"
            case let .addedHabit(_, title): return "加了习惯「\(title)」"
            }
        }
    }

    /// 她提出要删、等你点确认的一条
    public struct PendingDelete: Equatable, Identifiable {
        public let id: String
        public let title: String
    }

    /// AI 回答时能选的表情：启动时换成形象包里的
    public static var expressions = builtinExpressions

    public static let builtinExpressions = ["pat", "tap_bliss", "tap_grin", "tap_nuzzle", "tap_surprised", "tap_blush",
                                     "love", "poke", "pout", "cheer", "sleepy"]

    private let store: TodoStore
    private let now: () -> Date
    /// 是否也能看日历、GitLab 等来源的待办（默认读设置里的开关）
    private let includeSources: () -> Bool
    /// 没打开记忆时为 nil，也就没有 remember / recall
    private let memory: AgentMemory?
    private let dates: ImportantDateStore?
    private let habits: HabitStore?
    private let notes: NoteStore?
    private let moods: MoodStore?
    private let tasks: ScheduledTaskStore?
    /// 这次对话里模型见过的 id
    private var knownIDs: Set<String> = []
    public private(set) var expression: String?
    /// 这次对话里她提出要删的，等你确认
    public private(set) var pendingDeletes: [PendingDelete] = []

    public init(store: TodoStore, now: @escaping () -> Date = Date.init,
                includeSources: @escaping () -> Bool = { AgentPrivacy.shareSourceItems }, memory: AgentMemory? = nil,
                dates: ImportantDateStore? = nil, habits: HabitStore? = nil, notes: NoteStore? = nil,
                moods: MoodStore? = nil, tasks: ScheduledTaskStore? = nil) {
        self.store = store
        self.tasks = tasks
        self.moods = moods
        self.notes = notes
        self.habits = habits
        self.memory = memory
        self.dates = dates
        self.now = now
        self.includeSources = includeSources
    }

    private func visible(_ item: TodoItem) -> Bool {
        AgentPrivacy.isShareable(item, includeSources: includeSources())
    }

    // MARK: - 定义（随请求发给 DeepSeek）

    /// 这次对话能用的工具
    public var definitions: [[String: Any]] {
        AgentTools.definitions + (memory == nil ? [] : AgentTools.memoryDefinitions) + (dates == nil ? [] : AgentTools.dateDefinitions)
            + (habits == nil ? [] : AgentTools.habitDefinitions)
            + (notes == nil ? [] : AgentTools.noteDefinitions)
            + (moods == nil ? [] : AgentTools.moodDefinitions)
            + (tasks == nil ? [] : AgentTools.taskDefinitions)
    }

    public static var taskDefinitions: [[String: Any]] {
        [
            tool("schedule_task", "让你以后定时做一件事（不是提醒\(Config.he)做事，那个用 add_todo）：如“每天早上8点用一句话鼓励我”“每周五下午6点帮我总结这周”。text 用\(Config.he)的原话，要有几点。",
                 ["text": ["type": "string"]], ["text"]),
        ]
    }

    public static var moodDefinitions: [[String: Any]] {
        [
            tool("log_mood", "记下\(Config.he)今天整体的心情。只在\(Config.he)说起今天整体过得怎样时用（“今天超开心”“今天好累好烦”），一时的情绪不用记。score 1 很糟 2 不太好 3 一般 4 不错 5 超开心；note 一句话说为什么。",
                 ["score": ["type": "integer", "minimum": 1, "maximum": 5], "note": ["type": "string"]], ["score"]),
        ]
    }

    public static var noteDefinitions: [[String: Any]] {
        [
            tool("save_note", "把\(Config.he)让你记下的一段话存进随手记（想法、地址、电话、书名、灵感……没有时间的那种；有时间要做的用 add_todo）。text 用\(Config.he)的原话。",
                 ["text": ["type": "string"]], ["text"]),
            tool("search_notes", "在\(Config.he)的随手记里找。query 是几个关键词，空格隔开。",
                 ["query": ["type": "string"]], ["query"]),
        ]
    }

    public static var habitDefinitions: [[String: Any]] {
        [
            tool("check_habit", "给一个习惯打卡（\(Config.he)说喝过水了、跑完步了之类）。name 用习惯的名字。",
                 ["name": ["type": "string"]], ["name"]),
            tool("add_habit", "加一个每天（或每周几）要坚持的习惯。text 如“喝水 每天晚上9点提醒”“健身 每周一三五”。",
                 ["text": ["type": "string"]], ["text"]),
        ]
    }

    public static var dateDefinitions: [[String: Any]] {
        [
            tool("add_date", "记下一个每年都要过的重要日子（生日、纪念日），到之前会提前提醒\(Config.he)。text 写名字加日期，如“妈妈生日 农历八月十五”“第一次约会 2024年5月20日”。",
                 ["text": ["type": "string"]], ["text"]),
        ]
    }

    private static func tool(_ name: String, _ desc: String, _ props: [String: [String: Any]], _ required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": desc,
                      "parameters": ["type": "object", "properties": props, "required": required]]]
    }

    public static var memoryDefinitions: [[String: Any]] {
        [
            tool("remember", "记下一件以后用得上的、关于\(Config.he)的事（喜好、习惯、在意的人和日子、正在忙的事）。一句话，用「\(Config.he)…」开头，不超过 40 个字。不记密码、账号、钱数这类敏感信息。",
                 ["fact": ["type": "string"]], ["fact"]),
            tool("recall", "翻以前的日记、周记、月记。query 用几个关键词，空格隔开（如“面馆 吃饭”），对上越多越靠前；按时间找就写日期（如 2026-09、2026-10-25），不要写“九月初”这种说法。",
                 ["query": ["type": "string"]], ["query"]),
        ]
    }

    public static var definitions: [[String: Any]] {
        [
            tool("list_todos", "查用户的待办。改某条待办之前必须先查，拿到 id。",
                 ["scope": ["type": "string", "enum": ["today", "later", "done"], "description": "today 今天和过期没做的；later 以后的；done 最近完成的"]],
                 ["scope"]),
            tool("add_todo", "给用户加一条待办。text 用用户的原话，保留里面的时间说法（如“明天下午三点”“每周五下午五点”“每天晚上十点”），不要自己换算成日期。说了每天、每周几、每月几号、工作日就是重复待办，打勾后会自动排下一次。",
                 ["text": ["type": "string", "description": "待办原话，含时间"]], ["text"]),
            tool("complete_todo", "把一条待办标成已完成。id 必须来自 list_todos。",
                 ["id": ["type": "string"]], ["id"]),
            tool("reschedule_todo", "改一条待办的时间。id 必须来自 list_todos；when 用中文时间说法，如“今天下午四点”“明天”。",
                 ["id": ["type": "string"], "when": ["type": "string"]], ["id", "when"]),
            tool("delete_todo", "提出删掉一条待办。不会马上删：\(Config.he)会看到一个「删除」按钮，点了才删。只在\(Config.he)明确说不要、删掉、取消这件事时用；做完了用 complete_todo。id 必须来自 list_todos。",
                 ["id": ["type": "string"]], ["id"]),
            tool("show_expression", "回答用户时配一个表情动作，每次回答最多一个。",
                 ["name": ["type": "string", "enum": expressions]], ["name"]),
        ]
    }

    /// 提示词里已经列给模型看的待办，模型可以直接用这些 id
    public func register(_ ids: [String]) {
        knownIDs.formUnion(ids)
    }

    // MARK: - 执行

    /// 执行一次工具调用，返回交回模型的结果（JSON 字符串）和可撤销的改动
    public func execute(name: String, arguments: String) -> (result: String, change: Change?) {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        func str(_ k: String) -> String? {
            (args[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        switch name {
        case "list_todos":
            let scope = str("scope") ?? "today"
            let s = TodoQuery.sections(store.items.filter(visible), now: now())
            let list = scope == "later" ? s.later : scope == "done" ? Array(s.done.prefix(10)) : s.today
            let shared = AgentPrivacy.share(Array(list.prefix(30)), now: now(), includeSources: includeSources())
            knownIDs.formUnion(shared.map(\.id))
            return (json(["scope": scope, "todos": shared.map { ["id": $0.id, "title": $0.title, "due": $0.due as Any, "from": $0.from as Any] }]), nil)

        case "add_todo":
            guard let text = str("text") else { return (error("text 不能为空"), nil) }
            guard let item = store.add(text: text, source: TodoSource.agent, now: now()) else { return (error("没加上"), nil) }
            knownIDs.insert(item.id)
            return (json(describe(item, extra: item.due == nil ? ["note": "没认出时间，加成了没有时间的待办"] : [:])),
                    .added(id: item.id, title: item.title))

        case "complete_todo":
            guard let item = known(str("id")) else { return (error("找不到这条待办，先用 list_todos 查 id"), nil) }
            guard !item.isDone else { return (json(["id": item.id, "title": item.title, "note": "已经是完成的"]), nil) }
            store.complete(item.id, at: now())
            let left = TodoQuery.sections(store.items.filter(visible), now: now()).today.count
            return (json(["id": item.id, "title": item.title, "left_today": left]), .modified(before: item, summary: "完成了「\(item.title)」"))

        case "reschedule_todo":
            guard let item = known(str("id")) else { return (error("找不到这条待办，先用 list_todos 查 id"), nil) }
            guard AgentPrivacy.isOwn(item) else {
                return (error("这条是\(TodoSource.displayName(item.source))同步来的，时间要在\(TodoSource.displayName(item.source))里改"), nil)
            }
            guard let when = str("when"), let parsed = TimeParser.parse(when, now: now()), let due = parsed.due else {
                return (error("没认出时间，请用“明天下午三点”这样的说法"), nil)
            }
            store.update(item.id) {
                $0.due = due
                $0.dueHasTime = parsed.hasTime
            }
            let updated = store.item(item.id) ?? item
            let summary = "「\(item.title)」改到 \(TodoFormat.describe(due, hasTime: parsed.hasTime, now: now()))"
            return (json(describe(updated)), .modified(before: item, summary: summary))

        case "delete_todo":
            guard let item = known(str("id")) else { return (error("找不到这条待办，先用 list_todos 查 id"), nil) }
            guard AgentPrivacy.isOwn(item) else {
                return (error("这条是\(TodoSource.displayName(item.source))同步来的，要在\(TodoSource.displayName(item.source))里删"), nil)
            }
            if !pendingDeletes.contains(where: { $0.id == item.id }) { pendingDeletes.append(.init(id: item.id, title: item.title)) }
            return (json(["id": item.id, "title": item.title, "note": "还没删：\(Config.he)会看到「删除」按钮，点了才删。回答里跟\(Config.he)说一声点一下确认"]), nil)

        case "show_expression":
            guard let e = str("name"), AgentTools.expressions.contains(e) else { return (error("没有这个表情"), nil) }
            expression = e
            return (json(["ok": true]), nil)

        case "remember":
            guard let memory else { return (error("没有这个工具：\(name)"), nil) }
            guard let fact = str("fact") else { return (error("fact 不能为空"), nil) }
            let normalized = AgentMemory.normalize(fact)
            guard memory.remember(normalized) else { return (json(["ok": true, "note": "之前就记得"]), nil) }
            return (json(["ok": true]), .remembered(fact: normalized))

        case "schedule_task":
            guard let tasks else { return (error("没有这个工具：\(name)"), nil) }
            guard let task = ScheduledTask.parse(str("text") ?? "", now: now()) else { return (error("没认出几点做，写成“每天早上8点 鼓励我”"), nil) }
            tasks.add(task)
            return (json(["what": task.prompt, "when": task.detail]), .scheduled(id: task.id, summary: "定好了：\(task.detail) \(task.prompt)"))

        case "log_mood":
            guard let moods else { return (error("没有这个工具：\(name)"), nil) }
            guard let score = (args["score"] as? Int) ?? Int(str("score") ?? ""), (1...5).contains(score) else { return (error("score 要 1～5"), nil) }
            let day = MemoryDay.of(now())
            let before = moods.set(score: score, note: str("note") ?? "", now: now())
            let m = moods.mood(on: day)!
            return (json(["mood": m.name]), .loggedMood(day: day, before: before, summary: "记下今天的心情：\(m.emoji)\(m.name)"))

        case "save_note":
            guard let notes else { return (error("没有这个工具：\(name)"), nil) }
            guard let n = notes.add(str("text") ?? "", source: TodoSource.agent, now: now()) else { return (error("text 不能为空"), nil) }
            return (json(["ok": true]), .savedNote(id: n.id, text: n.text))

        case "search_notes":
            guard let notes else { return (error("没有这个工具：\(name)"), nil) }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let hits = notes.search(str("query") ?? "", limit: 6)
            return (json(["found": hits.map { ["when": f.string(from: $0.createdAt), "text": String($0.text.prefix(300))] }]), nil)

        case "check_habit":
            guard let habits else { return (error("没有这个工具：\(name)"), nil) }
            guard let h = habits.find(str("name") ?? "") else {
                return (error("没有这个习惯；现在的习惯有：" + habits.habits.map(\.title).joined(separator: "、")), nil)
            }
            guard !habits.isDone(h.id, on: MemoryDay.of(now())) else { return (json(["title": h.title, "note": "今天已经打过卡了"]), nil) }
            habits.set(h.id, done: true, now: now())
            return (json(["title": h.title, "streak": habits.streak(h.id, now: now())]), .checkedHabit(id: h.id, title: h.title))

        case "add_habit":
            guard let habits else { return (error("没有这个工具：\(name)"), nil) }
            guard let h = Habit.parse(str("text") ?? "", now: now()) else { return (error("没认出来，写成“喝水 每天晚上9点提醒”"), nil) }
            habits.add(h)
            return (json(["title": h.title, "detail": h.detail]), .addedHabit(id: h.id, title: h.title))

        case "add_date":
            guard let dates else { return (error("没有这个工具：\(name)"), nil) }
            guard let d = ImportantDate.parse(str("text") ?? "") else {
                return (error("没认出名字和日期，写成“妈妈生日 3月8日”或“妈妈生日 农历八月十五”"), nil)
            }
            dates.add(d)
            return (json(["title": d.title, "date": d.dateText, "days_until": d.daysUntil(from: now()) as Any]), .addedDate(id: d.id, title: d.title))

        case "recall":
            guard let memory else { return (error("没有这个工具：\(name)"), nil) }
            let hits = memory.search(str("query") ?? "")
            return (json(["found": hits.map { ["when": $0.key, "text": $0.text] }]), nil)

        default:
            return (error("没有这个工具：\(name)"), nil)
        }
    }

    /// 撤销一次改动
    public func undo(_ change: Change) {
        switch change {
        case let .added(id, _):
            store.delete(id)
        case let .modified(before, _):
            // 撤销打勾走 uncomplete：重复待办打勾时排上的下一次要一起撤掉
            if before.doneAt == nil, store.item(before.id)?.isDone == true { store.uncomplete(before.id) }
            store.update(before.id) { $0 = before }
        case let .remembered(fact):
            memory?.forget(fact)
        case let .addedDate(id, _):
            dates?.delete(id)
        case let .scheduled(id, _):
            tasks?.delete(id)
        case let .loggedMood(day, before, _):
            moods?.restore(before, day: day)
        case let .savedNote(id, _):
            notes?.delete(id)
        case let .checkedHabit(id, _):
            habits?.set(id, done: false, now: now())
        case let .addedHabit(id, _):
            habits?.delete(id)
        }
    }

    // MARK: - 工具

    private func known(_ id: String?) -> TodoItem? {
        guard let id, knownIDs.contains(id), let item = store.item(id), visible(item) else { return nil }
        return item
    }

    private func describe(_ item: TodoItem, extra: [String: Any] = [:]) -> [String: Any] {
        var out: [String: Any] = ["id": item.id, "title": item.title]
        if let due = item.due { out["due"] = TodoFormat.describe(due, hasTime: item.dueHasTime, now: now()) }
        if let rule = RepeatRule(item.repeatRule) { out["repeat"] = rule.display }
        return out.merging(extra) { a, _ in a }
    }

    private func error(_ message: String) -> String { json(["error": message]) }

    private func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
