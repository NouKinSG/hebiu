import Charts
import FocusCore
import SwiftUI

// MARK: - Formatting

enum DurationFormat {
    /// 数据卡：不足 1 小时显示整分钟，否则显示一位小数的小时。
    static func tile(_ seconds: TimeInterval) -> (value: String, unit: String) {
        if seconds < 3600 {
            return ("\(Int(seconds / 60))", "分钟")
        }
        return (String(format: "%.1f", seconds / 3600), "小时")
    }

    /// 会话行：至少 1 分钟；满 1 小时写成「1 小时 5 分」。
    static func row(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) 小时" : "\(minutes / 60) 小时 \(rest) 分"
    }

    /// 「今天 14:05」/「昨天 21:30」/「10月23日」。
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = formatter("HH:mm", calendar: calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time)"
        }
        return formatter("M月d日", calendar: calendar).string(from: date)
    }

    static func formatter(_ format: String, calendar: Calendar = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Range picker

struct RangePicker: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @Binding var selection: Int
    let options: [Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { days in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = days }
                } label: {
                    Text("\(days) 天")
                        .font(.hebiuSystem(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(selection == days ? FocusTheme.ink : FocusTheme.textSecondary)
                        .frame(width: 46, height: 22)
                        .background {
                            if selection == days {
                                Capsule(style: .continuous)
                                    .fill(FocusTheme.ink.opacity(0.14))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(FocusTheme.ink.opacity(0.34), lineWidth: 1)
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(FocusTheme.surface))
        .overlay(Capsule(style: .continuous).strokeBorder(FocusTheme.stroke, lineWidth: 1))
    }
}

// MARK: - Stat tile

struct StatTile: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let title: String
    let value: String
    let unit: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typography.eyebrow)
                .tracking(1.2)
                .foregroundStyle(FocusTheme.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.hebiuSystem(size: 26, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(FocusTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(FocusTheme.textSecondary)
            }

            Text(caption ?? " ")
                .font(Typography.caption)
                .foregroundStyle(FocusTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 14)
    }
}

// MARK: - Bar chart

struct FocusBarChart: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let totals: [DailyTotal]
    let range: Int
    var calendar: Calendar = .current

    private static let weekdays = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        Chart(totals, id: \.day) { total in
            BarMark(
                x: .value("日", total.day, unit: .day),
                y: .value("分钟", total.seconds / 60),
                width: .ratio(range <= 7 ? 0.5 : 0.62)
            )
            .foregroundStyle(FocusTheme.ink)
            .opacity(isToday(total.day) ? 1 : 0.55)
            .cornerRadius(range <= 7 ? 4 : 2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range <= 7 ? 1 : 5)) { value in
                if let day = value.as(Date.self) {
                    AxisValueLabel(centered: true) {
                        Text(label(for: day))
                            .font(.hebiuSystem(size: 9.5, weight: .medium, design: .default))
                            .foregroundStyle(isToday(day) ? FocusTheme.textPrimary : FocusTheme.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(FocusTheme.stroke)
                AxisValueLabel()
                    .font(.hebiuSystem(size: 9, design: .default))
                    .foregroundStyle(FocusTheme.textTertiary)
            }
        }
        .frame(height: 150)
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDateInToday(day)
    }

    private func label(for day: Date) -> String {
        if range <= 7 {
            return Self.weekdays[calendar.component(.weekday, from: day) - 1]
        }
        return DurationFormat.formatter("M/d", calendar: calendar).string(from: day)
    }
}

// MARK: - Session row

struct SessionRow: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let session: FocusCore.FocusSession
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            outcomeMark
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "未命名专注" : session.title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(session.title.isEmpty ? FocusTheme.textSecondary : FocusTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(DurationFormat.when(session.startedAt, now: now)) · \(outcomeLabel)")
                    .font(Typography.caption)
                    .foregroundStyle(FocusTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(DurationFormat.row(session.focusedSeconds))
                .font(.hebiuSystem(size: 12.5, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(FocusTheme.textSecondary)
                .fixedSize()
        }
        .padding(.vertical, 8)
    }

    /// 不靠颜色区分结局：完成 = 实心点，中断 = 空心圈，自由专注 = 灰点。
    @ViewBuilder
    private var outcomeMark: some View {
        switch session.outcome {
        case .completed: Circle().fill(FocusTheme.ink)
        case .interrupted: Circle().strokeBorder(FocusTheme.ink, lineWidth: 1.5)
        case .free: Circle().fill(FocusTheme.textTertiary)
        }
    }

    private var outcomeLabel: String {
        switch session.outcome {
        case .completed: return "完成"
        case .interrupted: return "中断"
        case .free: return "自由专注"
        }
    }
}
