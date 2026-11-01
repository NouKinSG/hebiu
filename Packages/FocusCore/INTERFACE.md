# FocusOnYourself — TimerEngine 接口契约

Hebiu 的专注界面（`Sources/Hebiu/Focus/`）通过本地 Swift Package 使用这些接口。
核心检查通过 `scripts/test-focus-core.sh` 运行，不引入第三方依赖。

文件：`Packages/FocusCore/Sources/FocusCore/TimerEngine.swift`（只使用 Foundation + Combine）
Swift 语言版本：5（构建时传 `-swift-version 5`）
平台：macOS 14+，线程模型：`@MainActor`

```swift
public enum TimerMode: String, CaseIterable, Codable {
    case countdown   // 倒计时
    case countUp     // 正计时
}

public enum TimerPhase: Equatable {
    case idle, running, paused, finished
}

@MainActor
public final class TimerEngine: ObservableObject {
    @Published public private(set) var mode: TimerMode
    @Published public private(set) var phase: TimerPhase
    /// 已累计的专注秒数（含当前正在跑的这一段）
    @Published public private(set) var elapsed: TimeInterval
    /// 倒计时总秒数；正计时模式下该值保留但不参与显示
    @Published public private(set) var countdownSeconds: TimeInterval

    /// 时钟注入，测试用假时钟；默认 Date.init
    public let now: () -> Date

    public init(mode: TimerMode = .countdown,
                countdownSeconds: TimeInterval = 25 * 60,
                now: @escaping () -> Date = Date.init)

    public var isRunning: Bool { get }
    public var countdownRemaining: TimeInterval { get } // max(0, total - elapsed)
    /// 倒计时：ceil(remaining)，到点后为 0；正计时：floor(elapsed)
    public var displaySeconds: Int { get }
    /// "25:00"；>= 1 小时用 "1:05:00"（小时不补零，分秒补零）
    public var formattedTime: String { get }
    /// 倒计时：elapsed/total，夹在 0...1。正计时：(elapsed % 60)/60
    public var progress: Double { get }

    public func start()      // idle/paused 继续；finished 时先归零再开始
    public func pause()      // running -> paused，冻结 elapsed
    public func toggle()     // running 时 pause，否则 start
    public func reset()      // -> idle，elapsed = 0，保留 mode 与 countdownSeconds
    public func setMode(_ mode: TimerMode)          // 值变化时 reset
    public func setCountdownSeconds(_ seconds: TimeInterval) // 夹到 60...10800（1...180 分钟），reset
    @discardableResult public func tick() -> Bool   // 见下
}
```

## 行为语义

- **初始状态**：`mode = .countdown`，`phase = .idle`，`elapsed = 0`，
  `countdownSeconds = 1500`，`displaySeconds = 1500`，`formattedTime = "25:00"`，`progress = 0`。
- **start()**：记录内部锚点 `runStart = now()`，`phase = .running`；若 `phase == .finished`，
  先把 `elapsed` 归零再开始。已在 running 时幂等，不重置锚点。
- **pause()**：只对 running 生效，按 `now()` 结算 elapsed，`phase = .paused`；其它状态无操作。
- **tick()**：仅 running 时结算 `elapsed = 已结算 elapsed + now() - runStart`（避免逐 tick 累加漂移）。
  - 倒计时若 `elapsed >= countdownSeconds`：`elapsed = countdownSeconds`、`phase = .finished`、
    并返回 `true`（**只在首次到达完成态时返回 true**，之后再 tick 返回 false）；
  - 正计时永不 finished，始终返回 false；
  - 非 running 返回 false，且不改变状态。
- **暂停后再 start()**：从冻结的 elapsed 继续累加，不丢失已专注时间。
- **setMode**：仅当模式确实变化时 reset 并更新 mode；相同模式无副作用。
- **setCountdownSeconds**：先 clamp，再赋值并 reset；运行中调用也立即停止归零。
- **reset()**：保留 mode 和 countdownSeconds，可变回 idle。
- 所有参与 UI 的属性在变化时都必须触发 `objectWillChange`（用 `@Published` 即可）。
- 时间格式化必须与 `formattedTime` 规则一致；建议作为 `public func formatDuration(_ seconds: Int) -> String`
  或 internal helper 实现，但 UI 只用 `formattedTime`。

