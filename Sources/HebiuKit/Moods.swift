import Foundation

/// 每天的心情：1～5 分，可以带一句话
public struct Mood: Codable, Equatable {
    public var score: Int
    public var note: String
    public var at: Date

    public init(score: Int, note: String = "", at: Date = Date()) {
        self.score = min(5, max(1, score))
        self.note = note
        self.at = at
    }

    public static let levels: [(score: Int, emoji: String, name: String)] = [
        (1, "😫", "很糟"), (2, "😕", "不太好"), (3, "😐", "一般"), (4, "🙂", "不错"), (5, "😄", "超开心"),
    ]

    public var emoji: String { Mood.levels[score - 1].emoji }
    public var name: String { Mood.levels[score - 1].name }
}

/// 心情记录：~/.hebiu/moods.json，按天（凌晨 4 点换天）一条，再记会覆盖
public final class MoodStore {
    public let url: URL
    private var days: [String: Mood] = [:]
    /// 晚上问过的日子
    private var askedDay: String?
    public var onChange: (() -> Void)?

    public init(url: URL = Paths.dataDir.appendingPathComponent("moods.json")) {
        self.url = url
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        days = (try? Data(contentsOf: url)).flatMap { try? d.decode([String: Mood].self, from: $0) } ?? [:]
    }

    public func mood(on day: String) -> Mood? { days[day] }

    public func today(_ now: Date = Date()) -> Mood? { days[MemoryDay.of(now)] }

    /// 记今天的心情；返回之前那条（撤销用）
    @discardableResult
    public func set(score: Int, note: String = "", now: Date = Date()) -> Mood? {
        let day = MemoryDay.of(now)
        let before = days[day]
        days[day] = Mood(score: score, note: note.trimmingCharacters(in: .whitespacesAndNewlines), at: now)
        save()
        return before
    }

    /// 恢复成之前的样子（nil 就是删掉）
    public func restore(_ mood: Mood?, day: String) {
        days[day] = mood
        save()
    }

    /// 最近 n 天，旧的在前；没记的为 nil
    public func recent(_ n: Int, now: Date = Date()) -> [(day: String, mood: Mood?)] {
        let today = MemoryDay.of(now)
        return (0..<n).reversed().map { offset in
            let d = MemoryDay.add(today, -offset)
            return (d, days[d])
        }
    }

    /// 晚上该不该问一句：到点了、今天还没记、还没问过
    public func shouldAsk(now: Date = Date(), hour: Int = 21, calendar cal: Calendar = .current) -> Bool {
        let day = MemoryDay.of(now)
        let h = cal.component(.hour, from: now)
        guard h >= hour, h < 24, days[day] == nil, askedDay != day else { return false }
        askedDay = day
        return true
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(days) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }
}
