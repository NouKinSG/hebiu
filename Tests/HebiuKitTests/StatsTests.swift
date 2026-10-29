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
    @Test func 专注恢复后只记一次_按实际完成日记账_兼容旧文件() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-stat-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("stats.json")
        try Data(#"{"days":{"2026-10-25":{"taps":2}}}"#.utf8).write(to: url)
        let s = Stats(url: url)
        let id = UUID(), end = date("2026-10-26 03:50")
        #expect(s.total()[.taps] == 2)
        #expect(try s.recordFocusCompletion(id: id, at: end))
        #expect(try !s.recordFocusCompletion(id: id, at: end))
        let loaded = Stats(url: url)
        #expect(try !loaded.recordFocusCompletion(id: id, at: end))
        #expect(loaded.day(date("2026-10-25 12:00"))[.focus] == 1)
        #expect(loaded.total()[.focus] == 1)
    }

    @Test func 专注统计写入失败不吞事件_恢复后能重试() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("focus-stat-fail-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("stats.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let stats = Stats(url: url), id = UUID(), end = date("2026-10-26 12:00")
        #expect(throws: (any Error).self) { try stats.recordFocusCompletion(id: id, at: end) }
        #expect(stats.total()[.focus] == nil)
        try FileManager.default.removeItem(at: url)
        #expect(try stats.recordFocusCompletion(id: id, at: end))
        #expect(Stats(url: url).total()[.focus] == 1)
    }

}
