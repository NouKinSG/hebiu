import Foundation
import Testing
@testable import HebiuKit

struct TapReactionsTests {
    @Test func 连续两次不一样() {
        var taps = TapReactions()
        var last = ""
        let start = Date()
        for i in 0..<200 {
            // 每次隔 10 秒，不会触发「戳太多」
            let r = taps.next(now: start.addingTimeInterval(Double(i) * 10))
            #expect(r != last)
            last = r
        }
    }

    @Test func 每种反应都会出现_摸头最多() {
        var taps = TapReactions()
        var count: [String: Int] = [:]
        let start = Date()
        for i in 0..<2000 { count[taps.next(now: start.addingTimeInterval(Double(i) * 10)), default: 0] += 1 }
        #expect(Set(count.keys) == Set(TapReactions.defaultPool.map(\.event)))
        #expect(count["pat"]! == count.values.max())
    }

    @Test func 大约每N次说一句() {
        var taps = TapReactions()
        let talks = (0..<1000).filter { _ in taps.shouldTalk(every: 10) }.count
        #expect((70...140).contains(talks))                     // 平均约 100 次
        var never = TapReactions(), always = TapReactions()
        #expect(!(0..<50).contains { _ in never.shouldTalk(every: 0) })
        #expect((0..<50).allSatisfy { _ in always.shouldTalk(every: 1) })
    }

    @Test func 六秒内戳五下就鼓嘴() {
        var taps = TapReactions()
        let start = Date()
        let results = (0..<5).map { taps.next(now: start.addingTimeInterval(Double($0))) }
        #expect(results.last == "annoyed")
        #expect(!results.dropLast().contains("annoyed"))
        #expect(taps.next(now: start.addingTimeInterval(5)) != "annoyed")      // 鼓完嘴重新计数
    }
}
