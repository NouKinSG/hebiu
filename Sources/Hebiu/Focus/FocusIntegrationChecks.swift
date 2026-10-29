import Foundation
import HebiuKit
import SwiftData
import FocusCore

/// Local prototype checks; only invoked by an explicit environment variable.
@MainActor
enum FocusIntegrationChecks {
    static func run() {
        let domain = "hebiu.focus.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = SwiftDataSessionStore.inMemory()
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = FocusModel(defaults: defaults, environment: [:], store: store,
                               clock: { now }, scheduler: NoopNotificationScheduler())
        var starts = 0
        var completions = 0
        model.onStart = { starts += 1 }
        model.onCompleted = { completions += 1 }
        model.selectPreset(minutes: 1)
        model.startPause()
        precondition(starts == 1 && model.engine.isRunning)
        now.addTimeInterval(20)
        model.tick()
        precondition(Int(model.engine.elapsed) == 20)
        model.startPause()
        now.addTimeInterval(40)
        model.tick()
        precondition(Int(model.engine.elapsed) == 20)
        model.startPause()
        now.addTimeInterval(40)
        model.tick()
        model.tick()
        precondition(completions == 1 && model.sessions.count == 1)
        precondition(try! store.load().count == 1)
        model.reset()
        precondition(model.sessions.count == 1)
        model.setMode(.countUp)
        model.startPause()
        now.addTimeInterval(65)
        model.tick()
        precondition(completions == 1 && model.engine.isRunning)
        model.reset()
        precondition(model.sessions.last?.outcome == .free)
        model.setMode(.countdown)
        model.selectPreset(minutes: 1)
        model.startPause()
        now.addTimeInterval(15)
        let restored = FocusModel(defaults: defaults, environment: [:], store: store,
                                  clock: { now }, scheduler: NoopNotificationScheduler())
        restored.tick()
        precondition(Int(restored.engine.elapsed) == 15)
        now.addTimeInterval(45)
        restored.tick()
        restored.tick()
        precondition(restored.sessions.count == 3)
        let controller = IntegratedFocusController(model: restored)
        var rests = 0
        controller.onRestDone = { rests += 1 }
        controller.restEnd = Date(timeIntervalSinceNow: -1)
        controller.tick(); controller.tick()
        precondition(rests == 1 && controller.restEnd == nil)
        runRegressions()
        print("PASS: start, pause/resume, completion once, SwiftData save, free focus, active timer restore, rest once")
    }
}


@MainActor
private final class FocusCheckFixture {
    let name = "hebiu.focus.check.\(UUID().uuidString)"
    lazy var defaults = UserDefaults(suiteName: name)!
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = SwiftDataSessionStore.inMemory()
    func model(store: SessionStore? = nil) -> FocusModel {
        FocusModel(defaults: defaults, environment: [:], store: store ?? self.store,
                   clock: { [unowned self] in self.now }, scheduler: NoopNotificationScheduler())
    }
    func clean() { defaults.removePersistentDomain(forName: name) }
}

private final class FailingFocusStore: SessionStore {
    var fails = true
    var records: [FocusCore.FocusSession] = []
    func load() throws -> [FocusCore.FocusSession] { records }
    func append(_ session: FocusCore.FocusSession) throws {
        if fails { throw NSError(domain: "FocusCheck", code: 1) }
        if !records.contains(where: { $0.id == session.id }) { records.append(session) }
    }
}

