import Foundation

/// 点她时做什么：按权重随机，连续两次不一样；短时间戳太多次就鼓嘴
public struct TapReactions {
    /// 没有形象包时用的反应和权重（测试也用它）：摸摸头最常见，其余穿插
    public static let defaultPool: [(event: String, weight: Int)] = [
        ("pat", 22), ("tap_bliss", 12), ("love", 10), ("poke", 10), ("tap_grin", 10), ("tap_nuzzle", 10),
        ("tap_surprised", 7), ("tap_blush", 8), ("tap_cheer", 6), ("tap_tea", 6),
    ]
    /// 这次用的反应（形象包里配的）
    public let pool: [(event: String, weight: Int)]
    /// 戳太多时的动作
    public let annoyedAction: String
    /// 和点她有关的所有事件（含连戳的「别戳啦」）
    public var events: Set<String> { Set(pool.map(\.event)).union([annoyedAction]) }
    /// 这么多秒内点了这么多下，算「戳太多了」
    public static let annoyWindow: TimeInterval = 6
    public static let annoyCount = 5

    private var recentTaps: [Date] = []
    private var last: String?
    private var untilTalk: Int?

    public init(pool: [(event: String, weight: Int)] = TapReactions.defaultPool, annoyed: String = "annoyed") {
        self.pool = pool.isEmpty ? TapReactions.defaultPool : pool
        self.annoyedAction = annoyed
    }

    /// 这次点击要不要说话：大约每 every 次说一次（上下浮动三成，不会死板地正好第几次）；0 不说，1 每次说
    public mutating func shouldTalk(every: Int, roll: (ClosedRange<Int>) -> Int = { Int.random(in: $0) }) -> Bool {
        guard every > 0 else { return false }
        guard every > 1 else { return true }
        let range = max(1, Int((Double(every) * 0.7).rounded()))...Int((Double(every) * 1.3).rounded())
        var left = untilTalk ?? roll(range)
        left -= 1
        if left <= 0 {
            untilTalk = roll(range)
            return true
        }
        untilTalk = left
        return false
    }

    public mutating func next(now: Date = Date(), roll: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        recentTaps = recentTaps.filter { now.timeIntervalSince($0) < TapReactions.annoyWindow } + [now]
        if recentTaps.count >= TapReactions.annoyCount {
            recentTaps.removeAll()
            last = annoyedAction
            return annoyedAction
        }
        let choices = pool.count > 1 ? pool.filter { $0.event != last } : pool
        var r = roll(choices.reduce(0) { $0 + $1.weight })
        for c in choices {
            if r < c.weight { last = c.event; return c.event }
            r -= c.weight
        }
        last = choices[0].event
        return choices[0].event
    }
}
