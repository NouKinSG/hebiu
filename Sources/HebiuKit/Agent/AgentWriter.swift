import Foundation

/// AI 写的、不需要工具的话：主动提醒的那一句、每天一批新台词
extension AgentSession {
    /// 主动说的一句话（早上、下班、休息、深夜）。task 写清楚场景；失败返回 nil，调用方用固定台词
    public func compose(_ task: String, maxChars: Int = 40) async -> String? {
        guard ledger.withinBudget(budget(), now: now()), let key = keyProvider() else { return nil }
        var messages: [[String: Any]] = [
            ["role": "system", "content": "你是住在\(Config.he)电脑桌面上的桌宠（你是谁、什么性格、和\(Config.he)什么关系，看下面的人设）。用中文口语，\(maxChars <= 40 ? "一两句话、" : "")不超过 \(maxChars) 个字，不要列清单、不要 markdown、不要引号。\n\n" + persona()],
        ]
        if let remembered = memoryText() { messages.append(["role": "system", "content": remembered]) }
        messages.append(["role": "system", "content": await contextText()])
        messages.append(["role": "user", "content": task])
        guard let reply = try? await client.chat(messages: messages, tools: [], key: key) else { return nil }
        ledger.record(reply.usage, model: DeepSeekClient.model, at: now(), purpose: .talk)
        let text = reply.content.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”「」"))
        guard !text.isEmpty else { return nil }
        chatLog.append(.init(time: now(), role: "assistant", content: text))
        return text
    }

    /// 给各个动作写一批新台词，返回 {事件: [几句]}；只收下合格的（短、不重复、不带引号）
    public func writeLines(for events: [(key: String, when: String)], perEvent: Int = 5) async -> [String: [String]]? {
        guard ledger.withinBudget(budget(), now: now()), let key = keyProvider() else { return nil }
        let list = events.map { "- \($0.key)：\($0.when)" }.joined(separator: "\n")
        let messages: [[String: Any]] = [
            ["role": "system", "content": "你是住在\(Config.he)电脑桌面上的桌宠（你是谁、什么性格、和\(Config.he)什么关系，看下面的人设），要给自己写台词。\n\n" + persona()],
            ["role": "user", "content": """
            给下面每个场景各写 \(perEvent) 句你会说的话：口语、可爱、每句不超过 20 个字，句句不一样，不要带引号和编号。
            \(list)
            只输出一个 JSON 对象，键是场景名（冒号前的英文），值是字符串数组。
            """],
        ]
        guard let reply = try? await client.chat(messages: messages, tools: [], key: key, json: true) else { return nil }
        ledger.record(reply.usage, model: DeepSeekClient.model, at: now(), purpose: .lines)
        return AgentSession.parseLines(reply.content, keys: Set(events.map(\.key)))
    }

    static func parseLines(_ text: String, keys: Set<String>) -> [String: [String]]? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return nil }
        var out: [String: [String]] = [:]
        for (k, v) in obj where keys.contains(k) {
            let lines = (v as? [String] ?? [])
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”「」")) }
                .filter { !$0.isEmpty && $0.count <= 30 }
            let unique = lines.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if !unique.isEmpty { out[k] = unique }
        }
        return out.isEmpty ? nil : out
    }
}

/// AI 写的台词存在 ~/.hebiu/agent/lines.json，一天写一次
public struct AgentLinesStore {
    public struct Body: Codable, Equatable {
        public var day: String
        public var lines: [String: [String]]

        public init(day: String, lines: [String: [String]]) {
            self.day = day
            self.lines = lines
        }
    }

    public let url: URL
    public init(url: URL = Paths.agentDir.appendingPathComponent("lines.json")) { self.url = url }

    public func load() -> Body? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Body.self, from: data)
    }

    public func save(_ body: Body) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(body) { try? data.write(to: url, options: .atomic) }
    }

    /// 今天写过没有
    public func isFresh(now: Date = Date()) -> Bool {
        load()?.day == ReminderState.day(now)
    }
}
