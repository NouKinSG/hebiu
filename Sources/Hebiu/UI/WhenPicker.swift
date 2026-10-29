import HebiuKit
import SwiftUI

/// 选时间：左边月历点一天，右边点一个钟点就选好了（「全天」只要日期）；也可以在下面直接写「周五下午三点」
struct WhenPicker: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let initial: Date?
    let initialHasTime: Bool
    let onPick: ((date: Date, hasTime: Bool)) -> Void

    @State private var month = Date()
    @State private var day = Date()
    @State private var typed = ""
    @State private var typedError = false
    private let cal: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    /// 07:00 到 23:30，每半小时一个
    static let times: [(Int, Int)] = (7...23).flatMap { [($0, 0), ($0, 30)] }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                weekdays
                grid
                Spacer(minLength: 0)
                typeField
            }
            .padding(16)
            .frame(width: 300)
            Divider()
            timeList.frame(width: 96)
        }
        .frame(height: 330)
        .tint(Theme.accent)
        .onAppear {
            let start = initial ?? Date()
            day = cal.startOfDay(for: start)
            month = start
        }
    }

    // MARK: - 月历

    private var header: some View {
        HStack(spacing: 6) {
            Text(monthTitle).font(.hebiuSystem(size: 15, weight: .semibold)).monospacedDigit()
            Spacer()
            navButton("chevron.left") { shiftMonth(-1) }
            Button("今天") { month = Date(); day = cal.startOfDay(for: Date()) }
                .buttonStyle(.plain).font(.hebiuSystem(size: 12)).foregroundStyle(Theme.accent)
            navButton("chevron.right") { shiftMonth(1) }
        }
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                Text(w).font(.hebiuSystem(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = monthDays
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { d in
                let inMonth = cal.isDate(d, equalTo: month, toGranularity: .month)
                let selected = cal.isDate(d, inSameDayAs: day)
                let today = cal.isDateInToday(d)
                let past = d < cal.startOfDay(for: Date())
                Button {
                    day = d
                    if !inMonth { month = d }
                } label: {
                    Text("\(cal.component(.day, from: d))")
                        .font(.hebiuSystem(size: 13, weight: selected || today ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(selected ? Color.white : !inMonth || past ? Color.secondary.opacity(0.5) : today ? Theme.accent : Color.primary)
                        .frame(width: 32, height: 30)
                        .background(Circle().fill(selected ? Theme.accent : Color.clear))
                        .overlay(Circle().stroke(today && !selected ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthTitle: String {
        "\(cal.component(.year, from: month)) 年 \(cal.component(.month, from: month)) 月"
    }

    /// 这个月的格子：从包含 1 号那周的周一，排满 6 行
    private var monthDays: [Date] {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let weekday = (cal.component(.weekday, from: first) + 5) % 7      // 周一 = 0
        let start = cal.date(byAdding: .day, value: -weekday, to: first)!
        return (0..<42).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    private func shiftMonth(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month) ?? month
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.hebiuSystem(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 钟点

    private var timeList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    timeRow("全天", id: "allday", selected: initial != nil && !initialHasTime && cal.isDate(initial!, inSameDayAs: day)) {
                        onPick((cal.startOfDay(for: day), false))
                    }
                    ForEach(Array(WhenPicker.times.enumerated()), id: \.offset) { _, t in
                        let (h, m) = t
                        let at = cal.date(bySettingHour: h, minute: m, second: 0, of: day)!
                        let isPast = at < Date()
                        let selected = initialHasTime && initial.map { cal.isDate($0, equalTo: at, toGranularity: .minute) } ?? false
                        timeRow(String(format: "%02d:%02d", h, m), id: "\(h)-\(m)", selected: selected, dim: isPast) {
                            onPick((at, true))
                        }
                    }
                }
                .padding(8)
            }
            .onAppear {
                // 滚到选过的钟点；没选过就滚到现在之后的钟点（今天）或早上 9 点
                let target: String
                if initialHasTime, let i = initial {
                    target = "\(cal.component(.hour, from: i))-\(cal.component(.minute, from: i) >= 30 ? 30 : 0)"
                } else if cal.isDateInToday(day) {
                    target = "\(min(23, max(7, cal.component(.hour, from: Date()) + 1)))-0"
                } else {
                    target = "9-0"
                }
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private func timeRow(_ text: String, id: String, selected: Bool, dim: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.hebiuSystem(size: 13, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : dim ? Color.secondary.opacity(0.6) : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .id(id)
    }

    // MARK: - 直接写

    private var typeField: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard").font(.hebiuSystem(size: 11)).foregroundStyle(.secondary)
            TextField("或者直接写：周五下午三点", text: $typed)
                .textFieldStyle(.plain).font(.hebiuSystem(size: 12))
                .onSubmit {
                    if let p = TimeParser.parse(typed), let due = p.due {
                        onPick((due, p.hasTime))
                    } else {
                        typedError = true
                    }
                }
                .onChange(of: typed) { _ in typedError = false }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(typedError ? Theme.overdue.opacity(0.7) : Color.clear))
        .help(typedError ? "没认出来，试试「明天 15:00」「周五下午三点」" : "回车就选好")
    }
}

/// 鼠标移上去淡淡高亮一下
struct HoverRowStyle: ButtonStyle {
    @ObservedObject private var appTypography = TypographySettings.shared
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
    @ObservedObject private var appTypography = TypographySettings.shared
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering || configuration.isPressed ? 0.07 : 0)))
                .onHover { hovering = $0 }
        }
    }
}
