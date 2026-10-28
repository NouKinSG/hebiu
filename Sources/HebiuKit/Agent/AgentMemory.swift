import Foundation

/// 她的记忆：~/.hebiu/agent/memory/
///
///     profile.md          对你的了解，一行一条，有上限；每晚改写，不是只追加
///     diary/2026-10-25.md 每天一篇日记
///     weekly/2026-W43.md  过完的一周压成一篇
///     monthly/2026-10.md  过完的一个月压成一篇
///     state.json          整理到哪一天了
///
/// 每次聊天只带「了解 + 最近几天日记 + 上周 + 上个月」，用多久都是差不多的长度；更早的细节用 recall 工具现查
public final class AgentMemory {
    public static let maxFacts = 50
    public static let maxFactLength = 60
    /// 凌晨 4 点前算前一天（熬夜到一点还是「今天」）
    public static let dayStartsAtHour = 4

    public enum Kind: String, CaseIterable {
        case diary, weekly, monthly
    }

    public struct Entry: Identifiable, Equatable {
        public var kind: Kind
        public var key: String          // 2026-10-25 / 2026-W43 / 2026-10
        public var text: String
        public var id: String { "\(kind.rawValue)/\(key)" }
    }

    struct State: Codable {
        var diaryDone: String?          // 最后整理过的一天
        var weeklyDone: String?
        var monthlyDone: String?
    }

    public let dir: URL

    public init(dir: URL = Paths.agentDir.appendingPathComponent("memory", isDirectory: true)) {
        self.dir = dir
    }

    // MARK: - 对你的了解

    var profileURL: URL { dir.appendingPathComponent("profile.md") }

