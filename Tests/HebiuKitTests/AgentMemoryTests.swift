import Foundation
import Testing
@testable import HebiuKit

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-memory-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func jsonReply(_ object: [String: Any]) -> String {
    let content = String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    let wrapped: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": content]]],
                                  "usage": ["prompt_cache_hit_tokens": 0, "prompt_cache_miss_tokens": 900, "completion_tokens": 150]]
    return String(decoding: try! JSONSerialization.data(withJSONObject: wrapped), as: UTF8.self)
}

private struct Rig {
    let dir: URL
    let session: AgentSession
    let memory: AgentMemory
    let chat: AgentChatLog
    let store: TodoStore
    let ledger: AgentLedger
    let events: URL
}

private func rig(_ transport: FakeTransport, now: Date, memoryOn: Bool = true, activityOn: Bool = true) -> Rig {
    let dir = tempDir()
    let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("backup"))
    let ledger = AgentLedger(url: dir.appendingPathComponent("usage.jsonl"))
    let chat = AgentChatLog(url: dir.appendingPathComponent("chat.jsonl"))
    let memory = AgentMemory(dir: dir.appendingPathComponent("memory"))
    let events = dir.appendingPathComponent("events")
    let session = AgentSession(store: store, ledger: ledger, chatLog: chat, client: DeepSeekClient(transport: transport),
                               keyProvider: { "sk-test" }, budget: { 30 }, persona: { "测试人设" }, now: { now },
                               memory: memory, memoryEnabled: { memoryOn }, activityEnabled: { activityOn },
                               events: events, onMain: { $0() })
    return Rig(dir: dir, session: session, memory: memory, chat: chat, store: store, ledger: ledger, events: events)
}

@Suite struct MemoryDayTests {
    @Test func 凌晨四点前算前一天() {
        #expect(MemoryDay.of(date("2026-10-26 01:47")) == "2026-10-25")
        #expect(MemoryDay.of(date("2026-10-26 04:00")) == "2026-10-26")
        let r = MemoryDay.range("2026-10-25")
        #expect(r.contains(date("2026-10-26 03:59")))
        #expect(!r.contains(date("2026-10-25 03:59")))
    }

    @Test func 周和月() {
        #expect(MemoryDay.weekDays(of: "2026-10-25") == ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"])
        #expect(MemoryDay.weekKey("2026-10-19") == "2026-W43")
        #expect(AgentSession.mondayOf("2026-W43") == "2026-10-19")
        #expect(MemoryDay.add("2026-11-01", -1) == "2026-10-31")
    }
}

@Suite struct AgentMemoryStoreTests {
    @Test func 了解_去重截断限条数() {
        let m = AgentMemory(dir: tempDir())
        #expect(m.remember("- 他不喝冰的"))
        #expect(!m.remember("他不喝冰的"))
        #expect(m.facts() == ["他不喝冰的"])
        #expect(AgentMemory.normalize("「他说「辛苦你啦」」") == "他说「辛苦你啦」")
        #expect(AgentMemory.normalize("他被夸会说「辛苦你啦」") == "他被夸会说「辛苦你啦」")
        m.saveFacts((0..<60).map { "他第 \($0) 件事" } + [String(repeating: "长", count: 100)])
        #expect(m.facts().count == AgentMemory.maxFacts)
        m.remember("最新的一条")
        #expect(m.facts().last == "最新的一条")
        #expect(m.facts().count == AgentMemory.maxFacts)
        m.forget("最新的一条")
        #expect(!m.facts().contains("最新的一条"))
    }

    @Test func 提示词只带了解和最近三篇日记加最近的周记月记() {
        let m = AgentMemory(dir: tempDir())
        #expect(m.promptText() == nil)
        m.remember("他喜欢奶茶")
        for d in 20...25 { m.save(.diary, "2026-10-\(d)", text: "第\(d)号的日记") }
        m.save(.weekly, "2026-W42", text: "旧的一周")
        m.save(.weekly, "2026-W43", text: "这一周")
        m.save(.monthly, "2026-09", text: "九月")
        let text = m.promptText()!
        #expect(text.contains("他喜欢奶茶"))
        #expect(text.contains("第25号") && text.contains("第23号") && !text.contains("第22号"))
        #expect(text.contains("这一周") && !text.contains("旧的一周"))
        #expect(text.contains("九月"))
        // 旧的在前，读起来按时间顺序
        #expect(text.range(of: "第23号")!.lowerBound < text.range(of: "第25号")!.lowerBound)
    }

    @Test func 翻日记_关键词和日期() {
        let m = AgentMemory(dir: tempDir())
        m.save(.diary, "2026-09-03", text: "他带我去了一家叫小满的面馆")
        m.save(.diary, "2026-10-25", text: "他在改桌宠")
        m.save(.monthly, "2026-09", text: "九月他很忙")
        #expect(m.search("面馆").map(\.key) == ["2026-09-03"])
        #expect(Set(m.search("2026-09").map(\.key)) == ["2026-09-03", "2026-09"])
        #expect(m.search("九月初 面馆").map(\.key) == ["2026-09-03"])
        #expect(m.search("小满 桌宠").map(\.key) == ["2026-10-25", "2026-09-03"])   // 各对上一个词时新的在前
        #expect(m.search("他 面馆").first?.key == "2026-09-03")         // 对上两个词的排前面
        #expect(m.search("火锅").isEmpty)
        #expect(m.search("  ").isEmpty)
    }

