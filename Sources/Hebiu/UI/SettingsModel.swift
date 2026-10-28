import HebiuKit
import AppKit
import SwiftUI

/// 主窗口要用到的程序状态；大小、勿扰、开机自启、显示隐藏存在程序里，其余写回 hebiu.md
protocol SettingsHost: AnyObject {
    var petSide: CGFloat { get set }
    var isQuiet: Bool { get set }
    var launchAtLogin: Bool { get set }
    var petHidden: Bool { get set }
    func play(_ event: String)
    func resetPetPosition()
    var sourceScheduler: SourceScheduler { get }
    /// Claude 各事件最近一次收到的时间
    var claudeActivity: [String: Date] { get }
    var stats: Stats { get }
    var focus: FocusSession { get }
    func startFocus(minutes: Int?)
    func previewAction(_ action: CharacterPack.Action)
    func characterChanged()
    var photoCount: Int { get }
    var dates: ImportantDateStore { get }
    var habits: HabitStore { get }
    var notes: NoteStore { get }
    var moods: MoodStore { get }
    var todoItems: [TodoItem] { get }
    var weather: WeatherReport? { get }
    var claudeSummary: String? { get }
    func logMood(_ score: Int)
    func checkHabit(_ id: String)
    var allDates: [(date: ImportantDate, days: Int)] { get }
    func showPhoto()
    func stopFocus()
}

/// 台词页列出的事件：显示名、什么时候说
let lineEvents: [(key: String, name: String, when: String)] = [
    ("hello", "打招呼", "打开 Claude Code / Codex 时"),
    ("wait", "等你", "Claude / Codex 等你批准时"),
    ("done", "做完了", "Claude / Codex 做完一件事时"),
    ("error", "出错了", "Claude Code 出错时"),
    ("pat", "摸摸头", "点\(Her.she)时最常出现"),
    ("poke", "眨眼坏笑", "点\(Her.she)、右键点\(Her.she)"),
    ("love", "冒爱心", "点\(Her.she)、双击\(Her.she)"),
    ("tap_cheer", "被点时欢呼", "点\(Her.she)时随机出现"),
    ("tap_tea", "被点时分你奶茶", "点\(Her.she)时随机出现"),
    ("tap_bliss", "被点时眯眼享受", "点\(Her.she)时随机出现"),
    ("tap_grin", "被点时大笑", "点\(Her.she)时随机出现"),
    ("tap_nuzzle", "被点时歪头蹭蹭", "点\(Her.she)时随机出现"),
    ("tap_surprised", "被点时小惊讶", "点\(Her.she)时随机出现"),
    ("tap_blush", "被点时害羞", "点\(Her.she)时随机出现"),
    ("annoyed", "别戳啦", "6 秒内连续戳\(Her.she) 5 下"),
    ("rest", "休息提醒", "连续忙太久时"),
    ("night", "深夜提醒", "深夜还在用 Claude 时"),
    ("focus_start", "开始专心", "番茄钟开始时"),
    ("focus_done", "番茄完成", "专心时间到了"),
    ("rest_done", "休息结束", "番茄钟的休息时间到了"),
    ("together", "纪念日", "在一起的纪念日、每满 100 天"),
    ("birthday", "生日", "\(Her.she)生日当天"),
    ("sleepy", "打瞌睡", "菜单「做个动作」里点"),
    ("pout", "鼓嘴", "菜单「做个动作」里点"),
    ("cheer", "欢呼", "菜单「做个动作」里点"),
]


final class SettingsModel: ObservableObject {
    private let config: Config
    private weak var host: SettingsHost?
    private var saveWork: DispatchWorkItem?

    @Published var side: CGFloat = 220 { didSet { if !loading { host?.petSide = side } } }
    @Published var quiet = false { didSet { if !loading { host?.isQuiet = quiet } } }
    @Published var launchAtLogin = true { didSet { if !loading { host?.launchAtLogin = launchAtLogin } } }
    @Published var petHidden = false { didSet { if !loading { host?.petHidden = petHidden } } }

