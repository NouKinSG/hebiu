import Foundation

/// 重复规则：每天、工作日、每周几、每月几号、每年几月几号。
/// 存成短字符串（daily / workdays / weekly:1,5 / monthly:15 / yearly:10-25），周一 = 1 … 周日 = 7
public enum RepeatRule: Hashable {
    case daily
    case workdays
    case weekly([Int])
    case monthly(Int)
    case yearly(month: Int, day: Int)

    // MARK: - 存取

    public init?(_ text: String?) {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "daily": self = .daily
        case "workdays": self = .workdays
        case "weekly":
            let days = (parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) }
            guard !days.isEmpty else { return nil }
            self = .weekly(Array(Set(days)).sorted())
        case "monthly":
            guard parts.count > 1, let d = Int(parts[1]), (1...31).contains(d) else { return nil }
            self = .monthly(d)
        case "yearly":
            let md = (parts.count > 1 ? parts[1] : "").split(separator: "-").compactMap { Int($0) }
            guard md.count == 2, (1...12).contains(md[0]), (1...31).contains(md[1]) else { return nil }
            self = .yearly(month: md[0], day: md[1])
        default: return nil
        }
    }

    public var text: String {
        switch self {
        case .daily: return "daily"
        case .workdays: return "workdays"
        case let .weekly(days): return "weekly:" + days.map(String.init).joined(separator: ",")
        case let .monthly(d): return "monthly:\(d)"
        case let .yearly(m, d): return "yearly:\(m)-\(d)"
        }
    }

    /// 「每周五」「工作日」「每月 15 号」
    public var display: String {
        let names = ["", "一", "二", "三", "四", "五", "六", "日"]
        switch self {
        case .daily: return "每天"
        case .workdays: return "工作日"
        case let .weekly(days): return "每周" + days.map { names[$0] }.joined(separator: "、")
        case let .monthly(d): return "每月 \(d) 号"
        case let .yearly(m, d): return "每年 \(m) 月 \(d) 日"
        }
    }

    // MARK: - 下一次

    /// 这一天符不符合规则
    public func matches(_ day: Date, calendar cal: Calendar = .current) -> Bool {
        let weekday = (cal.component(.weekday, from: day) + 5) % 7 + 1
        switch self {
        case .daily: return true
        case .workdays: return weekday <= 5
        case let .weekly(days): return days.contains(weekday)
        case let .monthly(d):
            // 31 号这种，小月就落在月底那天
            let last = cal.range(of: .day, in: .month, for: day)?.count ?? 31
            return cal.component(.day, from: day) == min(d, last)
        case let .yearly(m, d):
            return cal.component(.month, from: day) == m && cal.component(.day, from: day) == d
        }
    }

    /// 严格晚于 after 的下一次；hour 为 nil 时只有日期（当天 0 点）
    public func next(after: Date, hour: Int?, minute: Int, calendar cal: Calendar = .current) -> Date? {
        var day = cal.startOfDay(for: after)
        for _ in 0..<(366 * 5) {
            if matches(day, calendar: cal) {
                let at = hour.flatMap { cal.date(bySettingHour: $0, minute: minute, second: 0, of: day) } ?? day
                if at > after { return at }
            }
            guard let d = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = d
        }
        return nil
    }

    // MARK: - 从一句话里认出来

    /// 认出「每天」「工作日」「每周一三五」「每月15号」「每年10月25日」，返回规则和去掉这部分后的句子
    public static func extract(_ text: String) -> (rule: RepeatRule, rest: String)? {
        let ns = text as NSString
        func find(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        }
        func removed(_ m: NSTextCheckingResult) -> String { ns.replacingCharacters(in: m.range, with: " ") }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        if let m = find("每年\\s*(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]?"),
           let mo = Int(group(m, 1) ?? ""), let d = Int(group(m, 2) ?? ""), (1...12).contains(mo), (1...31).contains(d) {
            return (.yearly(month: mo, day: d), removed(m))
        }
        if let m = find("每(?:个)?月\\s*(\\d{1,2}|[一二三四五六七八九十]{1,3})\\s*[日号]"),
           let d = TimeParser.number(group(m, 1)).map({ Int($0) }), (1...31).contains(d) {
            return (.monthly(d), removed(m))
        }
        if let m = find("每个?工作日|工作日|每?周一到周五|每?星期一到星期五") {
            return (.workdays, removed(m))
        }
        if let m = find("每(?:个)?(?:周|星期|礼拜)([一二三四五六日天1-7](?:\\s*[、和,，及]?\\s*(?:周|星期)?[一二三四五六日天1-7])*)") {
            let names: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7,
                                           "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7]
            let days = (group(m, 1) ?? "").compactMap { names[$0] }
            if !days.isEmpty { return (.weekly(Array(Set(days)).sorted()), removed(m)) }
        }
        if let m = find("(?:每天|每日|天天|每晚|每天晚上|每早|每天早上)") {
            let word = ns.substring(with: m.range)
            // 「每晚」「每天早上」的时段留给时间识别
            let keep = word.hasSuffix("晚上") || word == "每晚" ? "晚上" : word.hasSuffix("早上") || word == "每早" ? "早上" : ""
            return (.daily, ns.replacingCharacters(in: m.range, with: " \(keep) "))
        }
        return nil
    }
}
