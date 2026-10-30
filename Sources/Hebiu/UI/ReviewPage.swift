import HebiuKit
import SwiftUI

/// 日常 → 回顾：这周（或上周）做了什么、写代码到几点、习惯、心情，她写一段总结
struct ReviewPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var settings: SettingsModel
    @ObservedObject var agent: AgentController
    @State private var offset = 0
    @State private var written: [String: String] = [:]
    @State private var writing = false

    var body: some View {
        let r = settings.weekReview(offset: offset)
        Page(title: "回顾", subtitle: subtitle(r), trailing: AnyView(
            Picker("", selection: $offset) {
                Text("上周").tag(-1)
                Text("这周").tag(0)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 140)
        )) {
            StatsTiles(day: r.total)

            section("\(Her.she)的总结") {
                if let text = written[r.key] ?? agent.memory.text(.weekly, r.key) {
                    HStack(alignment: .top, spacing: 12) {
                        PetThumb(frame: "bliss", size: 44)
                        Text(text).font(.hebiuStyle(.callout)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                } else {
                    HStack {
                        Text(agent.enabled ? "让\(Her.she)看看这周的数字和日记，写一段" : "打开 AI 大脑后，\(Her.she)可以帮你写一段这周的总结")
                            .font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
                        Spacer()
                        if writing { ProgressView().controlSize(.small) }
                        Button("让\(Her.she)写一段") { write(r) }.disabled(!agent.enabled || writing)
                    }
                }
            }

            section("写代码的时间", trailing: footer(r)) {
                CodingChart(days: r.days, activity: r.activity)
            }

            section("心情") {
                HStack(spacing: 0) {
                    ForEach(Array(zip(r.days, r.moods).enumerated()), id: \.offset) { _, pair in
                        VStack(spacing: 6) {
                            if let m = pair.1 {
                                Text(m.emoji).font(.hebiuSystem(size: 24)).help(m.note.isEmpty ? m.name : "\(m.name) · \(m.note)")
                            } else {
                                Circle().stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    .frame(width: 24, height: 24).padding(3)
                            }
                            Text(Self.weekday(pair.0)).font(.hebiuStyle(.caption2)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            if !r.habits.isEmpty {
                section("习惯") {
                    VStack(spacing: 10) {
                        ForEach(r.habits) { h in
                            HStack(spacing: 10) {
                                Text(h.habit.emoji)
                                Text(h.habit.title).frame(width: 120, alignment: .leading)
                                ProgressView(value: h.scheduled == 0 ? 0 : Double(h.done) / Double(h.scheduled)).tint(Theme.accent)
                                Text("\(h.done) / \(h.scheduled)").font(.hebiuStyle(.callout)).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            section("完成的事", trailing: r.todosDone.isEmpty ? nil : "\(r.todosDone.count) 件") {
                if r.todosDone.isEmpty {
                    Text(offset == 0 ? "这周还没有打勾的待办" : "上周的完成记录已经清掉了（只留 7 天）").font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(r.todosDone) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Text(item.doneAt.map { TodoFormat.describe($0, hasTime: false) } ?? "").font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func subtitle(_ r: WeekReview) -> String {
        "\(MonthDay.text(r.days[0])) – \(MonthDay.text(r.days[6]))"
    }

    private func footer(_ r: WeekReview) -> String? {
        guard r.codingDays > 0 else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "写了 \(r.codingDays) 天" + (r.latestFinish.map { "，最晚 \(f.string(from: $0)) 收工" } ?? "")
    }

    private func write(_ r: WeekReview) {
        writing = true
        agent.writeWeekReview(r) { text in
            writing = false
            written[r.key] = text ?? "没写成（网络或额度），等会儿再试"
        }
    }

    static func weekday(_ day: String) -> String {
        guard let d = MemoryDay.formatter.date(from: day) else { return "" }
        return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][Calendar.current.component(.weekday, from: d.addingTimeInterval(43200)) - 1]
    }

    private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title, trailing: trailing)
            Card { content() }
        }
    }
}

/// 每天一根竖条：从第一次到最后一次有 Claude 动静；纵轴是凌晨 4 点到第二天凌晨 4 点
private struct CodingChart: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let days: [String]
    let activity: [ClaudeActivity]
    private let height: CGFloat = 150

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ForEach([8, 12, 16, 20, 24, 28], id: \.self) { h in
                    Text(String(format: "%02d", h % 24)).font(.hebiuSystem(size: 9)).foregroundStyle(.tertiary).monospacedDigit()
                        .offset(y: height * position(hour: Double(h)) - 6)
                }
            }
            .frame(width: 16, height: height, alignment: .topTrailing)
            ForEach(Array(zip(days, activity).enumerated()), id: \.offset) { _, pair in
                VStack(spacing: 6) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.07))
                        if let first = pair.1.first, let last = pair.1.last {
                            let a = position(first), b = max(position(last), a + 0.02)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.accent.opacity(b > position(hour: 24) ? 1 : 0.7))
                                .frame(height: height * (b - a))
                                .offset(y: height * a)
                                .help(pair.1.summary ?? "")
                        }
                    }
                    .frame(height: height)
                    Text(ReviewPage.weekday(pair.0)).font(.hebiuStyle(.caption2)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// 从早上 8 点画到第二天凌晨 4 点（再早的贴着顶）
    private func position(_ d: Date) -> CGFloat {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        var h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        if h < Double(AgentMemory.dayStartsAtHour) { h += 24 }
        return position(hour: h)
    }

    private func position(hour h: Double) -> CGFloat {
        CGFloat(min(1, max(0, (h - 8) / 20)))
    }
}