    @Published var hasTogether = false { didSet { scheduleSave() } }
    @Published var photos = "" { didSet { scheduleSave() } }
    @Published var together = Date() { didSet { scheduleSave() } }
    @Published var hasBirthday = false { didSet { scheduleSave() } }
    @Published var birthdayMonth = 1 { didSet { scheduleSave() } }
    @Published var birthdayDay = 1 { didSet { scheduleSave() } }
    @Published var restOn = true { didSet { scheduleSave() } }
    @Published var restMinutes = 120 { didSet { scheduleSave() } }
    @Published var sleepMinutes = 2 { didSet { scheduleSave() } }
    @Published var followCursor = true { didSet { scheduleSave() } }
    @Published var focusMinutes = 25 { didSet { scheduleSave() } }
    @Published var breakMinutes = 5 { didSet { scheduleSave() } }
    @Published var moodAskHour = 21 { didSet { scheduleSave() } }
    @Published var weatherCity = "" { didSet { scheduleSave() } }
    @Published var quietHours = "" { didSet { scheduleSave() } }
    /// 只在这些 App 在最前面时显示她；空表示任何地方
    @Published var showApps: Set<String> = [] { didSet { scheduleSave() } }
    @Published var showMode: ShowIn.Mode = .everywhere { didSet { scheduleSave() } }
    @Published var peek = false { didSet { scheduleSave() } }
    @Published var character = "default" { didSet { scheduleSave() } }
    /// 能选的形象：文件夹名、名字、介绍
    var characters: [(id: String, name: String, summary: String)] {
        CharacterLibrary.available(bundled: Character.bundled).compactMap { id, dir in
            (try? CharacterPack.load(from: dir)).map { (id, $0.name, $0.summary) }
        }.sorted { $0.id < $1.id }
    }
    @Published var popKinds: Set<ShowIn.PopKind> = ShowIn.defaultPop { didSet { scheduleSave() } }
    @Published var nightOn = true { didSet { scheduleSave() } }
    @Published var nightHour = 23 { didSet { scheduleSave() } }
    @Published var lines: [String: String] = [:] { didSet { scheduleSave() } }
    @Published var morningSummary = true { didSet { scheduleSave() } }
    @Published var eveningOn = true { didSet { scheduleSave() } }
    @Published var eveningTime = Date() { didSet { scheduleSave() } }
    @Published var notify = true { didSet { scheduleSave() } }
    @Published var tapTalkEvery = 10 { didSet { scheduleSave() } }
    @Published var userPronoun = "TA" { didSet { scheduleSave() } }
    @Published var agentEnabled = false { didSet { scheduleSave() } }
    @Published var agentBudget: Double = 30 { didSet { scheduleSave() } }
    @Published var agentHotkey = "ctrl+alt+h" { didSet { scheduleSave() } }
    @Published var agentProactive = true { didSet { scheduleSave() } }
    @Published var agentLines = true { didSet { scheduleSave() } }
    @Published var agentShareSources = false { didSet { scheduleSave() } }
    @Published var agentMemory = true { didSet { scheduleSave() } }
    @Published var agentActivity = true { didSet { scheduleSave() } }
    @Published var talk = true { didSet { scheduleSave() } }
    @Published var sourceMinutes: [String: Int] = [:] { didSet { scheduleSave() } }
    /// 来源状态变了就加一，界面跟着刷新
    @Published var sourceTick = 0

    private var loading = false

    init(config: Config, host: SettingsHost) {
        self.config = config
        self.host = host
        reload()
    }

