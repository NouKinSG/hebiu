import Foundation

/// 她的人设：~/.hebiu/persona.md，没有就用默认的
public enum AgentPersona {
    /// 默认人设：启动时换成形象包里的
    public static var defaultText = builtinText

    public static let builtinText = """
    # 它的人设

    - 你是 Biu，住在TA电脑屏幕角落的小团子助手：圆滚滚、头顶一颗薄荷色小芽
    - 性格：温和、贴心、有点小调皮；会关心TA累不累，也会认真帮TA办事
    - 说话：口语、短句，一两句说完；不说教，不用书面语
    - 称呼TA：你
    - TA忙的时候不打扰，TA累的时候提醒休息，TA熬夜时催TA睡觉
    """

    public static func load(url: URL = Paths.persona) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text! : defaultText
    }
}

/// 和她说一句话的完整过程：拼提示词 → 问 DeepSeek → 执行工具 → 再问，最多来回 4 次
public final class AgentSession {
    public enum Failure: Equatable {
        case noKey, overBudget, badKey, noBalance, network, confused
    }

    public struct Reply: Equatable {
        public var text: String
        public var expression: String?
        public var changes: [AgentTools.Change]
        public var failure: Failure?
        /// 她提出要删、等你点「删除」的待办
        public var pendingDeletes: [AgentTools.PendingDelete]

        public init(text: String, expression: String?, changes: [AgentTools.Change], failure: Failure?,
                    pendingDeletes: [AgentTools.PendingDelete] = []) {
            self.text = text
            self.expression = expression
            self.changes = changes
            self.failure = failure
            self.pendingDeletes = pendingDeletes
        }
    }

    public static let maxRounds = 4

    let store: TodoStore
    let ledger: AgentLedger
    let chatLog: AgentChatLog
    let client: DeepSeekClient
    let keyProvider: () -> String?
    let budget: () -> Decimal
    let persona: () -> String
    let now: () -> Date
    let memory: AgentMemory
    /// 设置里「她记住你」开关
    let memoryEnabled: () -> Bool
    /// 日记里带不带用 Claude 的时间和次数
    let activityEnabled: () -> Bool
    let events: URL
    /// 重要日子（含内置的两个）；没有就 nil
    let dates: ImportantDateStore?
    let extraDates: () -> [ImportantDate]
    let habits: HabitStore?
    let notes: NoteStore?
    let moods: MoodStore?
    /// 今天的天气（给她说早报、提醒带伞用）；没设城市为 nil
    let weather: () -> String?
    let tasks: ScheduledTaskStore?
    /// 工具要在主线程执行（和窗口改待办走同一个存储）
    let onMain: (@escaping () -> Void) async -> Void
    public private(set) var lastTools: AgentTools?

    public init(store: TodoStore, ledger: AgentLedger = AgentLedger(), chatLog: AgentChatLog = AgentChatLog(),
                client: DeepSeekClient = DeepSeekClient(), keyProvider: @escaping () -> String? = { AgentSecrets.shared.load() },
                budget: @escaping () -> Decimal, persona: @escaping () -> String = { AgentPersona.load() },
                now: @escaping () -> Date = Date.init,
                memory: AgentMemory = AgentMemory(), memoryEnabled: @escaping () -> Bool = { true },
                activityEnabled: @escaping () -> Bool = { true }, events: URL = Paths.events,
                dates: ImportantDateStore? = nil, extraDates: @escaping () -> [ImportantDate] = { [] },
                habits: HabitStore? = nil, notes: NoteStore? = nil, moods: MoodStore? = nil,
                weather: @escaping () -> String? = { nil }, tasks: ScheduledTaskStore? = nil,
                onMain: @escaping (@escaping () -> Void) async -> Void = { work in await MainActor.run { work() } }) {
        self.store = store
        self.ledger = ledger
        self.chatLog = chatLog
        self.client = client
        self.keyProvider = keyProvider
        self.budget = budget
        self.persona = persona
        self.now = now
        self.memory = memory
        self.memoryEnabled = memoryEnabled
        self.activityEnabled = activityEnabled
        self.events = events
        self.dates = dates
        self.extraDates = extraDates
        self.habits = habits
        self.notes = notes
        self.moods = moods
        self.weather = weather
        self.tasks = tasks
        self.onMain = onMain
    }

    public func send(_ text: String) async -> Reply {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Reply(text: "", expression: nil, changes: [], failure: nil) }
        guard ledger.withinBudget(budget(), now: now()) else { return fail(.overBudget, said: text) }
        guard let key = keyProvider() else { return fail(.noKey, said: text) }

