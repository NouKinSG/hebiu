import HebiuKit
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, SettingsHost {
    private let defaults = UserDefaults.standard
    private let config = Config()
    private var panel: PetPanel!
    private var view: PetView!
    private var pet: PetController!
    private var inbox: EventInbox?
    private var companion: Companion!
    private static let claudeEvents: Set<String> = ["hello", "working", "wait", "done", "error"]
    let claudeSessions = ClaudeSessions()
    /// 后台会话做完、她正忙着没说的，攒成角标
    private var backgroundDoneCount = 0
    private var configWatcher: FileWatcher?
    private var statusItem: NSStatusItem!
    private var hoverTimer: DispatchSourceTimer?
    private var cursorIsHand = false
    private var main: MainWindowController?
    private var taps = TapReactions()
    /// 换形象包后重建点她的反应
    private func reloadTaps() {
        taps = TapReactions(pool: Character.pack.taps.map { ($0.action, $0.weight) }, annoyed: Character.pack.annoyed)
    }
    let stats = Stats()
    let focus = IntegratedFocusController()
    let dates = ImportantDateStore()
    let habits = HabitStore()
    let notes = NoteStore()
    let moods = MoodStore()
    private let weatherClient = WeatherClient()
    private(set) var weather: WeatherReport?
    private var habitTimer: Timer?
    private var datesTimer: Timer?
    private let photoPopup = PhotoPopup()
    private var album = PhotoAlbum(folder: nil)
    private var albumPath = ""
    private var focusTimer: Timer?
    private lazy var agent: AgentController = {
        let a = AgentController(config: config, store: todos.store, dates: dates, habits: habits, notes: notes, moods: moods)
        // 她回答时：做表情，说出回答（勿扰也说，因为是你主动问的）
        a.react = { [weak self] event, line in
            guard let self else { return }
            if line == nil { self.play(event); return }
            self.say(event, line, sticky: false)
            if let line { self.popOut(.chat, seconds: min(9, max(3.6, Double(line.count) / 5)) + 1) }
        }
        a.onChange = { [weak self] in self?.main?.refreshTodos(); self?.rebuildMenu() }
        a.onSent = { [weak self] in self?.stats.bump(.chats) }
        a.weatherText = { [weak self] in self?.weather?.promptText }
        return a
    }()
    private lazy var chatPanel: ChatPanelController = {
        let c = ChatPanelController(agent: agent)
        c.anchor = { [weak self] in self?.panel.frame ?? .zero }
        c.openSettings = { [weak self] in self?.chatPanel.hide(); self?.showMain(.brain) }
        return c
    }()
    private let hotkey = GlobalHotkey()
    private var registeredHotkey: String?
    /// Claude 各事件最近一次收到的时间（主窗口「Claude Code」页显示）
    private(set) var claudeActivity: [String: Date] = [:]
    private let todos = TodoCoordinator()
    private(set) lazy var sourceScheduler = SourceScheduler(config: config)
    /// 当前气泡是不是待办相关的（点了才打开待办窗口）
    private var bubbleIsTodo = false
    private var nextBubbleIsTodo = false

    private var side: CGFloat {
        let v = defaults.double(forKey: "size")
        return v > 0 ? CGFloat(v) : 220
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Paths.prepare()
        config.load()
        // 先知道用哪个形象，再按它的默认台词重新读一遍配置
        Character.load(config.settings.character)
        config.load()
        reloadTaps()
        Log.write("launched")

        panel = PetPanel(size: panelSize())
        view = PetView(frame: NSRect(origin: .zero, size: panelSize()))
        panel.contentView = view
        pet = PetController(imageLayer: view.imageLayer, config: config)
        pet.quiet = defaults.bool(forKey: "quiet")
        applyQuietHours()
        pet.mute = { [weak self] in self?.config.settings.talk == false }
        pet.userIdleSeconds = { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) }
        pet.sleepAfter = { [weak self] in Double(self?.config.settings.sleepMinutes ?? 0) * 60 }
        pet.showBubble = { [weak self] text, sticky in
            guard let self else { return }
            self.bubbleIsTodo = self.nextBubbleIsTodo
            self.nextBubbleIsTodo = false
            // 长的话多停一会儿：大约一秒读 5 个字，3.6～9 秒
            let reading = min(9, max(3.6, Double(text.count) / 5))
            self.view.bubble.show(text, seconds: sticky ? nil : max(reading, self.bubbleIsTodo ? 6 : 0))
        }
        pet.hideBubble = { [weak self] in self?.view.bubble.hide() }
        view.frameProvider = { [weak self] in self?.pet.currentFrame }
        // 点她：每次随机一种反应；右键、双击固定，也算进「戳了几下」
        view.onClick = { [weak self] in
            guard let self else { return }
            self.tap(self.taps.next())
        }
        view.onRightClick = { [weak self] in self?.tapOrAnnoyed(Character.pack.rightClick) }
        view.onDoubleClick = { [weak self] in self?.tapOrAnnoyed(Character.pack.doubleClick) }
        view.onMoved = { [weak self] in self?.saveOrigin() }
        view.onBubbleClick = { [weak self] in
            guard let self else { return }
            self.pet.clearSticky()
            if self.bubbleIsTodo { self.openTodos() }
            self.applyVisibility()
        }
        view.onMenu = { [weak self] point in
            guard let self else { return }
            let menu = self.buildMenu()
            // 菜单默认从点击处往下展开。她在屏幕底部、下面放不下时，整个菜单放到鼠标上方：
            // 长按弹出时鼠标还按着，菜单项要是正好在鼠标底下，一松手就会被选中（比如「退出」）
            var at = point
            if let window = self.view.window, let screen = window.screen {
                let onScreen = window.convertPoint(toScreen: self.view.convert(point, to: nil))
                if onScreen.y - screen.visibleFrame.minY < menu.size.height + 8 { at.y += menu.size.height + 6 }
            }
            menu.popUp(positioning: nil, at: at, in: self.view)
        }

        applySize()
        placeWindow()
        pet.start()
        applyVisibility()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostChanged),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        for delay in [1.0, 3.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.applyVisibility() } }

        companion = Companion(config: config) { [weak self] event in self?.companionSays(event) }
        habitTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.checkHabits() }
        habits.onChange = { [weak self] in self?.main?.refreshHostState() }
        datesTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.checkDates()
            self?.refreshWeather()
        }
        weather = weatherClient.cached.flatMap { $0.city == config.settings.weatherCity ? $0 : nil }
        refreshWeather()
        todos.morningExtra = { [weak self] in
            guard let w = self?.weather, Calendar.current.isDateInToday(w.fetchedAt) else { return nil }
            return "\(w.emoji)今天 \(Int(w.today.min.rounded()))～\(Int(w.today.max.rounded()))°" + (w.advice.first.map { "，" + $0 } ?? "")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkDates() }
        focus.breakMinutes = { [weak self] in self?.config.settings.breakMinutes ?? 0 }
        focus.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .started:
                self.play("focus_start")
            case let .completed(session, recovered):
                // Persist the session ID with the counter so replay cannot count it twice.
                guard try self.stats.recordFocusCompletion(id: session.id, at: session.endedAt) else { return }
                self.say("focus_done", recovered ? "刚才那轮专注已完成，记录已经保存。" : nil, sticky: true)
                self.popOut(.focus)
                if self.config.settings.notify {
                    self.todos.notifier.post(title: "专注完成", body: "这一轮完成了，起来活动一下吧。")
                }
                self.main?.refreshHostState()
            case .restDone:
                self.play("rest_done")
                self.popOut(.focus, seconds: 4)
            }
        }
        let focusClock = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.focusTick() }
        RunLoop.main.add(focusClock, forMode: .common)
        focusTimer = focusClock
        companion.isFocusing = { [weak self] in self?.focus.isFocusing ?? false }
        companion.start()
        inbox = EventInbox { [weak self] line in
            guard let self else { return }
            let event = line.name
            if event == "settings" { self.openSettings(); return }
            if event == "open" { self.openMain(); return }
            if event == "close" { self.main?.close(); return }
            if event == "chat" { self.openChat(); return }
            if event == "photo" { self.showPhoto(); return }
            if event.hasPrefix("habit-"), self.habits.habit(String(event.dropFirst(6))) != nil {
                self.checkHabit(String(event.dropFirst(6)))
                return
            }
            if event == "focus" { self.startFocus(); return }
            if event == "focus-stop" { self.stopFocus(); return }
            if event.hasPrefix("focus-"), let minutes = Int(event.dropFirst(6)) { self.startFocus(minutes: minutes); return }
            if event == "memory-sync" { self.agent.consolidateIfNeeded(); return }
            if event == "diary" { self.agent.writeTodayDiary(); return }
            if event == "rest" || event == "night" { self.companionSays(event); return }
            // hebiu open-todos、open-settings……：打开主窗口的某一页
            if event.hasPrefix("open-"), let page = MainPage(rawValue: String(event.dropFirst(5))) { self.showMain(page); return }
            if event == "todo" { self.openTodos(); return }
            if event.hasPrefix("sync-") { self.sourceScheduler.run(String(event.dropFirst(5))); return }
            if AppDelegate.claudeEvents.contains(event) || event == "nudge" {
                if event == "done" { self.stats.bump(.claudeDone) }
                if event != "nudge" {                    // 闲着等你回话不算在忙
                    self.companion.noteActivity()
                    self.claudeActivity[event] = Date()
                }
                // 好几个会话同时开着：只有你正在看的那个照常演，后台的不打断
                switch self.claudeSessions.note(line) {
                case .play: break
                case let .backgroundDone(project):
                    self.backgroundDone(project)
                    self.main?.refreshHostState()
                    return
                case let .backgroundWaiting(project):
                    self.say("wait", "\(project) 那边在等你确认～", sticky: false)
                    self.popOut(.claude, seconds: 6)
                    self.main?.refreshHostState()
                    return
                case .ignore:
                    self.main?.refreshHostState()
                    return
                }
                if event == "done" || event == "error" { self.popOut(.claude, seconds: 4.5) }
                // 专心时 Claude 的动静只做动作、不说话
                if self.focus.isFocusing { self.pet.handle(event, silent: true); return }
            }
            self.pet.handle(event)
        }
        todos.react = { [weak self] event, line, sticky in
            guard let self else { return }
            self.say(event, line, sticky: sticky)
            // 待办到点：不在选中的 App 里也出来喊你，点她之后再按规则藏起来
            if sticky { self.popOut(.todo) }
        }
        todos.isQuiet = { [weak self] in self?.pet.quiet ?? false }
        todos.config = config
        todos.onChange = { [weak self] in
            self?.rebuildMenu()
            self?.main?.refreshTodos()
        }
        todos.notifier.onOpen = { [weak self] in self?.openTodos() }
        todos.onSay = { [weak self] text in self?.agent.say(text) }
        todos.onNote = { [weak self] text in
            guard let self, self.notes.add(text, source: TodoSource.cli) != nil else { return }
            self.say("pat", "记下啦～", sticky: false)
        }
        notes.onChange = { [weak self] in self?.main?.refreshHostState() }
        moods.onChange = { [weak self] in self?.main?.refreshHostState() }
        todos.compose = { [weak self] task, done in
            guard let self, self.agent.proactive else { done(nil); return }
            self.agent.compose(task, completion: done)
        }
        todos.store.onCompleted = { [weak self] _ in self?.stats.bump(.todosDone) }
        todos.start()
        sourceScheduler.onStatusChange = { [weak self] in self?.main?.refreshSources() }
        claudeActivity = AppDelegate.recentClaudeActivity()
        sourceScheduler.start()
        configWatcher = FileWatcher(url: Paths.config) { [weak self] in
            defer {
                self?.applyAgentSettings()
                self?.agent.applyLines()
            }
            guard let self else { return }
            let before = self.config.settings.character
            self.config.load()
            // 设置里换了形象：重新读形象包
            if self.config.settings.character != before, Character.load(self.config.settings.character) {
                self.config.load()
                self.characterChanged()
            }
            self.applyVisibility()
            self.refreshWeather()
            self.rebuildMenu()          // 菜单顶部的「在一起第 N 天」跟着变
        }
        setupStatusItem()
        setupEditMenu()
        applyAgentSettings()            // 要在菜单栏图标建好之后：会刷新菜单
        _ = agent                       // 启动时就建好：每天写台词的定时器要跑起来
        BackgroundCursor.enable()
        startHoverTracking()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.save()
    }

    // MARK: - 尺寸与位置

    private func panelSize() -> NSSize { NSSize(width: side * 1.5, height: side * 1.4) }

    private func applySize() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let origin = panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: panelSize()), display: true)
        view.frame = NSRect(origin: .zero, size: panelSize())
        view.layoutPet(side: side, scale: scale)
        pet.setFrames(FrameStore.load(pixelSide: Int(side * scale)))
    }

    private func placeWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: screen.maxX - panel.frame.width - 16, y: screen.minY + 8)
        if defaults.object(forKey: "originX") != nil {
            let saved = NSPoint(x: defaults.double(forKey: "originX"), y: defaults.double(forKey: "originY"))
            let rect = NSRect(origin: saved, size: panel.frame.size)
            // 存下的位置在当前任何一块屏幕上都看不到（比如拔了外接屏），就回到默认位置
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect.insetBy(dx: rect.width * 0.3, dy: rect.height * 0.3)) }) {
                origin = saved
            }
        }
        panel.setFrameOrigin(origin)
    }

    private func saveOrigin() {
        if peeking { peeking = false; homeOrigin = nil }
        defaults.set(panel.frame.origin.x, forKey: "originX")
        defaults.set(panel.frame.origin.y, forKey: "originY")
    }

    @objc private func screensChanged() { placeWindow() }

    /// 闲着时身子往鼠标那边歪一点，像在看你；在做动作、睡觉、露头时站直
    private func followCursor(_ p: NSPoint) {
        guard config.settings.followCursor, pet.isIdle, !pet.sleeping, !peeking,
              pet.current == "idle" || pet.current == "blink" else { view.lean(0); return }
        let side = self.side
        let center = NSPoint(x: panel.frame.maxX - side / 2, y: panel.frame.minY + side * 0.6)
        let dx = p.x - center.x
        // 身边一小圈里不动，远了慢慢歪到最大
        let dead = side * 0.3
        let amount = abs(dx) < dead ? 0 : (dx - (dx > 0 ? dead : -dead)) / (side * 4)
        view.lean(amount)
    }

    /// 鼠标在她身上才接收点击，透明处点击直接穿透到下面的窗口；10 次/秒的检查，开销可以忽略
    private func startHoverTracking() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.1, leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if self.view.isDragging { self.panel.ignoresMouseEvents = false; return }
            let p = NSEvent.mouseLocation
            self.followCursor(p)
            guard self.panel.frame.contains(p) else {
                self.panel.ignoresMouseEvents = true
                if self.cursorIsHand { NSCursor.arrow.set(); self.cursorIsHand = false }
                return
            }
            let local = NSPoint(x: p.x - self.panel.frame.minX, y: p.y - self.panel.frame.minY)
            let interactive = self.view.isInteractive(at: local)
            self.panel.ignoresMouseEvents = !interactive
            if interactive {
                NSCursor.pointingHand.set()
                self.cursorIsHand = true
            } else if self.cursorIsHand {
                NSCursor.arrow.set()
                self.cursorIsHand = false
            }
        }
        timer.resume()
        hoverTimer = timer
    }

    // MARK: - 天气

    /// 设了城市才查；一小时内用缓存
    func refreshWeather() {
        let city = config.settings.weatherCity
        guard !city.isEmpty else {
            if weather != nil { weather = nil; main?.refreshHostState() }
            return
        }
        Task {
            let report = await weatherClient.report(city: city)
            await MainActor.run {
                guard report != self.weather else { return }
                self.weather = report
                self.main?.refreshHostState()
            }
        }
    }

    // MARK: - 重要日子

    var allDates: [(date: ImportantDate, days: Int)] {
        dates.upcoming(extra: ImportantDate.builtIns(config.settings))
    }

    /// 白天检查一次：到了提前提醒的日子就说一句（打开 AI 时由她结合着说）
    private func checkDates(now: Date = Date()) {
        let hour = Calendar.current.component(.hour, from: now)
        guard (9..<23).contains(hour) else { return }
        for (d, days) in dates.due(now: now, extra: ImportantDate.builtIns(config.settings)) {
            let fixed: String
            if days == 0 { fixed = "今天是\(d.title)！别忘啦～" }
            else if d.id == "builtin-birthday" { fixed = "再过 \(days) 天就是我生日啦，嘿嘿，记得哦" }
            else { fixed = "再过 \(days) 天就是\(d.title)了，" + (days >= 3 ? "要不要提前准备一下？" : "准备好了吗？") }
            let task = days == 0
                ? "今天是\(d.title)（\(d.dateText)）。提醒\(Config.he)一下，一两句。"
                : "再过 \(days) 天就是\(d.title)（\(d.dateText)）。提醒\(Config.he)提前准备，结合你对\(Config.he)和对方的了解给一个具体的小建议（送什么、怎么安排），两句以内。如果是你自己的生日就撒娇暗示你想要什么。"
            let speak: (String) -> Void = { [weak self] text in
                guard let self else { return }
                self.say("love", text, sticky: true)
                self.popOut(.date)
                if self.config.settings.notify { self.todos.notifier.post(title: "📅 \(d.title)", body: days == 0 ? "就是今天" : "还有 \(days) 天") }
            }
            if agent.proactive { agent.compose(task, maxChars: days == 0 ? 40 : 70) { speak($0 ?? fixed) } } else { speak(fixed) }
            Log.write("date reminder: \(d.id) in \(days) days")
        }
    }

    // MARK: - 习惯

    /// 打卡（或取消）；打上了她欢呼一下，报连续天数
    func checkHabit(_ id: String) {
        guard let h = habits.habit(id) else { return }
        if habits.toggle(id) {
            let streak = habits.streak(id)
            say("tap_cheer", "\(h.emoji) \(h.title) 打卡！" + (streak > 1 ? "连续 \(streak) 天啦" : "好棒～"), sticky: false)
        }
    }

    /// 到点还没打卡的习惯，她提醒一句
    /// 点了今天的心情：她回应一下
    var todoItems: [TodoItem] { todos.store.items }

    func logMood(_ score: Int) {
        moods.set(score: score)
        switch score {
        case 5: say("tap_grin", "超开心！我也跟着开心～", sticky: false)
        case 4: say("love", "不错不错，保持住～", sticky: false)
        case 3: say("chin", "平平淡淡也挺好的嘛", sticky: false)
        default: say("tap_nuzzle", "抱抱你…有我在呢", sticky: false)
        }
    }

    /// 定时任务到点：她去做，说出结果（挂着等你看），也发个通知
    private func runScheduledTasks() {
        guard config.settings.agentEnabled else { return }
        for task in agent.tasks.due() {
            Log.write("scheduled task: \(task.id)")
            agent.runTask(task) { [weak self] text in
                guard let self, let text else { return }
                self.say("hello", text, sticky: true)
                self.popOut(.task)
                if self.config.settings.notify { self.todos.notifier.post(title: "⏰ \(task.prompt)", body: text) }
            }
        }
    }

    /// 周日晚上 8 点后说一声：这周的回顾可以看了（一周一次）
    private func announceWeekReview(now: Date = Date()) {
        let cal = Calendar.current
        guard cal.component(.weekday, from: now) == 1, cal.component(.hour, from: now) >= 20 else { return }
        let key = MemoryDay.weekKey(MemoryDay.of(now))
        guard defaults.string(forKey: "reviewAnnounced") != key else { return }
        defaults.set(key, forKey: "reviewAnnounced")
        say("love", "这周辛苦啦～回顾做好了，去主窗口「回顾」看看嘛", sticky: false)
    }

    private func checkHabits() {
        announceWeekReview()
        applyQuietHours()
        applyVisibility()
        runScheduledTasks()
        let ask = config.settings.moodAskHour
        if ask > 0, moods.shouldAsk(hour: ask) {
            say("chin", "今天过得怎么样呀？在主页点个心情嘛～", sticky: false)
        }
        for h in habits.dueReminders() {
            let fixed = "今天的\(h.emoji)\(h.title)还没打卡哦～"
            let task = "\(Config.he)今天的习惯「\(h.title)」还没做（已经连续 \(habits.streak(h.id)) 天了）。温柔提醒\(Config.he)去做，一句话。"
            let speak: (String) -> Void = { [weak self] text in
                self?.say("remind", text, sticky: true)
                self?.popOut(.habit)
            }
            if agent.proactive { agent.compose(task) { speak($0 ?? fixed) } } else { speak(fixed) }
            Log.write("habit reminder: \(h.id)")
        }
    }

    // MARK: - 好几个 Claude 会话

    /// 后台会话做完：她闲着就说一句是哪个项目，正忙着就在身边记个角标
    private func backgroundDone(_ project: String) {
        if pet.isIdle && !focus.isFocusing {
            say("done", "\(project) 那边做完啦～", sticky: false)
            popOut(.claude, seconds: 4.5)
        } else {
            backgroundDoneCount += 1
            view.setBadge(backgroundDoneCount)
        }
    }

    var claudeSummary: String? { claudeSessions.summary }

    // MARK: - 形象包

    func previewAction(_ action: CharacterPack.Action) {
        let wasQuiet = pet.quiet
        pet.quiet = false
        pet.preview(Recipe(action))
        pet.quiet = wasQuiet
    }

    /// 动作表改了、换了形象：重新读帧图和点她的反应
    func characterChanged() {
        reloadTaps()
        PetImages.clear()
        pet.setFrames(FrameStore.load(pixelSide: Int(side * (panel.screen?.backingScaleFactor ?? 2))))
        config.load()
        rebuildMenu()
    }

    // MARK: - 合照

    /// 设置里的文件夹变了就换一本相册
    private var currentAlbum: PhotoAlbum {
        if albumPath != config.settings.photos {
            albumPath = config.settings.photos
            album = PhotoAlbum(folder: PhotoAlbum.folder(from: albumPath))
        }
        return album
    }

    var photoCount: Int { currentAlbum.photos().count }

    func showPhoto() {
        guard let url = currentAlbum.random() else { return }
        stats.bump(.photos)
        photoPopup.show(url, near: panel.frame)
    }

    // MARK: - 番茄钟

    func startFocus(minutes: Int? = nil) {
        focus.start(minutes: minutes ?? config.settings.focusMinutes)
    }

    func stopFocus() { focus.stop() }

    private func focusTick() {
        focus.tick()
        statusItem.button?.title = focus.menuTitle
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Hebiu")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        rebuildMenu()
    }

    private func rebuildMenu() {
        // A new data directory creates todo.json before setupStatusItem has run.
        guard let statusItem else { return }
        statusItem.menu = buildMenu()
        main?.refreshHostState()
    }

    /// 不在 Dock 显示的程序没有菜单栏，设置页里的 ⌘C / ⌘V / ⌘Z 要靠这个隐藏的编辑菜单才能用
    private func setupEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// 菜单固定这几项，以后加功能放进主窗口，不往菜单里加
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let today = TodoQuery.sections(todos.store.items).today.count
        let open = item(today > 0 ? "打开 Hebiu（今天 \(today) 件）" : "打开 Hebiu", #selector(openMain))
        open.keyEquivalent = "o"
        menu.addItem(open)
        // 第二项：打开 AI 大脑时是「和她说话」，否则是「快速加待办」
        let add = config.settings.agentEnabled
            ? item("和\(Her.she)说话…" + (HotkeySpec(config.settings.agentHotkey).map { "（\($0.display)）" } ?? ""), #selector(openChat))
            : item("快速加待办…", #selector(quickAdd))
        add.keyEquivalent = "n"
        menu.addItem(add)
        menu.addItem(.separator())
        let quiet = item("勿扰模式", #selector(toggleQuiet))
        quiet.state = pet.quiet ? .on : .off
        menu.addItem(quiet)
        menu.addItem(item(defaults.bool(forKey: "hidden") ? "显示\(Her.she)" : "隐藏\(Her.she)", #selector(toggleVisible)))
        menu.addItem(.separator())
        let settingsItem = item("设置…", #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let quitItem = item("退出 Hebiu", #selector(quit))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    @objc private func toggleVisible() {
        defaults.set(!defaults.bool(forKey: "hidden"), forKey: "hidden")
        applyVisibility()
        rebuildMenu()
    }

    @objc private func frontmostChanged() { applyVisibility() }

    /// 有事出来时：要等你点她的（提醒挂着），或者露几秒就回去的
    private var popOutSticky = false
    /// 提醒的气泡真挂上过（动作播到一半才挂上，之前不能当成「已经点掉了」）
    private var popOutSawBubble = false
    private var popOutUntil = Date.distantPast

    /// 不显示的时候，设置里勾了的这类事让她出来；seconds 为 nil 时等你点她
    private func popOut(_ kind: ShowIn.PopKind, seconds: Double? = nil) {
        guard config.settings.showIn.pop.contains(kind) else { return }
        if let seconds {
            popOutUntil = max(popOutUntil, Date().addingTimeInterval(seconds))
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.1) { [weak self] in self?.applyVisibility() }
        } else {
            popOutSticky = true
            popOutSawBubble = false
            // 气泡挂上之后再看一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.applyVisibility() }
        }
        applyVisibility()
    }

    /// 要不要显示她：没手动隐藏，并且（任何地方都显示 / 最前面是选中的 App / 有到点的提醒挂着）
    func applyVisibility() {
        if pet.stickyShown { popOutSawBubble = true }
        if popOutSticky, popOutSawBubble, !pet.stickyShown { popOutSticky = false }
        // 刚启动时可能还拿不到最前面是谁，先不动，等下一次再看
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        let rule = config.settings.showIn
        // 任何地方：每个桌面都有她。其余模式：她只待在一个桌面上，要出来时跟到当前桌面；
        // 不然 Ctrl+←/→ 切桌面时，滑动动画里新桌面上会先闪一下她
        let behavior: NSWindow.CollectionBehavior = rule.everywhere
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        if panel.collectionBehavior != behavior { panel.collectionBehavior = behavior }
        let want = !defaults.bool(forKey: "hidden")
            && (rule.allows(frontmost: front, own: Bundle.main.bundleIdentifier) || popOutSticky || Date() < popOutUntil)
        let shown = panel.isVisible && panel.alphaValue > 0.5
        let peek = config.settings.peek && !rule.everywhere && !defaults.bool(forKey: "hidden")
        // 已经显示着（或在边上露头）但可能在别的桌面上：再往前放一次，跟到当前桌面
        if (want || peeking), shown, !rule.everywhere, !panel.isOnActiveSpace { panel.orderFrontRegardless() }
        if want, peeking { slideBack(); return }
        if !want, peek {
            if !peeking { slideToEdge() }
            return
        }
        if !want, peeking { slideBack() }
        guard want != shown else { return }
        if want {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        } else {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 }, completionHandler: { [weak self] in
                guard let self, self.panel.alphaValue < 0.5 else { return }
                self.panel.orderOut(nil)
            })
        }
    }

    // MARK: - 在屏幕边露个头

    /// 藏起来时滑到最近的左右屏幕边，只露出一小半
    private(set) var peeking = false
    private var homeOrigin: NSPoint?

    private func slideToEdge() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        homeOrigin = panel.frame.origin
        peeking = true
        let side = self.side, width = panel.frame.width
        let petMinX = width - side                      // 她在窗口里靠右，占 side 那么宽
        let showing = side * 0.42
        let toRight = panel.frame.midX >= screen.frame.midX
        let x = toRight ? screen.frame.maxX - petMinX - showing : screen.frame.minX - width + showing
        view.bubble.hide()
        if !panel.isVisible || panel.alphaValue < 0.5 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: NSPoint(x: x, y: panel.frame.minY), size: panel.frame.size), display: true)
        }
    }

    private func slideBack() {
        guard peeking else { return }
        peeking = false
        let target = homeOrigin ?? panel.frame.origin
        homeOrigin = nil
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(origin: target, size: panel.frame.size), display: true)
        }
    }

    @objc private func toggleQuiet() {
        let manual = !defaults.bool(forKey: "quiet")
        defaults.set(manual, forKey: "quiet")
        pet.quiet = manual || inQuietHours
        if pet.quiet { view.bubble.hide(); pet.handle("idle") }
        rebuildMenu()
    }

    /// 现在在不在设置的安静时段里
    var inQuietHours: Bool { QuietHours(config.settings.quietHours)?.contains(Date()) ?? false }

    /// 每分钟看一次：进出安静时段时跟着开关勿扰（你手动开的勿扰不受影响）
    private func applyQuietHours() {
        let want = defaults.bool(forKey: "quiet") || inQuietHours
        guard want != pet.quiet else { return }
        pet.quiet = want
        if want { view.bubble.hide() }
        rebuildMenuIfReady()
    }

    private func rebuildMenuIfReady() {
        if statusItem != nil { rebuildMenu() }
    }


    @objc private func toggleLogin() {
        if LoginItem.isEnabled { LoginItem.disable() } else { LoginItem.enable() }
        rebuildMenu()
    }

    private func showMain(_ page: MainPage?, focusInput: Bool = false) {
        if main == nil { main = MainWindowController(todoCoordinator: todos, config: config, host: self, agent: agent) }
        main?.show(page, focusInput: focusInput)
    }

    @objc private func openMain() { showMain(nil) }
    @objc private func openTodos() { showMain(.todos) }
    @objc private func openSettings() { showMain(.settings) }
    @objc private func quickAdd() { showMain(.todos, focusInput: true) }

    /// 和她说话：打开 AI 大脑时弹浮窗，没打开就去设置页
    @objc private func openChat() {
        if config.settings.agentEnabled { chatPanel.toggle() } else { showMain(.brain) }
    }

    /// 休息、深夜、纪念日这些陪伴提醒：打开 AI 大脑时，休息和深夜那句由 AI 结合今天的事来说
    private func companionSays(_ event: String) {
        let tasks = [
            "rest": "\(Config.he)已经连续用电脑忙了很久。劝\(Config.he)起来动一动、喝口水，可以提一下今天还剩的事，但别催工作。",
            "night": "已经很晚了\(Config.he)还在用电脑。催\(Config.he)早点睡，语气撒娇，可以说没做完的明天再做。",
        ]
        if event == "together" || event == "birthday" { showPhoto() }
        guard let task = tasks[event], agent.proactive else { pet.handle(event); return }
        agent.compose(task) { [weak self] text in
            if let text { self?.pet.handle(event, line: text) } else { self?.pet.handle(event) }
        }
    }

    /// 配置变了：快捷键按新的注册，开关关掉时注销
    private func applyAgentSettings() {
        let s = config.settings
        AgentPrivacy.shareSourceItems = s.agentEnabled && s.agentShareSources
        let wanted = s.agentEnabled ? s.agentHotkey : nil
        guard wanted != registeredHotkey else { return }
        registeredHotkey = wanted
        if let wanted, let spec = HotkeySpec(wanted) {
            hotkey.register(spec) { [weak self] in self?.openChat() }
        } else {
            hotkey.unregister()
            chatPanel.hide()
        }
        rebuildMenu()
    }

    var petHidden: Bool {
        get { defaults.bool(forKey: "hidden") }
        set { if newValue != petHidden { toggleVisible() } }
    }

    func resetPetPosition() { resetPosition() }

    /// 右键、双击有固定反应，但戳太多次时还是鼓嘴
    private func tapOrAnnoyed(_ event: String) {
        let next = taps.next()
        tap(next == taps.annoyedAction ? next : event)
    }

    /// 点她的反应：大多数时候只做表情，大约每 N 次说一句；「别戳啦」每次都说
    private func tap(_ event: String) {
        stats.bump(.taps)
        if backgroundDoneCount > 0 { backgroundDoneCount = 0; view.setBadge(0) }
        if peeking {
            popOutUntil = Date().addingTimeInterval(15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.1) { [weak self] in self?.applyVisibility() }
        }
        defer { applyVisibility() }
        // 有合照时，大约每 12 下弹一张
        if Int.random(in: 0..<12) == 0, !currentAlbum.photos().isEmpty { showPhoto() }
        let talk = event == "annoyed" || taps.shouldTalk(every: config.settings.tapTalkEvery)
        pet.handle(event, silent: !talk)
    }

    /// 启动时从事件文件里找回每种 Claude 事件最近一次的时间
    private static func recentClaudeActivity() -> [String: Date] {
        guard let text = try? String(contentsOf: Paths.events, encoding: .utf8) else { return [:] }
        var out: [String: Date] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let ts = TimeInterval(parts[0]) else { continue }
            let event = String(parts[1])
            if claudeEvents.contains(event) { out[event] = Date(timeIntervalSince1970: ts) }
        }
        return out
    }

    // MARK: - 设置页

    var petSide: CGFloat {
        get { side }
        set {
            guard newValue != side else { return }
            defaults.set(Double(newValue), forKey: "size")
            applySize()
            placeWindow()
            rebuildMenu()
        }
    }

    var isQuiet: Bool {
        get { pet.quiet }
        set { if newValue != pet.quiet { toggleQuiet() } }
    }

    var launchAtLogin: Bool {
        get { LoginItem.isEnabled }
        set { if newValue != LoginItem.isEnabled { toggleLogin() } }
    }

    /// 做个动作并说一句指定的话（待办提醒用，台词不从配置里挑）
    private func say(_ event: String, _ line: String?, sticky: Bool) {
        nextBubbleIsTodo = line != nil
        let wasQuiet = pet.quiet
        pet.quiet = false
        pet.handle(event, line: line, sticky: sticky)
        pet.quiet = wasQuiet
    }

    func play(_ event: String) {
        let wasQuiet = pet.quiet
        pet.quiet = false
        pet.handle(event)
        pet.quiet = wasQuiet
    }

    @objc private func resetPosition() {
        defaults.removeObject(forKey: "originX")
        defaults.removeObject(forKey: "originY")
        placeWindow()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// 带参数就是命令行工具，做完就退出
if let code = CLI.run(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

// 已经开着一个就不再开第二个
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)     // 不在 Dock 栏显示图标
app.run()