    /// 打开窗口时从配置和程序状态整份重读
    func reload() {
        reloadHostState()
        loading = true
        defer { loading = false }
        hasTogether = config.together != nil
        photos = config.settings.photos
        together = config.together.flatMap { Calendar.current.date(from: $0) } ?? Date()
        hasBirthday = config.birthday != nil
        birthdayMonth = config.birthday?.month ?? 1
        birthdayDay = config.birthday?.day ?? 1
        restOn = config.restMinutes > 0
        restMinutes = config.restMinutes > 0 ? config.restMinutes : 120
        sleepMinutes = config.settings.sleepMinutes
        followCursor = config.settings.followCursor
        focusMinutes = config.settings.focusMinutes
        breakMinutes = config.settings.breakMinutes
        moodAskHour = config.settings.moodAskHour
        weatherCity = config.settings.weatherCity
        quietHours = config.settings.quietHours
        showApps = config.settings.showIn.apps
        showMode = config.settings.showIn.mode
        popKinds = config.settings.showIn.pop
        peek = config.settings.peek
        character = config.settings.character
        nightOn = config.nightHour > 0
        nightHour = config.nightHour > 0 ? config.nightHour : 23
        lines = config.lines.mapValues { $0.joined(separator: "\n") }
        morningSummary = config.settings.morningSummary
        eveningOn = config.settings.eveningReminder != nil
        let evening = config.settings.eveningReminder ?? DateComponents(hour: 18, minute: 0)
        eveningTime = Calendar.current.date(bySettingHour: evening.hour ?? 18, minute: evening.minute ?? 0, second: 0, of: Date()) ?? Date()
        notify = config.settings.notify
        tapTalkEvery = config.settings.tapTalkEvery
        userPronoun = config.settings.userPronoun
        agentEnabled = config.settings.agentEnabled
        agentBudget = NSDecimalNumber(decimal: config.settings.agentBudget).doubleValue
        agentHotkey = config.settings.agentHotkey
        agentProactive = config.settings.agentProactive
        agentLines = config.settings.agentLines
        agentShareSources = config.settings.agentShareSources
        agentMemory = config.settings.agentMemory
        agentActivity = config.settings.agentActivity
        talk = config.settings.talk
        sourceMinutes = config.settings.sources
    }

    /// 只同步菜单里也能改的几项；台词和日期正在编辑，不能被覆盖
    func reloadHostState() {
        guard let host else { return }
        loading = true
        defer { loading = false }
        if side != host.petSide { side = host.petSide }
        if quiet != host.isQuiet { quiet = host.isQuiet }
        if launchAtLogin != host.launchAtLogin { launchAtLogin = host.launchAtLogin }
        if petHidden != host.petHidden { petHidden = host.petHidden }
        objectWillChange.send()      // 习惯、番茄这些不是 @Published 的状态也刷新
    }

