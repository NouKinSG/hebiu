//
//  TimerEngineTests.swift
//  FocusOnYourself — TimerEngine 核心测试（无 XCTest 依赖的独立运行器）
//
//  运行方式：bash Scripts/test-core.sh
//  约定：全部通过时打印 `ALL TESTS PASSED (N)` 并以 0 退出；
//        任一检查失败时打印失败详情并以非 0 退出。
//
//  契约来源：focusonyourself/INTERFACE.md
//

import Foundation
import Combine

// MARK: - 假时钟

/// 可手动推进的假时钟，注入给 TimerEngine 以避免真实等待。
final class FakeClock {
    private(set) var now: Date

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = start
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

// MARK: - 极简测试运行器

@MainActor
final class TestRunner {
    private(set) var failures: [String] = []
    private(set) var checkCount = 0
    private(set) var testCount = 0
    private var currentTest = ""

    /// 注册并执行一个测试用例。
    func test(_ name: String, _ body: () -> Void) {
        testCount += 1
        currentTest = name
        let before = failures.count
        body()
        print(failures.count == before ? "PASS  \(name)" : "FAIL  \(name)")
    }

    func check(
        _ condition: Bool,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        checkCount += 1
        guard !condition else { return }
        let text = "FAIL [\(currentTest)] \(message()) (\(file):\(line))"
        failures.append(text)
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    func checkEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        check(actual == expected, "\(label): expected \(expected), got \(actual)", file: file, line: line)
    }

