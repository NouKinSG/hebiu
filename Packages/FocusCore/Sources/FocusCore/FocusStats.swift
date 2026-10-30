import Foundation

/// 某一天（当日 00:00）的专注总秒数。
public struct DailyTotal: Equatable {
    public let day: Date
    public let seconds: TimeInterval

    public init(day: Date, seconds: TimeInterval) {
        self.day = day
        self.seconds = seconds
    }
}

/// 基于会话列表的统计快照。会话按 `startedAt` 归属日期，一周从周一算起。
public struct FocusStats {
    public let sessions: [FocusSession]
    public let now: Date
    private let calendar: Calendar

    public init(sessions: [FocusSession], now: Date, calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2
        self.sessions = sessions
        self.now = now
        self.calendar = calendar
    }

    private var today: Date { calendar.startOfDay(for: now) }

    private var todaySessions: [FocusSession] {
        sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
    }

    public var todayFocused: TimeInterval {
        todaySessions.reduce(0) { $0 + $1.focusedSeconds }
    }

    public var todayCompletedCount: Int {
        todaySessions.filter { $0.outcome == .completed }.count
    }

    public var weekFocused: TimeInterval {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return sessions
            .filter { $0.startedAt >= week.start && $0.startedAt <= now }
            .reduce(0) { $0 + $1.focusedSeconds }
    }

    /// 从今天往回数连续有记录的天数；今天还没有记录时从昨天开始数。
    public var streakDays: Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
        var cursor = today
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    /// 最近 `days` 天（含今天）的每日合计，按时间升序，无记录的日子为 0。
    public func dailyTotals(days: Int) -> [DailyTotal] {
        var totals: [Date: TimeInterval] = [:]
        for session in sessions {
            totals[calendar.startOfDay(for: session.startedAt), default: 0] += session.focusedSeconds
        }
        return (0 ..< max(0, days)).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return DailyTotal(day: day, seconds: totals[day] ?? 0)
        }
    }

    /// 最近的会话，按开始时间倒序。
    public func recent(limit: Int) -> [FocusSession] {
        Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(max(0, limit)))
    }
}
