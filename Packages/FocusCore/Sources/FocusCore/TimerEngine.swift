//
//  TimerEngine.swift
//  FocusOnYourself
//
//  专注计时核心引擎（纯逻辑，不依赖 SwiftUI）。
//  公开接口契约见 Packages/FocusCore/INTERFACE.md，UI 层依赖其公开名称与语义。
//

import Foundation
import Combine

/// 计时模式。
public enum TimerMode: String, CaseIterable, Codable {
    /// 倒计时。
    case countdown
    /// 正计时。
    case countUp
}

/// 计时阶段。
public enum TimerPhase: Equatable {
    case idle
    case running
    case paused
    case finished
}

/// 专注计时引擎。
///
/// 计时采用「锚点 + 结算」而非逐 tick 累加：
/// `start()` 记录当前 running 段的起点 `runStart` 与已结算的 `elapsed`，
/// `tick()` / `pause()` 时用 `now()` 与锚点求差得到本段经过时间，
/// 因此实际耗时不会因 tick 频率或丢 tick 而产生累计漂移。
///
/// 线程模型：`@MainActor`，UI 可直接观察 `@Published` 属性。
@MainActor
public final class TimerEngine: ObservableObject {
    @Published public private(set) var mode: TimerMode
    @Published public private(set) var phase: TimerPhase
    /// 已累计的专注秒数（含当前正在跑的这一段）。
    @Published public private(set) var elapsed: TimeInterval
    /// 倒计时总秒数；正计时模式下该值保留但不参与显示。
    @Published public private(set) var countdownSeconds: TimeInterval

    /// 倒计时实际到点的时刻（= 本段起点 + 剩余秒数）；非 finished 时为 nil。
    /// 用于 app 关闭期间完成的一轮按真实到点时刻记录。
    public private(set) var finishedAt: Date?

    /// 时钟注入，测试用假时钟；默认 `Date.init`。
    public let now: () -> Date

    /// 进入当前 running 段时已结算的 `elapsed`（暂停/恢复的接续点）。
    private var elapsedAtRunStart: TimeInterval
    /// 当前 running 段的起点；非 running 状态为 nil。
    private var runStart: Date?

    /// countdownSeconds 下限：1 分钟。
    private static let minimumCountdownSeconds: TimeInterval = 60
    /// countdownSeconds 上限：180 分钟。
    private static let maximumCountdownSeconds: TimeInterval = 10800

    public init(mode: TimerMode = .countdown,
                countdownSeconds: TimeInterval = 25 * 60,
                now: @escaping () -> Date = Date.init) {
        self.mode = mode
        self.phase = .idle
        self.elapsed = 0
        self.countdownSeconds = countdownSeconds
        self.now = now
        self.elapsedAtRunStart = 0
        self.runStart = nil
    }

    // MARK: - 派生状态

    /// 是否正在计时。
    public var isRunning: Bool {
        phase == .running
    }

    /// 倒计时剩余秒数（不小于 0）。
    public var countdownRemaining: TimeInterval {
        max(0, countdownSeconds - elapsed)
    }

    /// 显示用的整秒数：倒计时取 `ceil(remaining)`，正计时取 `floor(elapsed)`。
    public var displaySeconds: Int {
        switch mode {
        case .countdown:
            return Int(ceil(countdownRemaining))
        case .countUp:
            return Int(floor(elapsed))
        }
    }

    /// 格式化时间："25:00"；满 1 小时用 "1:05:00"（小时不补零，分秒补零）。
    public var formattedTime: String {
        Self.format(seconds: displaySeconds)
    }

    /// 进度：倒计时为 `elapsed / countdownSeconds`（夹在 0...1）；
    /// 正计时为 `(elapsed % 60) / 60`。
    public var progress: Double {
        switch mode {
        case .countdown:
            guard countdownSeconds > 0 else { return 0 }
            return min(max(elapsed / countdownSeconds, 0), 1)
        case .countUp:
            return elapsed.truncatingRemainder(dividingBy: 60) / 60
        }
    }

    // MARK: - 控制

    /// 开始或继续计时；`finished` 状态会先归零再开始。
    public func start() {
        guard phase != .running else { return } // 已在 running 时幂等
        if phase == .finished {
            elapsed = 0
            finishedAt = nil
        }
        elapsedAtRunStart = elapsed
        runStart = now()
        phase = .running
    }

