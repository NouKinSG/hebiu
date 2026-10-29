import FocusCore
import Foundation

/// 演示 / 截图模式下的固定假数据：近 30 天约 40 条会话，最近 5 天（含今天）
/// 每天都有记录、第 6 天空缺，三种 outcome 都有，今天至少 2 条完成。
/// 不使用随机数，同一时刻生成的结果完全一致。
enum DemoSessions {
    private static let titles = [
        "写周报",
        "读《深度工作》第三章",
        "整理第四季度产品路线图，并和设计、研发、市场三方逐条对齐优先级与上线时间节点",
        "刷算法题",
        "",
        "准备周四的分享",
    ]
    private static let minutes: [Double] = [25, 45, 15, 60, 25, 30, 50]
    private static let hours = [9, 14, 20]
    /// 每天的会话条数，按天循环；0 表示那天没有记录。
    private static let perDay = [2, 1, 3, 1, 2, 0, 1, 2, 0, 1, 1, 2]

    static func make(now: Date, calendar: Calendar = .current) -> [FocusCore.FocusSession] {
        let today = calendar.startOfDay(for: now)
        var sessions: [FocusCore.FocusSession] = []
        var index = 0

        // 今天：两条完成的会话，都在 now 之前开始。
        for (gap, mins) in [(150.0, 25.0), (60.0, 45.0)] {
            let start = max(today, now.addingTimeInterval(-gap * 60))
            sessions.append(make(index: index, start: start, minutes: mins, outcome: .completed))
            index += 1
        }

        for offset in 1 ..< 30 {
            // 第 6 天（offset 5）固定空缺，保证连续 5 天。
            let count = offset == 5 ? 0 : perDay[offset % perDay.count]
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for slot in 0 ..< count {
                let start = day.addingTimeInterval(TimeInterval(hours[slot % hours.count] * 3600))
                let mins = minutes[index % minutes.count]
                let outcome: SessionOutcome
                if index % 5 == 3 {
                    outcome = .interrupted
                } else if index % 7 == 4 {
                    outcome = .free
                } else {
                    outcome = .completed
                }
                sessions.append(make(index: index, start: start, minutes: mins, outcome: outcome))
                index += 1
            }
        }
        return sessions
    }

    private static func make(index: Int, start: Date, minutes mins: Double, outcome: SessionOutcome) -> FocusCore.FocusSession {
        // 中断的会话只专注了计划时长的一部分。
        let focused = outcome == .interrupted ? mins * 0.6 * 60 : mins * 60
        return FocusCore.FocusSession(
            title: titles[index % titles.count],
            mode: outcome == .free ? .countUp : .countdown,
            startedAt: start,
            endedAt: start.addingTimeInterval(focused),
            focusedSeconds: focused,
            plannedSeconds: outcome == .free ? nil : mins * 60,
            outcome: outcome
        )
    }
}
