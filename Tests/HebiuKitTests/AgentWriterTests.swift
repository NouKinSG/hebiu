import Foundation
import Testing
@testable import HebiuKit

private func final(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
    return #"{"choices":[{"finish_reason":"stop","message":{"content":"\#(escaped)"}}],"usage":{"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":500,"completion_tokens":60}}"#
}

private func session(_ t: FakeTransport, key: String? = "sk-test", budget: Decimal = 30) -> (AgentSession, AgentLedger, AgentChatLog, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-writer-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("b"))
    store.add(TodoItem(title: "交周报", source: TodoSource.manual))
    let ledger = AgentLedger(url: dir.appendingPathComponent("usage.jsonl"))
    let chat = AgentChatLog(url: dir.appendingPathComponent("chat.jsonl"))
    let s = AgentSession(store: store, ledger: ledger, chatLog: chat, client: DeepSeekClient(transport: t),
                         keyProvider: { key }, budget: { budget }, persona: { "人设" }, now: { date("2026-10-23 08:30") }, onMain: { $0() })
    return (s, ledger, chat, dir)
}

@Suite(.serialized) struct AgentWriterTests {
    @Test func 主动说一句_不带工具_记账_进对话记录() async {
        let t = FakeTransport([(200, final("早呀～今天先把周报交了吧"))])
        let (s, ledger, chat, dir) = session(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = await s.compose("早上第一次见到他，告诉他今天先做哪件")
        #expect(text == "早呀～今天先把周报交了吧")
        #expect(t.requests[0]["tools"] == nil)
        #expect((t.requests[0]["messages"] as? [[String: Any]])?.description.contains("交周报") == true)
        #expect(ledger.entries().count == 1)
        #expect(chat.all().last?.role == "assistant")
    }

    @Test func 没key或超上限或失败_返回nil让调用方用固定台词() async {
        let (s1, _, _, d1) = session(FakeTransport([]), key: nil)
        defer { try? FileManager.default.removeItem(at: d1) }
        #expect(await s1.compose("x") == nil)
        let (s2, _, _, d2) = session(FakeTransport([(401, "{}")]))
        defer { try? FileManager.default.removeItem(at: d2) }
        #expect(await s2.compose("x") == nil)
    }

    @Test func 写台词_要JSON_只收合格的() async {
        let json = #"{\"pat\":[\"嘿嘿～\",\"嘿嘿～\",\"再摸一下嘛\",\"这一句实在是太长太长太长了超过了三十个字的限制会被丢掉的哦哦哦\"],\"love\":[\"喜欢你\"],\"unknown\":[\"不要\"]}"#
        let t = FakeTransport([(200, #"{"choices":[{"finish_reason":"stop","message":{"content":"\#(json)"}}],"usage":{"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":800,"completion_tokens":300}}"#)])
        let (s, ledger, _, dir) = session(t)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lines = await s.writeLines(for: [("pat", "被摸头"), ("love", "被双击")])
        #expect(lines == ["pat": ["嘿嘿～", "再摸一下嘛"], "love": ["喜欢你"]])
        #expect((t.requests[0]["response_format"] as? [String: String])?["type"] == "json_object")
        #expect(ledger.entries().count == 1)
        #expect(AgentSession.parseLines("不是 json", keys: ["pat"]) == nil)
    }

    @Test func 台词文件存取和今天写过没有() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-lines-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AgentLinesStore(url: url)
        #expect(!store.isFresh(now: date("2026-10-23 08:00")))
        store.save(.init(day: "2026-10-23", lines: ["pat": ["嘿"]]))
        #expect(store.isFresh(now: date("2026-10-23 20:00")))
        #expect(!store.isFresh(now: date("2026-10-24 08:00")))
    }
}
