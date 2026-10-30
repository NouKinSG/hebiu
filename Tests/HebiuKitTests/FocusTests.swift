import Foundation
import Testing
@testable import HebiuKit

@Suite struct FocusTests {
    @Test func 倒计时向上取整_显示分钟和秒() {
        #expect(FocusClock.clock(59.2) == "1:00")
        #expect(FocusClock.clock(1440) == "24:00")
        #expect(FocusClock.clock(0) == "0:00")
    }
}