        let tools = AgentTools(store: store, now: now, memory: memoryEnabled() ? memory : nil, dates: dates, habits: habits, notes: notes, moods: moods, tasks: tasks)
        lastTools = tools
        var messages = await buildMessages(text, tools: tools)
        var changes: [AgentTools.Change] = []
        chatLog.append(.init(time: now(), role: "user", content: text))

        for _ in 0..<AgentSession.maxRounds {
            let reply: DeepSeekClient.Reply
            do {
                reply = try await client.chat(messages: messages, tools: tools.definitions, key: key)
            } catch let f as DeepSeekClient.Failure {
                return finishWithFailure(map(f), changes: changes)
            } catch {
                return finishWithFailure(.network, changes: changes)
            }
            ledger.record(reply.usage, model: DeepSeekClient.model, at: now())
            if reply.toolCalls.isEmpty {
                let answer = reply.content.isEmpty ? "嗯嗯～" : reply.content
                for p in tools.pendingDeletes {
                    chatLog.append(.init(time: now(), role: "action", content: "想删「\(p.title)」，等你点「删除」"))
                }
                chatLog.append(.init(time: now(), role: "assistant", content: answer, expression: tools.expression))
                return Reply(text: answer, expression: tools.expression, changes: changes, failure: nil, pendingDeletes: tools.pendingDeletes)
            }
            messages.append(reply.rawMessage)
            for call in reply.toolCalls {
                var result = ""
                var change: AgentTools.Change?
                await onMain { (result, change) = tools.execute(name: call.name, arguments: call.arguments) }
                if let change {
                    changes.append(change)
                    chatLog.append(.init(time: now(), role: "action", content: change.summary))
                }
                messages.append(["role": "tool", "tool_call_id": call.id, "content": result])
            }
        }
        return finishWithFailure(.confused, changes: changes)
    }

    /// 你点了「删除」：真删掉她提出的那条（只删你自己加的）
    @discardableResult
    public func confirmDelete(_ pending: AgentTools.PendingDelete) async -> Bool {
        var deleted = false
        await onMain {
            guard let item = self.store.item(pending.id), AgentPrivacy.isOwn(item) else { return }
            self.store.delete(item.id)
            deleted = true
        }
        if deleted { chatLog.append(.init(time: now(), role: "action", content: "删了「\(pending.title)」")) }
        return deleted
    }

    /// 撤销这一句话里做的某个改动
    public func undo(_ change: AgentTools.Change) async {
        guard let tools = lastTools else { return }
        await onMain { tools.undo(change) }
        chatLog.append(.init(time: now(), role: "action", content: "撤销：\(change.summary)"))
    }

    // MARK: - 提示词

    /// 顺序：规则和人设 → 记忆 → 最近对话 → 现在（时间、待办、天气……）→ 这一句；前面不常变，能命中 DeepSeek 的缓存
    private func buildMessages(_ text: String, tools: AgentTools) async -> [[String: Any]] {
        var today: [AgentPrivacy.SharedTodo] = [], later: [AgentPrivacy.SharedTodo] = []
        let date = now()
        await onMain {
            let s = TodoQuery.sections(self.store.items.filter(AgentPrivacy.isShareable), now: date)
            today = AgentPrivacy.share(Array(s.today.prefix(20)), now: date)
            later = AgentPrivacy.share(Array(s.later.prefix(10)), now: date)
        }
        tools.register(today.map(\.id) + later.map(\.id))
        let rules = """
        你是住在\(Config.he)电脑桌面上的桌宠（你是谁、什么性格、和\(Config.he)什么关系，看下面的人设），在和\(Config.he)聊天。规则：
        1. 用中文口语回答，一两句话说完，像微信聊天，不要列清单、不要用 markdown；\(Config.he)让你排计划、做总结时可以长一点，用「先…再…最后…」串起来，四句以内。
        2. 要加、查、打勾、改时间待办，必须调用工具；不要假装做了。
        3. 加待办时 text 用\(Config.he)的原话（保留「明天下午三点」这类说法），不要自己换算日期。
        4. 改某条待办用下面列表里方括号中的 id；拿不准\(Config.he)说的是哪一条，就问\(Config.he)，不要猜。
        5. 你只能管待办和陪\(Config.he)聊天：删待办只能用 delete_todo 提出来、由\(Config.he)点确认；不能发消息、发邮件，做不到的事就撒娇说做不到。
        6. 不要编造\(Config.he)没有的待办。
        7. 每次回答都调用一次 show_expression 配一个表情。
        """ + (memoryEnabled() ? """

        8. \(Config.he)让你记住什么，或者聊到以后用得上的事（喜好、习惯、在意的人和日子、正在忙的事），调用 remember 记下来。
        9. \(Config.he)问起以前的事、下面的记忆里又没有，先用 recall 翻日记再回答；翻不到就老实说不记得了。
        """ : "")
        // 不常变的放前面（规则、人设、记忆、之前的聊天），DeepSeek 能按前缀命中缓存；每分钟都变的「现在」放最后
        var messages: [[String: Any]] = [["role": "system", "content": rules + "\n\n" + persona()]]
        if let remembered = memoryText() { messages.append(["role": "system", "content": remembered]) }
        let history = chatLog.recentConversation(20)
        for line in history {
            messages.append(["role": line.role, "content": line.content])
        }
        var now = await contextText()
        // 记录里只存了说的话、没存当时调的工具，模型照着学就会只动嘴不调工具；紧挨着这一句再提醒一次
        if !history.isEmpty {
            now += "\n\n（提醒：上面是之前的聊天，省略了你当时调用的工具。这一句照样按规则来：要做的事必须调用工具，不能只嘴上说做了；每次回答都调用 show_expression。）"
        }
        messages.append(["role": "system", "content": now])
        messages.append(["role": "user", "content": text])
        return messages
    }

    /// 记忆里带进提示词的部分；关掉时不带
    func memoryText() -> String? {
        memoryEnabled() ? memory.promptText() : nil
    }

    /// 「现在几点 + 今天和以后的待办」，聊天和主动说话都用
    func contextText() async -> String {
        var today: [AgentPrivacy.SharedTodo] = [], later: [AgentPrivacy.SharedTodo] = []
        let date = now()
        await onMain {
            let s = TodoQuery.sections(self.store.items.filter(AgentPrivacy.isShareable), now: date)
            today = AgentPrivacy.share(Array(s.today.prefix(20)), now: date)
            later = AgentPrivacy.share(Array(s.later.prefix(10)), now: date)
        }
        func list(_ items: [AgentPrivacy.SharedTodo]) -> String {
            items.isEmpty ? "（没有）" : items.map {
                "- [\($0.id)] \($0.title)" + ($0.due.map { "（\($0)）" } ?? "") + ($0.from.map { "〔来自\($0)〕" } ?? "")
            }.joined(separator: "\n")
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE HH:mm"
        let soon = (dates?.upcoming(from: date, extra: extraDates()) ?? []).filter { $0.days <= 60 }.prefix(5)
        let soonText = soon.isEmpty ? "" : "\n快到的重要日子：\n" + soon.map { "- \($0.date.title)（\($0.date.dateText)）" + ($0.days == 0 ? "就是今天" : "还有 \($0.days) 天") }.joined(separator: "\n")
        var aboutToday = ""
        await onMain {
            let today = self.habits?.today(now: date) ?? []
            if let m = self.moods?.today(date) {
                aboutToday += "\n\(Config.he)今天的心情：\(m.emoji)\(m.name)" + (m.note.isEmpty ? "" : "（\(m.note)）")
            }
            if !today.isEmpty {
                aboutToday += "\n今天的习惯：" + today.map { "\($0.habit.emoji)\($0.habit.title)" + ($0.done ? "（已打卡）" : "（还没打卡）") }.joined(separator: "、")
            }
        }
        return """
        现在是 \(f.string(from: date))。\(weather().map { "\n" + $0 } ?? "")\(soonText)\(aboutToday)
        \(Config.he)今天的待办（含过期没做的）：
        \(list(today))
        以后的待办：
        \(list(later))
        """
    }

    // MARK: - 失败

    private func map(_ f: DeepSeekClient.Failure) -> Failure {
        switch f {
        case .badKey: return .badKey
        case .noBalance: return .noBalance
        case .busy, .network, .badResponse: return .network
        }
    }

    private func fail(_ failure: Failure, said text: String) -> Reply {
        Reply(text: AgentSession.message(for: failure), expression: "pout", changes: [], failure: failure)
    }

    private func finishWithFailure(_ failure: Failure, changes: [AgentTools.Change]) -> Reply {
        let message = AgentSession.message(for: failure)
        chatLog.append(.init(time: now(), role: "error", content: message))
        return Reply(text: message, expression: "pout", changes: changes, failure: failure)
    }

    public static func message(for failure: Failure) -> String {
        switch failure {
        case .noKey: return "还没给我填 DeepSeek 的 key 呢，去设置里填一下嘛"
        case .overBudget: return "这个月的额度用完啦，下个月再陪你聊～"
        case .badKey: return "key 好像不对，去设置里检查一下嘛"
        case .noBalance: return "DeepSeek 没余额啦，要去充值哦"
        case .network: return "连不上网啦，等会儿再试试"
        case .confused: return "我有点晕…换个说法试试嘛"
        }
    }
}
