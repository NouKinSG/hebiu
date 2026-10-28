import Foundation

/// 一句话识别出来的待办
public struct ParsedTodo: Equatable {
    public var title: String
    public var due: Date?
    /// false：只有日期没有钟点（「明天 交周报」）
    public var hasTime: Bool
}

/// 从一句中文里认出时间，剩下的部分当标题。
/// 支持：15:00、3点半、下午3点、晚上8点、明天/后天/大后天、今晚/明早、周五/下周一、10月30日、10-30、30分钟后、2小时后、半小时后
public enum TimeParser {
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedTodo? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        let cal = calendar

        // 1. 相对时间：「30分钟后」「1个半小时后」
        if let m = firstMatch(relativePattern, in: rest) {
            let amount = number(m.group(1)) ?? 0
            let half = m.group(2) != nil ? 0.5 : 0
            let unit = m.group(3) ?? ""
            let minutes = unit.hasPrefix("分") ? amount + half : (amount + half) * 60
            if minutes > 0 {
                rest = m.removed
                return ParsedTodo(title: cleanTitle(rest, fallback: text), due: now.addingTimeInterval(minutes * 60), hasTime: true)
            }
        }

        // 2. 日期
        var day: Date?
        var impliedPeriod: String?
        if let m = firstMatch(fullDatePattern, in: rest),
           let y = Int(m.group(1) ?? ""), let mo = Int(m.group(2) ?? ""), let d = Int(m.group(3) ?? ""),
           let date = cal.date(from: DateComponents(year: y, month: mo, day: d)), validDay(date, mo, d, cal) {
            day = date
            rest = m.removed
        } else if let m = firstMatch(monthDayPattern, in: rest) ?? firstMatch(slashDatePattern, in: rest),
                  let mo = Int(m.group(1) ?? ""), let d = Int(m.group(2) ?? ""),
                  var date = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: mo, day: d)),
                  validDay(date, mo, d, cal) {
            if date < cal.startOfDay(for: now) { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
            day = date
            rest = m.removed
        } else if let m = firstMatch(weekdayPattern, in: rest), let w = weekdayNumber(m.group(3)) {
            day = weekday(w, prefix: m.group(1) ?? "", now: now, cal: cal)
            rest = m.removed
        } else if let m = firstMatch(relativeDayPattern, in: rest), let word = m.group(1) {
            let offsets = ["大后天": 3, "后天": 2, "明天": 1, "明日": 1, "明早": 1, "明晚": 1, "今天": 0, "今日": 0, "今晚": 0, "今早": 0]
            day = cal.date(byAdding: .day, value: offsets[word] ?? 0, to: cal.startOfDay(for: now))
            if word.hasSuffix("晚") { impliedPeriod = "晚上" }
            if word.hasSuffix("早") { impliedPeriod = "早上" }
            rest = m.removed
        }

        // 3. 时段
        var period = impliedPeriod
        if let m = firstMatch(periodPattern, in: rest) {
            period = m.group(1)
            rest = m.removed
        }

        // 4. 钟点
        var hour: Int?
        var minute = 0
        if let m = firstMatch(colonTimePattern, in: rest), let h = Int(m.group(1) ?? ""), let mi = Int(m.group(2) ?? ""),
           (0...23).contains(h), (0...59).contains(mi) {
            hour = h
            minute = mi
            rest = m.removed
        } else if let m = firstMatch(chineseTimePattern, in: rest), let h = number(m.group(1)).map({ Int($0) }), (0...24).contains(h) {
            hour = h == 24 ? 0 : h
            switch m.group(2) {
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            default: minute = Int(m.group(3) ?? "") ?? 0
            }
            rest = m.removed
        }
        if hour == nil, let period { hour = defaultHour[period] }
        if var h = hour { hour = adjust(hour: &h, period: period) }

        let title = cleanTitle(rest, fallback: text)
        guard hour != nil || day != nil else { return ParsedTodo(title: title, due: nil, hasTime: false) }

        let base = day ?? cal.startOfDay(for: now)
        guard let h = hour else { return ParsedTodo(title: title, due: base, hasTime: false) }
        guard var due = cal.date(bySettingHour: h, minute: minute, second: 0, of: base) else {
            return ParsedTodo(title: title, due: base, hasTime: false)
        }
        // 只说了钟点、今天已经过了，就是明天
        if day == nil, due <= now { due = cal.date(byAdding: .day, value: 1, to: due) ?? due }
        return ParsedTodo(title: title, due: due, hasTime: true)
    }

    // MARK: - 规则

    private static let num = "(\\d{1,3}|[零一二两三四五六七八九十]{1,3}|半)"
    private static let relativePattern = "\(num)\\s*个?\\s*(半)?\\s*(分钟|分|小时|钟头)\\s*(?:后|以后|之后)"
    private static let fullDatePattern = "(\\d{4})\\s*[-/年.]\\s*(\\d{1,2})\\s*[-/月.]\\s*(\\d{1,2})\\s*[日号]?"
    private static let monthDayPattern = "(\\d{1,2})\\s*月\\s*(\\d{1,2})\\s*[日号]?"
    private static let slashDatePattern = "(?<![\\d:：])(\\d{1,2})[/-](\\d{1,2})(?![\\d:：])"
    private static let weekdayPattern = "(下下|下|这|本)?(周|星期|礼拜)([一二三四五六日天1-7])"
    private static let relativeDayPattern = "(大后天|后天|明天|明日|明早|明晚|今天|今日|今晚|今早)"
    private static let periodPattern = "(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|夜里)"
    private static let colonTimePattern = "(?<!\\d)(\\d{1,2})[:：](\\d{2})(?!\\d)"
    private static let chineseTimePattern = "(?<![快慢早晚多少差好有])(\\d{1,2}|[零一二两三四五六七八九十]{1,3})\\s*点\\s*(半|一刻|三刻|(\\d{1,2})\\s*分?)?"

    /// 只说了时段没说钟点时用的默认钟点
    private static let defaultHour = ["凌晨": 6, "早上": 9, "早晨": 9, "上午": 10, "中午": 12, "下午": 15, "傍晚": 18, "晚上": 20, "夜里": 22]

    /// 「下午3点」→15；没说时段的 1～7 点按下午算（「3点开会」一般是 15:00）
    private static func adjust(hour h: inout Int, period: String?) -> Int {
        switch period {
        case "下午", "傍晚", "晚上", "夜里":
            if h < 12 { h += 12 }
        case "中午":
            if h <= 2 { h += 12 }
        case "凌晨", "早上", "早晨", "上午":
            if h == 12 { h = 0 }
        default:
            if (1...7).contains(h) { h += 12 }
        }
        return h
    }

    private static func validDay(_ date: Date, _ month: Int, _ day: Int, _ cal: Calendar) -> Bool {
        cal.component(.month, from: date) == month && cal.component(.day, from: date) == day
    }

    private static func weekdayNumber(_ s: String?) -> Int? {
        guard let s else { return nil }
        if let n = Int(s), (1...7).contains(n) { return n }
        return ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7][s]
    }

    /// 周一=1 … 周日=7。「周五」：今天起最近的周五（今天就是周五就是今天）；「下周五」：下周的周五；「这周五」：本周的周五
    private static func weekday(_ target: Int, prefix: String, now: Date, cal: Calendar) -> Date? {
        let today = cal.startOfDay(for: now)
        let iso = (cal.component(.weekday, from: today) + 5) % 7 + 1
        let offset: Int
        switch prefix {
        case "下": offset = (8 - iso) + (target - 1)
        case "下下": offset = (8 - iso) + 7 + (target - 1)
        case "这", "本": offset = target - iso
        default: offset = (target - iso + 7) % 7
        }
        return cal.date(byAdding: .day, value: offset, to: today)
    }

    /// 阿拉伯数字或简单中文数字（一～九十九、两、半）
    static func number(_ s: String?) -> Double? {
        guard let s, !s.isEmpty else { return nil }
        if let n = Double(s) { return n }
        if s == "半" { return 0.5 }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let i = s.firstIndex(of: "十") {
            let tens = s[..<i].isEmpty ? 1 : digits[s[s.startIndex]] ?? -100
            let after = s[s.index(after: i)...]
            let ones = after.isEmpty ? 0 : digits[after.first!] ?? -100
            let n = tens * 10 + ones
            return n >= 0 ? Double(n) : nil
        }
        return s.count == 1 ? digits[s.first!].map(Double.init) : nil
    }

    /// 去掉时间之后的标题：合并空白，去掉首尾的标点和「提醒我」「记得」之类的口头语
    private static func cleanTitle(_ s: String, fallback: String) -> String {
        var t = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let junk = CharacterSet(charactersIn: " ，,。.：:；;、的在到-—~～").union(.whitespacesAndNewlines)
        t = t.trimmingCharacters(in: junk)
        for prefix in ["提醒我", "记得要", "记得", "要"] where t.hasPrefix(prefix) && t.count > prefix.count {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: junk)
        }
        let clean = t.trimmingCharacters(in: junk)
        return clean.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : clean
    }

    // MARK: - 正则小工具

    private struct Match {
        let groups: [String?]
        let removed: String
        func group(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func firstMatch(_ pattern: String, in text: String) -> Match? {
        cacheLock.lock()
        let regex = cache[pattern] ?? (try? NSRegularExpression(pattern: pattern))
        cache[pattern] = regex
        cacheLock.unlock()
        let ns = text as NSString
        guard let regex, let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groups = (0..<m.numberOfRanges).map { i -> String? in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        return Match(groups: groups, removed: ns.replacingCharacters(in: m.range, with: " "))
    }
}

/// 待办时间的显示文字
public enum TodoFormat {
    /// 「今天 15:00」「明天」「周五 10:00」「10月30日」「2027年1月2日」
    public static func describe(_ due: Date, hasTime: Bool, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let today = cal.startOfDay(for: now)
        let day = cal.startOfDay(for: due)
        let diff = cal.dateComponents([.day], from: today, to: day).day ?? 0
        let dayText: String
        switch diff {
        case 0: dayText = "今天"
        case 1: dayText = "明天"
        case 2: dayText = "后天"
        case -1: dayText = "昨天"
        case 3...6:
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            dayText = names[cal.component(.weekday, from: due) - 1]
        default:
            let m = cal.component(.month, from: due), d = cal.component(.day, from: due), y = cal.component(.year, from: due)
            dayText = y == cal.component(.year, from: now) ? "\(m)月\(d)日" : "\(y)年\(m)月\(d)日"
        }
        guard hasTime else { return dayText }
        return dayText + " " + String(format: "%02d:%02d", cal.component(.hour, from: due), cal.component(.minute, from: due))
    }
}

extension TodoFormat {
    /// 「10月25日 周日」
    public static func weekdayDate(_ date: Date, calendar cal: Calendar = .current) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日 \(names[cal.component(.weekday, from: date) - 1])"
    }
}