## 测试要求

`Tests/TimerEngineTests.swift` 为**无 XCTest 依赖**的独立测试运行器，入口为 `@main struct TimerEngineTests`，
用 `assert`/自定义 `check` 累计失败，最后打印 `ALL TESTS PASSED (N)` 并以非 0 退出表示失败。
必须用假时钟（`var fakeNow: Date; TimerEngine(now: { fakeNow })`）覆盖：

1. 初始状态与格式化（25:00 / 01:05 / 1:05:00 边界）
2. 倒计时 start → 推进 5s → 暂停 → 推进 10s（elapsed 不变）→ 继续 → 完成，`tick()` 恰好返回一次 true
3. 倒计时暂停/继续不丢时间
4. 正计时 65s 显示 `01:05`，progress 为 5/60
5. 正计时不会 finished，tick 始终 false
6. reset / setMode / setCountdownSeconds clamp（小于 60 和大于 10800）与运行中变更
7. finished 后 start() 会归零重新开始
8. progress 在 0...1 且倒计时到点恰为 1

`Scripts/test-core.sh` 负责编译并运行测试：使用 `swiftc -swift-version 5 -module-cache-path <项目内路径>`
把 `Packages/FocusCore/Sources/FocusCore/*.swift` 与 `Checks/FocusCore/*.swift`（`@main` 在 `TimerEngineTests.swift`）一起编译到 `build/tests/`。
（本机沙箱禁止写 `/var/folders` 下的默认 clang module cache，**必须**显式设置项目内 module cache。）

---

# 会话记录（FocusCore）

文件：`Packages/FocusCore/Sources/FocusCore/FocusSession.swift`（只使用 Foundation）。测试在 `Checks/FocusCore/SessionTests.swift`，由 `TimerEngineTests.main` 注册（编号 9 起）。

```swift
public enum SessionOutcome: String, Codable, Equatable { case completed, interrupted, free }

public struct FocusSession: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String                  // 结束时的标题，已去首尾空白；可为空串
    public let mode: TimerMode
    public let startedAt: Date
    public let endedAt: Date
    public let focusedSeconds: TimeInterval   // 不含暂停 = engine.elapsed
    public let plannedSeconds: TimeInterval?  // 倒计时目标；正计时为 nil
    public let outcome: SessionOutcome
    public init(id: UUID = UUID(), title:, mode:, startedAt:, endedAt:, focusedSeconds:, plannedSeconds:, outcome:)
}

public struct SessionRecorder {
    public static let minimumSeconds: TimeInterval = 60
    public init()
    public var isActive: Bool { get }
    public mutating func begin(at: Date, mode: TimerMode, plannedSeconds: TimeInterval?)
    public mutating func finish(elapsed: TimeInterval, title: String, at: Date, completed: Bool) -> FocusSession?
    @MainActor public mutating func finalize(engine: TimerEngine, title: String) -> FocusSession?
}
```

## 记录规则

| 情形 | 门槛 | outcome |
| --- | --- | --- |
| 倒计时跑完（`completed: true`） | 无 | `completed` |
| 倒计时中途结束 | `elapsed ≥ 60` | `interrupted` |
| 正计时结束 | `elapsed ≥ 60` | `free` |
| 其余 | — | 返回 nil，不存 |

- `begin` 在已有进行中会话时什么都不做（暂停后继续属于同一会话）。
- `finish` 无进行中会话时返回 nil；调用后进行中状态总是清空（即使未达门槛）。
- mode / plannedSeconds / startedAt 取 `begin` 时的值；title 取 `finish` 时的值。
- `finalize(engine:title:)` 用于重置 / 切模式 / 改时长 / 退出前：先 `engine.tick()`，若倒计时恰好在此刻到点则按 `completed` 记录（时长钳到计划时长，`endedAt = engine.finishedAt`）；否则运行中先 `pause()` 结算当前这段，再按门槛记录或丢弃。

## 存储

文件：`Packages/FocusCore/Sources/FocusCore/SessionStore.swift`。

