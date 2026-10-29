//
//  SessionTests.swift
//  FocusOnYourself — 会话记录 / 存储 / 统计测试（由 TimerEngineTests.main 注册）
//
//  契约来源：focusonyourself/INTERFACE.md「会话记录」
//

import Foundation

// MARK: - 辅助

func shanghaiCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    c.firstWeekday = 2
    return c
}

/// 按上海时区构造日期，例如 date(2026, 10, 25, 23, 30)。
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    shanghaiCalendar().date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

/// 每次调用返回一个新的临时目录（进程结束时由 cleanupTempDirs 删除）。
private var createdTempDirs: [URL] = []

func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("foy-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    createdTempDirs.append(url)
    return url
}

func cleanupTempDirs() {
    for url in createdTempDirs {
        try? FileManager.default.removeItem(at: url)
    }
    createdTempDirs.removeAll()
}

func sampleSession() -> FocusSession {
    FocusSession(
        title: "样例", mode: .countdown,
        startedAt: date(2026, 10, 25, 9), endedAt: date(2026, 10, 25, 9, 25),
        focusedSeconds: 1500, plannedSeconds: 1500, outcome: .completed
    )
}

// MARK: - 9. 记录门槛与 outcome

@MainActor
func testRecorderOutcomesAndThreshold(_ t: TestRunner) {
    let t0 = date(2026, 10, 25, 9, 0)
    var r = SessionRecorder()
    t.checkEqual(r.finish(elapsed: 500, title: "x", at: t0, completed: false) == nil, true, "无进行中会话 → nil")

    r.begin(at: t0, mode: .countdown, plannedSeconds: 1500)
    t.checkEqual(r.isActive, true, "begin 后 isActive")
    t.checkEqual(r.finish(elapsed: 59, title: "x", at: t0 + 59, completed: false) == nil, true, "倒计时 59s 中断 → 丢弃")
    t.checkEqual(r.isActive, false, "finish 后清空（即使丢弃）")

    r.begin(at: t0, mode: .countdown, plannedSeconds: 1500)
    guard let s1 = r.finish(elapsed: 60, title: "  写报告 \n", at: t0 + 70, completed: false) else {
        t.check(false, "倒计时 60s 中断应保存"); return
    }
    t.checkEqual(s1.outcome, .interrupted, "倒计时 60s 中断 → interrupted")
    t.checkEqual(s1.title, "写报告", "标题去首尾空白")
    t.checkEqual(s1.focusedSeconds, 60, "focusedSeconds = elapsed")
    t.checkEqual(s1.plannedSeconds, 1500, "保留 planned")
    t.checkEqual(s1.startedAt, t0, "startedAt")
    t.checkEqual(s1.endedAt, t0 + 70, "endedAt")

    r.begin(at: t0, mode: .countdown, plannedSeconds: 60)
    t.checkEqual(r.finish(elapsed: 60, title: "", at: t0 + 60, completed: true)?.outcome, .completed, "完成 → completed")
    r.begin(at: t0, mode: .countdown, plannedSeconds: 60)
    t.checkEqual(r.finish(elapsed: 30, title: "", at: t0 + 30, completed: true)?.outcome, .completed, "完成不受门槛限制")

    r.begin(at: t0, mode: .countUp, plannedSeconds: nil)
    t.checkEqual(r.finish(elapsed: 59.9, title: "", at: t0 + 60, completed: false) == nil, true, "正计时 59.9s → 丢弃")
    r.begin(at: t0, mode: .countUp, plannedSeconds: nil)
    guard let s2 = r.finish(elapsed: 61, title: "", at: t0 + 61, completed: false) else {
        t.check(false, "正计时 61s 应保存"); return
    }
    t.checkEqual(s2.outcome, .free, "正计时 ≥60s → free")
    t.checkEqual(s2.plannedSeconds == nil, true, "正计时 planned 为 nil")
    t.checkEqual(s2.title, "", "空标题存空串")
}

// MARK: - 10. begin 不会重复开始

