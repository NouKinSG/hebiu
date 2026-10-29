#if os(macOS)
import AppKit
#endif
import HebiuKit
import Combine
import FocusCore
import Foundation
import SwiftUI

/// Mutable wall clock used only by demo/snapshot states, so the app can render
/// a realistic mid-session UI without waiting. Production sessions keep offset 0.
final class DemoClock {
    static let shared = DemoClock()
    var offset: TimeInterval = 0

    func now() -> Date {
        Date().addingTimeInterval(offset)
    }
}

@MainActor
final class FocusModel: ObservableObject {
    enum DefaultsKey {
        static let focusTitle = "foy.focusTitle"
        static let mode = "foy.mode"
        static let countdownSeconds = "foy.countdownSeconds"
        static let completedSessions = "foy.completedSessions"
        static let completionDay = "foy.completionDay"
        static let legacyMigrationDone = "foy.legacyMigrationDone"
        static let dashboardVisible = "foy.dashboardVisible"
        static let activeTimer = "foy.activeTimer"
        static let pendingSessions = "foy.pendingSessions"
        static let completionOutbox = "foy.completionOutbox"
    }

    private enum LegacyDefaults {
        static let suiteName = "com.lukaspeng.pomodoro"
        static let keyMap: [(old: String, new: String)] = [
            ("pomodoro.focusTitle", DefaultsKey.focusTitle),
            ("pomodoro.mode", DefaultsKey.mode),
            ("pomodoro.countdownSeconds", DefaultsKey.countdownSeconds),
            ("pomodoro.completedSessions", DefaultsKey.completedSessions),
            ("pomodoro.completionDay", DefaultsKey.completionDay),
        ]
    }

    static var defaultDefaults: UserDefaults {
        let suffix: String
        if ProcessInfo.processInfo.environment["HEBIU_HOME"] != nil {
            suffix = "." + Data(Paths.dataDir.path.utf8).base64EncodedString()
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        } else { suffix = "" }
        return UserDefaults(suiteName: "io.github.hebiu.focus" + suffix)!
    }
    static let presets = [15, 25, 45, 60]
    static let demoDefaultTitle = "把今天最重要的事做完"

    var onStart: (() -> Void)?
    var onCompleted: (() -> Void)?
    var onSessionCompleted: ((FocusCore.FocusSession) -> Void)?
    var onReset: (() -> Void)?
    struct CompletionNotice: Codable {
        var session: FocusCore.FocusSession
        var recovered: Bool
        var breakCancelled: Bool = false
    }
    private(set) var pendingCompletions: [CompletionNotice] = []
    @Published private(set) var persistenceError: String?
    private var pendingSessions: [FocusCore.FocusSession] = []
    private var nextSaveRetry = Date.distantPast
    private let fallbackMemory: Bool
    var integrationDefaults: UserDefaults { defaults }
    let engine: TimerEngine
    let isDemo: Bool

    @Published var focusTitle: String {
        didSet { persist(focusTitle, forKey: DefaultsKey.focusTitle) }
    }
    @Published var customMinutes: Int = 25
    @Published var isCustomEditorPresented = false
    @Published private(set) var sessions: [FocusCore.FocusSession]
    /// 空闲时每 60 秒更新一次，让「今日」等统计跨过午夜后刷新。
    @Published private(set) var statsClock = Date()
    @Published var isDashboardVisible: Bool {
        didSet { persist(isDashboardVisible, forKey: DefaultsKey.dashboardVisible) }
    }

    private let defaults: UserDefaults
    private let environment: [String: String]
    private let store: SessionStore
    private let scheduler: NotificationScheduling
    private var recorder = SessionRecorder()
    private var terminationObserver: NSObjectProtocol?
    private var didPrepareDemo = false

