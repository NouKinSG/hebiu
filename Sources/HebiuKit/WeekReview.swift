import Foundation

/// 一周回顾：把这周的统计、写代码的时间、习惯、心情、完成的待办凑到一起
public struct WeekReview {
    public struct HabitWeek: Identifiable {
        public let habit: Habit
        public let done: Int
        public let scheduled: Int
        public var id: String { habit.id }
    }

    public let key: String               // 2026-W43
    public let days: [String]            // 周一到周日
    public let perDay: [Stats.Day]
    public let total: Stats.Day
    public let activity: [ClaudeActivity]
    public let moods: [Mood?]
    public let habits: [HabitWeek]
    public let todosDone: [TodoItem]

    /// offset 0 是这周，-1 是上周
    public static func build(offset: Int = 0, now: Date = Date(), stats: Stats, habits: HabitStore?, moods: MoodStore?,
                             todos: [TodoItem], events: URL = Paths.events) -> WeekReview {
        let days = MemoryDay.weekDays(of: MemoryDay.add(MemoryDay.of(now), offset * 7))
        let today = MemoryDay.of(now)
        let perDay = days.map { stats.day(key: $0) }
        let total = perDay.reduce(into: Stats.Day()) { sum, d in for (k, v) in d { sum[k, default: 0] += v } }
        let habitWeeks = (habits?.habits ?? []).map { h -> HabitWeek in
            let created = MemoryDay.of(h.createdAt)
            let counted = days.filter { $0 <= today && $0 >= created && h.scheduled(on: $0) }
            return HabitWeek(habit: h, done: counted.filter { habits!.isDone(h.id, on: $0) }.count, scheduled: counted.count)
        }
        let first = MemoryDay.range(days[0]).lowerBound, last = MemoryDay.range(days[6]).upperBound
        let done = todos.filter { ($0.doneAt.map { $0 >= first && $0 < last }) ?? false }.sorted { $0.doneAt! < $1.doneAt! }
        return WeekReview(key: MemoryDay.weekKey(days[0]), days: days, perDay: perDay, total: total,
                          activity: days.map { ClaudeActivity.of(day: $0, events: events) },
                          moods: days.map { moods?.mood(on: $0) }, habits: habitWeeks, todosDone: done)
    }

    /// 最晚几点收工（凌晨的算到前一天里）
    public var latestFinish: Date? {
        activity.compactMap(\.last).max { minutesIntoDay($0) < minutesIntoDay($1) }
    }

    /// 这周有几天用 Claude 写了代码
    public var codingDays: Int { activity.filter { !$0.isEmpty }.count }

    /// 从凌晨 4 点算起过了几分钟（一点半比晚上十点晚）
    private func minutesIntoDay(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return ((c.hour ?? 0) - AgentMemory.dayStartsAtHour + 24) % 24 * 60 + (c.minute ?? 0)
    }

    /// 给她写总结用的材料（只有数字和你自己的待办标题）
    public var material: String {
        var lines: [String] = []
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        lines.append("这周完成待办 \(total[.todosDone] ?? 0) 件，专心 \(total[.focus] ?? 0) 个番茄，跟你说了 \(total[.chats] ?? 0) 句，摸了你 \(total[.taps] ?? 0) 下。")
        let coding = zip(names, activity).compactMap { name, a in a.summary.map { "\(name)\($0)" } }
        if !coding.isEmpty { lines.append("写代码：\n" + coding.joined(separator: "\n")) }
        if !habits.isEmpty { lines.append("习惯：" + habits.map { "\($0.habit.title) \($0.done)/\($0.scheduled)" }.joined(separator: "，")) }
        let moodText = zip(names, moods).compactMap { name, m in m.map { "\(name)\($0.name)" + ($0.note.isEmpty ? "" : "（\($0.note)）") } }
        if !moodText.isEmpty { lines.append("心情：" + moodText.joined(separator: "，")) }
        let own = todosDone.filter(AgentPrivacy.isOwn).prefix(30).map(\.title)
        if !own.isEmpty { lines.append("完成的事：" + own.joined(separator: "、")) }
        return lines.joined(separator: "\n")
    }
}

extension Stats {
    /// 某一天（yyyy-MM-dd）
    public func day(key: String) -> Day {
        day(MemoryDay.range(key).lowerBound.addingTimeInterval(3600))
    }
}
