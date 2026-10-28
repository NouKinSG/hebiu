import Foundation

/// 番茄钟：专心 N 分钟 → 休息 M 分钟 → 回到空闲。只管时间，提醒和动作由桌宠那边做
public final class FocusSession {
    public enum Phase: Equatable {
        case idle
        case focus(start: Date, end: Date)
        case rest(end: Date)
    }

    /// 一次 tick 里发生的转换
    public enum Transition: Equatable {
        case focusDone      // 专心满了，开始休息
        case restDone       // 休息完了
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    public var isFocusing: Bool { if case .focus = phase { return true }; return false }
    public var isActive: Bool { phase != .idle }

    public func start(minutes: Int, now: Date = Date()) {
        phase = .focus(start: now, end: now.addingTimeInterval(Double(max(1, minutes)) * 60))
    }

    public func stop() {
        phase = .idle
    }

    /// 时间到了就往下走一步；restMinutes 为 0 时专心完直接回空闲
    @discardableResult
    public func tick(now: Date = Date(), restMinutes: Int) -> Transition? {
        switch phase {
        case let .focus(_, end) where now >= end:
            phase = restMinutes > 0 ? .rest(end: now.addingTimeInterval(Double(restMinutes) * 60)) : .idle
            return .focusDone
        case let .rest(end) where now >= end:
            phase = .idle
            return .restDone
        default:
            return nil
        }
    }

    /// 还剩几秒（空闲时 0）
    public func remaining(now: Date = Date()) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case let .focus(_, end), let .rest(end): return max(0, end.timeIntervalSince(now))
        }
    }

    /// 走了多少（0～1），画进度用
    public func progress(now: Date = Date()) -> Double {
        guard case let .focus(start, end) = phase else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    /// 18:05 这样的倒计时
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