    var daysTogether: Int? {
        guard hasTogether else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: together), to: cal.startOfDay(for: Date())).day ?? 0
        return days >= 0 ? days + 1 : nil
    }

    func resetLines(_ key: String) {
        lines[key] = (Config.defaultLines[key] ?? []).joined(separator: "\n")
    }

    /// 先把还没落盘的修改存下来再播，台词才是刚改的
    func tryOut(_ event: String) {
        if saveWork != nil { saveNow() }
        host?.play(event)
    }

    func resetPetPosition() { host?.resetPetPosition() }
    var claudeActivity: [String: Date] { host?.claudeActivity ?? [:] }
    func statsToday(_ now: Date = Date()) -> Stats.Day { host?.stats.day(now) ?? [:] }
    var statsTotal: Stats.Day { host?.stats.total() ?? [:] }
    var focus: FocusSession? { host?.focus }
    func previewAction(_ action: CharacterPack.Action) { host?.previewAction(action) }
    func characterChanged() { host?.characterChanged(); objectWillChange.send() }
    var photoCount: Int { host?.photoCount ?? 0 }
    var allDates: [(date: ImportantDate, days: Int)] { host?.allDates ?? [] }
    @discardableResult
    func addDate(_ text: String) -> Bool {
        guard let d = ImportantDate.parse(text) else { return false }
        host?.dates.add(d)
        objectWillChange.send()
        return true
    }
    var habits: HabitStore? { host?.habits }
    var notes: NoteStore? { host?.notes }
    var moods: MoodStore? { host?.moods }
    var weather: WeatherReport? { host?.weather }
    var claudeSummary: String? { host?.claudeSummary }
    func weekReview(offset: Int) -> WeekReview {
        WeekReview.build(offset: offset, stats: host?.stats ?? Stats(url: URL(fileURLWithPath: "/dev/null")),
                         habits: host?.habits, moods: host?.moods, todos: host?.todoItems ?? [])
    }
    func logMood(_ score: Int) { host?.logMood(score); objectWillChange.send() }
    func checkHabit(_ id: String) { host?.checkHabit(id); objectWillChange.send() }
    @discardableResult
    func addHabit(_ text: String) -> Bool {
        guard let h = Habit.parse(text) else { return false }
        host?.habits.add(h)
        objectWillChange.send()
        return true
    }
    func deleteHabit(_ id: String) { host?.habits.delete(id); objectWillChange.send() }
    func deleteDate(_ id: String) { host?.dates.delete(id); objectWillChange.send() }
    /// 先存盘，桌宠读到新文件夹再挑
    func showPhoto() { if saveWork != nil { saveNow() }; host?.showPhoto() }
    func startFocus() { host?.startFocus(minutes: nil); objectWillChange.send() }
    func stopFocus() { host?.stopFocus(); objectWillChange.send() }
    var statsFirstDay: String? { host?.stats.firstDay }

    var sources: [(name: String, title: String, detail: String, installed: Bool)] { host?.sourceScheduler.available() ?? [] }
    func status(_ name: String) -> SourceScheduler.Status { host?.sourceScheduler.status[name] ?? .init() }

    func setSource(_ name: String, on: Bool) {
        sourceMinutes[name] = on ? (SourceCatalog.entry(name)?.defaultMinutes ?? 15) : 0
        saveNow()
        if on { host?.sourceScheduler.run(name) } else { host?.sourceScheduler.clear(name) }
    }

    func sync(_ name: String) {
        saveNow()
        host?.sourceScheduler.run(name)
    }

    /// 打字时每停 0.6 秒存一次，不用点保存
    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        let cal = Calendar.current
        let parsed = lines.mapValues {
            $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var settings = config.settings
        settings.photos = photos
        settings.together = hasTogether ? cal.dateComponents([.year, .month, .day], from: together) : nil
        settings.birthday = hasBirthday ? DateComponents(month: birthdayMonth, day: birthdayDay) : nil
        settings.restMinutes = restOn ? restMinutes : 0
        settings.sleepMinutes = sleepMinutes
        settings.followCursor = followCursor
        settings.focusMinutes = focusMinutes
        settings.breakMinutes = breakMinutes
        settings.moodAskHour = moodAskHour
        settings.weatherCity = weatherCity.trimmingCharacters(in: .whitespaces)
        settings.showIn = ShowIn(mode: showMode, apps: showApps, pop: popKinds)
        settings.peek = peek
        settings.character = character
        settings.quietHours = QuietHours(quietHours) == nil ? "" : quietHours.trimmingCharacters(in: .whitespaces)
        settings.nightHour = nightOn ? nightHour : 0
        settings.morningSummary = morningSummary
        settings.eveningReminder = eveningOn ? cal.dateComponents([.hour, .minute], from: eveningTime) : nil
        settings.notify = notify
        settings.tapTalkEvery = tapTalkEvery
        settings.userPronoun = userPronoun
        settings.agentEnabled = agentEnabled
        settings.agentProactive = agentProactive
        settings.agentLines = agentLines
        settings.agentShareSources = agentShareSources
        settings.agentMemory = agentMemory
        settings.agentActivity = agentActivity
        settings.talk = talk
        settings.agentBudget = Decimal(agentBudget)
        if HotkeySpec(agentHotkey) != nil { settings.agentHotkey = agentHotkey.lowercased() }
        settings.sources = sourceMinutes
        config.save(settings, lines: parsed)
    }
}
