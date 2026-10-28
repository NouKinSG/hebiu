import Foundation

/// 一个习惯：喝水、运动、早睡……每天（或每周几）打一次卡
public struct Habit: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var emoji: String
    /// 哪些天要做（RepeatRule 文字形式），默认每天
    public var rule: String
    /// 几点还没打卡就提醒，如 21:00；nil 不提醒
    public var remindAt: String?
    public var createdAt: Date

    public init(id: String = "h_" + UUID().uuidString.prefix(8).lowercased(), title: String, emoji: String? = nil,
                rule: String = "daily", remindAt: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.emoji = emoji ?? Habit.guessEmoji(title)
        self.rule = rule
        self.remindAt = remindAt
        self.createdAt = createdAt
    }

    public var repeatRule: RepeatRule { RepeatRule(rule) ?? .daily }

    /// 这一天（yyyy-MM-dd）要不要做
    public func scheduled(on day: String) -> Bool {
        repeatRule.matches(MemoryDay.formatter.date(from: day)!.addingTimeInterval(12 * 3600))
    }

    /// 「每天 · 21:00 提醒」
    public var detail: String {
        repeatRule.display + (remindAt.map { " · \($0) 提醒" } ?? "")
    }

    static func guessEmoji(_ title: String) -> String {
        let table: [(String, String)] = [("水", "💧"), ("跑", "🏃"), ("运动", "🏃"), ("健身", "💪"), ("走", "🚶"), ("睡", "😴"),
                                         ("读", "📖"), ("书", "📖"), ("药", "💊"), ("维生素", "💊"), ("冥想", "🧘"), ("拉伸", "🧘"),
                                         ("单词", "📝"), ("英语", "📝"), ("学", "📝"), ("吃", "🥗"), ("早起", "🌅"), ("护肤", "🧴"),
                                         ("日记", "✏️"), ("电话", "📞"), ("奶茶", "🧋")]
        return table.first { title.contains($0.0) }?.1 ?? "✅"
    }

    /// 「喝水 每天晚上9点提醒」「健身 每周一三五」→ 习惯；时间当提醒时间
    public static func parse(_ text: String, now: Date = Date()) -> Habit? {
        var rest = text
        var rule = RepeatRule.daily
        if let r = RepeatRule.extract(text) {
            rule = r.rule
            rest = r.rest
        }
        for word in ["提醒我", "叫我", "喊我", "提醒"] { rest = rest.replacingOccurrences(of: word, with: " ") }
        guard let p = TimeParser.parse(rest, now: now) else { return nil }
        let title = p.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let cal = Calendar.current
        let remind = p.hasTime ? p.due.map { String(format: "%02d:%02d", cal.component(.hour, from: $0), cal.component(.minute, from: $0)) } : nil
        return Habit(title: title, rule: rule.text, remindAt: remind, createdAt: now)
    }
}

/// 习惯和打卡记录：~/.hebiu/habits.json，只有桌宠写
public final class HabitStore {
    struct Body: Codable {
        var habits: [Habit] = []
        /// 习惯 id → 打过卡的日子（yyyy-MM-dd，凌晨 4 点换天）
        var checkins: [String: [String]] = [:]
        /// 习惯 id → 最后提醒过的日子
        var reminded: [String: String] = [:]
    }

    public let url: URL
    private var body = Body()
    public var onChange: (() -> Void)?

    public init(url: URL = Paths.dataDir.appendingPathComponent("habits.json")) {
        self.url = url
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let b = try? d.decode(Body.self, from: data) { body = b }
    }

    public var habits: [Habit] { body.habits }

    public func habit(_ id: String) -> Habit? { body.habits.first { $0.id == id } }

    /// 按名字找：完全一样优先，其次包含
    public func find(_ text: String) -> Habit? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return body.habits.first { $0.id == t || $0.title == t } ?? body.habits.first { $0.title.contains(t) || t.contains($0.title) }
    }

    @discardableResult
    public func add(_ habit: Habit) -> Habit {
        body.habits.append(habit)
        save()
        return habit
    }

    public func delete(_ id: String) {
        body.habits.removeAll { $0.id == id }
        body.checkins[id] = nil
        body.reminded[id] = nil
        save()
    }

    public func isDone(_ id: String, on day: String) -> Bool {
        body.checkins[id]?.contains(day) == true
    }

    /// 打卡或取消；返回打完之后是不是打上了
    @discardableResult
    public func toggle(_ id: String, now: Date = Date()) -> Bool {
        set(id, done: !isDone(id, on: MemoryDay.of(now)), now: now)
    }

    @discardableResult
    public func set(_ id: String, done: Bool, now: Date = Date()) -> Bool {
        guard habit(id) != nil else { return false }
        let day = MemoryDay.of(now)
        var days = body.checkins[id] ?? []
        if done, !days.contains(day) { days.append(day) }
        if !done { days.removeAll { $0 == day } }
        body.checkins[id] = days.sorted()
        save()
        return done
    }

    /// 连续几次：从今天往回数要做的日子，今天还没打卡就从昨天算起，碰到漏了的就停
    public func streak(_ id: String, now: Date = Date()) -> Int {
        guard let h = habit(id) else { return 0 }
        var day = MemoryDay.of(now)
        if !isDone(id, on: day) { day = MemoryDay.add(day, -1) }
        var n = 0
        for _ in 0..<1000 {
            if h.scheduled(on: day) {
                guard isDone(id, on: day) else { break }
                n += 1
            }
            day = MemoryDay.add(day, -1)
        }
        return n
    }

    /// 最近 7 天：nil 是那天不用做
    public func week(_ id: String, now: Date = Date()) -> [(day: String, done: Bool?)] {
        guard let h = habit(id) else { return [] }
        let today = MemoryDay.of(now)
        return (0..<7).reversed().map { offset in
            let d = MemoryDay.add(today, -offset)
            // 加这个习惯之前的日子不算漏
            let before = d < MemoryDay.of(h.createdAt)
            return (d, h.scheduled(on: d) && !before ? isDone(id, on: d) : nil)
        }
    }

    /// 今天要做的，和做没做
    public func today(now: Date = Date()) -> [(habit: Habit, done: Bool)] {
        let day = MemoryDay.of(now)
        return body.habits.filter { $0.scheduled(on: day) }.map { ($0, isDone($0.id, on: day)) }
    }

    /// 到了提醒时间还没打卡的；返回后记成今天提醒过
    public func dueReminders(now: Date = Date(), calendar cal: Calendar = .current) -> [Habit] {
        let day = MemoryDay.of(now)
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let list = today(now: now).filter { item in
            guard !item.done, let at = item.habit.remindAt, body.reminded[item.habit.id] != day else { return false }
            let p = at.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2 else { return false }
            // 提醒时间过了两小时还没来得及提醒（电脑没开）就算了
            let target = p[0] * 60 + p[1]
            return minutes >= target && minutes < target + 120
        }.map(\.habit)
        for h in list { body.reminded[h.id] = day }
        if !list.isEmpty { save() }
        return list
    }

    /// 某一天做了哪些（写日记用）
    public func done(on day: String) -> [Habit] {
        body.habits.filter { isDone($0.id, on: day) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(body) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }
}