extension FocusIntegrationChecks {
    static func runRegressions() {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() { print("PASS: \(name)") }
            else { failures.append(name); print("FAIL: \(name)") }
        }
        for command in ["pause", "reset", "mode", "duration", "quit"] {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); var completions = 0
            m.onCompleted = { completions += 1 }
            m.selectPreset(minutes: 1); m.startPause(); f.now.addTimeInterval(61)
            switch command {
            case "pause": m.startPause()
            case "reset": m.reset()
            case "mode": m.setMode(.countUp)
            case "duration": m.selectPreset(minutes: 5)
            default: m.handleTermination()
            }
            check(m.sessions.count == 1 && m.sessions.first?.outcome == .completed,
                  "deadline before \(command) records completion")
            check(completions == 1, "deadline before \(command) emits one completion")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); var starts = 0
            m.onStart = { starts += 1 }
            m.startPause(); f.now.addTimeInterval(5); m.startPause(); m.startPause()
            check(starts == 1, "resume does not replay pet start event")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); m.selectPreset(minutes: 1); m.startPause()
            let snapshot = f.defaults.data(forKey: FocusModel.DefaultsKey.activeTimer)!
            f.now.addTimeInterval(60); m.tick()
            // Simulate a crash after DB commit but before clearing the active snapshot.
            f.defaults.set(snapshot, forKey: FocusModel.DefaultsKey.activeTimer)
            let restored = f.model()
            check(restored.sessions.count == 1, "crash replay keeps stable session identity")
            check((try? f.store.load().count) == 1, "crash replay does not duplicate stored history")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let store = FailingFocusStore()
            let m = f.model(store: store); m.selectPreset(minutes: 1); m.startPause()
            f.now.addTimeInterval(60); m.tick()
            check(m.sessions.count == 1, "failed save remains visible")
            store.fails = false
            let restored = f.model(store: store); restored.tick()
            check(store.records.count == 1 && restored.sessions.count == 1,
                  "failed save retries across restart without losing history")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let first = IntegratedFocusController(model: f.model())
            let end = f.now.addingTimeInterval(60)
            first.restEnd = end
            let restored = IntegratedFocusController(model: f.model())
            check(restored.restEnd == end, "rest countdown survives restart")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); let controller = IntegratedFocusController(model: m)
            controller.breakMinutes = { 1 }
            var starts = 0, completions = 0, rests = 0
            controller.onEvent = { event in
                switch event {
                case .started: starts += 1
                case .completed: completions += 1
                case .restDone: rests += 1
                }
            }
            controller.start(minutes: 1)
            f.now.addTimeInterval(10); m.startPause(); m.startPause()
            check(starts == 1 && controller.isFocusing, "pet starts once per session, not on resume")
            f.now.addTimeInterval(80); controller.tick(); controller.tick()
            check(completions == 1 && !controller.isFocusing, "pet completion event occurs exactly once")
            check(controller.restEnd == f.now.addingTimeInterval(30), "break anchored to actual deadline after delayed tick")
            f.now.addTimeInterval(30); controller.tick(); controller.tick()
            check(rests == 1 && controller.restEnd == nil, "pet rest completion event occurs exactly once")
            controller.restEnd = f.now.addingTimeInterval(60); m.reset()
            check(controller.restEnd == nil, "reset clears rest banner and menu state")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); m.selectPreset(minutes: 1); m.startPause()
            f.now.addTimeInterval(65)
            let recovered = f.model(); let controller = IntegratedFocusController(model: recovered)
            controller.breakMinutes = { 1 }
            var events = 0
            controller.onEvent = { event in
                if case let .completed(_, restored) = event, restored { events += 1 }
            }
            controller.tick(); controller.tick()
            check(events == 1 && recovered.sessions.count == 1, "recovery emits deferred completion after handlers bind")
            check(controller.restEnd == f.now.addingTimeInterval(55), "recovered completion restores remaining break")
        }
        for seconds in [59.0, 60.0, 61.0] {
            for mode in TimerMode.allCases {
                let f = FocusCheckFixture(); defer { f.clean() }
                let m = f.model(); m.selectPreset(minutes: 5); m.setMode(mode); m.startPause()
                f.now.addTimeInterval(seconds); m.reset(); m.reset()
                check(m.sessions.count == (seconds >= 60 ? 1 : 0), "record threshold \(seconds)s / \(mode.rawValue), repeated reset")
            }
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); m.startPause(); f.now.addTimeInterval(12); m.startPause()
            let restored = f.model(); f.now.addTimeInterval(3600); restored.tick()
            check(restored.engine.phase == .paused && Int(restored.engine.elapsed) == 12,
                  "paused snapshot stays frozen across restart and long idle")
        }
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-type-check-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("typography.json")
            let prefs = TypographySettings(url: url)
            prefs.scale = 9
            check(prefs.scale == 1.25, "font size clamps above maximum")
            prefs.scale = -.infinity
            check(prefs.scale == 1, "nonfinite font size safely resets")
            prefs.family = "font-that-is-not-installed"
            check(prefs.family.isEmpty, "missing font falls back to system")
            let family = TypographySettings.families.first(where: { $0 == "Arial" }) ?? ""
            prefs.family = family; prefs.scale = 1.15
            let loaded = TypographySettings(url: url)
            check(loaded.family == family && abs(loaded.scale - 1.15) < 0.0001, "font family and size persist across reload")
            loaded.reset()
            let reset = TypographySettings(url: url)
            check(reset.family.isEmpty && reset.scale == 1, "restore-defaults is persisted")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let original = f.model(); original.selectPreset(minutes: 1); original.startPause()
            f.now.addTimeInterval(65)
            _ = f.model() // recovery commits history, but app exits before binding the pet bridge
            let restarted = f.model(); let controller = IntegratedFocusController(model: restarted)
            var events = 0
            controller.onEvent = { if case .completed = $0 { events += 1 } }
            controller.tick()
            check(events == 1, "completion side effects survive a second crash before first tick")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let original = f.model(); original.selectPreset(minutes: 1); original.startPause()
            f.now.addTimeInterval(65)
            let restored = f.model(); let controller = IntegratedFocusController(model: restored)
            controller.breakMinutes = { 1 }
            controller.start(minutes: 5); controller.tick()
            check(controller.restEnd == nil && controller.isFocusing, "old recovery cannot start a break during a new focus")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); let controller = IntegratedFocusController(model: m)
            var attempts = 0
            controller.onEvent = { event in
                if case .completed = event {
                    attempts += 1
                    if attempts == 1 { throw NSError(domain: "transient-stats", code: 1) }
                }
            }
            controller.start(minutes: 1); f.now.addTimeInterval(60); controller.tick()
            check(m.pendingCompletions.count == 1 && controller.deliveryError != nil, "failed pet/stat delivery retains durable completion")
            f.now.addTimeInterval(5); controller.tick(); controller.tick()
            check(attempts == 2 && m.pendingCompletions.isEmpty, "completion delivery retries and acknowledges once")
        }
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-store-check-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: dir) }
            let f = FocusCheckFixture(); defer { f.clean() }
            let first = SwiftDataSessionStore.openOnDisk(directory: dir)
            let m = f.model(store: first); m.selectPreset(minutes: 1); m.startPause()
            f.now.addTimeInterval(60); m.tick()
            let session = m.sessions[0]
            try! first.append(session)
            check((try? first.container.mainContext.fetchCount(FetchDescriptor<SessionRecord>())) == 1,
                  "SwiftData duplicate append creates one physical row")
            let reloaded = SwiftDataSessionStore.openOnDisk(directory: dir)
            check(reloaded.isPersistent && (try? reloaded.load().count) == 1, "history survives a fresh on-disk container")
        }
        do {
            let f = FocusCheckFixture(); defer { f.clean() }
            let m = f.model(); m.startPause()
            // Crash between writing the new timer snapshot and clearing the prior break.
            f.defaults.set(f.now.addingTimeInterval(30), forKey: "foy.restEnd")
            let recovered = IntegratedFocusController(model: f.model())
            check(recovered.isFocusing && recovered.restEnd == nil, "active timer recovery takes precedence over stale break snapshot")
        }
        if !failures.isEmpty {
            print("REGRESSION FAILURES: \(failures.count)")
            exit(1)
        }
    }
}
