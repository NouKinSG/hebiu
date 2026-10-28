import Foundation
import Testing
@testable import HebiuKit

private let now = date("2026-10-23 14:30")

private func item(_ title: String, _ due: String? = nil, hasTime: Bool = true, done: Bool = false, reminded: Bool = false) -> TodoItem {
    TodoItem(title: title, due: due.map(date), dueHasTime: due == nil ? false : hasTime, createdAt: date("2026-10-20"),
             doneAt: done ? now : nil, remindedAt: reminded ? now : nil)
}

struct ReminderPlannerTests {
    @Test func 到点提醒只挑该喊的() {
        let items = [
            item("到点了", "2026-10-23 14:30"),
            item("早过了", "2026-10-23 14:00"),
            item("太久以前", "2026-10-23 08:00"),          // 超过 6 小时不补喊
            item("还没到", "2026-10-23 15:00"),
            item("喊过了", "2026-10-23 14:10", reminded: true),
            item("做完了", "2026-10-23 14:10", done: true),
            item("只有日期", "2026-10-23", hasTime: false),
        ]
        #expect(ReminderPlanner.dueNow(items, now: now).map(\.title) == ["早过了", "到点了"])
    }

    @Test func 早上汇总每天一次_要在用电脑_今天有事才说() {
        let items = [item("开会", "2026-10-23 16:00"), item("买猫粮"), item("明天的", "2026-10-24 10:00")]
        let fresh = ReminderState()
        #expect(ReminderPlanner.morningSummary(items, now: now, state: fresh, enabled: true, userActive: true)?.map(\.title) == ["开会", "买猫粮"])
        #expect(ReminderPlanner.morningSummary(items, now: now, state: fresh, enabled: true, userActive: false) == nil)
        #expect(ReminderPlanner.morningSummary(items, now: now, state: fresh, enabled: false, userActive: true) == nil)
        let said = ReminderState(morningDay: "2026-10-23")
        #expect(ReminderPlanner.morningSummary(items, now: now, state: said, enabled: true, userActive: true) == nil)
        #expect(ReminderPlanner.morningSummary(items, now: date("2026-10-23 05:30"), state: fresh, enabled: true, userActive: true) == nil)
        #expect(ReminderPlanner.morningSummary([item("明天的", "2026-10-24 10:00")], now: now, state: fresh, enabled: true, userActive: true) == nil)
    }

    @Test func 下班提醒到点后一次() {
        let items = [item("交周报")]
        let six = DateComponents(hour: 18, minute: 0)
        let fresh = ReminderState()
        #expect(ReminderPlanner.eveningReminder(items, now: date("2026-10-23 17:59"), state: fresh, at: six, userActive: true) == nil)
        #expect(ReminderPlanner.eveningReminder(items, now: date("2026-10-23 18:20"), state: fresh, at: six, userActive: true)?.count == 1)
        #expect(ReminderPlanner.eveningReminder(items, now: date("2026-10-23 18:20"), state: ReminderState(eveningDay: "2026-10-23"),
                                                at: six, userActive: true) == nil)
        #expect(ReminderPlanner.eveningReminder(items, now: date("2026-10-23 18:20"), state: fresh, at: nil, userActive: true) == nil)
        #expect(ReminderPlanner.eveningReminder([], now: date("2026-10-23 18:20"), state: fresh, at: six, userActive: true) == nil)
    }

    @Test func 台词() {
        #expect(ReminderPlanner.dueLine([item("开会", "2026-10-23 14:30")]) == "⏰ 14:30 开会，到点啦！")
        #expect(ReminderPlanner.dueLine([item("开会", "2026-10-23 14:30"), item("喝水", "2026-10-23 14:30")])
                == "⏰ 14:30 开会，到点啦！还有 1 件也到点了")
        let four = (1...4).map { item("事\($0)") }
        #expect(ReminderPlanner.eveningLine(four) == "快下班啦，还有 4 件没做：事1、事2、事3 等")
        #expect(ReminderPlanner.morningLine([item("开会", "2026-10-23 10:00")], now: now) == "早呀～今天有 1 件事：开会（有 1 件已经过期了哦）")
    }

    @Test func 状态存取() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ReminderState.load(url: url) == ReminderState())
        ReminderState(morningDay: "2026-10-23", eveningDay: nil).save(url: url)
        #expect(ReminderState.load(url: url).morningDay == "2026-10-23")
    }
}
