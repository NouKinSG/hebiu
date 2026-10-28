import HebiuKit
import SwiftUI

/// 日常 → 习惯：每天打卡、连续天数、最近 7 天
struct HabitsPage: View {
    @ObservedObject var settings: SettingsModel
    @State private var draft = ""
    @State private var hint: String?

    var body: some View {
        Page(title: "习惯", subtitle: "每天坚持的小事。到点没打卡\(Her.she)会提醒你，聊天时说「喝过水了」\(Her.she)也会帮你打卡") {
            let list = settings.habits?.habits ?? []
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "加一个习惯")
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            TextField("比如：喝水 每天晚上9点提醒 / 健身 每周一三五", text: $draft)
                                .textFieldStyle(.plain).onSubmit(add)
                            Button("加上", action: add).controlSize(.small).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        if let hint {
                            Text(hint).font(.caption).foregroundStyle(.secondary)
                        } else if let h = Habit.parse(draft) {
                            Label("\(h.emoji) \(h.title) · \(h.detail)", systemImage: "flame").font(.caption).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            if list.isEmpty {
                Text("还没有习惯。可以从「喝水 每天下午3点提醒」开始～").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(list) { h in
                HabitRow(settings: settings, habit: h)
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if settings.addHabit(text) { draft = ""; hint = nil } else { hint = "没认出来：写个名字，后面可以跟「每天晚上9点」「每周一三五」" }
    }
}

private struct HabitRow: View {
    @ObservedObject var settings: SettingsModel
    let habit: Habit

    var body: some View {
        let store = settings.habits
        let today = MemoryDay.of(Date())
        let scheduled = habit.scheduled(on: today)
        let done = store?.isDone(habit.id, on: today) ?? false
        let streak = store?.streak(habit.id) ?? 0
        Card(padding: 14) {
            HStack(spacing: 14) {
                Button { settings.checkHabit(habit.id) } label: {
                    ZStack {
                        Circle().fill(done ? Theme.accent : Color.secondary.opacity(0.12)).frame(width: 44, height: 44)
                        Text(habit.emoji).font(.system(size: 22)).opacity(done ? 1 : 0.85)
                    }
                }
                .buttonStyle(.plain)
                .help(done ? "取消今天的打卡" : "打卡")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(habit.title).font(.headline)
                        if !scheduled { Text("今天不用").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(habit.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                WeekDots(days: store?.week(habit.id) ?? [])
                VStack(spacing: 0) {
                    Text("\(streak)").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(streak > 0 ? Theme.accent : Color.secondary)
                    Text("连续").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 40)
                Button { settings.deleteHabit(habit.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("删掉这个习惯和打卡记录")
            }
        }
    }
}

/// 最近 7 天的小圆点：实心做了，空心没做，细线那天不用做
struct WeekDots: View {
    let days: [(day: String, done: Bool?)]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.day) { d in
                VStack(spacing: 3) {
                    Group {
                        switch d.done {
                        case true?: Circle().fill(Theme.accent)
                        case false?: Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1.5)
                        case nil: Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 2)
                        }
                    }
                    .frame(width: 10, height: 10)
                    Text(weekday(d.day)).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func weekday(_ day: String) -> String {
        guard let d = MemoryDay.formatter.date(from: day) else { return "" }
        return ["日", "一", "二", "三", "四", "五", "六"][Calendar.current.component(.weekday, from: d.addingTimeInterval(43200)) - 1]
    }
}

/// 主页上今天的习惯：一排胶囊，点一下打卡
struct HabitsTodayCard: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var nav: MainNavigation

    var body: some View {
        let today = settings.habits?.today() ?? []
        if !today.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "今天的习惯", trailing: "\(today.filter(\.done).count) / \(today.count)")
                HStack(spacing: 8) {
                    ForEach(today, id: \.habit.id) { item in
                        Button { settings.checkHabit(item.habit.id) } label: {
                            HStack(spacing: 6) {
                                Text(item.habit.emoji)
                                Text(item.habit.title).font(.callout)
                                if item.done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                            }
                            .foregroundStyle(item.done ? Color.white : Color.primary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(item.done ? Theme.accent : Color(nsColor: .controlBackgroundColor)))
                            .overlay(Capsule().stroke(item.done ? Color.clear : Color(nsColor: .separatorColor).opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { nav.page = .habits } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
        }
    }
}