@MainActor
func testRecorderBeginIsIdempotent(_ t: TestRunner) {
    let t0 = date(2026, 10, 25, 9, 0)
    var r = SessionRecorder()
    r.begin(at: t0, mode: .countdown, plannedSeconds: 1500)
    r.begin(at: t0 + 300, mode: .countUp, plannedSeconds: nil)
    let s = r.finish(elapsed: 600, title: "", at: t0 + 900, completed: false)
    t.checkEqual(s?.startedAt, t0, "第二次 begin 不覆盖 startedAt")
    t.checkEqual(s?.mode, .countdown, "第二次 begin 不覆盖 mode")
}

// MARK: - 11. 引擎运行中先 pause 再结算

@MainActor
func testRecorderWithEnginePauseSettles(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(mode: .countUp, now: { clock.now })
    var r = SessionRecorder()
    r.begin(at: clock.now, mode: .countUp, plannedSeconds: nil)
    engine.start()
    clock.advance(90) // 没有 tick
    engine.pause()
    let s = r.finish(elapsed: engine.elapsed, title: "", at: clock.now, completed: false)
    t.checkApprox(s?.focusedSeconds ?? -1, 90, "pause 结算后记录 90s")
}

// MARK: - 12. 完成后再来一轮

@MainActor
func testRecorderCompletionThenRestart(_ t: TestRunner) {
    let t0 = date(2026, 10, 25, 9, 0)
    var r = SessionRecorder()
    r.begin(at: t0, mode: .countdown, plannedSeconds: 60)
    let a = r.finish(elapsed: 60, title: "", at: t0 + 60, completed: true)
    t.checkEqual(r.finish(elapsed: 60, title: "", at: t0 + 61, completed: false) == nil, true, "完成后再 reset 不重复存")
    r.begin(at: t0 + 120, mode: .countdown, plannedSeconds: 60)
    let b = r.finish(elapsed: 60, title: "", at: t0 + 180, completed: true)
    t.check(a != nil && b != nil && a?.id != b?.id, "新一轮是新会话")
}

// MARK: - 13. 文件存储往返

@MainActor
func testFileStoreRoundTrip(_ t: TestRunner) {
    let url = tempDir().appendingPathComponent("sub/sessions.json") // 子目录不存在
    let s = FocusSession(
        title: "读书", mode: .countdown,
        startedAt: date(2026, 10, 25, 9), endedAt: date(2026, 10, 25, 9, 25),
        focusedSeconds: 1500, plannedSeconds: 1500, outcome: .completed
    )
    let a = FileSessionStore(url: url)
    t.checkEqual((try? a.load())?.count, 0, "文件不存在 → 空列表")
    t.check((try? a.append(s)) != nil, "append 成功")
    let loaded = try? FileSessionStore(url: url).load()
    t.checkEqual(loaded, [s], "新实例读回同一条")
    let json = String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
    t.check(json.contains("\"version\" : 1"), "包含 version 1：\(json.prefix(80))")
}

// MARK: - 14. 损坏文件留底

@MainActor
func testFileStoreCorruptBackedUp(_ t: TestRunner) {
    let dir = tempDir()
    let url = dir.appendingPathComponent("sessions.json")
    try? Data("{not json".utf8).write(to: url)
    let store = FileSessionStore(url: url, now: { date(2026, 10, 25, 21, 30, 5) })
    t.checkEqual((try? store.load())?.count, 0, "损坏 → 空列表")
    let backup = dir.appendingPathComponent("sessions.corrupt-20261025-213005.json")
    t.checkEqual(store.lastBackupURL?.lastPathComponent, backup.lastPathComponent, "留底文件名")
    t.checkEqual(try? String(contentsOf: backup, encoding: .utf8), "{not json", "留底内容原样")
}

// MARK: - 15. 未知版本留底，之后写入正常

