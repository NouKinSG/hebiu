import Foundation
import Testing
@testable import HebiuKit

/// 基准时间：2026-10-23 周五 14:30
private let now = date("2026-10-23 14:30")

private func p(_ text: String) -> ParsedTodo { TimeParser.parse(text, now: now)! }

struct TimeParserTests {
    @Test(arguments: [
        ("15:00 开会", "开会", "2026-10-23 15:00"),
        ("开会 16：30", "开会", "2026-10-23 16:30"),
        ("3点开会", "开会", "2026-10-23 15:00"),               // 没说时段的 1～7 点按下午
        ("下午3点半 开会", "开会", "2026-10-23 15:30"),
        ("晚上8点 看电影", "看电影", "2026-10-23 20:00"),
        ("今晚 跑步", "跑步", "2026-10-23 20:00"),
        ("中午1点 吃饭", "吃饭", "2026-10-24 13:00"),         // 今天 13:00 已过，顺延到明天
        ("9:00 站会", "站会", "2026-10-24 09:00"),             // 已过，明天
        ("明天 10:00 交周报", "交周报", "2026-10-24 10:00"),
        ("明早 跑步", "跑步", "2026-10-24 09:00"),
        ("后天上午十点 体检", "体检", "2026-10-25 10:00"),
        ("周一 9点 例会", "例会", "2026-10-26 09:00"),
        ("下周五 下午两点 评审", "评审", "2026-10-30 14:00"),
        ("10月30日 15:00 体检", "体检", "2026-10-30 15:00"),
        ("提醒我明天晚上8点给妈妈打电话", "给妈妈打电话", "2026-10-24 20:00"),
        ("12点 午饭", "午饭", "2026-10-24 12:00"),
        ("十二点半 午饭", "午饭", "2026-10-24 12:30"),
        ("3点20 开会", "开会", "2026-10-23 15:20"),
    ])
    func 带钟点(text: String, title: String, due: String) {
        let r = p(text)
        #expect(r.title == title)
        #expect(r.due == date(due))
        #expect(r.hasTime)
    }

    @Test(arguments: [
        ("明天 交周报", "交周报", "2026-10-24"),
        ("周五 交报告", "交报告", "2026-10-23"),               // 今天就是周五
        ("周日 打扫", "打扫", "2026-10-25"),
        ("下周一 交材料", "交材料", "2026-10-26"),
        ("这周三 补材料", "补材料", "2026-10-21"),
        ("10-30 续费", "续费", "2026-10-30"),
        ("1月2日 体检", "体检", "2027-01-02"),                 // 今年已过，算明年
        ("2027-03-01 换证", "换证", "2027-03-01"),
    ])
    func 只有日期(text: String, title: String, day: String) {
        let r = p(text)
        #expect(r.title == title)
        #expect(r.due == date(day))
        #expect(!r.hasTime)
    }

    @Test(arguments: [
        ("30分钟后 拿外卖", "拿外卖", 30.0),
        ("半小时后喝水", "喝水", 30),
        ("2小时后 收衣服", "收衣服", 120),
        ("1个半小时后 出门", "出门", 90),
        ("两个小时以后 吃药", "吃药", 120),
        ("十分钟后 下楼", "下楼", 10),
    ])
    func 相对时间(text: String, title: String, minutes: Double) {
        let r = p(text)
        #expect(r.title == title)
        #expect(r.due == now.addingTimeInterval(minutes * 60))
        #expect(r.hasTime)
    }

    @Test(arguments: ["买猫粮", "快一点把文档写完", "看第3章", "版本 2.0 发布说明"])
    func 没有时间(text: String) {
        let r = p(text)
        #expect(r.title == text)
        #expect(r.due == nil)
    }

    @Test func 只有时间没有内容时标题用原文() {
        let r = p("明天 10:00")
        #expect(r.title == "明天 10:00")
        #expect(r.due == date("2026-10-24 10:00"))
    }

    @Test func 空字符串返回nil() {
        #expect(TimeParser.parse("   ", now: now) == nil)
    }

    @Test func 中文数字() {
        #expect(TimeParser.number("十") == 10)
        #expect(TimeParser.number("十二") == 12)
        #expect(TimeParser.number("二十三") == 23)
        #expect(TimeParser.number("两") == 2)
        #expect(TimeParser.number("半") == 0.5)
    }

    @Test func 显示文字() {
        #expect(TodoFormat.describe(date("2026-10-23 15:00"), hasTime: true, now: now) == "今天 15:00")
        #expect(TodoFormat.describe(date("2026-10-24"), hasTime: false, now: now) == "明天")
        #expect(TodoFormat.describe(date("2026-10-27 09:05"), hasTime: true, now: now) == "周二 09:05")
        #expect(TodoFormat.describe(date("2026-11-30"), hasTime: false, now: now) == "11月30日")
        #expect(TodoFormat.describe(date("2027-01-02"), hasTime: false, now: now) == "2027年1月2日")
    }
}
