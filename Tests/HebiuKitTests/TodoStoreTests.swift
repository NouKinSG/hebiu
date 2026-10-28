import Foundation
import Testing
@testable import HebiuKit

/// 每个测试一个独立目录，可以并行跑
private func makeStore() -> (TodoStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-todo-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("backup")), dir)
}

private let now = date("2026-10-23 14:30")

struct TodoStoreTests {
    @Test func 增删改查和打勾都会落盘() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = store.add(text: "15:00 开会", now: now)!
        let b = store.add(text: "买猫粮", now: now)!
        #expect(a.title == "开会" && a.dueHasTime)
        #expect(store.items.count == 2)

        store.update(b.id) { $0.title = "买猫粮和猫砂" }
        store.complete(a.id, at: now)
        let reloaded = TodoStore(url: store.url, backupDir: dir.appendingPathComponent("backup"))
        #expect(reloaded.item(b.id)?.title == "买猫粮和猫砂")
        #expect(reloaded.item(a.id)?.doneAt == now)

        reloaded.uncomplete(a.id)
        reloaded.delete(b.id)
        let again = TodoStore(url: store.url, backupDir: dir.appendingPathComponent("backup"))
        #expect(again.items.map(\.id) == [a.id])
        #expect(again.item(a.id)?.isDone == false)
    }

    @Test func 改了提醒时间会重新提醒() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = store.add(text: "15:00 开会", now: now)!
        store.markReminded([a.id], at: now)
        #expect(store.item(a.id)?.remindedAt != nil)
        store.update(a.id) { $0.title = "开周会" }
        #expect(store.item(a.id)?.remindedAt != nil)          // 只改标题不影响
        store.update(a.id) { $0.due = date("2026-10-23 16:00") }
        #expect(store.item(a.id)?.remindedAt == nil)
    }

    @Test func 已完成超过7天的自动清掉() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = store.add(TodoItem(title: "旧的", doneAt: now.addingTimeInterval(-8 * 86400)))
        let recent = store.add(TodoItem(title: "新的", doneAt: now.addingTimeInterval(-86400)))
        let open = store.add(TodoItem(title: "没做完", createdAt: now.addingTimeInterval(-30 * 86400)))
        store.purgeOldDone(now: now)
        #expect(Set(store.items.map(\.id)) == [recent.id, open.id])
        #expect(store.item(old.id) == nil)
    }

    @Test func 文件坏了不覆盖_挪到一边从空列表开始() throws {
        let (_, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("todo.json")
        try "{ 坏掉的".write(to: url, atomically: true, encoding: .utf8)
        let store = TodoStore(url: url, backupDir: dir.appendingPathComponent("backup"))
        #expect(store.items.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("todo.broken-") })
    }

    @Test func 运行中文件被改坏_保留最后一份好的并写回() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.add(TodoItem(title: "重要的事"))
        Thread.sleep(forTimeInterval: 1.1)                       // 修改时间精度到秒
        try "{ 手抖改坏了".write(to: store.url, atomically: true, encoding: .utf8)
        #expect(store.reloadIfChangedOnDisk())
        #expect(store.items.map(\.title) == ["重要的事"])
        #expect(TodoStore.readItems(url: store.url).map(\.title) == ["重要的事"])   // 写回磁盘了
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("todo.broken-") })               // 坏文件留着
    }

    @Test func 没有文件时建一个空的() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        store.ensureFile()
        #expect(FileManager.default.fileExists(atPath: store.url.path))
        #expect(store.items.isEmpty)
    }

    @Test func 旧格式缺字段也能读() throws {
        let (_, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("todo.json")
        try #"{"version":1,"items":[{"id":"t_1","title":"只有标题"}]}"#.write(to: url, atomically: true, encoding: .utf8)
        let store = TodoStore(url: url, backupDir: dir.appendingPathComponent("backup"))
        #expect(store.items.first?.title == "只有标题")
        #expect(store.items.first?.source == TodoSource.manual)
    }

    @Test func 每天第一次写之前备份() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.add(TodoItem(title: "一"))
        store.add(TodoItem(title: "二"))       // 这次写之前文件已存在，触发备份
        store.add(TodoItem(title: "三"))       // 同一天不再备份
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backup").path)
        #expect(backups.count == 1)
    }

    @Test func 按标题找没完成的() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.add(TodoItem(title: "交周报"))
        store.add(TodoItem(title: "交月报"))
        store.add(TodoItem(title: "周会"))
        #expect(store.findOpen(matching: "周报")?.title == "交周报")
        #expect(store.findOpen(matching: "周会")?.title == "周会")        // 完全相同优先
        #expect(store.findOpen(matching: "交") == nil)                  // 多条匹配不猜
    }

    @Test func 来源对账_新增更新删除_已完成的不复活() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.add(TodoItem(title: "手动的"))
        var r = store.reconcile(source: "gitlab", snapshot: [
            SourceItem(id: "mr-1", title: "Review A", link: "https://x/1"),
            SourceItem(id: "mr-2", title: "Review B"),
            SourceItem(id: "mr-3", title: "Review C"),
        ], now: now)
        #expect(r == (3, 0, 0))
        let c = store.items.first { $0.externalID == "mr-3" }!
        store.complete(c.id, at: now)

        r = store.reconcile(source: "gitlab", snapshot: [
            SourceItem(id: "mr-1", title: "Review A（改了标题）", link: "https://x/1"),
            SourceItem(id: "mr-3", title: "Review C"),
            SourceItem(id: "mr-4", title: "Review D"),
        ], now: now)
        #expect(r == (1, 1, 1))                                  // 加 D、改 A、删 B
        #expect(store.items.contains { $0.title == "Review A（改了标题）" })
        #expect(!store.items.contains { $0.externalID == "mr-2" })
        #expect(store.item(c.id)?.isDone == true)                // C 还在快照里，但已完成，不复活
        #expect(store.items.contains { $0.title == "手动的" })   // 别的来源不受影响
    }
}

