import Foundation
import Testing
@testable import HebiuKit

@Suite struct HabitsTests {
    private func store() -> (HabitStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("habits-\(UUID().uuidString).json")
        return (HabitStore(url: url), url)
    }

    @Test func 一句话认出习惯() {
        let water = Habit.parse("喝水 每天晚上9点提醒", now: date("2026-10-26 10:00"))!
        #expect(water.title == "喝水" && water.emoji == "💧" && water.rule == "daily" && water.remindAt == "21:00")
        let gym = Habit.parse("健身 每周一三五")!
        #expect(gym.rule == "weekly:1,3,5" && gym.remindAt == nil && gym.emoji == "💪")
        #expect(Habit.parse("每天")?.title != "")
        #expect(Habit.parse("喝水，每天下午3点提醒我")?.title == "喝水")
        let fresh = HabitStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("h-\(UUID().uuidString).json"))
        let h = fresh.add(Habit(title: "跑步", createdAt: date("2026-10-24 12:00")))
        #expect(fresh.week(h.id, now: date("2026-10-25 20:00")).map(\.done) == [nil, nil, nil, nil, nil, false, false])
    }

    @Test func 打卡_连续天数_漏一天就断() {
        let (s, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let h = s.add(Habit(title: "喝水", createdAt: date("2026-10-01")))
        for d in ["2026-10-22", "2026-10-23", "2026-10-25"] { s.set(h.id, done: true, now: date(d + " 12:00")) }
        #expect(s.streak(h.id, now: date("2026-10-25 20:00")) == 1)          // 24 号漏了
        s.set(h.id, done: true, now: date("2026-10-24 12:00"))
        #expect(s.streak(h.id, now: date("2026-10-25 20:00")) == 4)
        #expect(s.streak(h.id, now: date("2026-10-26 10:00")) == 4)          // 今天还没打，从昨天算
        #expect(s.week(h.id, now: date("2026-10-25 20:00")).map(\.done) == [false, false, false, true, true, true, true])
        // 重新读进来还在
        #expect(HabitStore(url: url).streak(h.id, now: date("2026-10-24 20:00")) == 3)
        #expect(s.toggle(h.id, now: date("2026-10-26 01:00")) == false)     // 凌晨一点还算 25 号，再点是取消
        #expect(!s.isDone(h.id, on: "2026-10-25"))
    }

    @Test func 只在要做的日子算() {
        let (s, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let gym = s.add(Habit(title: "健身", rule: "weekly:1,3,5", createdAt: date("2026-10-01")))
        s.set(gym.id, done: true, now: date("2026-10-21 20:00"))   // 周三
        s.set(gym.id, done: true, now: date("2026-10-23 20:00"))   // 周五
        #expect(s.streak(gym.id, now: date("2026-10-25 20:00")) == 2)      // 周末不用做，不算断
        #expect(s.week(gym.id, now: date("2026-10-25 20:00")).filter { $0.done == nil }.count == 4)
        #expect(s.today(now: date("2026-10-26 09:00")).map(\.habit.title) == ["健身"])
        #expect(s.today(now: date("2026-10-25 09:00")).isEmpty)
    }

    @Test func 到点没打卡提醒一次_过了两小时不补() {
        let (s, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }
        let h = s.add(Habit(title: "喝水", remindAt: "21:00"))
        #expect(s.dueReminders(now: date("2026-10-26 20:59")).isEmpty)
        #expect(s.dueReminders(now: date("2026-10-26 21:05")).map(\.id) == [h.id])
        #expect(s.dueReminders(now: date("2026-10-26 21:30")).isEmpty)
        #expect(s.dueReminders(now: date("2026-10-27 23:30")).isEmpty)    // 太晚了
        s.set(h.id, done: true, now: date("2026-10-28 12:00"))
        #expect(s.dueReminders(now: date("2026-10-28 21:05")).isEmpty)    // 打过卡了
        #expect(s.find("水")?.id == h.id)
    }
}
