import Foundation
import Testing
@testable import HebiuKit

@Suite struct ScheduledTaskTests {
    @Test func 一句话认出定时任务() {
        let t = ScheduledTask.parse("每天早上8点 用一句话鼓励我")!
        #expect(t.prompt == "用一句话鼓励我" && t.rule == "daily" && t.time == "08:00")
        let w = ScheduledTask.parse("每周五下午6点帮我总结这周")!
        #expect(w.rule == "weekly:5" && w.time == "18:00" && w.prompt == "帮我总结这周")
        #expect(ScheduledTask.parse("用一句话鼓励我") == nil)          // 没说几点
        #expect(ScheduledTask.parse("晚上11点 催我睡觉")?.rule == "daily")
    }

    @Test func 到点做一次_不在那天不做_过了两小时不补() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = ScheduledTaskStore(url: url)
        let fri = s.add(ScheduledTask(prompt: "总结这周", rule: "weekly:5", time: "18:00"))
        let daily = s.add(ScheduledTask(prompt: "鼓励我", rule: "daily", time: "08:00"))
        #expect(s.due(now: date("2026-10-30 07:59")).isEmpty)
        #expect(s.due(now: date("2026-10-30 08:01")).map(\.id) == [daily.id])
        #expect(s.due(now: date("2026-10-30 08:30")).isEmpty)
        #expect(s.due(now: date("2026-10-30 18:05")).map(\.id) == [fri.id])
        #expect(s.due(now: date("2026-10-29 18:05")).isEmpty)              // 周四
        #expect(s.due(now: date("2026-10-31 11:00")).isEmpty)              // 8 点的过了两小时
        s.setEnabled(daily.id, false)
        #expect(ScheduledTaskStore(url: url).due(now: date("2026-11-01 08:01")).isEmpty)
    }
}