    @Test func 待整理的日子_最多补七天且不重复() {
        let m = AgentMemory(dir: tempDir())
        let now = date("2026-10-26 09:00")
        #expect(m.pendingDiaryDays(now: now) == (19...25).map { "2026-10-\($0)" })
        m.markDiaryDone("2026-10-24")
        #expect(m.pendingDiaryDays(now: now) == ["2026-10-25"])
        m.markDiaryDone("2026-10-25")
        #expect(m.pendingDiaryDays(now: now).isEmpty)
        // 凌晨两点还没过完「25 号」
        m.saveState(.init())
        #expect(m.pendingDiaryDays(now: date("2026-10-26 02:00")).last == "2026-10-24")
    }

    @Test func 上周和上个月() {
        let m = AgentMemory(dir: tempDir())
        let now = date("2026-11-03 10:00")
        #expect(m.pendingWeek(now: now)?.key == "2026-W44")
        #expect(m.pendingMonth(now: now) == "2026-10")
        m.markWeekDone("2026-W44")
        m.markMonthDone("2026-10")
        #expect(m.pendingWeek(now: now) == nil)
        #expect(m.pendingMonth(now: now) == nil)
    }
}

@Suite struct ClaudeActivityTests {
    @Test func 只数时间和次数_跨过半夜算前一天() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("events")
        func ts(_ s: String) -> String { String(Int(date(s).timeIntervalSince1970)) }
        let text = """
        \(ts("2026-10-25 03:00")) hello
        \(ts("2026-10-25 21:10")) hello
        \(ts("2026-10-25 21:11")) working
        \(ts("2026-10-25 22:40")) done
        \(ts("2026-10-25 23:05")) error
        \(ts("2026-10-25 23:30")) pat
        \(ts("2026-10-26 01:47")) done
        \(ts("2026-10-26 09:00")) hello
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
        let a = ClaudeActivity.of(day: "2026-10-25", events: url)
        #expect(a.sessions == 1 && a.finished == 2 && a.errors == 1)
        #expect(a.summary == "用 Claude 写代码：21:10 到 01:47，开了 1 次会话，干完 2 次活，报错 1 次")
        #expect(ClaudeActivity.of(day: "2026-10-20", events: url).summary == nil)
    }
}

@Suite(.serialized) struct AgentMemoryWriterTests {
    @Test func 每晚整理_写日记改写了解_只发当天的事() async {
        let now = date("2026-10-26 09:00")
        let t = FakeTransport([(200, jsonReply(["diary": "今天他一直在给我做记忆，好开心", "facts": ["他喜欢奶茶", "他在做桌宠 hebiu"]]))])
        let r = rig(t, now: now)
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.memory.remember("他喜欢奶茶")
        r.memory.markWeekDone("2026-W43")
        r.memory.markMonthDone("2026-09")
        r.chat.append(.init(time: date("2026-10-25 20:00"), role: "user", content: "我在给你做记忆"))
        r.chat.append(.init(time: date("2026-10-25 20:00"), role: "assistant", content: "哇好耶"))
        r.chat.append(.init(time: date("2026-10-18 20:00"), role: "user", content: "前一天的话"))
        try? "\(Int(date("2026-10-25 21:00").timeIntervalSince1970)) hello\n".write(to: r.events, atomically: true, encoding: .utf8)
        r.store.add(text: "交周报", source: TodoSource.manual, now: date("2026-10-25 10:00"))
        r.store.complete(r.store.items[0].id, at: date("2026-10-25 18:00"))

        let result = await r.session.consolidate()
        #expect(result.diaries == ["2026-10-25"])
        #expect(!result.failed)
        #expect(r.memory.text(.diary, "2026-10-25") == "今天他一直在给我做记忆，好开心")
        #expect(r.memory.facts() == ["他喜欢奶茶", "他在做桌宠 hebiu"])
        #expect(r.ledger.entries().count == t.requests.count)
        let prompt = ((t.requests.last?["messages"] as? [[String: Any]])?.last?["content"] as? String) ?? ""
        #expect(prompt.contains("我在给你做记忆") && prompt.contains("交周报") && prompt.contains("21:00"))
        #expect(!prompt.contains("前一天的话"))
        // 再跑一次不会重复请求
        let before = t.requests.count
        _ = await r.session.consolidate()
        #expect(t.requests.count == before)
    }

    @Test func 没发生事的日子不请求_请求失败停下下次接着做() async {
        let now = date("2026-10-26 09:00")
        let t = FakeTransport([(500, "{}"), (500, "{}")])
        let r = rig(t, now: now)
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.chat.append(.init(time: date("2026-10-25 20:00"), role: "user", content: "在吗"))
        let result = await r.session.consolidate()
        #expect(result.failed)
        #expect(t.requests.count == 2)                      // 只有 25 号有事，失败后重试了一次
        #expect(r.memory.pendingDiaryDays(now: now) == ["2026-10-25"])
    }

    @Test func 关掉活动记录就不带用Claude的时间() async {
        let t = FakeTransport([])
        let r = rig(t, now: date("2026-10-26 09:00"), activityOn: false)
        defer { try? FileManager.default.removeItem(at: r.dir) }
        try? "\(Int(date("2026-10-25 21:00").timeIntervalSince1970)) hello\n".write(to: r.events, atomically: true, encoding: .utf8)
        #expect(await r.session.dayMaterial("2026-10-25") == nil)
    }

    @Test func 带今天明天的是待办_不进了解() {
        let parsed = AgentSession.parseDiary(#"{"diary":"好","facts":["他明天三点给妈妈打电话","他常熬夜","他今天交完周报了"]}"#)
        #expect(parsed?.facts == ["他常熬夜"])
    }

    @Test func 模型把了解全丢了_保留原来的() async {
        let t = FakeTransport([(200, jsonReply(["diary": "平平常常的一天", "facts": []]))])
        let r = rig(t, now: date("2026-10-26 09:00"))
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.memory.remember("他怕冷")
        r.chat.append(.init(time: date("2026-10-25 20:00"), role: "user", content: "晚安"))
        _ = await r.session.consolidate()
        #expect(r.memory.facts() == ["他怕冷"])
    }

    @Test func 过完一周压成周记() async {
        let t = FakeTransport([(200, jsonReply(["summary": "这周他天天加班"]))])
        let r = rig(t, now: date("2026-10-27 09:00"))
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.memory.markDiaryDone("2026-10-26")
        r.memory.markMonthDone("2026-09")
        r.memory.save(.diary, "2026-10-21", text: "加班")
        let result = await r.session.consolidate()
        #expect(result.weekly == "2026-W43")
        #expect(r.memory.text(.weekly, "2026-W43") == "这周他天天加班")
    }

    @Test func 聊天时带上记忆和两个记忆工具_关掉就都不带() async {
        let t = FakeTransport([])
        let r = rig(t, now: date("2026-10-26 09:00"))
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.memory.remember("他叫我小禾")
        _ = await r.session.send("你记得我吗")
        let req = t.requests[0]
        let system = (req["messages"] as! [[String: Any]]).filter { $0["role"] as? String == "system" }.compactMap { $0["content"] as? String }.joined()
        #expect(system.contains("他叫我小禾"))
        let names = (req["tools"] as! [[String: Any]]).compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        #expect(names.contains("remember") && names.contains("recall"))
        // 有历史时，这一句前面紧挨着一条「要调工具」的提醒
        _ = await r.session.send("再说一句")
        let msgs = t.requests.last!["messages"] as! [[String: Any]]
        #expect(msgs[msgs.count - 2]["role"] as? String == "system")
        #expect((msgs[msgs.count - 2]["content"] as? String)?.contains("必须调用工具") == true)

        let t2 = FakeTransport([])
        let off = rig(t2, now: date("2026-10-26 09:00"), memoryOn: false)
        defer { try? FileManager.default.removeItem(at: off.dir) }
        off.memory.remember("他叫我小禾")
        _ = await off.session.send("你记得我吗")
        let req2 = t2.requests[0]
        #expect(!((req2["messages"] as! [[String: Any]]).compactMap { $0["content"] as? String }.joined().contains("小禾")))
        #expect(!(req2["tools"] as! [[String: Any]]).contains { (($0["function"] as? [String: Any])?["name"] as? String) == "remember" })
        #expect(await off.session.consolidate() == .init())
    }
}

@Suite struct AgentMemoryToolsTests {
    @Test func 记住和撤销_翻日记() {
        let dir = tempDir()
        let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("backup"))
        let memory = AgentMemory(dir: dir.appendingPathComponent("memory"))
        memory.save(.diary, "2026-09-03", text: "去了小满面馆")
        let tools = AgentTools(store: store, memory: memory)
        let (_, change) = tools.execute(name: "remember", arguments: #"{"fact":"他不吃香菜"}"#)
        #expect(change == .remembered(fact: "他不吃香菜"))
        #expect(memory.facts() == ["他不吃香菜"])
        let (again, none) = tools.execute(name: "remember", arguments: #"{"fact":"他不吃香菜"}"#)
        #expect(none == nil && again.contains("之前就记得"))
        tools.undo(change!)
        #expect(memory.facts().isEmpty)
        let (found, _) = tools.execute(name: "recall", arguments: #"{"query":"面馆"}"#)
        #expect(found.contains("2026-09-03") && found.contains("小满"))

        let plain = AgentTools(store: store)
        #expect(plain.execute(name: "remember", arguments: #"{"fact":"x"}"#).result.contains("没有这个工具"))
        #expect(plain.definitions.count == AgentTools.definitions.count)
    }
}
