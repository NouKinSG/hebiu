import Foundation
import Testing
@testable import HebiuKit

@Suite struct ImportantDatesTests {
    @Test func 一句话认出日子() {
        let mom = ImportantDate.parse("妈妈生日 农历八月十五")!
        #expect(mom.title == "妈妈生日" && mom.lunar && mom.month == 8 && mom.day == 15)
        #expect(mom.dateText == "农历八月十五")
        let date1 = ImportantDate.parse("第一次约会 2024年5月20日")!
        #expect(date1.title == "第一次约会" && date1.month == 5 && date1.day == 20 && date1.year == 2024 && !date1.lunar)
        #expect(ImportantDate.parse("腊八 农历腊月初八")?.month == 12)
        #expect(ImportantDate.parse("结婚纪念日 10-01")?.day == 1)
        #expect(ImportantDate.parse("没有日期的话") == nil)
        #expect(ImportantDate.parse("3月8日") == nil)        // 没有名字
    }

    @Test func 公历和农历的下一次() {
        let now = date("2026-10-26 10:00")
        #expect(ImportantDate(title: "a", month: 10, day: 26).daysUntil(from: now) == 0)
        #expect(ImportantDate(title: "a", month: 10, day: 25).next(from: now) == date("2027-10-25"))
        // 2027 年中秋（农历八月十五）是 9 月 15 日
        #expect(ImportantDate(title: "中秋", month: 8, day: 15, lunar: true).next(from: now) == date("2027-09-15"))
        // 2027 年春节是 2 月 6 日
        #expect(ImportantDate(title: "春节", month: 1, day: 1, lunar: true).next(from: now) == date("2027-02-06"))
        #expect(ImportantDate(title: "a", month: 2, day: 29).next(from: date("2026-03-01")) == date("2027-02-28"))
        #expect(ImportantDate(title: "a", month: 5, day: 20, year: 2024).yearsAt(date("2027-05-20")) == 3)
    }

    @Test func 提前几天提醒_同一次只提醒一回() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ImportantDateStore(url: dir.appendingPathComponent("d.json"), stateURL: dir.appendingPathComponent("s.json"))
        store.add(ImportantDate(title: "妈妈生日", month: 11, day: 2))
        #expect(store.due(now: date("2026-10-25 09:00")).isEmpty)              // 还有 8 天
        #expect(store.due(now: date("2026-10-26 09:00")).map(\.days) == [7])
        #expect(store.due(now: date("2026-10-26 18:00")).isEmpty)              // 今天提醒过了
        #expect(store.due(now: date("2026-11-02 09:00")).map(\.days) == [0])
        // 重新读进来也记得提醒过
        let again = ImportantDateStore(url: dir.appendingPathComponent("d.json"), stateURL: dir.appendingPathComponent("s.json"))
        #expect(again.items.count == 1)
        #expect(again.due(now: date("2026-11-02 12:00")).isEmpty)
        #expect(again.upcoming(from: date("2026-10-26")).first?.days == 7)
    }
}
