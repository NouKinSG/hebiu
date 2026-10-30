import FocusCore
import Foundation

/// 正在进行的计时（引擎 + 记录器）的快照，存于 UserDefaults `foy.activeTimer`。
/// app 被系统杀掉（iOS 常见）或崩溃后，下次启动据此恢复。
struct ActiveTimerState: Codable, Equatable {
    var engine: TimerSnapshot
    var recorder: RecorderSnapshot?
}
