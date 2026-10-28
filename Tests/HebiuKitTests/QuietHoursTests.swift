import Foundation
import Testing
@testable import HebiuKit

@Suite struct QuietHoursTests {
    @Test func 几段时间_跨午夜_写法宽松() {
        let q = QuietHours("12:00-13:30, 22:30~8")!
        #expect(q.contains(date("2026-10-26 12:10")))
        #expect(!q.contains(date("2026-10-26 13:30")))
        #expect(q.contains(date("2026-10-26 23:00")))
        #expect(q.contains(date("2026-10-26 07:59")))
        #expect(!q.contains(date("2026-10-26 08:00")))
        #expect(QuietHours("12点到13点") == nil)
        #expect(QuietHours("") == nil)
        #expect(QuietHours("12:00到13:00")?.ranges.count == 1)
    }
}
