import Foundation
import Testing
@testable import HebiuKit

@Suite struct MoodTests {
    @Test func 一天一条_再记覆盖_晚上问一次() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moods-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = MoodStore(url: url)
        #expect(s.shouldAsk(now: date("2026-10-25 20:00")) == false)
        #expect(s.shouldAsk(now: date("2026-10-25 21:10")) == true)
        #expect(s.shouldAsk(now: date("2026-10-25 22:00")) == false)          // 问过了
        s.set(score: 2, note: "加班", now: date("2026-10-25 22:00"))
        let before = s.set(score: 4, now: date("2026-10-26 01:00"))            // 还算 25 号
        #expect(before?.score == 2)
        #expect(MoodStore(url: url).mood(on: "2026-10-25")?.emoji == "🙂")
        #expect(s.recent(3, now: date("2026-10-26 10:00")).map { $0.mood?.score } == [nil, 4, nil])
        s.restore(before, day: "2026-10-25")
        #expect(s.mood(on: "2026-10-25")?.note == "加班")
        #expect(Mood(score: 9).score == 5)
    }

    @Test func 工具记心情可撤销() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mood-tools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("b"))
        let moods = MoodStore(url: dir.appendingPathComponent("m.json"))
        let now = date("2026-10-25 22:00")
        let tools = AgentTools(store: store, now: { now }, moods: moods)
        let (_, change) = tools.execute(name: "log_mood", arguments: #"{"score":5,"note":"周报写完了"}"#)
        #expect(moods.today(now)?.name == "超开心")
        tools.undo(change!)
        #expect(moods.today(now) == nil)
        #expect(tools.execute(name: "log_mood", arguments: #"{"score":8}"#).result.contains("1～5"))
    }
}
