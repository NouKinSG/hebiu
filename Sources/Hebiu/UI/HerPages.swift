import HebiuKit
import SwiftUI

/// 动作库：缩略图 + 名字 + 什么时候出现，点一下她就做
struct ActionsPage: View {
    @ObservedObject var model: SettingsModel
    @State private var played: String?
    @State private var editing: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        Page(title: "动作", subtitle: "点一下，\(Her.she)就做给你看；鼠标移上去点铅笔能改", trailing: Character.isEdited ? AnyView(
            Button("恢复成自带的") { Character.resetToBundled(); model.characterChanged() }.controlSize(.small)
        ) : nil) {
            ForEach(ActionCatalog.groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: group.title)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.actions) { action in
                            ActionTile(action: action, highlighted: played == action.event, onEdit: { editing = action.event }) {
                                model.tryOut(action.event)
                                played = action.event
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    if played == action.event { played = nil }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: Binding(get: { editing.map(EditingAction.init) }, set: { editing = $0?.id })) { e in
            ActionEditor(event: e.id, model: model) { editing = nil }
        }
    }
}

private struct EditingAction: Identifiable {
    let id: String
}

private struct ActionTile: View {
    let action: ActionCatalog.Action
    let highlighted: Bool
    let onEdit: () -> Void
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                PetThumb(frame: action.thumb, size: 76)
                    .padding(.top, 6)
                Text(action.title).font(.system(size: 13, weight: .semibold))
                Text(action.when).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(highlighted || hovering ? Theme.accent.opacity(highlighted ? 0.9 : 0.5) : Color(nsColor: .separatorColor).opacity(0.6),
                        lineWidth: highlighted ? 2 : 1))
            .scaleEffect(highlighted ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: highlighted)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(Circle().stroke(Color(nsColor: .separatorColor)))
                }
                .buttonStyle(.plain).padding(8).help("改这个动作")
            }
        }
        .onHover { hovering = $0 }
        .help("让\(Her.she)\(action.title)")
    }
}

/// 台词：左边选事件，右边一行一句
struct LinesPage: View {
    @ObservedObject var model: SettingsModel
    @State private var selected = "hello"

