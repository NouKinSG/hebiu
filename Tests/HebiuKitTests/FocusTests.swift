import Foundation
import Testing
@testable import HebiuKit

@Suite struct FocusTests {
    @Test func 专心_休息_回到空闲() {
        let f = FocusSession()
        let t0 = date("2026-10-25 10:00")
        f.start(minutes: 25, now: t0)
        #expect(f.isFocusing)
        #expect(f.tick(now: t0.addingTimeInterval(60), restMinutes: 5) == nil)
        #expect(FocusSession.clock(f.remaining(now: t0.addingTimeInterval(60))) == "24:00")
        #expect(abs(f.progress(now: t0.addingTimeInterval(750)) - 0.5) < 0.001)
        #expect(f.tick(now: t0.addingTimeInterval(25 * 60), restMinutes: 5) == .focusDone)
        #expect(!f.isFocusing && f.isActive)
        #expect(f.tick(now: t0.addingTimeInterval(30 * 60), restMinutes: 5) == .restDone)
        #expect(f.phase == .idle)
    }

    @Test func 不休息时专心完直接空闲_中途可以结束() {
        let f = FocusSession()
        let t0 = date("2026-10-25 10:00")
        f.start(minutes: 1, now: t0)
        #expect(f.tick(now: t0.addingTimeInterval(61), restMinutes: 0) == .focusDone)
        #expect(f.phase == .idle)
        f.start(minutes: 25, now: t0)
        f.stop()
        #expect(f.phase == .idle && f.remaining(now: t0) == 0)
        #expect(FocusSession.clock(59.2) == "1:00")
    }
}
