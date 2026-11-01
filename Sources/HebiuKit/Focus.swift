import Foundation

/// 倒计时文字格式；计时和休息状态统一由专注模块管理。
public enum FocusClock {
    /// 18:05 这样的倒计时。
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
