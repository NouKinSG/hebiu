import HebiuKit
import AppKit
import QuartzCore

/// 按剧本切换画面：空闲时眨眼、偶尔来个小动作；收到事件就播对应的剧本，播完回到空闲
final class PetController {
    private let imageLayer: CALayer
    private let config: Config
    private var frames: [String: Frame] = [:]
    private var generation = 0
    private var idleTimer: DispatchSourceTimer?
    private var lastEventAt = Date()
    private var lastErrorAt = Date.distantPast
    private var playing: String?
    /// 到点提醒的台词挂着：别的自动事件照常做动作，但不换掉这句话；点她（摸头/戳/双击）才算看到了
    private(set) var stickyShown = false
    private var userEvents: Set<String> { Character.tapEvents }
    private(set) var current = "idle"
    private var idleFrame: String { Character.pack.idle.frame }
    private(set) var isIdle = true
    var quiet = false
    /// 「她说话」关掉时为 true：不弹气泡（待办到点提醒除外）
    var mute: () -> Bool = { false }
    var showBubble: ((_ text: String, _ sticky: Bool) -> Void)?
    /// 离上次动键盘鼠标过了几秒
    var userIdleSeconds: () -> TimeInterval = { 0 }
    /// 闲多久睡着（秒），0 不睡
    var sleepAfter: () -> TimeInterval = { 0 }
    private(set) var sleeping = false
    var hideBubble: (() -> Void)?

    init(imageLayer: CALayer, config: Config) {
        self.imageLayer = imageLayer
        self.config = config
        imageLayer.actions = ["contents": NSNull(), "transform": NSNull()]   // 换帧不要淡入淡出
    }

    func setFrames(_ frames: [String: Frame]) {
        self.frames = frames
        show(current)
    }

    var currentFrame: Frame? { frames[current] }

    func start() {
        backToIdle()
        startIdleTimer()
    }

    // MARK: - 事件

    /// line：指定这次要说的话（不从配置里随机挑）
    /// silent：这次只做动作不说话（点她时大多数时候这样）
    func handle(_ event: String, line: String? = nil, sticky: Bool = false, silent: Bool = false) {
        guard let recipe = Recipes.all[event] else {
            if event == "idle" { backToIdle() } else { Log.write("unknown event: \(event)") }
            return
        }
        if quiet && !Recipes.allowedWhenQuiet.contains(event) { Log.write("event \(event) (quiet, skipped)"); return }
        // 工具失败很常见（比如 grep 没搜到），出错的动作一分钟最多一次
        if event == "error" {
            guard Date().timeIntervalSince(lastErrorAt) >= 60 else { Log.write("event error (throttled)"); return }
            lastErrorAt = Date()
        }
        // Claude 还在干活时插进来的动作，播完接着敲键盘
        var afterwards: (() -> Void)?
        if Recipes.resumesWorking.contains(event), playing == "working", let working = Recipes.all["working"] {
            afterwards = { self.playing = "working"; self.runLoop(working.loop) }
        }
        if sleeping { stopSleeping() }
        Log.write("event \(event)\(silent ? " (silent)" : "")")
        lastEventAt = Date()
        playing = event
        if userEvents.contains(event) || sticky { clearSticky() }
        play(recipe, line: line, sticky: sticky, silent: silent, afterwards: afterwards)
    }

    private func play(_ recipe: Recipe, line override: String? = nil, sticky: Bool = false, silent quietOnce: Bool = false,
                      afterwards: (() -> Void)? = nil) {
        cancelScheduled()
        if !stickyShown { hideBubble?() }   // 上一个动作的台词不要挂到下一个动作上（提醒除外）
        isIdle = false
        let silent = quiet || quietOnce || (mute() && !sticky)   // 开始时就定下要不要说话；手动触发的动作会临时关掉勿扰
        var t = 0.0
        for step in recipe.steps {
            schedule(at: t) { self.show(step.frame, effect: step.effect ?? .pop) }
            t += step.seconds
        }
        schedule(at: t) {
            self.show(recipe.hold, effect: recipe.holdEffect)
            if let text = override ?? recipe.line.flatMap({ self.config.randomLine(for: $0) }), !silent, !self.stickyShown || sticky {
                self.showBubble?(text, sticky)
                if sticky { self.stickyShown = true }
            }
        }
        if !recipe.loop.isEmpty {
            schedule(at: t) { self.runLoop(recipe.loop) }
        } else if let hold = recipe.holdSeconds {
            schedule(at: t + hold) { if let afterwards { afterwards() } else { self.backToIdle() } }
        }
    }

    /// 循环动作（敲键盘）一直播到下一个事件；30 分钟没有新事件就自己停下，防止卡在这个状态
    private func runLoop(_ steps: [Step]) {
        guard Date().timeIntervalSince(lastEventAt) < 30 * 60 else { backToIdle(); return }
        var t = 0.0
        for step in steps {
            schedule(at: t) { self.show(step.frame, effect: nil) }
            t += step.seconds
        }
        schedule(at: t) { self.runLoop(steps) }
    }

