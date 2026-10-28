import Foundation
import Testing
@testable import HebiuKit

/// 假的 DeepSeek：按顺序返回写好的响应，并记下收到的请求
final class FakeTransport: AgentTransport, @unchecked Sendable {
    var responses: [(Int, String)]
    var requests: [[String: Any]] = []
    var failNetwork = false
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func send(method: String, url: URL, key: String, body: Data?) async throws -> (status: Int, data: Data) {
        if let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { requests.append(json) }
        if failNetwork { throw URLError(.notConnectedToInternet) }
        let (status, text) = responses.isEmpty ? (200, final("…")) : responses.removeFirst()
        return (status, Data(text.utf8))
    }
}

private func toolCall(_ name: String, _ args: String, id: String = "call_1") -> String {
    let escaped = args.replacingOccurrences(of: "\"", with: "\\\"")
    return """
    {"choices":[{"finish_reason":"tool_calls","message":{"content":"","tool_calls":[{"id":"\(id)","type":"function","function":{"name":"\(name)","arguments":"\(escaped)"}}]}}],
     "usage":{"prompt_cache_hit_tokens":1792,"prompt_cache_miss_tokens":356,"completion_tokens":31}}
    """
}

private func final(_ text: String) -> String {
    #"{"choices":[{"finish_reason":"stop","message":{"content":"\#(text)"}}],"usage":{"prompt_cache_hit_tokens":2048,"prompt_cache_miss_tokens":120,"completion_tokens":20}}"#
}

private let now = date("2026-10-23 14:30")

private func makeSession(_ transport: FakeTransport, key: String? = "sk-test", budget: Decimal = 30) -> (AgentSession, TodoStore, AgentLedger, AgentChatLog, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-session-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("backup"))
    let ledger = AgentLedger(url: dir.appendingPathComponent("usage.jsonl"))
    let chat = AgentChatLog(url: dir.appendingPathComponent("chat.jsonl"))
    let session = AgentSession(store: store, ledger: ledger, chatLog: chat,
                               client: DeepSeekClient(transport: transport), keyProvider: { key },
                               budget: { budget }, persona: { "测试人设" }, now: { now }, memoryEnabled: { false }, onMain: { $0() })
    return (session, store, ledger, chat, dir)
}

