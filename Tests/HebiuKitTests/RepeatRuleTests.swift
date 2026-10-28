import Foundation
import Testing
@testable import HebiuKit

@Suite struct RepeatRuleTests {
    // 2026-10-25 是周日
    let now = date("2026-10-25 20:00")

    @Test(arguments: [
        ("每周五下午五点 交周报", "weekly:5", "交周报", "2026-10-30 17:00"),
        ("每天晚上十点吃维生素", "daily", "吃维生素", "2026-10-25 22:00"),
        ("每晚11点 洗漱", "daily", "洗漱", "2026-10-25 23:00"),
        ("工作日早上9点 打卡", "workdays", "打卡", "2026-10-26 09:00"),
        ("每周一三五 健身", "weekly:1,3,5", "健身", "2026-10-26"),
        ("每月15号 还信用卡", "monthly:15", "还信用卡", "2026-11-15"),
        ("每年3月8日 给妈妈买花", "yearly:3-8", "给妈妈买花", "2027-03-08"),
        ("每天 喝水", "daily", "喝水", "2026-10-25"),
    ])
    func 一句话认出重复和第一次(text: String, rule: String, title: String, first: String) {
        let p = TodoStore.parse(text, now: now)!
        #expect(p.rule?.text == rule)
        #expect(p.title == title)
        #expect(p.due == date(first))
        #expect(p.hasTime == first.contains(":"))
    }

    @Test func 不重复的照旧() {
        let p = TodoStore.parse("明天下午三点 开会", now: now)!
        #expect(p.rule == nil)
        #expect(p.due == date("2026-10-26 15:00"))
    }

    @Test func 存取和显示() {
        #expect(RepeatRule("weekly:5,1")?.display == "每周一、五")
        #expect(RepeatRule("monthly:31").map { $0.next(after: date("2026-11-01"), hour: nil, minute: 0) } == date("2026-11-30"))
        #expect(RepeatRule("nonsense") == nil)
        #expect(RepeatRule("weekly:9") == nil)
    }

    @Test func 打勾排上下一次_取消打勾撤掉_拖了几天从今天往后排() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("repeat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("b"))
        let item = store.add(text: "每周五下午五点 交周报", now: now)!
        store.complete(item.id, at: date("2026-10-30 17:30"))
        let next = store.items.first { $0.repeatOf == item.id }
        #expect(next?.due == date("2026-11-06 17:00"))
        #expect(next?.repeatRule == "weekly:5" && next?.isDone == false)
        // 打两次勾也只排一次
        store.uncomplete(item.id)
        #expect(!store.items.contains { $0.repeatOf == item.id })
        store.complete(item.id, at: date("2026-11-12 09:00"))    // 拖到下下周四才打勾
        #expect(store.items.first { $0.repeatOf == item.id }?.due == date("2026-11-13 17:00"))
        #expect(store.items.filter { $0.repeatOf == item.id }.count == 1)

        let water = store.add(text: "每天 喝水", now: now)!
        store.complete(water.id, at: date("2026-10-25 21:00"))
        #expect(store.items.first { $0.repeatOf == water.id }?.due == date("2026-10-26"))
    }
}