struct TodoInboxTests {
    @Test func 命令行加完成撤销删除() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inboxDir = dir.appendingPathComponent("inbox")
        let inbox = TodoInbox(dir: inboxDir, store: store)

        try TodoInbox.post(.init(op: "add", text: "明天 10:00 交周报"), dir: inboxDir)
        try TodoInbox.post(.init(op: "add", title: "带链接的", link: "https://example.com"), dir: inboxDir)
        var out = inbox.process(now: now)
        #expect(out.count == 2)
        #expect(store.items.map(\.title) == ["交周报", "带链接的"])
        #expect(store.items[0].source == TodoSource.cli)

        try TodoInbox.post(.init(op: "done", match: "周报"), dir: inboxDir)
        out = inbox.process(now: now)
        guard case .completed(let done) = out.first else { Issue.record("没有完成"); return }
        #expect(done.isDone)

        try TodoInbox.post(.init(op: "undo", match: "周报"), dir: inboxDir)
        try TodoInbox.post(.init(op: "delete", match: "链接"), dir: inboxDir)
        try TodoInbox.post(.init(op: "done", match: "不存在的"), dir: inboxDir)
        out = inbox.process(now: now)
        #expect(out.count == 3)
        if case .failed = out[2] {} else { Issue.record("找不到的应该失败") }
        #expect(store.items.count == 1 && store.items[0].isDone == false)

        // 处理完的命令文件都删掉了
        let left = try FileManager.default.contentsOfDirectory(atPath: inboxDir.path).filter { $0.hasSuffix(".json") }
        #expect(left.isEmpty)
    }

    @Test func 已完成的也能删和撤销() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inboxDir = dir.appendingPathComponent("inbox")
        let inbox = TodoInbox(dir: inboxDir, store: store)
        let a = store.add(TodoItem(title: "买猫粮"))
        store.complete(a.id, at: now)
        store.add(TodoItem(title: "买猫砂"))
        try TodoInbox.post(.init(op: "delete", match: "猫粮"), dir: inboxDir)
        _ = inbox.process(now: now)
        #expect(store.items.map(\.title) == ["买猫砂"])
    }

    @Test func 坏文件挪到bad目录() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inboxDir = dir.appendingPathComponent("inbox")
        let inbox = TodoInbox(dir: inboxDir, store: store)
        try "不是 json".write(to: inboxDir.appendingPathComponent("x.json"), atomically: true, encoding: .utf8)
        let out = inbox.process(now: now)
        if case .failed = out.first {} else { Issue.record("应该失败") }
        #expect(FileManager.default.fileExists(atPath: inboxDir.appendingPathComponent("bad/x.json").path))
        #expect(!FileManager.default.fileExists(atPath: inboxDir.appendingPathComponent("x.json").path))
    }

    @Test func 来源快照只在变化时处理() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inboxDir = dir.appendingPathComponent("inbox")
        let inbox = TodoInbox(dir: inboxDir, store: store)
        try TodoInbox.publish(.init(source: "calendar", items: [
            SourceItem(id: "e1", title: "周会", due: date("2026-10-23 16:00")),
        ]), dir: inboxDir)
        #expect(inbox.process(now: now) == [.synced(source: "calendar", added: 1, updated: 0, removed: 0)])
        #expect(inbox.process(now: now).isEmpty)               // 文件没变，不重复处理
        Thread.sleep(forTimeInterval: 1.1)                      // 修改时间精度到秒
        try TodoInbox.publish(.init(source: "calendar", items: []), dir: inboxDir)
        #expect(inbox.process(now: now) == [.synced(source: "calendar", added: 0, updated: 0, removed: 1)])
        #expect(store.items.isEmpty)
    }
}