```swift
public protocol SessionStore: AnyObject {
    func load() throws -> [FocusSession]
    func append(_ session: FocusSession) throws
}
public final class FileSessionStore: SessionStore {
    public static var defaultURL: URL   // ~/Library/Application Support/FocusOnYourself/sessions.json
    public init(url: URL, now: @escaping () -> Date = Date.init)
    public private(set) var lastBackupURL: URL?
}
public final class InMemorySessionStore: SessionStore { public init(seed: [FocusSession] = []) }
```

- 文件格式：`{"version":1,"sessions":[…]}`，日期 ISO8601，`prettyPrinted + sortedKeys`。
- 文件不存在 → `[]`。无法解析或 `version != 1` → 原文件改名为同目录 `sessions.corrupt-<yyyyMMdd-HHmmss>.json`（重名时追加短 UUID）后返回 `[]`；原文件绝不被覆盖。文件存在但读不出（权限等）→ `load()` 抛错，不改名；此时 `append` 也抛错且不写入（不覆盖原文件），记录暂存在内存，文件能读后的下一次 `append` 一并落盘。
- `load()` 结果缓存在内存；`append` 先追加到内存，再建目录并 `.atomic` 写入完整列表。写入失败时抛错，内存里的记录保留，下次成功写入时一并落盘。

## 统计

文件：`Packages/FocusCore/Sources/FocusCore/FocusStats.swift`。

```swift
public struct DailyTotal: Equatable { public let day: Date; public let seconds: TimeInterval }   // day = 当日 00:00

public struct FocusStats {
    public init(sessions: [FocusSession], now: Date, calendar: Calendar = .current)  // 内部强制 firstWeekday = 2
    public var todayFocused: TimeInterval        // 今日全部 outcome 的专注秒数
    public var todayCompletedCount: Int          // 今日 completed 条数
    public var weekFocused: TimeInterval         // 本周一 00:00 至 now
    public var streakDays: Int                   // 今天起往回连续有记录的天数；今天无记录时从昨天数
    public func dailyTotals(days: Int) -> [DailyTotal]   // 升序，末项为今天，无记录补 0
    public func recent(limit: Int) -> [FocusSession]     // 按 startedAt 倒序
}
```

会话一律按 `startedAt` 归属日期；跨午夜的会话整条算在开始那天。

## 计时快照（被杀后恢复）

`TimerEngine`（`TimerEngine.swift`）与 `SessionRecorder`（`FocusSession.swift`）新增：

```swift
public struct TimerSnapshot: Codable, Equatable {
    public var mode: TimerMode
    public var countdownSeconds: TimeInterval
    public var isRunning: Bool              // false = paused
    public var elapsedAtAnchor: TimeInterval
    public var anchor: Date                 // 运行中：本段起点；暂停：拍快照时刻（恢复时不用）
}
public var snapshot: TimerSnapshot? { get }   // TimerEngine；idle / finished 为 nil
public func restore(_ snapshot: TimerSnapshot)
public private(set) var finishedAt: Date?     // 倒计时实际到点时刻 = 本段起点 + (总长 − 段前已累计)

public struct RecorderSnapshot: Codable, Equatable { id: UUID?; startedAt: Date; mode: TimerMode; plannedSeconds: TimeInterval? }
public var snapshot: RecorderSnapshot? { get } // SessionRecorder；无进行中会话为 nil
public mutating func restore(_ snapshot: RecorderSnapshot)
```

- `restore` 不经过 `reset`。运行中按锚点把 `elapsed` 结算到 `now()`，但**不判定完成**；完成交给下一次 `tick()`，保证只触发一次（不变量 1）。暂停恢复后 `elapsed` 冻结。
- `finishedAt` 在 `tick()` 首次判定完成时赋值；`reset()` 和从 finished 再 `start()` 时清为 nil。
- 测试 23–26 覆盖：运行中跨停机时间恢复、暂停恢复、恢复后过截止只完成一次且 `finishedAt` 正确（含中途暂停）、记录器恢复。

RecorderSnapshot.id preserves the session UUID across restoration. Legacy snapshots without id remain decodable; history and completion consumers deduplicate by session ID.
