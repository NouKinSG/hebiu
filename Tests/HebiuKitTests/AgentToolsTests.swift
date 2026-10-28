import Foundation
import Testing
@testable import HebiuKit

private let now = date("2026-10-23 14:30")

private func setup() -> (TodoStore, AgentTools, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-tools-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("backup"))
    return (store, AgentTools(store: store, now: { now }), dir)
}

private func obj(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}

struct AgentToolsTests {
    @Test func 加待办_时间用现有识别_来源记为她加的_可撤销() {
        let (store, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (result, change) = tools.execute(name: "add_todo", arguments: #"{"text":"明天下午三点 给妈妈打电话"}"#)
        let r = obj(result)
        #expect(r["title"] as? String == "给妈妈打电话")
        #expect(r["due"] as? String == "明天 15:00")
        #expect(store.items.first?.source == TodoSource.agent)
        tools.undo(change!)
        #expect(store.items.isEmpty)
    }

    @Test func 查待办_不返回日历和GitLab来的() {
        let (store, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.add(TodoItem(title: "交周报", source: TodoSource.manual))
        store.add(TodoItem(title: "周会 10:00 开始", source: "calendar"))
        store.add(TodoItem(title: "Review：xxx", source: "gitlab-review"))
        let r = obj(tools.execute(name: "list_todos", arguments: #"{"scope":"today"}"#).result)
        let titles = (r["todos"] as? [[String: Any]])?.compactMap { $0["title"] as? String }
        #expect(titles == ["交周报"])
    }

    @Test func 打勾和改时间_只认查过的id_能撤销() {
        let (store, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        let item = store.add(TodoItem(title: "开会", due: date("2026-10-23 15:00"), dueHasTime: true, source: TodoSource.manual))
        // 没查过 id：拒绝
        #expect(obj(tools.execute(name: "complete_todo", arguments: "{\"id\":\"\(item.id)\"}").result)["error"] != nil)
        _ = tools.execute(name: "list_todos", arguments: #"{"scope":"today"}"#)
        let (r1, c1) = tools.execute(name: "reschedule_todo", arguments: "{\"id\":\"\(item.id)\",\"when\":\"今天下午四点\"}")
        #expect(obj(r1)["due"] as? String == "今天 16:00")
        let (r2, c2) = tools.execute(name: "complete_todo", arguments: "{\"id\":\"\(item.id)\"}")
        #expect(obj(r2)["left_today"] as? Int == 0)
        #expect(store.item(item.id)?.isDone == true)
        tools.undo(c2!)
        tools.undo(c1!)
        #expect(store.item(item.id)?.isDone == false)
        #expect(store.item(item.id)?.due == date("2026-10-23 15:00"))
    }

    @Test func 公司来源的待办就算知道id也改不了() {
        let (store, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cal = store.add(TodoItem(title: "周会", source: "calendar"))
        #expect(obj(tools.execute(name: "complete_todo", arguments: "{\"id\":\"\(cal.id)\"}").result)["error"] != nil)
        #expect(store.item(cal.id)?.isDone == false)
    }

    @Test func 参数不对和不存在的工具都返回错误() {
        let (_, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(obj(tools.execute(name: "add_todo", arguments: "{}").result)["error"] != nil)
        #expect(obj(tools.execute(name: "add_todo", arguments: "不是json").result)["error"] != nil)
        #expect(obj(tools.execute(name: "delete_todo", arguments: #"{"id":"x"}"#).result)["error"] != nil)
        #expect(obj(tools.execute(name: "show_expression", arguments: #"{"name":"dance"}"#).result)["error"] != nil)
        _ = tools.execute(name: "show_expression", arguments: #"{"name":"tap_blush"}"#)
        #expect(tools.expression == "tap_blush")
    }

    @Test func 删除只是提出来_不马上删_来源待办不能删() {
        let (store, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mine = store.add(text: "取快递", source: TodoSource.manual, now: now)!
        tools.register([mine.id])
        let (result, change) = tools.execute(name: "delete_todo", arguments: #"{"id":"\#(mine.id)"}"#)
        #expect(change == nil)
        #expect(result.contains("还没删"))
        #expect(store.items.count == 1)
        #expect(tools.pendingDeletes == [.init(id: mine.id, title: "取快递")])
        #expect(tools.execute(name: "delete_todo", arguments: #"{"id":"nope"}"#).result.contains("找不到"))
    }

    @Test func 撤销重复待办的打勾_排上的下一次一起撤掉() {
        let (store, tools, dir) = setup()
        defer { try? FileManager.default.removeItem(at: dir) }
        let water = store.add(text: "每天 喝水", now: now)!
        tools.register([water.id])
        let (_, change) = tools.execute(name: "complete_todo", arguments: #"{"id":"\#(water.id)"}"#)
        #expect(store.items.count == 2)
        tools.undo(change!)
        #expect(store.items.count == 1)
        #expect(store.item(water.id)?.isDone == false)
    }

    @Test func 工具定义是合法的JSON() throws {
        let data = try JSONSerialization.data(withJSONObject: AgentTools.definitions)
        #expect(data.count > 100)
        #expect(AgentTools.definitions.count == 6)
    }
}

struct AgentShareSourcesTests {
    @Test func 打开后能看能打勾_但改不了来源待办的时间() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-share-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("b"))
        var share = false
        let tools = AgentTools(store: store, now: { date("2026-10-23 14:30") }, includeSources: { share })
        let cal = store.add(TodoItem(title: "周会", due: date("2026-10-23 16:00"), dueHasTime: true, source: "calendar"))

        #expect(!tools.execute(name: "list_todos", arguments: #"{"scope":"today"}"#).result.contains("周会"))

        share = true
        let listed = tools.execute(name: "list_todos", arguments: #"{"scope":"today"}"#).result
        #expect(listed.contains("周会") && listed.contains("日历"))
        #expect(tools.execute(name: "reschedule_todo", arguments: "{\"id\":\"\(cal.id)\",\"when\":\"五点\"}").result.contains("日历里改"))
        _ = tools.execute(name: "complete_todo", arguments: "{\"id\":\"\(cal.id)\"}")
        #expect(store.item(cal.id)?.isDone == true)
    }
}
