import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#endif

/// 倒计时到点通知的调度。iOS 上 app 在后台会被挂起，必须提前预约本地通知；
/// Mac 在完成时即时通知（见 `NotificationService`），这里用空实现。
@MainActor
protocol NotificationScheduling: AnyObject {
    /// 首次开始倒计时时请求授权；重复调用无副作用。用户拒绝也不影响计时与记录。
    func requestAuthorizationIfNeeded()
    /// 预约一条「专注完成」通知，`after` 秒后送达。
    func scheduleCompletion(after interval: TimeInterval, title: String)
    /// 取消尚未送达的预约。
    func cancelPending()
    /// 前台计时到点时的即时提醒（Mac：提示音 + Dock 弹跳 + 横幅）。
    /// iOS 依赖已预约的通知按时送达，这里不再另发。
    func deliverCompletion(focusTitle: String)
}

/// Mac 由桌宠控制器提醒，测试也使用此空实现，不触达系统通知。
@MainActor
final class NoopNotificationScheduler: NotificationScheduling {
    func requestAuthorizationIfNeeded() {}
    func scheduleCompletion(after interval: TimeInterval, title: String) {}
    func cancelPending() {}
    func deliverCompletion(focusTitle: String) {}
}

/// 「专注完成」通知文案，Mac 与 iOS 共用。
enum CompletionCopy {
    static let title = "专注完成"
    /// 通知 identifier 前缀（不变量 5）。
    static let identifierPrefix = "com.lukaspeng.focusonyourself.complete."
    /// iOS 预约用的固定 identifier：重新预约即替换；app 被杀后新进程也能按它取消旧预约。
    static let scheduledIdentifier = identifierPrefix + "current"

    static func body(focusTitle: String) -> String {
        let trimmed = focusTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "这一轮专注结束了，起来活动一下，喝口水吧。"
        }
        return "「\(trimmed)」完成了一轮专注，起来活动一下，喝口水吧。"
    }
}

/// 系统通知中心的最小接口，便于在测试里替换。
protocol CompletionNotificationCenter: AnyObject {
    func add(identifier: String, title: String, body: String, after interval: TimeInterval)
    func removePending(identifiers: [String])
}

/// 基于 `UNUserNotificationCenter` 的实现。
final class SystemNotificationCenter: CompletionNotificationCenter {
    func add(identifier: String, title: String, body: String, after interval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// 按剩余时间预约本地通知（iOS 使用；逻辑跨平台以便在 Mac 上测试）。
/// app 在前台到点时仍显示横幅、播放提示音，iOS 上再给一次成功触感。
@MainActor
final class UserNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationScheduler(center: SystemNotificationCenter(), installDelegate: true)

    private let center: CompletionNotificationCenter
    private var didRequestAuthorization = false

    init(center: CompletionNotificationCenter, installDelegate: Bool = false) {
        self.center = center
        super.init()
        if installDelegate {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 同一个 identifier 再次 add 会替换旧预约，任何时候最多只有一条。
    func scheduleCompletion(after interval: TimeInterval, title: String) {
        guard interval > 0 else {
            cancelPending()
            return
        }
        center.add(identifier: CompletionCopy.scheduledIdentifier, title: CompletionCopy.title,
                   body: CompletionCopy.body(focusTitle: title), after: interval)
    }

    /// 不依赖内存状态：无论是本进程还是被杀之前的进程预约的，都能取消。
    func cancelPending() {
        center.removePending(identifiers: [CompletionCopy.scheduledIdentifier])
    }

    /// 预约的那条正好在此刻送达（前台时由 willPresent 展示），这里不重复发送。
    func deliverCompletion(focusTitle: String) {}

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
        #if os(iOS)
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        #endif
    }
}