@MainActor
func testFileStoreUnknownVersionBackedUp(_ t: TestRunner) {
    let dir = tempDir()
    let url = dir.appendingPathComponent("sessions.json")
    try? Data(#"{"version":2,"sessions":[]}"#.utf8).write(to: url)
    let store = FileSessionStore(url: url)
    _ = try? store.load()
    t.check(store.lastBackupURL != nil, "version 2 被留底")
    t.check((try? store.append(sampleSession())) != nil, "append 成功")
    t.checkEqual((try? FileSessionStore(url: url).load())?.count, 1, "新文件只含新写入的一条")
    if let backup = store.lastBackupURL {
        t.checkEqual(
            try? String(contentsOf: backup, encoding: .utf8),
            #"{"version":2,"sessions":[]}"#,
            "留底文件仍在且内容未变"
        )
    }
}

// MARK: - 16. 写入失败后下次补齐

@MainActor
func testFileStoreRetriesAfterWriteFailure(_ t: TestRunner) {
    let dir = tempDir()
    let blocker = dir.appendingPathComponent("blocked")
    try? Data().write(to: blocker) // 用同名文件占住目录位置
    let url = blocker.appendingPathComponent("sessions.json")
    let store = FileSessionStore(url: url)
    t.check((try? store.append(sampleSession())) == nil, "目录不可建 → append 抛错")
    try? FileManager.default.removeItem(at: blocker)
    t.check((try? store.append(sampleSession())) != nil, "目录可建后 append 成功")
    t.checkEqual((try? FileSessionStore(url: url).load())?.count, 2, "两条都落盘")
}

// MARK: - 统计辅助

func session(_ start: Date, _ secs: TimeInterval, _ outcome: SessionOutcome = .completed) -> FocusSession {
    FocusSession(
        title: "", mode: outcome == .free ? .countUp : .countdown,
        startedAt: start, endedAt: start + secs,
        focusedSeconds: secs, plannedSeconds: outcome == .free ? nil : 1500, outcome: outcome
    )
}

// MARK: - 17. 今日 / 本周边界与跨午夜归属

@MainActor
func testStatsTodayAndWeek(_ t: TestRunner) {
    let cal = shanghaiCalendar()
    let ss = [
        session(date(2026, 10, 25, 23, 30), 3600),            // 周日 23:30 开始、跨午夜 → 算周日
        session(date(2026, 10, 26, 0, 10), 1500),             // 周一
        session(date(2026, 10, 26, 8, 0), 600, .interrupted), // 周一
        session(date(2026, 10, 19, 10, 0), 900),              // 上周一
    ]
    let st = FocusStats(sessions: ss, now: date(2026, 10, 26, 9, 0), calendar: cal)
    t.checkEqual(st.todayFocused, 2100, "今日 = 1500 + 600（含中断）")
    t.checkEqual(st.todayCompletedCount, 1, "完成数只数 completed")
    t.checkEqual(st.weekFocused, 2100, "本周从周一 00:00 起，不含周日")

    let sunday = FocusStats(sessions: ss, now: date(2026, 10, 25, 23, 59), calendar: cal)
    t.checkEqual(sunday.weekFocused, 4500, "周日看本周 = 10/19（周一）+ 10/25")
    t.checkEqual(sunday.todayFocused, 3600, "跨午夜会话算开始那天")

    var sundayFirst = cal
    sundayFirst.firstWeekday = 1
    let forced = FocusStats(sessions: ss, now: date(2026, 10, 26, 9, 0), calendar: sundayFirst)
    t.checkEqual(forced.weekFocused, 2100, "传入周日为首的日历也按周一算")
}

// MARK: - 18. 连续天数

@MainActor
func testStatsStreak(_ t: TestRunner) {
    let cal = shanghaiCalendar()
    let now = date(2026, 10, 26, 9, 0)
    let days = [26, 25, 24, 22].map { session(date(2026, 10, $0, 10), 1500) }
    t.checkEqual(FocusStats(sessions: days, now: now, calendar: cal).streakDays, 3, "26/25/24 连续，22 断档")
    let noToday = [25, 24].map { session(date(2026, 10, $0, 10), 1500) }
    t.checkEqual(FocusStats(sessions: noToday, now: now, calendar: cal).streakDays, 2, "今天无记录时从昨天数")
    let old = [session(date(2026, 10, 23, 10), 1500)]
    t.checkEqual(FocusStats(sessions: old, now: now, calendar: cal).streakDays, 0, "昨天也无 → 0")
    t.checkEqual(FocusStats(sessions: [], now: now, calendar: cal).streakDays, 0, "空 → 0")
    let twice = [session(date(2026, 10, 26, 8), 600), session(date(2026, 10, 26, 7), 600)]
    t.checkEqual(FocusStats(sessions: twice, now: now, calendar: cal).streakDays, 1, "同一天多条只算 1 天")
}

// MARK: - 19. dailyTotals

@MainActor
func testStatsDailyTotals(_ t: TestRunner) {
    let cal = shanghaiCalendar()
    let st = FocusStats(
        sessions: [
            session(date(2026, 10, 26, 8), 600), session(date(2026, 10, 26, 7), 300),
            session(date(2026, 10, 23, 10), 1200), session(date(2026, 10, 1, 10), 999),
        ],
        now: date(2026, 10, 26, 9, 0),
        calendar: cal
    )
    let w = st.dailyTotals(days: 7)
    t.checkEqual(w.count, 7, "7 项")
    t.checkEqual(w.first?.day, date(2026, 10, 20), "首项 10/20 00:00")
    t.checkEqual(w.last?.day, date(2026, 10, 26), "末项今天 00:00")
    t.checkEqual(w.map(\.seconds), [0, 0, 0, 1200, 0, 0, 900], "按天合计并补 0")
    let m = st.dailyTotals(days: 30)
    t.checkEqual(m.count, 30, "30 项")
    t.checkEqual(m.first?.day, date(2026, 9, 27), "30 天首项 9/27")
}

// MARK: - 20. recent

@MainActor
func testStatsRecent(_ t: TestRunner) {
    let ss = (0 ..< 25).map { session(date(2026, 10, 1) + Double($0) * 3600, 600) }
    let r = FocusStats(sessions: ss.shuffled(), now: date(2026, 10, 26), calendar: shanghaiCalendar())
        .recent(limit: 20)
    t.checkEqual(r.count, 20, "上限 20")
    t.checkEqual(r.first?.startedAt, ss.last?.startedAt, "最新的在前")
    t.check(zip(r, r.dropFirst()).allSatisfy { $0.startedAt >= $1.startedAt }, "倒序")
}

// MARK: - 21. 到点未 tick 时结算记为完成（审查发现 #1）

@MainActor
func testRecorderFinalizeAfterDeadlineCompletes(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(countdownSeconds: 60, now: { clock.now })
    var r = SessionRecorder()
    r.begin(at: clock.now, mode: .countdown, plannedSeconds: 60)
    engine.start()
    clock.advance(100) // 已过终点，但没有 tick（例如 App Nap 后被注销）
    let s = r.finalize(engine: engine, title: "x")
    t.checkEqual(s?.outcome, .completed, "过终点后结算 → completed")
    t.checkApprox(s?.focusedSeconds ?? -1, 60, "时长钳到计划时长")
    t.check(engine.phase == .finished, "engine 进入 finished")

    // 未到终点：先结算正在跑的这一段，按门槛存为中断
    let clock2 = FakeClock()
    let e2 = TimerEngine(countdownSeconds: 1500, now: { clock2.now })
    var r2 = SessionRecorder()
    r2.begin(at: clock2.now, mode: .countdown, plannedSeconds: 1500)
    e2.start()
    clock2.advance(90)
    let s2 = r2.finalize(engine: e2, title: "x")
    t.checkEqual(s2?.outcome, .interrupted, "未到终点 → interrupted")
    t.checkApprox(s2?.focusedSeconds ?? -1, 90, "含未 tick 的 90s")
    t.check(e2.phase == .paused, "engine 被暂停")
    t.checkEqual(r2.finalize(engine: e2, title: "x") == nil, true, "重复结算 → nil")
}

// MARK: - 22. 文件暂时读不出：不覆盖原文件，恢复后补齐（审查发现 #4）

@MainActor
func testFileStoreUnreadableThenRecovers(_ t: TestRunner) {
    let url = tempDir().appendingPathComponent("sessions.json")
    let original = FileSessionStore(url: url)
    t.check((try? original.append(sampleSession())) != nil, "准备：原文件含 1 条")

    let fm = FileManager.default
    try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
    let store = FileSessionStore(url: url)
    t.check((try? store.load()) == nil, "读不出 → load 抛错")
    t.check((try? store.append(sampleSession())) == nil, "读不出时 append 抛错（不覆盖）")
    t.checkEqual(store.lastBackupURL == nil, true, "读不出不等于损坏，不留底改名")

    try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    t.check((try? store.append(sampleSession())) != nil, "恢复后 append 成功")
    t.checkEqual((try? FileSessionStore(url: url).load())?.count, 3, "原 1 条 + 失败那条 + 新的一条")
}

// MARK: - 23. 运行中快照跨「停机时间」恢复

@MainActor
func testEngineSnapshotRunningRestore(_ t: TestRunner) {
    let clock = FakeClock()
    let a = TimerEngine(countdownSeconds: 1500, now: { clock.now })
    a.start(); clock.advance(100); a.tick()
    guard let snap = a.snapshot else { t.check(false, "运行中应有快照"); return }
    t.checkEqual(snap.isRunning, true, "运行中快照")
    clock.advance(200) // app 被杀了 200 秒
    let b = TimerEngine(now: { clock.now })
    b.restore(snap)
    t.check(b.phase == .running, "恢复为 running")
    t.checkApprox(b.elapsed, 300, "elapsed = 100 + 200")
    t.checkEqual(b.countdownSeconds, 1500, "countdown 原样")
    clock.advance(10); b.tick()
    t.checkApprox(b.elapsed, 310, "恢复后继续走")
}

// MARK: - 24. 暂停快照恢复后时间冻结

@MainActor
func testEngineSnapshotPausedRestore(_ t: TestRunner) {
    let clock = FakeClock()
    let a = TimerEngine(mode: .countUp, now: { clock.now })
    a.start(); clock.advance(90); a.pause()
    guard let snap = a.snapshot else { t.check(false, "暂停应有快照"); return }
    t.checkEqual(snap.isRunning, false, "暂停快照")
    clock.advance(1000)
    let b = TimerEngine(now: { clock.now })
    b.restore(snap)
    t.check(b.phase == .paused && b.mode == .countUp, "恢复为 paused / countUp")
    t.checkApprox(b.elapsed, 90, "暂停期间不计时")
    b.start(); clock.advance(5); b.tick()
    t.checkApprox(b.elapsed, 95, "继续后接着累计")
    t.checkEqual(TimerEngine(now: { clock.now }).snapshot == nil, true, "idle 无快照")
}

// MARK: - 25. 恢复后已过截止：只完成一次，finishedAt = 真实到点时刻

@MainActor
func testEngineFinishedAtAfterRestore(_ t: TestRunner) {
    let clock = FakeClock()
    let t0 = clock.now
    let a = TimerEngine(countdownSeconds: 60, now: { clock.now })
    a.start(); clock.advance(10); a.tick()
    guard let snap = a.snapshot else { t.check(false, "应有快照"); return }
    clock.advance(500)
    let b = TimerEngine(now: { clock.now })
    b.restore(snap)
    t.checkEqual(b.tick(), true, "第一次 tick 完成")
    t.checkEqual(b.tick(), false, "只完成一次")
    t.checkEqual(b.finishedAt, t0 + 60, "finishedAt = 开始 + 60s")
    t.checkApprox(b.elapsed, 60, "钳到 60")
    t.checkEqual(b.snapshot == nil, true, "finished 无快照")
    b.start()
    t.checkEqual(b.finishedAt == nil, true, "finished 后再开始清 finishedAt")
    b.reset()
    t.checkEqual(b.finishedAt == nil, true, "reset 后 finishedAt 为 nil")

    // 不经快照的正常完成也记录 finishedAt
    let c = TimerEngine(countdownSeconds: 60, now: { clock.now })
    let c0 = clock.now
    c.start(); clock.advance(30); c.pause(); clock.advance(100); c.start(); clock.advance(45)
    t.checkEqual(c.tick(), true, "正常完成")
    t.checkEqual(c.finishedAt, c0 + 30 + 100 + 30, "finishedAt 计入暂停")
}

// MARK: - 26. 记录器快照恢复

@MainActor
func testRecorderSnapshotRestore(_ t: TestRunner) {
    let t0 = date(2026, 10, 26, 9)
    var a = SessionRecorder()
    t.checkEqual(a.snapshot == nil, true, "无进行中无快照")
    a.begin(at: t0, mode: .countdown, plannedSeconds: 1500)
    guard let snap = a.snapshot else { t.check(false, "应有快照"); return }
    var b = SessionRecorder()
    b.restore(snap)
    t.checkEqual(b.isActive, true, "恢复后进行中")
    let s = b.finish(elapsed: 1500, title: "x", at: t0 + 1500, completed: true)
    t.checkEqual(s?.startedAt, t0, "startedAt 恢复")
    t.checkEqual(s?.plannedSeconds, 1500, "planned 恢复")
    t.checkEqual(s?.mode, .countdown, "mode 恢复")
}