@Suite(.serialized) struct AgentSessionTests {
    @Test func 她提出删除_点删除才真删() async {
        let t = FakeTransport([])
        let (session, store, _, chat, dir) = makeSession(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = store.add(text: "取快递", source: TodoSource.manual, now: now)!
        t.responses = [(200, toolCall("delete_todo", "{\"id\":\"\(item.id)\"}")), (200, final("点一下删除就好啦"))]
        let reply = await session.send("快递不用取了，删掉吧")
        #expect(reply.pendingDeletes.map(\.title) == ["取快递"])
        #expect(store.items.count == 1)
        #expect(chat.all().contains { $0.content == "想删「取快递」，等你点「删除」" })
        #expect(await session.confirmDelete(reply.pendingDeletes[0]))
        #expect(store.items.isEmpty)
        #expect(chat.all().last?.content == "删了「取快递」")
    }

    @Test func 一句话加待办_调工具再回答_两次请求都记账() async {
        let t = FakeTransport([(200, toolCall("add_todo", #"{"text":"明天下午三点 给妈妈打电话"}"#)), (200, final("记下啦～"))])
        let (session, store, ledger, chat, dir) = makeSession(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = await session.send("明天下午三点提醒我给妈妈打电话")
        #expect(reply.failure == nil)
        #expect(reply.text == "记下啦～")
        #expect(store.items.map(\.title) == ["给妈妈打电话"])
        #expect(reply.changes.count == 1)
        #expect(ledger.entries().count == 2)
        #expect(chat.all().map(\.role) == ["user", "action", "assistant"])
        // 第二次请求带上了工具结果
        let second = t.requests[1]["messages"] as! [[String: Any]]
        #expect(second.last?["role"] as? String == "tool")
        #expect((second.last?["content"] as? String)?.contains("明天 15:00") == true)
        // 关闭思考模式、带工具
        #expect((t.requests[0]["thinking"] as? [String: String])?["type"] == "disabled")
        #expect((t.requests[0]["tools"] as? [Any])?.count == 6)
        // 撤销
        await session.undo(reply.changes[0])
        #expect(store.items.isEmpty)
    }

    @Test func 提示词里不出现公司来源的待办_也不出现key() async {
        let t = FakeTransport([(200, final("今天就一件事哦"))])
        let (session, store, _, _, dir) = makeSession(t, key: "sk-secret-abcdef")
        defer { try? FileManager.default.removeItem(at: dir) }
        store.add(TodoItem(title: "交周报", source: TodoSource.manual))
        store.add(TodoItem(title: "周会 10:00 开始", source: "calendar"))
        store.add(TodoItem(title: "Review：登录页", source: "gitlab-review"))
        _ = await session.send("我今天还有什么事？")
        let body = String(decoding: try! JSONSerialization.data(withJSONObject: t.requests[0]), as: UTF8.self)
        #expect(body.contains("交周报"))
        #expect(!body.contains("周会") && !body.contains("Review") && !body.contains("sk-secret"))
    }

    @Test func 提示词里列出的待办可以直接打勾() async {
        let t = FakeTransport([])
        let (session, store, _, _, dir) = makeSession(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = store.add(TodoItem(title: "交周报", source: TodoSource.manual))
        t.responses = [(200, toolCall("complete_todo", "{\"id\":\"\(item.id)\"}")), (200, final("biu～"))]
        let reply = await session.send("周报写完了")
        #expect(reply.failure == nil)
        #expect(store.item(item.id)?.isDone == true)
    }

    @Test func 没key和超上限_不发请求() async {
        let t = FakeTransport([])
        let (s1, _, _, _, d1) = makeSession(t, key: nil)
        defer { try? FileManager.default.removeItem(at: d1) }
        #expect(await s1.send("你好").failure == .noKey)
        let (s2, _, ledger, _, d2) = makeSession(t, budget: Decimal(string: "0.0001")!)
        defer { try? FileManager.default.removeItem(at: d2) }
        ledger.record(AgentUsage(promptCacheHitTokens: 0, promptCacheMissTokens: 1000, completionTokens: 100), model: "x", at: now)
        #expect(await s2.send("你好").failure == .overBudget)
        #expect(t.requests.isEmpty)
    }

    @Test func key错和没余额() async {
        let (s1, _, _, _, d1) = makeSession(FakeTransport([(401, "{}")]))
        defer { try? FileManager.default.removeItem(at: d1) }
        #expect(await s1.send("你好").failure == .badKey)
        let (s2, _, _, _, d2) = makeSession(FakeTransport([(402, "{}")]))
        defer { try? FileManager.default.removeItem(at: d2) }
        #expect(await s2.send("你好").failure == .noBalance)
    }

    @Test func 断网_重试一次后放弃() async {
        let t = FakeTransport([])
        t.failNetwork = true
        let (session, _, ledger, _, dir) = makeSession(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = await session.send("你好")
        #expect(reply.failure == .network)
        #expect(t.requests.count == 2)
        #expect(ledger.entries().isEmpty)
    }

    @Test func 一直调工具不回答_四次后停下() async {
        let t = FakeTransport((0..<6).map { _ in (200, toolCall("list_todos", #"{"scope":"today"}"#)) })
        let (session, _, ledger, _, dir) = makeSession(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = await session.send("你好")
        #expect(reply.failure == .confused)
        #expect(t.requests.count == AgentSession.maxRounds)
        #expect(ledger.entries().count == AgentSession.maxRounds)
    }

    @Test func 带上最近的对话() async {
        let t = FakeTransport([(200, final("嗯嗯")), (200, final("好的呀"))])
        let (session, _, _, _, dir) = makeSession(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await session.send("第一句")
        _ = await session.send("第二句")
        let messages = t.requests[1]["messages"] as! [[String: Any]]
        let contents = messages.compactMap { $0["content"] as? String }
        #expect(contents.contains("第一句") && contents.contains("嗯嗯") && contents.last == "第二句")
    }
}