    func checkApprox(
        _ actual: Double,
        _ expected: Double,
        _ label: String,
        tolerance: Double = 1e-9,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        check(
            abs(actual - expected) <= tolerance,
            "\(label): expected \(expected) (±\(tolerance)), got \(actual)",
            file: file,
            line: line
        )
    }
}

// MARK: - 测试入口

@main
struct TimerEngineTests {
    @MainActor
    static func main() {
        print("TimerEngineTests — FocusCore")
        let runner = TestRunner()

        runner.test("1. 初始状态与时间格式化（25:00 / 01:05 / 1:05:00 边界）") {
            testInitialStateAndFormatting(runner)
        }
        runner.test("2. 倒计时 start → 5s → pause → 10s → resume → 完成，tick() 仅首次返回 true") {
            testCountdownLifecycleCompletionOnce(runner)
        }
        runner.test("3. 倒计时暂停/继续不丢时间") {
            testPauseResumePreservesElapsed(runner)
        }
        runner.test("4. 正计时 65s 显示 01:05，progress 为 5/60") {
            testCountUpDisplayAndProgress(runner)
        }
        runner.test("5. 正计时永不 finished，tick 始终 false") {
            testCountUpNeverFinishes(runner)
        }
        runner.test("6. reset / setMode / setCountdownSeconds clamp 与运行中变更") {
            testResetSetModeAndCountdownClamp(runner)
        }
        runner.test("7. finished 后 start() 归零重新开始") {
            testRestartAfterFinished(runner)
        }
        runner.test("8. progress 在 0...1 且倒计时到点恰为 1") {
            testProgressBoundsAndCompletion(runner)
        }
        runner.test("9. 记录门槛与 outcome（59s 丢弃 / 60s 保存 / 完成不设门槛）") {
            testRecorderOutcomesAndThreshold(runner)
        }
        runner.test("10. SessionRecorder.begin 不会重复开始") {
            testRecorderBeginIsIdempotent(runner)
        }
        runner.test("11. 运行中先 pause 再结算，未 tick 的时间也计入") {
            testRecorderWithEnginePauseSettles(runner)
        }
        runner.test("12. 完成后再来一轮是新会话，完成后 reset 不重复存") {
            testRecorderCompletionThenRestart(runner)
        }
        runner.test("13. FileSessionStore 往返读写，文件不存在为空") {
            testFileStoreRoundTrip(runner)
        }
        runner.test("14. 损坏文件改名留底，不覆盖") {
            testFileStoreCorruptBackedUp(runner)
        }
        runner.test("15. 未知版本留底，之后写入新文件") {
            testFileStoreUnknownVersionBackedUp(runner)
        }
        runner.test("16. 写入失败保留内存，下次写入补齐") {
            testFileStoreRetriesAfterWriteFailure(runner)
        }
        runner.test("17. 今日 / 本周边界（周日→周一），跨午夜按开始时间归属") {
            testStatsTodayAndWeek(runner)
        }
        runner.test("18. 连续天数（今天有 / 今天无从昨天数 / 断档）") {
            testStatsStreak(runner)
        }
        runner.test("19. dailyTotals 升序补 0，末项今天") {
            testStatsDailyTotals(runner)
        }
        runner.test("20. recent 倒序与条数上限") {
            testStatsRecent(runner)
        }
        runner.test("21. 到点未 tick 时结算记为完成并钳到计划时长") {
            testRecorderFinalizeAfterDeadlineCompletes(runner)
        }
        runner.test("22. 文件暂时读不出时不覆盖，恢复后补齐") {
            testFileStoreUnreadableThenRecovers(runner)
        }
        runner.test("23. 运行中快照跨停机时间恢复，时间不丢") {
            testEngineSnapshotRunningRestore(runner)
        }
        runner.test("24. 暂停快照恢复后时间冻结，idle 无快照") {
            testEngineSnapshotPausedRestore(runner)
        }
        runner.test("25. 恢复后过截止只完成一次，finishedAt 为真实到点时刻") {
            testEngineFinishedAtAfterRestore(runner)
        }
        runner.test("26. 记录器快照恢复") {
            testRecorderSnapshotRestore(runner)
        }
        cleanupTempDirs()

        print("Checks run: \(runner.checkCount)")
        if runner.failures.isEmpty {
            print("ALL TESTS PASSED (\(runner.testCount))")
            exit(0)
        } else {
            print("TEST SUITE FAILED: \(runner.failures.count) failed check(s) in \(runner.testCount) test(s)")
            exit(1)
        }
    }
}

// MARK: - 1. 初始状态与格式化

@MainActor
private func testInitialStateAndFormatting(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(now: { clock.now })

    t.check(engine.mode == .countdown, "默认 mode 应为 .countdown")
    t.check(engine.phase == .idle, "默认 phase 应为 .idle")
    t.checkApprox(engine.elapsed, 0, "初始 elapsed")
    t.checkApprox(engine.countdownSeconds, 1500, "初始 countdownSeconds")
    t.check(!engine.isRunning, "初始 isRunning 应为 false")
    t.checkApprox(engine.countdownRemaining, 1500, "初始 countdownRemaining")
    t.checkEqual(engine.displaySeconds, 1500, "初始 displaySeconds")
    t.checkEqual(engine.formattedTime, "25:00", "初始 formattedTime")
    t.checkApprox(engine.progress, 0, "初始 progress")

    // 格式化边界：分钟补零、小时不补零、分秒补零。
    let e65 = TimerEngine(countdownSeconds: 65, now: { clock.now })
    t.checkEqual(e65.displaySeconds, 65, "65 秒 displaySeconds")
    t.checkEqual(e65.formattedTime, "01:05", "65 秒 formattedTime")

    let e3599 = TimerEngine(countdownSeconds: 3599, now: { clock.now })
    t.checkEqual(e3599.formattedTime, "59:59", "3599 秒 formattedTime")

    let e3600 = TimerEngine(countdownSeconds: 3600, now: { clock.now })
    t.checkEqual(e3600.formattedTime, "1:00:00", "3600 秒 formattedTime")

    let e3900 = TimerEngine(countdownSeconds: 3900, now: { clock.now })
    t.checkEqual(e3900.displaySeconds, 3900, "3900 秒 displaySeconds")
    t.checkEqual(e3900.formattedTime, "1:05:00", "3900 秒 formattedTime")

    let e3661 = TimerEngine(countdownSeconds: 3661, now: { clock.now })
    t.checkEqual(e3661.formattedTime, "1:01:01", "3661 秒 formattedTime")

    // 契约要求：参与 UI 的属性变化时触发 objectWillChange。
    var changeCount = 0
    let cancellable = engine.objectWillChange.sink { _ in changeCount += 1 }
    engine.start()
    t.check(changeCount > 0, "start() 应触发 objectWillChange，实际 \(changeCount) 次")
    cancellable.cancel()
}

// MARK: - 2. 倒计时生命周期与 completion 只触发一次

@MainActor
private func testCountdownLifecycleCompletionOnce(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(countdownSeconds: 10, now: { clock.now })

    engine.start()
    t.check(engine.isRunning, "start() 后应为 running")
    t.check(engine.phase == .running, "start() 后 phase 应为 .running")

    clock.advance(5)
    t.checkEqual(engine.tick(), false, "进行中 tick 不应返回 true")
    t.checkApprox(engine.elapsed, 5, "推进 5s 后 elapsed")
    t.checkApprox(engine.countdownRemaining, 5, "推进 5s 后 countdownRemaining")
    t.checkEqual(engine.displaySeconds, 5, "推进 5s 后 displaySeconds")

    engine.pause()
    t.check(engine.phase == .paused, "pause() 后 phase 应为 .paused")
    t.checkApprox(engine.elapsed, 5, "pause() 结算 elapsed")

    clock.advance(10)
    t.checkEqual(engine.tick(), false, "暂停时 tick 应返回 false")
    t.checkApprox(engine.elapsed, 5, "暂停期间 elapsed 不应变化")
    t.check(engine.phase == .paused, "暂停时 tick 不应改变 phase")

    engine.start() // 继续
    t.check(engine.isRunning, "暂停后 start() 应继续运行")
    clock.advance(4)
    t.checkEqual(engine.tick(), false, "未到点 tick 返回 false")
    t.checkApprox(engine.elapsed, 9, "继续后 elapsed 累加")

    clock.advance(1)
    var completionCount = 0
    if engine.tick() { completionCount += 1 }
    t.checkEqual(completionCount, 1, "首次到点 tick 应返回 true")
    t.check(engine.phase == .finished, "到点后 phase 应为 .finished")
    t.check(!engine.isRunning, "finished 时 isRunning 应为 false")
    t.checkApprox(engine.elapsed, 10, "到点后 elapsed 应钳到 countdownSeconds")
    t.checkEqual(engine.displaySeconds, 0, "到点后 displaySeconds 应为 0")

    // 完成之后再 tick 一律 false，且不再改变状态。
    if engine.tick() { completionCount += 1 }
    t.checkEqual(completionCount, 1, "再次 tick 不应再次返回 true")
    clock.advance(100)
    if engine.tick() { completionCount += 1 }
    t.checkEqual(completionCount, 1, "完成后推进时间再 tick 仍不应返回 true")
    t.check(engine.phase == .finished, "完成后 tick 不应改变 phase")
    t.checkApprox(engine.elapsed, 10, "完成后 elapsed 不应变化")
}

// MARK: - 3. 暂停/继续不丢时间

@MainActor
private func testPauseResumePreservesElapsed(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(countdownSeconds: 20, now: { clock.now })

    engine.start()
    clock.advance(7)
    engine.pause()
    t.checkApprox(engine.elapsed, 7, "暂停时应结算已专注 7s")

    clock.advance(1000)
    t.checkEqual(engine.tick(), false, "暂停期间 tick 返回 false")
    t.checkApprox(engine.elapsed, 7, "长时间暂停后 elapsed 保持 7")

    engine.start()
    clock.advance(3)
    engine.tick()
    t.checkApprox(engine.elapsed, 10, "继续 3s 后累计 10s（不丢时间）")
    t.checkApprox(engine.countdownRemaining, 10, "剩余时间应为 10s")
    t.checkEqual(engine.displaySeconds, 10, "displaySeconds 应为 10")
    t.checkEqual(engine.formattedTime, "00:10", "formattedTime 应为 00:10")

    clock.advance(10)
    t.checkEqual(engine.tick(), true, "累计满 20s tick 返回 true")
    t.check(engine.phase == .finished, "满 20s 后 finished")
    t.checkApprox(engine.elapsed, 20, "完成时 elapsed 为 20")
    t.checkApprox(engine.progress, 1, "完成时 progress 为 1")
}

// MARK: - 4. 正计时显示与 progress

@MainActor
private func testCountUpDisplayAndProgress(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(mode: .countUp, countdownSeconds: 1500, now: { clock.now })

    t.check(engine.mode == .countUp, "mode 应为 .countUp")
    t.check(engine.phase == .idle, "初始 phase 应为 .idle")
    t.checkEqual(engine.displaySeconds, 0, "正计时初始 displaySeconds 为 0")
    t.checkEqual(engine.formattedTime, "00:00", "正计时初始 formattedTime 为 00:00")
    t.checkApprox(engine.progress, 0, "正计时初始 progress 为 0")

    engine.start()
    clock.advance(65)
    t.checkEqual(engine.tick(), false, "正计时 tick 始终 false")
    t.checkApprox(engine.elapsed, 65, "正计时 65s elapsed")
    t.checkEqual(engine.displaySeconds, 65, "正计时 65s displaySeconds 为 floor(65)")
    t.checkEqual(engine.formattedTime, "01:05", "正计时 65s formattedTime")
    t.checkApprox(engine.progress, 5.0 / 60.0, "正计时 65s progress 为 5/60")

    clock.advance(65) // 累计 130s
    engine.tick()
    t.checkEqual(engine.displaySeconds, 130, "正计时 130s displaySeconds")
    t.checkEqual(engine.formattedTime, "02:10", "正计时 130s formattedTime")
    t.checkApprox(engine.progress, 10.0 / 60.0, "正计时 130s progress 为 10/60")

    // 正计时不消耗 countdownSeconds。
    t.checkApprox(engine.countdownSeconds, 1500, "正计时不改变 countdownSeconds")
}

// MARK: - 5. 正计时永不完成

@MainActor
private func testCountUpNeverFinishes(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(mode: .countUp, countdownSeconds: 60, now: { clock.now })

    engine.start()
    var sawTrue = false
    for _ in 0 ..< 10 {
        clock.advance(3600)
        if engine.tick() { sawTrue = true }
    }
    t.check(!sawTrue, "正计时 tick 始终不应返回 true")
    t.check(engine.phase == .running, "长时间运行后 phase 仍为 .running")
    t.check(engine.isRunning, "长时间运行后 isRunning 仍为 true")
    t.checkApprox(engine.elapsed, 36000, "正计时累计 36000s")
    t.checkEqual(engine.tick(), false, "再次 tick 仍为 false")
    t.check(engine.phase == .running, "再次 tick 后 phase 不变")

    // 非 running 状态下 tick 返回 false 且不改变状态。
    let idle = TimerEngine(mode: .countUp, now: { clock.now })
    t.checkEqual(idle.tick(), false, "idle 时 tick 返回 false")
    t.check(idle.phase == .idle, "idle 时 tick 不改变 phase")
    t.checkApprox(idle.elapsed, 0, "idle 时 tick 不改变 elapsed")

    idle.start()
    idle.pause()
    t.checkEqual(idle.tick(), false, "paused 时 tick 返回 false")
    t.check(idle.phase == .paused, "paused 时 tick 不改变 phase")
}

// MARK: - 6. reset / setMode / setCountdownSeconds

@MainActor
private func testResetSetModeAndCountdownClamp(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(now: { clock.now })

    // 下限 clamp。
    engine.setCountdownSeconds(30)
    t.checkApprox(engine.countdownSeconds, 60, "小于 60 应 clamp 到 60")
    t.checkEqual(engine.displaySeconds, 60, "clamp 后 displaySeconds 为 60")
    t.checkEqual(engine.formattedTime, "01:00", "clamp 后 formattedTime 为 01:00")
    t.check(engine.phase == .idle, "setCountdownSeconds 后应 reset 为 idle")

    // 上限 clamp。
    engine.setCountdownSeconds(20000)
    t.checkApprox(engine.countdownSeconds, 10800, "大于 10800 应 clamp 到 10800")
    t.checkEqual(engine.formattedTime, "3:00:00", "10800 秒 formattedTime 为 3:00:00")

    // 边界值本身不应被改变。
    engine.setCountdownSeconds(60)
    t.checkApprox(engine.countdownSeconds, 60, "下边界 60 保留")
    engine.setCountdownSeconds(10800)
    t.checkApprox(engine.countdownSeconds, 10800, "上边界 10800 保留")

    // setMode 变化时 reset 并更新 mode。
    engine.setMode(.countUp)
    t.check(engine.mode == .countUp, "setMode(.countUp) 后 mode 更新")
    t.check(engine.phase == .idle, "setMode 变化后应 reset 为 idle")
    t.checkApprox(engine.elapsed, 0, "setMode 变化后 elapsed 为 0")

    // reset 保留 mode 与 countdownSeconds。
    engine.start()
    clock.advance(42)
    engine.tick()
    t.checkApprox(engine.elapsed, 42, "运行 42s 后 elapsed")
    engine.reset()
    t.check(engine.phase == .idle, "reset 后 phase 为 idle")
    t.checkApprox(engine.elapsed, 0, "reset 后 elapsed 为 0")
    t.check(engine.mode == .countUp, "reset 保留 mode")
    t.checkApprox(engine.countdownSeconds, 10800, "reset 保留 countdownSeconds")
    t.check(!engine.isRunning, "reset 后 isRunning 为 false")

    // 相同 mode 无副作用（不 reset、不打断运行）。
    engine.start()
    clock.advance(5)
    engine.tick()
    engine.setMode(.countUp)
    t.check(engine.phase == .running, "相同 mode 的 setMode 不应打断运行")
    t.checkApprox(engine.elapsed, 5, "相同 mode 的 setMode 不应重置 elapsed")

    // mode 真正变化时 reset。
    engine.setMode(.countdown)
    t.check(engine.phase == .idle, "mode 变化后应 reset 为 idle")
    t.checkApprox(engine.elapsed, 0, "mode 变化后 elapsed 归零")

    // 运行中 setCountdownSeconds 应立即停止并归零。
    let running = TimerEngine(now: { clock.now })
    running.start()
    clock.advance(100)
    running.tick()
    t.checkApprox(running.elapsed, 100, "运行中已专注 100s")
    running.setCountdownSeconds(120)
    t.check(running.phase == .idle, "运行中 setCountdownSeconds 应立即 reset")
    t.checkApprox(running.elapsed, 0, "运行中 setCountdownSeconds 后 elapsed 归零")
    t.checkApprox(running.countdownSeconds, 120, "运行中 setCountdownSeconds 生效")
    t.check(!running.isRunning, "运行中 setCountdownSeconds 后停止运行")

    // pause / start 幂等性。
    let idempotent = TimerEngine(now: { clock.now })
    idempotent.pause() // idle 时 pause 无操作
    t.check(idempotent.phase == .idle, "idle 时 pause 无操作")
    idempotent.start()
    clock.advance(10)
    idempotent.start() // running 时 start 幂等，不重置锚点
    clock.advance(5)
    idempotent.tick()
    t.checkApprox(idempotent.elapsed, 15, "running 时重复 start 不重置锚点")
}

// MARK: - 7. finished 后重新开始

@MainActor
private func testRestartAfterFinished(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(countdownSeconds: 5, now: { clock.now })

    engine.start()
    clock.advance(5)
    t.checkEqual(engine.tick(), true, "5s 倒计时到点返回 true")
    t.check(engine.phase == .finished, "到点后 phase 为 finished")
    t.checkApprox(engine.elapsed, 5, "到点后 elapsed 为 5")
    t.checkEqual(engine.displaySeconds, 0, "到点后 displaySeconds 为 0")

    // finished 后 start() 先归零再开始。
    engine.start()
    t.check(engine.isRunning, "finished 后 start() 应重新运行")
    t.check(engine.phase == .running, "重新开始后 phase 为 running")
    t.checkApprox(engine.elapsed, 0, "重新开始后 elapsed 归零")
    t.checkEqual(engine.displaySeconds, 5, "重新开始后 displaySeconds 为 5")
    t.checkApprox(engine.countdownRemaining, 5, "重新开始后剩余 5s")
    t.checkEqual(engine.formattedTime, "00:05", "重新开始后 formattedTime 为 00:05")

    clock.advance(2)
    t.checkEqual(engine.tick(), false, "重新开始后 2s 未到点")
    t.checkApprox(engine.elapsed, 2, "重新开始后正常累计")
    t.checkEqual(engine.displaySeconds, 3, "重新开始后剩余 3s")
}

// MARK: - 8. progress 边界与完成态

@MainActor
private func testProgressBoundsAndCompletion(_ t: TestRunner) {
    let clock = FakeClock()
    let engine = TimerEngine(countdownSeconds: 60, now: { clock.now })

    t.checkApprox(engine.progress, 0, "倒计时初始 progress 为 0")

    engine.start()
    clock.advance(15)
    engine.tick()
    t.checkApprox(engine.progress, 0.25, "60s 中 15s progress 为 0.25")

    for _ in 0 ..< 9 {
        clock.advance(3)
        engine.tick()
        t.check(engine.progress >= 0 && engine.progress <= 1, "progress 越界：\(engine.progress)")
    }
    t.checkApprox(engine.progress, 0.7, "60s 中 42s progress 为 0.7")

    clock.advance(100)
    t.checkEqual(engine.tick(), true, "到点 tick 返回 true")
    t.check(engine.phase == .finished, "到点 phase 为 finished")
    t.check(engine.progress == 1.0, "到点 progress 恰为 1（实际 \(engine.progress)）")

    clock.advance(100)
    t.checkEqual(engine.tick(), false, "完成后再 tick 返回 false")
    t.check(engine.progress == 1.0, "完成后 progress 保持 1（实际 \(engine.progress)）")

    // 正计时的 progress 始终落在 0...1。
    let up = TimerEngine(mode: .countUp, now: { clock.now })
    up.start()
    for _ in 0 ..< 20 {
        clock.advance(7)
        up.tick()
        t.check(up.progress >= 0 && up.progress <= 1, "正计时 progress 越界：\(up.progress)")
    }
}
