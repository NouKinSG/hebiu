import Foundation

/// 一条专注会话的结局。
public enum SessionOutcome: String, Codable, Equatable {
    case completed    // 倒计时跑完
    case interrupted  // 倒计时中途结束（≥ 门槛）
    case free         // 正计时（≥ 门槛）
}

/// 一次已结束的专注会话。专注时长不含暂停。
public struct FocusSession: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public let mode: TimerMode
    public let startedAt: Date
    public let endedAt: Date
    public let focusedSeconds: TimeInterval
    /// 倒计时目标时长；正计时为 nil
    public let plannedSeconds: TimeInterval?
    public let outcome: SessionOutcome

    public init(
        id: UUID = UUID(),
        title: String,
        mode: TimerMode,
        startedAt: Date,
        endedAt: Date,
        focusedSeconds: TimeInterval,
        plannedSeconds: TimeInterval?,
        outcome: SessionOutcome
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds
        self.plannedSeconds = plannedSeconds
        self.outcome = outcome
    }
}

/// 决定一段计时是否值得存、存成什么。纯值类型，不持有时钟。
public struct SessionRecorder {
    public static let minimumSeconds: TimeInterval = 60

    private struct Active {
        let id: UUID
        let startedAt: Date
        let mode: TimerMode
        let plannedSeconds: TimeInterval?
    }

    private var active: Active?

    public init() {}

    public var isActive: Bool { active != nil }

    /// 进行中会话的可持久化状态；没有进行中会话时为 nil。
    public var snapshot: RecorderSnapshot? {
        active.map { RecorderSnapshot(startedAt: $0.startedAt, mode: $0.mode, plannedSeconds: $0.plannedSeconds, id: $0.id) }
    }

    /// 从快照恢复进行中的会话（覆盖当前状态）。
    public mutating func restore(_ snapshot: RecorderSnapshot) {
        active = Active(id: snapshot.id ?? UUID(), startedAt: snapshot.startedAt, mode: snapshot.mode, plannedSeconds: snapshot.plannedSeconds)
    }

    /// 开始一条会话；已有进行中会话时不覆盖（暂停后继续属于同一会话）。
    public mutating func begin(at date: Date, mode: TimerMode, plannedSeconds: TimeInterval?) {
        guard active == nil else { return }
        active = Active(id: UUID(), startedAt: date, mode: mode, plannedSeconds: plannedSeconds)
    }

    /// 结束进行中的会话。无进行中会话、或未达门槛时返回 nil；调用后总会清空。
    public mutating func finish(
        elapsed: TimeInterval,
        title: String,
        at date: Date,
        completed: Bool
    ) -> FocusSession? {
        guard let current = active else { return nil }
        active = nil

        let outcome: SessionOutcome
        if completed {
            outcome = .completed
        } else if elapsed < Self.minimumSeconds {
            return nil
        } else {
            outcome = current.mode == .countdown ? .interrupted : .free
        }

        return FocusSession(
            id: current.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: current.mode,
            startedAt: current.startedAt,
            endedAt: date,
            focusedSeconds: elapsed,
            plannedSeconds: current.plannedSeconds,
            outcome: outcome
        )
    }

    /// 在 engine 归零（重置 / 切模式 / 改时长）或退出之前结算进行中的会话。
    /// 先 tick 一次：倒计时已过终点但还没被 tick 到时，按完成记录并钳到计划时长；
    /// 否则暂停以结算正在跑的这一段，再按门槛记为中断 / 自由专注或丢弃。
    @MainActor
    public mutating func finalize(engine: TimerEngine, title: String) -> FocusSession? {
        guard isActive else { return nil }
        if engine.tick() {
            return finish(elapsed: engine.elapsed, title: title, at: engine.finishedAt ?? engine.now(), completed: true)
        }
        if engine.isRunning {
            engine.pause()
        }
        return finish(elapsed: engine.elapsed, title: title, at: engine.now(), completed: false)
    }
}

/// `SessionRecorder` 进行中会话的可持久化状态。
public struct RecorderSnapshot: Codable, Equatable {
    public var id: UUID?
    public var startedAt: Date
    public var mode: TimerMode
    public var plannedSeconds: TimeInterval?

    public init(startedAt: Date, mode: TimerMode, plannedSeconds: TimeInterval?, id: UUID? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.mode = mode
        self.plannedSeconds = plannedSeconds
    }
}
