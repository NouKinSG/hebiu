import HebiuKit
import SwiftUI

/// 主页：打开就看到今天——她、在一起第几天、下一个提醒、今天的待办
struct HomePage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var todos: TodoListModel
    @ObservedObject var settings: SettingsModel
    @ObservedObject var nav: MainNavigation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let s = todos.sections
            Page(title: greeting(now), subtitle: TodoFormat.weekdayDate(now)) {
                hero(now: now, today: s.today)
                FocusCard(settings: settings, nav: nav)
                HabitsTodayCard(settings: settings, nav: nav)
                MoodCard(settings: settings)
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "今天的小记录")
                    StatsTiles(day: settings.statsToday(now))
                }
                TodoInput(model: todos, placeholder: "加一条待办…", autoFocus: false, alwaysShowQuick: false)
                TodoGroup(title: "今天", items: s.today, model: todos, empty: "今天没有要做的，轻松一下～", limit: 6)
                if s.today.count > 6 || !s.later.isEmpty {
                    Button {
                        nav.page = .todos
                    } label: {
                        HStack(spacing: 4) {
                            Text(s.later.isEmpty ? "查看全部待办" : "查看全部待办（以后还有 \(s.later.count) 件）")
                            Image(systemName: "chevron.right").font(.hebiuSystem(size: 10, weight: .semibold))
                        }
                        .font(.hebiuStyle(.callout))
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                }
                statusRow(now: now)
            }
        }
    }

    private func greeting(_ now: Date) -> String {
        switch Calendar.current.component(.hour, from: now) {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了，早点睡"
        }
    }

    /// 顶部大卡片：她 + 在一起第几天 + 下一个提醒
    private func hero(now: Date, today: [TodoItem]) -> some View {
        let next = TodoQuery.sorted(todos.sections.today + todos.sections.later)
            .first { $0.dueHasTime && ($0.due ?? .distantPast) > now }
        return Card(padding: 18) {
            HStack(spacing: 18) {
                PetThumb(frame: "wave", size: 108)
                VStack(alignment: .leading, spacing: 10) {
                    if let days = settings.daysTogether {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("在一起第").foregroundStyle(.secondary)
                            Text("\(days)").font(.hebiuSystem(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.accent).monospacedDigit()
                            Text("天").foregroundStyle(.secondary)
                        }
                    } else {
                        Button { nav.page = .us } label: {
                            Label("填上在一起的日子", systemImage: "heart").foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .font(.hebiuSystem(size: 15, weight: .semibold))
                    }
                    if let w = settings.weather {
                        Label(w.line + (w.advice.first.map { " · " + $0 } ?? ""), systemImage: "cloud.sun")
                            .font(.hebiuStyle(.callout)).lineLimit(1)
                    }
                    if let soon = settings.allDates.first(where: { $0.days <= 30 }) {
                        Label(soon.days == 0 ? "今天是\(soon.date.title)" : "距离\(soon.date.title)还有 \(soon.days) 天", systemImage: "calendar")
                            .font(.hebiuStyle(.callout)).foregroundStyle(soon.days <= 7 ? Theme.accent : Color.primary).lineLimit(1)
                    }
                    if let next, let due = next.due {
                        Label("下一个提醒：\(TodoFormat.describe(due, hasTime: true)) \(next.title)", systemImage: "alarm")
                            .font(.hebiuStyle(.callout)).lineLimit(1)
                    } else {
                        Label(today.isEmpty ? "今天没有待办" : "今天还有 \(today.count) 件事，没有定时的", systemImage: "alarm")
                            .font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// 底部一排小状态：勿扰、Claude、数据来源，点了去对应的页
    private func statusRow(now: Date) -> some View {
        let last = settings.claudeActivity.values.max()
        let sourcesOn = settings.sourceMinutes.values.filter { $0 > 0 }.count
        return HStack(spacing: 10) {
            chip(icon: settings.quiet ? "moon.fill" : "moon", text: settings.quiet ? "勿扰中" : "勿扰：关",
                 active: settings.quiet) { settings.quiet.toggle() }
            chip(icon: "sparkles", text: settings.claudeSummary.map { "Claude：" + $0 }
                    ?? last.map { now.timeIntervalSince($0) < 120 ? "Claude 干活中" : "Claude 已连上" } ?? "Claude 未连上",
                 active: last != nil) { nav.page = .claude }
            chip(icon: "tray.and.arrow.down", text: sourcesOn > 0 ? "\(sourcesOn) 个数据来源" : "数据来源：未打开",
                 active: sourcesOn > 0) { nav.page = .sources }
            Spacer()
        }
    }

    private func chip(icon: String, text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.hebiuStyle(.caption))
                .foregroundStyle(active ? Theme.accent : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill((active ? Theme.accent : Color.secondary).opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// 一排小数字：摸了她几下、陪你干完几次活……主页显示今天的，「我们」页显示一共的
struct StatsTiles: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let day: Stats.Day

    private static let items: [(Stats.Counter, String, String)] = [
        (.taps, "摸了\(Her.she)", "下"),
        (.claudeDone, "陪你干完", "次活"),
        (.todosDone, "完成待办", "件"),
        (.focus, "专心", "个番茄"),
        (.chats, "跟\(Her.she)说了", "句"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(StatsTiles.items, id: \.0) { counter, title, unit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(day[counter] ?? 0)").font(.hebiuSystem(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle((day[counter] ?? 0) > 0 ? Theme.accent : Color.secondary).monospacedDigit()
                        Text(unit).font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.radius - 4).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius - 4).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
            }
        }
    }
}

/// 番茄钟卡片：没开时一个按钮；专心中显示倒计时和进度；休息中显示还能歇多久
struct FocusCard: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var settings: SettingsModel
    @ObservedObject var nav: MainNavigation
    var body: some View {
        if let focus = settings.focus {
            IntegratedFocusCard(focus: focus, open: { nav.page = .focus })
        }
    }
}

/// 今天的心情：五个表情点一个
struct MoodCard: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var settings: SettingsModel

    var body: some View {
        let today = settings.moods?.today()
        Card(padding: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天心情").font(.hebiuStyle(.headline))
                    Text(today.map { $0.note.isEmpty ? $0.name : "\($0.name) · \($0.note)" } ?? "点一个，\(Her.she)会记进日记")
                        .font(.hebiuStyle(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                ForEach(Mood.levels, id: \.score) { level in
                    let picked = today?.score == level.score
                    Button { settings.logMood(level.score) } label: {
                        Text(level.emoji).font(.hebiuSystem(size: picked ? 26 : 22))
                            .opacity(today == nil || picked ? 1 : 0.35)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(picked ? Theme.accent.opacity(0.18) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(level.name)
                }
            }
        }
    }
}