    var body: some View {
        Page(title: "台词", subtitle: "每个动作说什么。一行一句，触发时随机挑一句") {
            HStack(alignment: .top, spacing: 16) {
                Card(padding: 6) {
                    VStack(spacing: 2) {
                        ForEach(lineEvents, id: \.key) { e in
                            Button { selected = e.key } label: {
                                Text(e.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 7)
                                        .fill(selected == e.key ? Theme.accent.opacity(0.16) : .clear))
                                    .foregroundStyle(selected == e.key ? Theme.accent : Color.primary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 150)

                if let e = lineEvents.first(where: { $0.key == selected }) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.name).font(.title3.weight(.semibold))
                            Text(e.when).font(.callout).foregroundStyle(.secondary)
                        }
                        TextEditor(text: Binding(get: { model.lines[e.key] ?? "" }, set: { model.lines[e.key] = $0 }))
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 220)
                            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
                        Text(e.key == "together" ? "{days} 会换成在一起的天数。全删空就用默认台词。" : "全删空就用默认台词。改完自动保存。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("恢复默认") { model.resetLines(e.key) }
                            Spacer()
                            Button("试一下") { model.tryOut(e.key) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }
}

/// 我们：在一起第几天、纪念日、生日
struct UsPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Page(title: "我们", subtitle: "纪念日和生日那天，\(Her.she)会冒爱心提醒你") {
            Card(padding: 20) {
                HStack(spacing: 18) {
                    PetThumb(frame: "heart", size: 96)
                    if let days = model.daysTogether {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("在一起").font(.callout).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("第").foregroundStyle(.secondary)
                                Text("\(days)").font(.system(size: 48, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.accent).monospacedDigit()
                                Text("天").foregroundStyle(.secondary)
                            }
                            if let next = nextHundred(days) { Text(next).font(.caption).foregroundStyle(.secondary) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("还没填在一起的日子").font(.headline)
                            Text("在下面填上，这里会显示第几天").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "一起的小记录", trailing: model.statsFirstDay.map { "从 \(MonthDay.text($0)) 开始记" })
                StatsTiles(day: model.statsTotal)
            }

            DatesSection(model: model)

            Card {
                VStack(spacing: 12) {
                    SettingRow(title: "在一起的日子", detail: "每年这一天、每满 100 天提醒") {
                        Toggle("", isOn: $model.hasTogether).labelsHidden().toggleStyle(.switch)
                    }
                    if model.hasTogether {
                        Divider()
                        SettingRow(title: "日期") {
                            DatePicker("", selection: $model.together, in: ...Date(), displayedComponents: .date).labelsHidden()
                        }
                    }
                }
            }

            Card {
                VStack(spacing: 12) {
                    SettingRow(title: "我们的合照", detail: model.photos.isEmpty
                               ? "选一个放合照的文件夹（含子文件夹）。点\(Her.she)偶尔弹一张，纪念日和生日一定弹；照片只在本机看，不发给 AI"
                               : "\(model.photos) · \(model.photoCount) 张") {
                        HStack {
                            if !model.photos.isEmpty {
                                Button("看一张") { model.showPhoto() }.disabled(model.photoCount == 0)
                                Button("不用了") { model.photos = "" }
                            }
                            Button(model.photos.isEmpty ? "选文件夹…" : "换一个…") { choosePhotos() }
                        }
                    }
                }
            }

            Card {
                VStack(spacing: 12) {
                    SettingRow(title: "\(Her.she)的生日", detail: "当天欢呼、冒爱心") {
                        Toggle("", isOn: $model.hasBirthday).labelsHidden().toggleStyle(.switch)
                    }
                    if model.hasBirthday {
                        Divider()
                        SettingRow(title: "日期") {
                            HStack(spacing: 6) {
                                Picker("", selection: $model.birthdayMonth) {
                                    ForEach(1...12, id: \.self) { Text("\($0) 月").tag($0) }
                                }.labelsHidden().frame(width: 80)
                                Picker("", selection: $model.birthdayDay) {
                                    ForEach(1...31, id: \.self) { Text("\($0) 日").tag($0) }
                                }.labelsHidden().frame(width: 80)
                            }
                        }
                    }
                }
            }
        }
    }

    private func choosePhotos() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "就用这个"
        panel.message = "选一个放你们合照的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.photos = (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// 「再过 12 天就满 200 天」
    private func nextHundred(_ days: Int) -> String? {
        let next = (days / 100 + 1) * 100
        let left = next - days
        return left <= 30 ? "再过 \(left) 天就满 \(next) 天" : nil
    }
}

enum MonthDay {
    /// 2026-10-25 → 10 月 25 日
    static func text(_ day: String) -> String {
        let p = day.split(separator: "-")
        return p.count == 3 ? "\(Int(p[1]) ?? 0) 月 \(Int(p[2]) ?? 0) 日" : day
    }
}

/// 重要日子：倒数、提前提醒；一行字加一个，支持农历
struct DatesSection: View {
    @ObservedObject var model: SettingsModel
    @State private var draft = ""
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "重要日子", trailing: "提前 7 天、1 天和当天提醒")
            Card {
                VStack(spacing: 10) {
                    let list = model.allDates
                    if list.isEmpty {
                        Text("还没有。比如加上「妈妈生日 农历八月十五」「第一次约会 2024年5月20日」")
                            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(list.enumerated()), id: \.element.date.id) { i, item in
                        if i > 0 { Divider() }
                        DateRow(date: item.date, days: item.days) { model.deleteDate(item.date.id) }
                    }
                    Divider()
                    HStack(spacing: 8) {
                        TextField("加一个：名字 + 日期，如 妈妈生日 农历八月十五", text: $draft)
                            .textFieldStyle(.plain)
                            .onSubmit(add)
                        Button("加上", action: add).controlSize(.small).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let hint {
                        Text(hint).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else if let p = ImportantDate.parse(draft) {
                        Label("\(p.title) · \(p.dateText)" + (p.daysUntil(from: Date()).map { $0 == 0 ? " · 就是今天" : " · 还有 \($0) 天" } ?? ""),
                              systemImage: "calendar").font(.caption).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if model.addDate(text) { draft = ""; hint = nil } else { hint = "没认出来：要写名字和日期，如「妈妈生日 3月8日」或「妈妈生日 农历八月十五」" }
    }
}

private struct DateRow: View {
    let date: ImportantDate
    let days: Int
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if days == 0 {
                Text("就是今天").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("还有").font(.caption).foregroundStyle(.secondary)
                    Text("\(days)").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(days <= 7 ? Theme.accent : Color.primary)
                    Text("天").font(.caption).foregroundStyle(.secondary)
                }
            }
            if date.isBuiltIn {
                Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(.tertiary).help("在上面「在一起的日子」「\(Her.she)的生日」里改")
            } else {
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        var parts = [date.dateText]
        if let next = date.next(from: Date()) {
            if date.lunar { parts.append("下一次是 \(TodoFormat.describe(next, hasTime: false))") }
            if let years = date.yearsAt(next), years > 0 { parts.append("第 \(years) 年") }
        }
        return parts.joined(separator: " · ")
    }
}
