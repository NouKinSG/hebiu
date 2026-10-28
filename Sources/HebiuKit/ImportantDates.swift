import Foundation

/// 一个重要日子：妈妈生日、第一次约会……每年都过；可以是农历
public struct ImportantDate: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var month: Int
    public var day: Int
    /// 知道是哪一年时填（算「第几年」「几岁」）
    public var year: Int?
    public var lunar: Bool
    /// 提前几天提醒，0 是当天
    public var remindDays: [Int]

    public init(id: String = "d_" + UUID().uuidString.prefix(8).lowercased(), title: String, month: Int, day: Int,
                year: Int? = nil, lunar: Bool = false, remindDays: [Int] = [7, 1, 0]) {
        self.id = id
        self.title = title
        self.month = month
        self.day = day
        self.year = year
        self.lunar = lunar
        self.remindDays = remindDays
    }

    /// 「农历八月十五」「3 月 8 日」
    public var dateText: String {
        if lunar { return "农历" + LunarText.month(month) + LunarText.day(day) }
        return "\(month) 月 \(day) 日"
    }

    /// 今天起（含今天）下一次是哪天
    public func next(from now: Date, calendar cal: Calendar = .current) -> Date? {
        let today = cal.startOfDay(for: now)
        if !lunar {
            let y = cal.component(.year, from: today)
            for year in [y, y + 1] {
                // 2 月 29 日这种，平年落在 2 月 28 日
                var comps = DateComponents(year: year, month: month, day: day)
                if month == 2, day == 29, cal.range(of: .day, in: .month, for: cal.date(from: DateComponents(year: year, month: 2))!)?.count == 28 {
                    comps.day = 28
                }
                if let d = cal.date(from: comps), d >= today { return d }
            }
            return nil
        }
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = cal.timeZone
        var d = today
        for _ in 0..<400 {
            let c = chinese.dateComponents([.month, .day], from: d)
            if c.month == month, c.isLeapMonth != true {
                // 农历三十，小月没有三十就落在廿九
                let last = chinese.range(of: .day, in: .month, for: d)?.count ?? 30
                if c.day == min(day, last) { return d }
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return nil
    }

    /// 还有几天（今天是 0）
    public func daysUntil(from now: Date, calendar cal: Calendar = .current) -> Int? {
        guard let next = next(from: now, calendar: cal) else { return nil }
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: next).day
    }

    /// 下一次是第几年（知道年份时）
    public func yearsAt(_ date: Date, calendar cal: Calendar = .current) -> Int? {
        guard let year else { return nil }
        let y = lunar ? Calendar(identifier: .gregorian).component(.year, from: date) : cal.component(.year, from: date)
        return y - year
    }

    // MARK: - 从一句话里认出来

    /// 「妈妈生日 农历八月十五」「第一次约会 2024年5月20日」「结婚纪念日 10-01」
    public static func parse(_ text: String) -> ImportantDate? {
        let ns = text as NSString
        func find(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        func title(without m: NSTextCheckingResult) -> String {
            ns.replacingCharacters(in: m.range, with: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ，,。：:是的在").union(.whitespaces))
        }
        if let m = find("(?:农历|阴历)\\s*([正一二三四五六七八九十冬腊]{1,2}|十一|十二)\\s*月\\s*(初[一二三四五六七八九十]|十[一二三四五六七八九]?|二十|廿[一二三四五六七八九]|三十|\\d{1,2})"),
           let mo = LunarText.monthNumber(group(m, 1)), let d = LunarText.dayNumber(group(m, 2)) {
            let t = title(without: m)
            return t.isEmpty ? nil : ImportantDate(title: t, month: mo, day: d, lunar: true)
        }
        if let m = find("(?:(\\d{4})\\s*[年./-]\\s*)?(\\d{1,2})\\s*[月./-]\\s*(\\d{1,2})\\s*[日号]?"),
           let mo = Int(group(m, 2) ?? ""), let d = Int(group(m, 3) ?? ""), (1...12).contains(mo), (1...31).contains(d) {
            let t = title(without: m)
            return t.isEmpty ? nil : ImportantDate(title: t, month: mo, day: d, year: group(m, 1).flatMap { Int($0) })
        }
        return nil
    }
}

extension ImportantDate {
    /// 「我们」页填的在一起的日子和她的生日，也当重要日子算倒数；当天的庆祝由陪伴提醒做，这里只提前提醒
    public static func builtIns(_ s: Config.Settings) -> [ImportantDate] {
        var out: [ImportantDate] = []
        if let t = s.together, let m = t.month, let d = t.day {
            out.append(ImportantDate(id: "builtin-together", title: "在一起的纪念日", month: m, day: d, year: t.year, remindDays: [7, 1]))
        }
        if let b = s.birthday, let m = b.month, let d = b.day {
            out.append(ImportantDate(id: "builtin-birthday", title: "\(CharacterPack.she)的生日", month: m, day: d, remindDays: [7, 1]))
        }
        return out
    }

    public var isBuiltIn: Bool { id.hasPrefix("builtin-") }
}

/// 农历的月、日怎么写
public enum LunarText {
    static let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    static let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    public static func month(_ m: Int) -> String { (1...12).contains(m) ? months[m - 1] + "月" : "\(m)月" }

    public static func day(_ d: Int) -> String {
        switch d {
        case 1...10: return "初" + digits[d]
        case 11...19: return "十" + digits[d - 10]
        case 20: return "二十"
        case 21...29: return "廿" + digits[d - 20]
        case 30: return "三十"
        default: return "\(d)"
        }
    }

    static func monthNumber(_ s: String?) -> Int? {
        guard let s else { return nil }
        if let i = months.firstIndex(of: s) { return i + 1 }
        return ["一": 1, "十一": 11, "十二": 12][s]
    }

    static func dayNumber(_ s: String?) -> Int? {
        guard let s else { return nil }
        if let n = Int(s), (1...30).contains(n) { return n }
        return (1...30).first { day($0) == s }
    }
}

/// 重要日子都存在 ~/.hebiu/dates.json；提醒过哪些记在 dates-state.json，同一次提醒不重复
public final class ImportantDateStore {
    public let url: URL
    private let stateURL: URL
    public private(set) var items: [ImportantDate] = []
    private var reminded: Set<String> = []

    public init(url: URL = Paths.dataDir.appendingPathComponent("dates.json"),
                stateURL: URL = Paths.dataDir.appendingPathComponent("dates-state.json")) {
        self.url = url
        self.stateURL = stateURL
        load()
    }

    public func load() {
        items = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([ImportantDate].self, from: $0) } ?? []
        reminded = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    @discardableResult
    public func add(_ date: ImportantDate) -> ImportantDate {
        items.append(date)
        save()
        return date
    }

    public func delete(_ id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    /// 按还有几天排
    public func upcoming(from now: Date = Date(), extra: [ImportantDate] = []) -> [(date: ImportantDate, days: Int)] {
        (items + extra).compactMap { d in d.daysUntil(from: now).map { (d, $0) } }.sorted { $0.days < $1.days }
    }

    /// 今天该提醒的：还有几天正好在 remindDays 里、还没提醒过。返回后就记成提醒过
    public func due(now: Date = Date(), extra: [ImportantDate] = [], calendar cal: Calendar = .current) -> [(date: ImportantDate, days: Int)] {
        let list = upcoming(from: now, extra: extra).filter { $0.date.remindDays.contains($0.days) }
        var out: [(ImportantDate, Int)] = []
        for (d, days) in list {
            guard let next = d.next(from: now, calendar: cal) else { continue }
            let key = "\(d.id)|\(MemoryDay.formatter.string(from: next))|\(days)"
            guard !reminded.contains(key) else { continue }
            reminded.insert(key)
            out.append((d, days))
        }
        if !out.isEmpty { saveState() }
        return out
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(items) { try? data.write(to: url, options: .atomic) }
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(reminded) { try? data.write(to: stateURL, options: .atomic) }
    }
}