    /// 暂停计时并冻结 `elapsed`；只对 running 生效。
    public func pause() {
        guard phase == .running, let runStart else { return }
        elapsed = elapsedAtRunStart + now().timeIntervalSince(runStart)
        self.runStart = nil
        phase = .paused
    }

    /// running 时暂停，否则开始/继续。
    public func toggle() {
        if phase == .running {
            pause()
        } else {
            start()
        }
    }

    /// 回到 idle 并清零 `elapsed`，保留 `mode` 与 `countdownSeconds`。
    public func reset() {
        phase = .idle
        elapsed = 0
        elapsedAtRunStart = 0
        runStart = nil
        finishedAt = nil
    }

    /// 切换模式；仅当模式确实变化时 reset。
    public func setMode(_ mode: TimerMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        reset()
    }

    /// 设置倒计时总秒数：先夹到 60...10800，再 reset（运行中调用立即停止归零）。
    public func setCountdownSeconds(_ seconds: TimeInterval) {
        countdownSeconds = min(
            max(seconds, Self.minimumCountdownSeconds),
            Self.maximumCountdownSeconds
        )
        reset()
    }

    // MARK: - 结算

    /// 结算一次流逝时间。
    ///
    /// - 仅 running 状态有动作；非 running 返回 `false` 且不改变状态。
    /// - 倒计时首次到达 `countdownSeconds` 时 `elapsed` 钳到总数、`phase = .finished`，
    ///   并返回 `true`；之后（以及正计时永远）返回 `false`。
    @discardableResult
    public func tick() -> Bool {
        guard phase == .running, let runStart else { return false }

        let settledElapsed = elapsedAtRunStart + now().timeIntervalSince(runStart)

        if mode == .countdown, settledElapsed >= countdownSeconds {
            elapsed = countdownSeconds
            phase = .finished
            finishedAt = runStart.addingTimeInterval(countdownSeconds - elapsedAtRunStart)
            self.runStart = nil
            return true
        }

        elapsed = settledElapsed
        return false
    }

    // MARK: - 快照

    /// 运行中 / 暂停时的可恢复状态；idle 与 finished 时为 nil。
    public var snapshot: TimerSnapshot? {
        switch phase {
        case .running:
            guard let runStart else { return nil }
            return TimerSnapshot(mode: mode, countdownSeconds: countdownSeconds, isRunning: true,
                                 elapsedAtAnchor: elapsedAtRunStart, anchor: runStart)
        case .paused:
            return TimerSnapshot(mode: mode, countdownSeconds: countdownSeconds, isRunning: false,
                                 elapsedAtAnchor: elapsed, anchor: now())
        case .idle, .finished:
            return nil
        }
    }

    /// 从快照恢复（不经过 reset）。运行中：按锚点结算到 `now()`，但不判定完成——
    /// 完成交给下一次 `tick()`，保证「完成只触发一次」。
    public func restore(_ snapshot: TimerSnapshot) {
        mode = snapshot.mode
        countdownSeconds = snapshot.countdownSeconds
        finishedAt = nil
        if snapshot.isRunning {
            elapsedAtRunStart = snapshot.elapsedAtAnchor
            runStart = snapshot.anchor
            elapsed = snapshot.elapsedAtAnchor + now().timeIntervalSince(snapshot.anchor)
            phase = .running
        } else {
            elapsedAtRunStart = snapshot.elapsedAtAnchor
            runStart = nil
            elapsed = snapshot.elapsedAtAnchor
            phase = .paused
        }
    }

    // MARK: - 辅助

    /// 把整秒数格式化为 "MM:SS" 或 "H:MM:SS"。
    private static func format(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

/// `TimerEngine` 的可持久化状态。运行中：`anchor` 为本段起点，`elapsedAtAnchor` 为起点前已累计；
/// 暂停：`elapsedAtAnchor` 为冻结的 elapsed，`anchor` 为拍快照的时刻（恢复时不使用）。
public struct TimerSnapshot: Codable, Equatable {
    public var mode: TimerMode
    public var countdownSeconds: TimeInterval
    public var isRunning: Bool
    public var elapsedAtAnchor: TimeInterval
    public var anchor: Date

    public init(mode: TimerMode, countdownSeconds: TimeInterval, isRunning: Bool,
                elapsedAtAnchor: TimeInterval, anchor: Date) {
        self.mode = mode
        self.countdownSeconds = countdownSeconds
        self.isRunning = isRunning
        self.elapsedAtAnchor = elapsedAtAnchor
        self.anchor = anchor
    }
}
