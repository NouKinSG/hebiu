import Foundation

/// 待办页上那排快捷按钮算出来的时间：今天、今晚、明天、这周末、下周一，和几个常用钟点
public enum QuickWhen: String, CaseIterable, Identifiable {
    case today, tonight, tomorrow, weekend, nextMonday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今天"
        case .tonight: return "今晚"
        case .tomorrow: return "明天"
        case .weekend: return "这周末"
        case .nextMonday: return "下周一"
        }
    }

    /// 只有今晚带钟点（20:00）；其余只到日期，当天早上的汇总里提
    public func due(now: Date = Date(), calendar cal: Calendar = .current) -> (date: Date, hasTime: Bool) {
        let today = cal.startOfDay(for: now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7 + 1      // 周一 = 1
        switch self {
        case .today: return (today, false)
        case .tonight:
            let eight = cal.date(bySettingHour: 20, minute: 0, second: 0, of: today)!
            // 已经过了八点：一小时后，取整到半点
            if now < eight { return (eight, true) }
            let later = now.addingTimeInterval(3600)
            let m = cal.component(.minute, from: later)
            return (cal.date(bySettingHour: cal.component(.hour, from: later), minute: m < 30 ? 30 : 0, second: 0, of: later)!
                .addingTimeInterval(m < 30 ? 0 : 3600), true)
        case .tomorrow: return (cal.date(byAdding: .day, value: 1, to: today)!, false)
        case .weekend:
            // 周一到周五：这周六；周六、周日：就是今天
            return (weekday >= 6 ? today : cal.date(byAdding: .day, value: 6 - weekday, to: today)!, false)
        case .nextMonday: return (cal.date(byAdding: .day, value: 8 - weekday, to: today)!, false)
        }
    }

    /// 今晚过了 22 点就不显示了
    public func available(now: Date = Date(), calendar cal: Calendar = .current) -> Bool {
        self != .tonight || cal.component(.hour, from: now) < 22
    }

    /// 常用钟点（编辑时选）
    public static let hours: [(hour: Int, minute: Int)] = [(9, 0), (14, 0), (18, 0), (20, 0)]

    /// 给某一天配上钟点；hour 为 nil 是全天
    public static func set(_ day: Date, hour: Int?, minute: Int = 0, calendar cal: Calendar = .current) -> (date: Date, hasTime: Bool) {
        let start = cal.startOfDay(for: day)
        guard let hour, let d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: start) else { return (start, false) }
        return (d, true)
    }

    /// 编辑里「重复」能选的：不重复、每天、工作日、每周（那天是周几）、每月（那天几号）、每年
    public static func repeatChoices(for day: Date?, calendar cal: Calendar = .current) -> [RepeatRule?] {
        var out: [RepeatRule?] = [nil, .daily, .workdays]
        if let day {
            let weekday = (cal.component(.weekday, from: day) + 5) % 7 + 1
            out.append(.weekly([weekday]))
            out.append(.monthly(cal.component(.day, from: day)))
            out.append(.yearly(month: cal.component(.month, from: day), day: cal.component(.day, from: day)))
        }
        return out
    }
}
