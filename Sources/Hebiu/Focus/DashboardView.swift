import FocusCore
import SwiftUI

/// 主窗口右侧的统计侧栏：今日 / 本周 / 连续、近 7 或 30 天柱状图、最近会话。
struct DashboardView: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    static let width: CGFloat = 359

    @ObservedObject var model: FocusModel
    @State private var range = 7

    var body: some View {
        let stats = model.stats

        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: 18)
            tiles(stats)
            Spacer().frame(height: 18)
            chart(stats)
            Spacer().frame(height: 20)
            recent(stats)
        }
        .padding(.horizontal, 24)
        .padding(.top, Layout.dashboardTopInset)
        .padding(.bottom, 22)
        #if os(macOS)
        .frame(width: Self.width, height: 680, alignment: .top)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    private var header: some View {
        HStack {
            Text("最近专注")
                .font(Typography.wordmark)
                .foregroundStyle(FocusTheme.textPrimary)
            Spacer()
            RangePicker(selection: $range, options: [7, 30])
        }
        .frame(height: 30)
    }

    private func tiles(_ stats: FocusStats) -> some View {
        let today = DurationFormat.tile(stats.todayFocused)
        let week = DurationFormat.tile(stats.weekFocused)
        return HStack(spacing: 8) {
            StatTile(
                title: "今日",
                value: today.value,
                unit: today.unit,
                caption: "完成 \(stats.todayCompletedCount) 轮"
            )
            StatTile(title: "本周", value: week.value, unit: week.unit)
            StatTile(title: "连续", value: "\(stats.streakDays)", unit: "天")
        }
    }

    @ViewBuilder
    private func chart(_ stats: FocusStats) -> some View {
        if model.sessions.isEmpty {
            Text("完成第一轮专注后，这里会出现你的记录")
                .font(Typography.body)
                .foregroundStyle(FocusTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .surface(cornerRadius: 14)
        } else {
            FocusBarChart(totals: stats.dailyTotals(days: range), range: range)
                .padding(.top, 4)
        }
    }

    private func recent(_ stats: FocusStats) -> some View {
        let sessions = stats.recent(limit: 20)
        return VStack(alignment: .leading, spacing: 4) {
            Text("最近会话")
                .font(Typography.eyebrow)
                .tracking(1.2)
                .foregroundStyle(FocusTheme.textTertiary)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(sessions) { session in
                        SessionRow(session: session, now: stats.now)
                        if session.id != sessions.last?.id {
                            Rectangle().fill(FocusTheme.stroke).frame(height: 1)
                        }
                    }
                }
            }
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                }
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
