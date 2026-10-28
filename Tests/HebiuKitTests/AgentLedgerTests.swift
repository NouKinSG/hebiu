import Foundation
import Testing
@testable import HebiuKit

/// 北京时间
private func bj(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

struct AgentLedgerTests {
    let usage = AgentUsage(promptCacheHitTokens: 1792, promptCacheMissTokens: 356, completionTokens: 48)

    @Test func 近7天按天按用途_没花钱的日子也列出_老记录算聊天() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        // 早期没有 purpose 字段的一行
        try #"{"cost_cny":0.001,"model":"deepseek-flash","time":"2026-10-20T12:00:00Z","usage":{"completion_tokens":1,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":1}}"#
            .appending("\n").write(to: url, atomically: true, encoding: .utf8)
        let ledger = AgentLedger(url: url)
        ledger.record(usage, model: "m", at: date("2026-10-25 10:00"), purpose: .memory)
        ledger.record(usage, model: "m", at: date("2026-10-25 11:00"))
        ledger.record(usage, model: "m", at: date("2026-10-10 11:00"))        // 太早，不算
        let days = ledger.daily(last: 7, now: date("2026-10-25 23:00"))
        #expect(days.count == 7)
        #expect(days.first?.day == date("2026-10-19"))
        #expect(days.last?.requests == 2)
        #expect(days.last?.byPurpose[.memory] != nil && days.last?.byPurpose[.chat] != nil)
        #expect(days[1].byPurpose[.chat] == Decimal(string: "0.001"))
        #expect(days[2].total == 0)
    }

    @Test func 高峰和空闲时段() {
        #expect(AgentPricing.isPeak(bj("2026-10-23 10:00")))      // 周五上午
        #expect(AgentPricing.isPeak(bj("2026-10-23 17:59")))
        #expect(!AgentPricing.isPeak(bj("2026-10-23 12:30")))     // 午休
        #expect(!AgentPricing.isPeak(bj("2026-10-23 20:00")))     // 晚上
        #expect(!AgentPricing.isPeak(bj("2026-10-25 10:00")))     // 周日
    }

    @Test func 按官方价算钱() {
        // 1792×0.04 + 356×2 + 48×8 = 1167.68 → 0.00116768 元
        #expect(AgentPricing.deepseekFlash.cost(usage, at: bj("2026-10-23 10:00")) == Decimal(string: "0.00116768"))
        #expect(AgentPricing.deepseekFlash.cost(usage, at: bj("2026-10-23 20:00")) == Decimal(string: "0.00058384"))
    }

    @Test func 记账_按月合计_超上限() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-ledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = AgentLedger(url: dir.appendingPathComponent("usage.jsonl"))
        ledger.record(usage, model: "deepseek-flash", at: bj("2026-09-30 10:00"))
        ledger.record(usage, model: "deepseek-flash", at: bj("2026-10-23 10:00"))
        ledger.record(usage, model: "deepseek-flash", at: bj("2026-10-23 20:00"))
        #expect(ledger.entries().count == 3)
        #expect(ledger.total(monthOf: bj("2026-10-23 21:00")) == Decimal(string: "0.00175152"))
        #expect(ledger.total(monthOf: bj("2026-09-15 10:00")) == Decimal(string: "0.00116768"))
        #expect(ledger.withinBudget(30, now: bj("2026-10-23 21:00")))
        #expect(!ledger.withinBudget(Decimal(string: "0.001")!, now: bj("2026-10-23 21:00")))
        #expect(ledger.withinBudget(Decimal(string: "0.001")!, now: bj("2026-11-01 09:00")))   // 跨月清零
    }

    @Test func 坏行跳过不影响合计() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-ledger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("usage.jsonl")
        let ledger = AgentLedger(url: url)
        ledger.record(usage, model: "deepseek-flash", at: bj("2026-10-23 10:00"))
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile(); handle.write(Data("坏了的一行\n".utf8)); try handle.close()
        ledger.record(usage, model: "deepseek-flash", at: bj("2026-10-23 10:00"))
        #expect(ledger.entries().count == 2)
    }
}