    /// Storage and clock can be injected for isolated checks. Production history lives
    /// under Hebiu's data directory; pet completion notifications belong to the controller.
    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        store: SessionStore? = nil,
        clock: (() -> Date)? = nil,
        scheduler: NotificationScheduling? = nil
    ) {
        self.defaults = defaults
        self.environment = environment
        let isDemo = environment["FOY_DEMO_STATE"] != nil
            || environment["FOY_SNAPSHOT_DIR"] != nil
        self.isDemo = isDemo
        self.scheduler = scheduler ?? NoopNotificationScheduler()

        if !self.isDemo, defaults === UserDefaults.standard {
            Self.migrateLegacyDefaultsIfNeeded(into: defaults)
        }

        let savedMode = TimerMode(rawValue: defaults.string(forKey: DefaultsKey.mode) ?? "") ?? .countdown
        // 按 NSNumber 读：外部写入的 float / int 也能读到（`as? Double` 对 Float 存储会失败）
        let savedSeconds = (defaults.object(forKey: DefaultsKey.countdownSeconds) as? NSNumber)?.doubleValue ?? 25 * 60
        let safeSeconds = min(max(savedSeconds, 60), 180 * 60)

        self.engine = TimerEngine(
            mode: savedMode,
            countdownSeconds: safeSeconds,
            now: clock ?? { DemoClock.shared.now() }
        )

        let demoTitle = environment["FOY_DEMO_TITLE"]
        self.focusTitle = defaults.string(forKey: DefaultsKey.focusTitle)
            ?? demoTitle
            ?? (environment["FOY_DEMO_STATE"] != nil ? Self.demoDefaultTitle : "")
        self.customMinutes = Int((safeSeconds / 60).rounded())

        if self.isDemo {
            self.store = store ?? InMemorySessionStore(seed: DemoSessions.make(now: Date()))
            self.isDashboardVisible = environment["FOY_DEMO_STATE"]?.lowercased() == "dashboard"
        } else {
            self.store = store ?? Self.openProductionStore(defaults: defaults)
            self.isDashboardVisible = defaults.object(forKey: DefaultsKey.dashboardVisible) as? Bool ?? true
        }

        self.fallbackMemory = store == nil && !isDemo && (self.store as? SwiftDataSessionStore)?.isPersistent == false
        do {
            self.sessions = try self.store.load()
        } catch {
            NSLog("FocusOnYourself: failed to load sessions: \(error)")
            self.sessions = []
        }

        if !self.isDemo {
            if let data = defaults.data(forKey: DefaultsKey.pendingSessions),
               let pending = try? JSONDecoder().decode([FocusCore.FocusSession].self, from: data) {
                pendingSessions = pending
                for session in pending where !sessions.contains(where: { $0.id == session.id }) { sessions.append(session) }
            }
            if let data = defaults.data(forKey: DefaultsKey.completionOutbox),
               let notices = try? JSONDecoder().decode([CompletionNotice].self, from: data) {
                pendingCompletions = notices.map { var event = $0; event.recovered = true; return event }
                for event in notices {
                    if !sessions.contains(where: { $0.id == event.session.id }) {
                        sessions.append(event.session)
                        if !pendingSessions.contains(where: { $0.id == event.session.id }) { pendingSessions.append(event.session) }
                    }
                }
                persistPendingSessions()
            }
            retryPendingSaves()
            restoreActiveTimer()
            #if os(macOS)
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleTermination()
                }
            }
            #endif
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    private static func openProductionStore(defaults: UserDefaults) -> SessionStore {
        let directory = Paths.dataDir.appendingPathComponent("focus")
        return SwiftDataSessionStore.openOnDisk(directory: directory)
    }

    // MARK: - Preferences

    /// 写入用户偏好的唯一入口：演示 / 截图模式下一律不写（不变量 3）。
    /// 旧版迁移只在非演示模式下运行，单独直接写入。
    private func persist(_ value: Any, forKey key: String) {
        guard !isDemo else { return }
        defaults.set(value, forKey: key)
    }

    // MARK: - Legacy settings

    /// Copies the old `com.lukaspeng.pomodoro` preferences into the new
    /// `com.lukaspeng.focusonyourself` domain exactly once. The legacy domain is
    /// left untouched, and existing new-domain values always win.
    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.legacyMigrationDone) else { return }
        defer { defaults.set(true, forKey: DefaultsKey.legacyMigrationDone) }

        guard let legacy = UserDefaults(suiteName: LegacyDefaults.suiteName) else { return }
        for pair in LegacyDefaults.keyMap where defaults.object(forKey: pair.new) == nil {
            if let value = legacy.object(forKey: pair.old) {
                defaults.set(value, forKey: pair.new)
            }
        }
    }

    // MARK: - Derived state

    var durationMinutes: Int {
        max(1, Int((engine.countdownSeconds / 60).rounded()))
    }

    var isCustomDuration: Bool {
        !Self.presets.contains(durationMinutes)
    }

    var canReset: Bool {
        engine.phase != .idle || engine.elapsed > 0.4
    }

    var stats: FocusStats {
        FocusStats(sessions: sessions, now: max(statsClock, Date()))
    }

    var todayCount: Int {
        stats.todayCompletedCount
    }

    // MARK: - Commands

    func startPause() {
        // A click can arrive after the deadline but before the next timer tick.
        if engine.isRunning {
            tick()
            if engine.phase == .finished { return }
        }
        let isNewSession = engine.phase == .idle || engine.phase == .finished
        beginSessionIfNeeded()
        withAnimation(.easeOut(duration: 0.18)) {
            engine.toggle()
        }
        activeTimerDidChange()
        if isNewSession && engine.isRunning { onStart?() }
    }

    func reset() {
        finalizeActiveSession()
        withAnimation(.easeOut(duration: 0.2)) {
            engine.reset()
        }
        activeTimerDidChange()
        onReset?()
    }

    func setMode(_ mode: TimerMode) {
        guard engine.mode != mode else { return }
        finalizeActiveSession()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            engine.setMode(mode)
        }
        persist(mode.rawValue, forKey: DefaultsKey.mode)
        activeTimerDidChange()
        onReset?()
    }

    func selectPreset(minutes: Int) {
        guard engine.mode == .countdown else { return }
        finalizeActiveSession()
        withAnimation(.easeOut(duration: 0.2)) {
            engine.setCountdownSeconds(Double(minutes) * 60)
        }
        customMinutes = max(1, Int(engine.countdownSeconds / 60))
        persist(engine.countdownSeconds, forKey: DefaultsKey.countdownSeconds)
        activeTimerDidChange()
        onReset?()
    }

    func openCustomEditor() {
        customMinutes = durationMinutes
        isCustomEditorPresented = true
    }

    func applyCustomDuration() {
        let clamped = min(max(customMinutes, 1), 180)
        finalizeActiveSession()
        withAnimation(.easeOut(duration: 0.2)) {
            engine.setCountdownSeconds(Double(clamped * 60))
        }
        customMinutes = clamped
        isCustomEditorPresented = false
        persist(engine.countdownSeconds, forKey: DefaultsKey.countdownSeconds)
        activeTimerDidChange()
        onReset?()
    }

    func cancelCustomEditor() {
        isCustomEditorPresented = false
    }

    func toggleDashboard() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isDashboardVisible.toggle()
        }
    }

    /// iOS 场景回到前台时调用：立即结算，后台期间到点的倒计时马上按完成记录。
    func sceneBecameActive() {
        tick()
    }

    /// Called by the app's common-mode timer, independent of visible windows.
    func tick() {
        if engine.now() >= nextSaveRetry { retryPendingSaves() }
        if engine.tick() {
            handleCompletion()
        }
        if Date().timeIntervalSince(statsClock) >= 60 {
            statsClock = Date()
        }
    }

    func prepareDemoIfNeeded() {
        guard !didPrepareDemo else { return }
        didPrepareDemo = true
        guard let state = environment["FOY_DEMO_STATE"]?.lowercased() else { return }

        focusTitle = environment["FOY_DEMO_TITLE"] ?? Self.demoDefaultTitle

        switch state {
        case "countdown", "running":
            engine.setMode(.countdown)
            engine.setCountdownSeconds(25 * 60)
            beginSessionIfNeeded()
            engine.start()
            DemoClock.shared.offset = 9 * 60 + 18
            tickWithoutCompletionSideEffects()

        case "countup", "stopwatch":
            engine.setMode(.countUp)
            beginSessionIfNeeded()
            engine.start()
            DemoClock.shared.offset = 12 * 60 + 34
            tickWithoutCompletionSideEffects()

        case "paused":
            engine.setMode(.countdown)
            engine.setCountdownSeconds(25 * 60)
            beginSessionIfNeeded()
            engine.start()
            DemoClock.shared.offset = 11 * 60 + 6
            tickWithoutCompletionSideEffects()
            engine.pause()

        case "finished", "complete":
            engine.setMode(.countdown)
            engine.setCountdownSeconds(25 * 60)
            beginSessionIfNeeded()
            engine.start()
            DemoClock.shared.offset = 25 * 60 + 4
            tickWithoutCompletionSideEffects()

        case "dashboard":
            // 侧栏展开、计时器空闲；时长同 idle 固定 25 分钟
            engine.setMode(.countdown)
            engine.setCountdownSeconds(25 * 60)

        default:
            // 空闲态也固定 25 分钟，避免演示截图受真实用户设置影响
            engine.setMode(.countdown)
            engine.setCountdownSeconds(25 * 60)
        }
    }

    // MARK: - Sessions

    /// 从 idle / finished 开始时创建会话；暂停后继续沿用同一条。
    private func beginSessionIfNeeded() {
        guard engine.phase == .idle || engine.phase == .finished else { return }
        recorder.begin(
            at: engine.now(),
            mode: engine.mode,
            plannedSeconds: engine.mode == .countdown ? engine.countdownSeconds : nil
        )
    }

    /// 在 engine 归零（重置 / 切模式 / 改时长）或退出之前调用；判定见
    /// `SessionRecorder.finalize`。可重复调用。
    private func finalizeActiveSession() {
        tick() // Settle completion and emit its event before recorder finalization.
        save(recorder.finalize(engine: engine, title: focusTitle))
    }

    private func save(_ session: FocusCore.FocusSession?) {
        guard let session else { return }
        // Stable IDs make replay after DB commit / snapshot cleanup idempotent.
        if !sessions.contains(where: { $0.id == session.id }) { sessions.append(session) }
        if !pendingSessions.contains(where: { $0.id == session.id }) { pendingSessions.append(session) }
        statsClock = engine.now()
        persistPendingSessions() // Journal before clearing the active timer snapshot.
        retryPendingSaves()
    }

    private func persistPendingSessions() {
        guard !isDemo else { return }
        if pendingSessions.isEmpty { defaults.removeObject(forKey: DefaultsKey.pendingSessions) }
        else if let data = try? JSONEncoder().encode(pendingSessions) {
            defaults.set(data, forKey: DefaultsKey.pendingSessions)
        }
    }

    private func retryPendingSaves() {
        nextSaveRetry = engine.now().addingTimeInterval(5)
        guard !pendingSessions.isEmpty else { return }
        guard !fallbackMemory else {
            persistenceError = "专注数据库暂不可用，记录已暂存，重启后会重试。"
            return
        }
        while let session = pendingSessions.first {
            do { try store.append(session) }
            catch {
                persistenceError = "专注记录暂未写入数据库，已保留并会自动重试。"
                return
            }
            pendingSessions.removeFirst()
            persistPendingSessions()
        }
        persistenceError = nil
    }

    private func persistCompletionOutbox() {
        guard !isDemo else { return }
        if pendingCompletions.isEmpty { defaults.removeObject(forKey: DefaultsKey.completionOutbox) }
        else if let data = try? JSONEncoder().encode(pendingCompletions) { defaults.set(data, forKey: DefaultsKey.completionOutbox) }
    }

    func acknowledgeCompletion(_ id: UUID) {
        pendingCompletions.removeAll { $0.session.id == id }
        persistCompletionOutbox()
    }

    func cancelPendingBreaks() {
        for index in pendingCompletions.indices { pendingCompletions[index].breakCancelled = true }
        persistCompletionOutbox()
    }

    // MARK: - Active timer persistence

    /// 退出前结算进行中的会话并清掉快照，下次打开为空闲状态（Mac 正常退出路径）。
    func handleTermination() {
        finalizeActiveSession()
        engine.reset()
        activeTimerDidChange()
    }

    /// 计时状态变化后统一调用：保存快照，并同步到点通知的预约。
    private func activeTimerDidChange() {
        saveActiveTimer()
        syncCompletionNotification()
    }

    /// 运行中的倒计时按剩余时间预约通知；其余状态取消预约。
    private func syncCompletionNotification() {
        scheduler.cancelPending()
        guard engine.isRunning, engine.mode == .countdown else { return }
        scheduler.requestAuthorizationIfNeeded()
        scheduler.scheduleCompletion(after: engine.countdownRemaining, title: focusTitle)
    }

    /// 把运行中 / 暂停的计时写入 `foy.activeTimer`；空闲或已完成时删除该键。
    /// 只在状态变化时调用（不在 tick 里写）；演示模式不写（不变量 3）。
    private func saveActiveTimer() {
        guard !isDemo else { return }
        guard let snapshot = engine.snapshot else {
            defaults.removeObject(forKey: DefaultsKey.activeTimer)
            return
        }
        let state = ActiveTimerState(engine: snapshot, recorder: recorder.snapshot)
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: DefaultsKey.activeTimer)
        }
    }

    /// 启动时恢复上次未结束的计时；关闭期间已到点的倒计时立即按完成记录。
    private func restoreActiveTimer() {
        guard let data = defaults.data(forKey: DefaultsKey.activeTimer) else { return }
        guard let state = try? JSONDecoder().decode(ActiveTimerState.self, from: data) else {
            NSLog("FocusOnYourself: discarding unreadable active timer snapshot")
            defaults.removeObject(forKey: DefaultsKey.activeTimer)
            return
        }
        engine.restore(state.engine)
        if let recorderSnapshot = state.recorder {
            recorder.restore(recorderSnapshot)
        }
        customMinutes = max(1, Int((engine.countdownSeconds / 60).rounded()))
        if engine.tick() {
            handleCompletion(notify: false)
        } else {
            activeTimerDidChange()
        }
    }

    // MARK: - Completion

    private func tickWithoutCompletionSideEffects() {
        if engine.tick() {
            handleCompletion(notify: false)
        }
    }

    private func handleCompletion(notify: Bool = true) {
        // 结束时间用真实到点时刻：后台 / 关闭期间完成的一轮不会记成「下次打开的时刻」
        let endedAt = engine.finishedAt ?? engine.now()
        guard let session = recorder.finish(elapsed: engine.elapsed, title: focusTitle, at: endedAt, completed: true) else { return }
        // Journal the event before clearing the timer snapshot. A second crash must not
        // lose statistics/rest effects after the history record has already committed.
        if !isDemo && !pendingCompletions.contains(where: { $0.session.id == session.id }) {
            pendingCompletions.append(CompletionNotice(session: session, recovered: !notify))
            persistCompletionOutbox()
        }
        save(session)
        // 只保存快照、不取消通知：iOS 预约的那条正好在此刻送达（横幅 + 声音 + 触感），
        // 完成处理本身不再另发通知，避免重复
        saveActiveTimer()

        // 即时提醒只经由注入的调度器发出：测试注入假实现时不会触达真实通知 / 提示音 / Dock
        guard notify, !isDemo else { return }
        scheduler.deliverCompletion(focusTitle: focusTitle)
        onCompleted?()
        onSessionCompleted?(session)
    }
}
