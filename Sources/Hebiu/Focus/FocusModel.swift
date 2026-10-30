#if os(macOS)
import AppKit
#endif
import HebiuKit
import Combine
import FocusCore
import Foundation
import SwiftUI

@MainActor
final class FocusModel: ObservableObject {
    enum DefaultsKey {
        static let focusTitle = "foy.focusTitle"
        static let mode = "foy.mode"
        static let countdownSeconds = "foy.countdownSeconds"
        static let completedSessions = "foy.completedSessions"
        static let completionDay = "foy.completionDay"
        static let dashboardVisible = "foy.dashboardVisible"
        static let activeTimer = "foy.activeTimer"
        static let pendingSessions = "foy.pendingSessions"
        static let completionOutbox = "foy.completionOutbox"
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
    private let store: SessionStore
    private let scheduler: NotificationScheduling
    private var recorder = SessionRecorder()
    private var terminationObserver: NSObjectProtocol?

    /// 可注入存储与时钟进行隔离测试。正式历史放在 Hebiu 数据目录，桌宠通知交给控制器。
    init(
        defaults: UserDefaults = .standard,
        store: SessionStore? = nil,
        clock: (() -> Date)? = nil,
        scheduler: NotificationScheduling? = nil
    ) {
        self.defaults = defaults
        self.scheduler = scheduler ?? NoopNotificationScheduler()

        let savedMode = TimerMode(rawValue: defaults.string(forKey: DefaultsKey.mode) ?? "") ?? .countdown
        // 按 NSNumber 读：外部写入的 float / int 也能读到（`as? Double` 对 Float 存储会失败）
        let savedSeconds = (defaults.object(forKey: DefaultsKey.countdownSeconds) as? NSNumber)?.doubleValue ?? 25 * 60
        let safeSeconds = min(max(savedSeconds, 60), 180 * 60)

        self.engine = TimerEngine(
            mode: savedMode,
            countdownSeconds: safeSeconds,
            now: clock ?? Date.init
        )

        self.focusTitle = defaults.string(forKey: DefaultsKey.focusTitle) ?? ""
        self.customMinutes = Int((safeSeconds / 60).rounded())
        self.store = store ?? Self.openProductionStore()
        self.isDashboardVisible = defaults.object(forKey: DefaultsKey.dashboardVisible) as? Bool ?? true
        self.fallbackMemory = store == nil && (self.store as? SwiftDataSessionStore)?.isPersistent == false
        do {
            self.sessions = try self.store.load()
        } catch {
            NSLog("FocusOnYourself: failed to load sessions: \(error)")
            self.sessions = []
        }

        do {
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

    private static func openProductionStore() -> SessionStore {
        let directory = Paths.dataDir.appendingPathComponent("focus")
        return SwiftDataSessionStore.openOnDisk(directory: directory)
    }

    // MARK: - 偏好设置

    /// 写入用户偏好的统一入口。
    private func persist(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - 派生状态

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

    // MARK: - 操作

    func startPause() {
        // 点击可能发生在截止时间之后、下一次计时更新之前。
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

    /// 由应用级计时器调用，不依赖窗口是否可见。
    func tick() {
        if engine.now() >= nextSaveRetry { retryPendingSaves() }
        if engine.tick() {
            handleCompletion()
        }
        if Date().timeIntervalSince(statsClock) >= 60 {
            statsClock = Date()
        }
    }

    // MARK: - 会话记录

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
        tick() // 结算记录前先处理到点完成及其事件。
        save(recorder.finalize(engine: engine, title: focusTitle))
    }

    private func save(_ session: FocusCore.FocusSession?) {
        guard let session else { return }
        // 稳定标识保证数据库提交后、快照清理前的重放不会重复记账。
        if !sessions.contains(where: { $0.id == session.id }) { sessions.append(session) }
        if !pendingSessions.contains(where: { $0.id == session.id }) { pendingSessions.append(session) }
        statsClock = engine.now()
        persistPendingSessions() // 清除计时快照前先保存待写入记录。
        retryPendingSaves()
    }

    private func persistPendingSessions() {
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

    // MARK: - 计时快照

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
    /// 只在状态变化时调用，不在计时更新中重复写入。
    private func saveActiveTimer() {
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

    // MARK: - 完成处理

    private func handleCompletion(notify: Bool = true) {
        // 结束时间用真实到点时刻：后台 / 关闭期间完成的一轮不会记成「下次打开的时刻」
        let endedAt = engine.finishedAt ?? engine.now()
        guard let session = recorder.finish(elapsed: engine.elapsed, title: focusTitle, at: endedAt, completed: true) else { return }
        // 清除计时快照前保存事件，避免历史提交后的第二次崩溃丢失统计和休息联动。
        if !pendingCompletions.contains(where: { $0.session.id == session.id }) {
            pendingCompletions.append(CompletionNotice(session: session, recovered: !notify))
            persistCompletionOutbox()
        }
        save(session)
        // 只保存快照、不取消通知：iOS 预约的那条正好在此刻送达（横幅 + 声音 + 触感），
        // 完成处理本身不再另发通知，避免重复
        saveActiveTimer()

        // 即时提醒只经由注入的调度器发出：测试注入假实现时不会触达真实通知 / 提示音 / Dock
        guard notify else { return }
        scheduler.deliverCompletion(focusTitle: focusTitle)
        onCompleted?()
        onSessionCompleted?(session)
    }
}
