import Foundation
import Testing
@testable import HebiuKit

@Suite struct WeekReviewTests {
    @Test func 凑齐一周的数字_习惯只算加了之后到今天() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stats = Stats(url: dir.appendingPathComponent("s.json"))
        stats.bump(.todosDone, by: 3, now: date("2026-10-20 12:00"))
        stats.bump(.focus, by: 2, now: date("2026-10-22 12:00"))
        stats.bump(.focus, by: 9, now: date("2026-10-28 12:00"))          // 下周的不算
        let habits = HabitStore(url: dir.appendingPathComponent("h.json"))
        let h = habits.add(Habit(title: "喝水", createdAt: date("2026-10-21 09:00")))
        habits.set(h.id, done: true, now: date("2026-10-21 20:00"))
        habits.set(h.id, done: true, now: date("2026-10-23 20:00"))
        let moods = MoodStore(url: dir.appendingPathComponent("m.json"))
        moods.set(score: 5, note: "上线了", now: date("2026-10-23 22:00"))
        func ts(_ s: String) -> String { String(Int(date(s).timeIntervalSince1970)) }
        let events = dir.appendingPathComponent("events")
        try "\(ts("2026-10-22 21:00")) hello\n\(ts("2026-10-23 01:30")) done\n\(ts("2026-10-24 10:00")) hello\n"
            .write(to: events, atomically: true, encoding: .utf8)
        let done = TodoItem(title: "交周报", doneAt: date("2026-10-23 17:00"))
        let old = TodoItem(title: "上周的", doneAt: date("2026-10-15 17:00"))

        let r = WeekReview.build(now: date("2026-10-24 15:00"), stats: stats, habits: habits, moods: moods,
                                 todos: [done, old], events: events)
        #expect(r.key == "2026-W43")
        #expect(r.days.first == "2026-10-19" && r.days.last == "2026-10-25")
        #expect(r.total[.todosDone] == 3 && r.total[.focus] == 2)
        #expect(r.habits.first?.done == 2 && r.habits.first?.scheduled == 4)      // 21～24 号
        #expect(r.moods[4]?.score == 5)
        #expect(r.todosDone.map(\.title) == ["交周报"])
        #expect(r.codingDays == 2)
        #expect(r.latestFinish == date("2026-10-23 01:30"))
        #expect(r.material.contains("喝水 2/4") && r.material.contains("周五超开心（上线了）") && r.material.contains("交周报"))
    }
}