    public func facts() -> [String] {
        guard let text = try? String(contentsOf: profileURL, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { return nil }
            return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
    }

    public func saveFacts(_ facts: [String]) {
        let clean = AgentMemory.clean(facts)
        let text = "# \(CharacterPack.she)对你的了解\n\n" + clean.map { "- \($0)\n" }.joined()
        write(text, to: profileURL)
    }

    /// 记下一条；已经有一样的就不重复。满了挤掉最早的一条
    @discardableResult
    public func remember(_ fact: String) -> Bool {
        let fact = AgentMemory.normalize(fact)
        guard !fact.isEmpty else { return false }
        var all = facts()
        guard !all.contains(fact) else { return false }
        all.append(fact)
        if all.count > AgentMemory.maxFacts { all.removeFirst(all.count - AgentMemory.maxFacts) }
        saveFacts(all)
        return true
    }

    public func forget(_ fact: String) {
        saveFacts(facts().filter { $0 != fact })
    }

    /// 带「今天、明天」这类说法的是某天的事（待办），过一天就不对了，不进「了解」
    static func isDated(_ fact: String) -> Bool {
        ["今天", "明天", "后天", "昨天", "今晚", "明早", "明晚", "今早", "刚才"].contains { fact.contains($0) }
    }

    /// 去空、去重、截断、限条数
    static func clean(_ facts: [String]) -> [String] {
        var out: [String] = []
        for f in facts.map(normalize) where !f.isEmpty && !out.contains(f) { out.append(f) }
        return Array(out.prefix(maxFacts))
    }

    static func normalize(_ fact: String) -> String {
        var one = fact.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -•"))
        // 整句被引号包住时才去掉引号，句中的「」保留
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」")] where one.hasPrefix(open) && one.hasSuffix(close) && one.count > 1 {
            one = String(one.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return String(one.prefix(maxFactLength))
    }

    // MARK: - 日记、周记、月记

    public func text(_ kind: Kind, _ key: String) -> String? {
        (try? String(contentsOf: url(kind, key), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func save(_ kind: Kind, _ key: String, text: String) {
        write(text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n", to: url(kind, key))
    }

    public func delete(_ kind: Kind, _ key: String) {
        try? FileManager.default.removeItem(at: url(kind, key))
    }

    /// 某一类的全部，新的在前
    public func entries(_ kind: Kind) -> [Entry] {
        let folder = dir.appendingPathComponent(kind.rawValue, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted(by: >)
            .compactMap { key in text(kind, key).map { Entry(kind: kind, key: key, text: $0) } }
    }

    private func url(_ kind: Kind, _ key: String) -> URL {
        dir.appendingPathComponent(kind.rawValue, isDirectory: true).appendingPathComponent("\(key).md")
    }

    // MARK: - 带进提示词的部分

    /// 了解 + 最近 3 篇日记 + 最近一篇周记 + 最近一篇月记；一条都没有时返回 nil
    public func promptText() -> String? {
        var parts: [String] = []
        let facts = facts()
        if !facts.isEmpty {
            parts.append("你对\(Config.he)的了解（自己慢慢记下来的，可能有过时的，以\(Config.he)现在说的为准）：\n" + facts.map { "- \($0)" }.joined(separator: "\n"))
        }
        if let month = entries(.monthly).first { parts.append("\(month.key) 这个月：\(month.text)") }
        if let week = entries(.weekly).first { parts.append("\(week.key) 那一周：\(week.text)") }
        let diaries = entries(.diary).prefix(3).reversed()
        if !diaries.isEmpty {
            parts.append("最近的日记：\n" + diaries.map { "\($0.key)：\($0.text)" }.joined(separator: "\n"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// 在日记、周记、月记里找：关键词（空格隔开）或日期（2026-10、2026-10-25）。
    /// 对上的词越多越靠前，一样多时新的在前；一个都对不上的不要
    public func search(_ query: String, limit: Int = 5) -> [Entry] {
        let words = query.split(whereSeparator: { $0.isWhitespace || $0 == "，" || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return [] }
        let scored = Kind.allCases.flatMap { entries($0) }.compactMap { e -> (Entry, Int)? in
            let hits = words.filter { e.key.hasPrefix($0) || e.text.localizedCaseInsensitiveContains($0) }.count
            return hits > 0 ? (e, hits) : nil
        }
        return Array(scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.key > $1.0.key }.map(\.0).prefix(limit))
    }

    // MARK: - 整理进度

    var stateURL: URL { dir.appendingPathComponent("state.json") }

    func loadState() -> State {
        guard let data = try? Data(contentsOf: stateURL) else { return State() }
        return (try? JSONDecoder().decode(State.self, from: data)) ?? State()
    }

    func saveState(_ state: State) {
        if let data = try? JSONEncoder().encode(state) { write(data, to: stateURL) }
    }

    /// 还没写日记的日子：从上次整理的后一天到昨天，最多往回补 7 天
    public func pendingDiaryDays(now: Date) -> [String] {
        let yesterday = MemoryDay.add(MemoryDay.of(now), -1)
        let earliest = MemoryDay.add(yesterday, -6)
        var day = loadState().diaryDone.map { MemoryDay.add($0, 1) } ?? earliest
        if day < earliest { day = earliest }
        var out: [String] = []
        while day <= yesterday {
            out.append(day)
            day = MemoryDay.add(day, 1)
        }
        return out
    }

    public func markDiaryDone(_ day: String) {
        var s = loadState()
        if (s.diaryDone ?? "") < day { s.diaryDone = day }
        saveState(s)
    }

    /// 已经过完、有日记、还没压成周记的周（只看最近一周，避免一次补很多）
    public func pendingWeek(now: Date) -> (key: String, days: [String])? {
        let lastWeek = MemoryDay.weekDays(of: MemoryDay.add(MemoryDay.of(now), -7))
        let key = MemoryDay.weekKey(lastWeek[0])
        guard (loadState().weeklyDone ?? "") < key, text(.weekly, key) == nil else { return nil }
        return (key, lastWeek)
    }

    public func markWeekDone(_ key: String) {
        var s = loadState()
        if (s.weeklyDone ?? "") < key { s.weeklyDone = key }
        saveState(s)
    }

    /// 上个月还没压成月记
    public func pendingMonth(now: Date) -> String? {
        let key = String(MemoryDay.add(String(MemoryDay.of(now).prefix(7)) + "-01", -1).prefix(7))
        guard (loadState().monthlyDone ?? "") < key, text(.monthly, key) == nil else { return nil }
        return key
    }

    public func markMonthDone(_ key: String) {
        var s = loadState()
        if (s.monthlyDone ?? "") < key { s.monthlyDone = key }
        saveState(s)
    }

    // MARK: -

    private func write(_ text: String, to url: URL) {
        write(Data(text.utf8), to: url)
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// 记忆按「日」算，凌晨 4 点换天；日期一律用 yyyy-MM-dd 字符串，能直接比大小
public enum MemoryDay {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2      // 周一开始
        c.minimumDaysInFirstWeek = 4
        return c
    }

    public static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func of(_ date: Date) -> String {
        formatter.string(from: date.addingTimeInterval(-Double(AgentMemory.dayStartsAtHour) * 3600))
    }

    /// 这一天从几点到几点（凌晨 4 点到次日凌晨 4 点）
    public static func range(_ day: String) -> Range<Date> {
        let start = formatter.date(from: day)!.addingTimeInterval(Double(AgentMemory.dayStartsAtHour) * 3600)
        return start..<calendar.date(byAdding: .day, value: 1, to: start)!
    }

    public static func add(_ day: String, _ n: Int) -> String {
        let d = formatter.date(from: day)!.addingTimeInterval(12 * 3600)
        return formatter.string(from: calendar.date(byAdding: .day, value: n, to: d)!)
    }

    /// 这一天所在那周的周一到周日
    public static func weekDays(of day: String) -> [String] {
        let d = formatter.date(from: day)!.addingTimeInterval(12 * 3600)
        let weekday = (calendar.component(.weekday, from: d) + 5) % 7     // 周一 = 0
        let monday = add(day, -weekday)
        return (0..<7).map { add(monday, $0) }
    }

    public static func weekKey(_ day: String) -> String {
        let d = formatter.date(from: day)!.addingTimeInterval(12 * 3600)
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
    }
}

/// 从 Claude 钩子的事件记录里数出某一天写代码的时间和次数。事件文件里只有「时间戳 事件名」，没有项目和内容
public struct ClaudeActivity: Equatable {
    public var sessions = 0             // 开了几次会话
    public var finished = 0             // 干完了几次活
    public var errors = 0
    public var first: Date?
    public var last: Date?

    public var isEmpty: Bool { first == nil }

    public static func of(day: String, events url: URL = Paths.events) -> ClaudeActivity {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return ClaudeActivity() }
        let range = MemoryDay.range(day)
        var out = ClaudeActivity()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let ts = TimeInterval(parts[0]) else { continue }
            let time = Date(timeIntervalSince1970: ts)
            guard range.contains(time) else { continue }
            switch parts[1] {
            case "hello": out.sessions += 1
            case "done": out.finished += 1
            case "error": out.errors += 1
            case "working", "wait": break
            default: continue
            }
            out.first = min(out.first ?? time, time)
            out.last = max(out.last ?? time, time)
        }
        return out
    }

    /// 给模型看的一句话
    public var summary: String? {
        guard let first, let last else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        var s = "用 Claude 写代码：\(f.string(from: first)) 到 \(f.string(from: last))"
        if last.timeIntervalSince(first) < 60 { s = "用 Claude 写代码：\(f.string(from: first)) 左右" }
        s += "，开了 \(sessions) 次会话，干完 \(finished) 次活"
        if errors > 0 { s += "，报错 \(errors) 次" }
        return s
    }
}