    /// 编辑动作时「试一下」：直接演一个还没存的动作
    func preview(_ recipe: Recipe) {
        if sleeping { stopSleeping() }
        lastEventAt = Date()
        playing = nil
        play(recipe, line: nil, sticky: false, silent: false, afterwards: nil)
    }

    /// 提醒看到了：收起气泡
    func clearSticky() {
        guard stickyShown else { return }
        stickyShown = false
        hideBubble?()
    }

    private func backToIdle() {
        cancelScheduled()
        playing = nil
        isIdle = true
        show(idleFrame, effect: current == idleFrame ? nil : .pop)
    }

    // MARK: - 空闲小动作

    private var nextBlink = Date().addingTimeInterval(3)
    private var nextFidget = Date().addingTimeInterval(60)

    /// 一个 0.5 秒的低频定时器统一驱动眨眼和随机小动作，空闲时几乎不占 CPU
    private func startIdleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.idleTick() }
        timer.resume()
        idleTimer = timer
    }

    private func idleTick() {
        if sleeping {
            // 一动鼠标键盘就吓醒
            if userIdleSeconds() < 1.5 { wakeUp() }
            return
        }
        guard isIdle, current == idleFrame else { return }
        let now = Date()
        let after = sleepAfter()
        if after > 0, !stickyShown, userIdleSeconds() >= after, now.timeIntervalSince(lastEventAt) >= after {
            fallAsleep()
            return
        }
        if now >= nextFidget {
            nextFidget = now.addingTimeInterval(Double.random(in: 50...110))
            if let fidget = Character.pack.idle.fidgets.randomElement() { handle(fidget) }
        } else if now >= nextBlink {
            nextBlink = now.addingTimeInterval(Double.random(in: 2.8...5.2))
            guard let blink = Character.pack.idle.blink else { return }
            show(blink, effect: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self, self.isIdle, self.current == blink else { return }
                self.show(self.idleFrame, effect: nil)
            }
        }
    }

    // MARK: - 睡觉

    /// 闲着太久：打个哈欠睡着，慢慢呼吸
    private func fallAsleep() {
        sleeping = true
        isIdle = false
        hideBubble?()
        show(Character.pack.idle.sleep, effect: .pop)
        let breathe = CABasicAnimation(keyPath: "transform.scale.y")
        breathe.fromValue = 1.0
        breathe.toValue = 0.975
        breathe.duration = 1.6
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(breathe, forKey: "breathe")
        Log.write("pet: fell asleep")
    }

    private func stopSleeping() {
        sleeping = false
        imageLayer.removeAnimation(forKey: "breathe")
    }

    /// 被吵醒：吓一跳，然后挥手
    private func wakeUp() {
        stopSleeping()
        cancelScheduled()
        isIdle = false
        lastEventAt = Date()
        show(Character.pack.idle.startle, effect: .kick)
        schedule(at: 0.7) { self.show(Character.pack.idle.wake, effect: .sway) }
        schedule(at: 2.2) { self.backToIdle() }
        Log.write("pet: woke up")
    }

    // MARK: - 画面

    private func show(_ name: String, effect: Effect? = nil) {
        // 形象包里没有这一帧：用平时那一帧顶上，不至于空着
        guard let frame = frames[name] ?? frames[idleFrame] else { Log.write("missing frame: \(name)"); return }
        current = name
        imageLayer.contents = frame.image
        if let effect { apply(effect) }
    }

    private func apply(_ effect: Effect) {
        imageLayer.removeAnimation(forKey: "effect")
        let anim: CAAnimation
        switch effect {
        case .pop:
            let a = CAKeyframeAnimation(keyPath: "transform.scale")
            a.values = [0.95, 1.03, 1.0]; a.keyTimes = [0, 0.6, 1]; a.duration = 0.3
            anim = a
        case .kick:
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = [0, -0.05, 0.02, 0]; a.keyTimes = [0, 0.25, 0.6, 1]; a.duration = 0.36
            anim = a
        case .squish:
            let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
            // 只缩一下：缩几下看起来像点了好几次
            a.values = [1, 0.9, 1.03, 1]; a.keyTimes = [0, 0.35, 0.7, 1]; a.duration = 0.32
            anim = a
        case .sway:
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = [0, 0.06, -0.06, 0.06, -0.06, 0]; a.duration = 1.8
            anim = a
        }
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(anim, forKey: "effect")
    }

    // MARK: - 调度

    /// 每次换剧本代号加一，旧剧本里还没到点的任务执行时发现代号不对就直接跳过，不需要保存任务列表
    private func schedule(at seconds: Double, _ block: @escaping () -> Void) {
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == gen else { return }
            block()
        }
    }

    private func cancelScheduled() {
        generation &+= 1
    }
}
