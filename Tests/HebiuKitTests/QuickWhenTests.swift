import Foundation
import Testing
@testable import HebiuKit

@Suite struct QuickWhenTests {
    @Test func 快捷按钮算出来的时间() {
        let mon = date("2026-10-26 10:00")          // 周一
        #expect(QuickWhen.today.due(now: mon) == (date("2026-10-26"), false))
        #expect(QuickWhen.tonight.due(now: mon) == (date("2026-10-26 20:00"), true))
        #expect(QuickWhen.tonight.due(now: date("2026-10-26 20:40")).date == date("2026-10-26 22:00"))
        #expect(QuickWhen.tonight.due(now: date("2026-10-26 20:10")).date == date("2026-10-26 21:30"))
        #expect(!QuickWhen.tonight.available(now: date("2026-10-26 22:30")))
        #expect(QuickWhen.tomorrow.due(now: mon).date == date("2026-10-27"))
        #expect(QuickWhen.weekend.due(now: mon).date == date("2026-10-31"))
        #expect(QuickWhen.weekend.due(now: date("2026-11-01 10:00")).date == date("2026-11-01"))   // 周日就是今天
        #expect(QuickWhen.nextMonday.due(now: mon).date == date("2026-11-02"))
        #expect(QuickWhen.nextMonday.due(now: date("2026-11-01 10:00")).date == date("2026-11-02"))
        #expect(QuickWhen.set(date("2026-10-30 08:00"), hour: 18) == (date("2026-10-30 18:00"), true))
        #expect(QuickWhen.set(date("2026-10-30 08:00"), hour: nil) == (date("2026-10-30"), false))
        let choices = QuickWhen.repeatChoices(for: date("2026-10-30"))
        #expect(choices.map { $0?.display ?? "不重复" } == ["不重复", "每天", "工作日", "每周五", "每月 30 号", "每年 10 月 30 日"])
    }
}
