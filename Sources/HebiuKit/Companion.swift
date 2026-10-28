import Foundation

/// 陪你工作的几件小事：连续忙太久提醒休息、深夜催睡觉、纪念日和生日冒爱心。
/// 「在忙」的依据只有 Claude 的事件（hello / working / wait / done / error），不看键盘鼠标，不读任何别的数据
public final class Companion {
    private let config: Config
    private let trigger: (String) -> Void
    private var timer: DispatchSourceTimer?

    private var lastActivity: Date?
    private var streakStart: Date?
    private var lastRestReminder = Date.distantPast
    private var lastNightReminder = Date.distantPast
    private var celebratedDay: String?
    /// 番茄钟专心中时为 true：那会儿由番茄钟管休息，这边不再催
    public var isFocusing: () -> Bool = { false }

    /// 两次活动间隔超过这么久，就算你休息过了，连续时长重新计
    private let breakGap: TimeInterval = 15 * 60
    /// 提醒过一次之后，至少隔这么久才再提醒
    private let restRepeat: TimeInterval = 30 * 60
    private let nightRepeat: TimeInterval = 60 * 60

    public init(config: Config, trigger: @escaping (String) -> Void) {
        self.config = config
        self.trigger = trigger
    }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 5, repeating: 60, leeway: .seconds(5))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Claude 有动静时调用
    public func noteActivity(_ now: Date = Date()) {
        if let last = lastActivity, now.timeIntervalSince(last) < breakGap {
            // 还在同一段连续工作里
        } else {
            streakStart = now
        }
        lastActivity = now
    }

    private func tick(_ now: Date = Date()) {
        celebrateIfNeeded(now)
        guard let last = lastActivity, now.timeIntervalSince(last) < 5 * 60 else { return }   // 最近 5 分钟没动静就不打扰

        let hour = Calendar.current.component(.hour, from: now)
        let night = config.nightHour > 0 && (hour >= config.nightHour || hour < 5)
        if night, now.timeIntervalSince(lastNightReminder) >= nightRepeat {
            lastNightReminder = now
            trigger("night")
            return
        }
        if config.restMinutes > 0, !isFocusing(), let start = streakStart,
           now.timeIntervalSince(start) >= Double(config.restMinutes) * 60,
           now.timeIntervalSince(lastRestReminder) >= restRepeat {
            lastRestReminder = now
            trigger("rest")
        }
    }

    /// 纪念日（每年的同一天，以及每满 100 天）和生日：当天第一次检查到时冒爱心，一天一次
    private func celebrateIfNeeded(_ now: Date) {
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: now)
        let key = "\(today.year ?? 0)-\(today.month ?? 0)-\(today.day ?? 0)"
        guard celebratedDay != key else { return }
        if let b = config.birthday, b.month == today.month, b.day == today.day {
            celebratedDay = key
            trigger("birthday")
        } else if let t = config.together, let days = config.daysTogether(on: now), days > 1,
                  (t.month == today.month && t.day == today.day) || days % 100 == 0 {
            celebratedDay = key
            trigger("together")
        }
    }
}
