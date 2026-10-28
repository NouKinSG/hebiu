import Foundation
import Testing
@testable import HebiuKit

@Suite struct StatsTests {
    @Test func 按天记数_凌晨四点换天_合计和存盘() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = Stats(url: url)
        s.bump(.taps, now: date("2026-10-25 22:00"))
        s.bump(.taps, now: date("2026-10-26 01:30"))          // 还算 25 号
        s.bump(.focus, by: 2, now: date("2026-10-26 09:00"))
        #expect(s.day(date("2026-10-25 12:00"))[.taps] == 2)
        #expect(s.day(date("2026-10-26 12:00")) == [.focus: 2])
        #expect(s.total() == [.taps: 2, .focus: 2])
        #expect(s.firstDay == "2026-10-25")
        s.save()
        #expect(Stats(url: url).total() == [.taps: 2, .focus: 2])
    }

    @Test func 待办完成时通知一次_重复打勾不算() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stats-todo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("b"))
        var n = 0
        store.onCompleted = { _ in n += 1 }
        let item = store.add(text: "交周报", source: TodoSource.manual)!
        store.complete(item.id)
        store.complete(item.id)
        #expect(n == 1)
    }
}
