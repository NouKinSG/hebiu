import AppKit
import HebiuKit
import SwiftUI


/// 待办窗口的数据：从 TodoCoordinator 读，操作也交给它（打勾会让她 biu 一下）
final class TodoListModel: ObservableObject {
    private let todos: TodoCoordinator
    @Published private(set) var sections = TodoQuery.Sections(today: [], later: [], done: [])
    @Published var draft = ""
    @Published var editing: TodoItem?
    @Published var toast: Toast?
    /// 加一，输入框就拿到焦点（菜单「快速加待办」用）
    @Published var focusTick = 0
    private var toastWork: DispatchWorkItem?

    struct Toast: Equatable {
        let text: String
        let undoID: String?
    }

    init(todos: TodoCoordinator) {
        self.todos = todos
        reload()
    }

    func reload() {
        sections = TodoQuery.sections(todos.store.items)
    }

    /// 点快捷按钮选的时间（选了就不再从文字里认）
    @Published var picked: (date: Date, hasTime: Bool)?
    @Published var pickedRule: RepeatRule?
    /// 文字里认出的时间被你点 × 去掉了：整句当标题
    @Published var ignoreParsed = false

    /// 输入框里那个时间小标签显示什么；没有时间就 nil
    var draftWhen: String? {
        if picked != nil || pickedRule != nil {
            let rule = pickedRule.map(\.display)
            let when = picked.map { TodoFormat.describe($0.date, hasTime: $0.hasTime) }
            return [rule, when].compactMap { $0 }.joined(separator: " · ")
        }
        guard !ignoreParsed, let p = TodoStore.parse(draft), p.due != nil || p.rule != nil else { return nil }
        let rule = p.rule.map { "\($0.display) · 下一次 " } ?? ""
        return rule + (p.due.map { TodoFormat.describe($0, hasTime: p.hasTime) } ?? "")
    }

    /// 时间标签里要不要带重复的小图标
    var draftRepeats: Bool {
        pickedRule != nil || (picked == nil && !ignoreParsed && TodoStore.parse(draft)?.rule != nil)
    }

    /// 时间是从文字里认出来的（不是点按钮选的）
    var whenFromText: Bool { picked == nil && pickedRule == nil && draftWhen != nil }

    func clearWhen() {
        if whenFromText { ignoreParsed = true }
        picked = nil
        pickedRule = nil
    }

    func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if picked != nil || pickedRule != nil || ignoreParsed {
            var due = picked?.date, hasTime = picked?.hasTime ?? false
            // 选的重复和选的日子对不上（比如每周日配上了明天）：第一次排到之后最近对得上的那天
            if let d = due, let rule = pickedRule, !rule.matches(d) {
                let cal = Calendar.current
                due = rule.next(after: cal.startOfDay(for: d), hour: hasTime ? cal.component(.hour, from: d) : nil,
                                minute: cal.component(.minute, from: d)) ?? d
            }
            if due == nil, let rule = pickedRule {
                due = rule.next(after: Calendar.current.startOfDay(for: Date()).addingTimeInterval(-1), hour: nil, minute: 0)
                hasTime = false
            }
            todos.store.add(TodoItem(title: text, due: due, dueHasTime: hasTime, source: TodoSource.manual,
                                     repeatRule: pickedRule?.text))
        } else {
            todos.add(text: text)
        }
        draft = ""
        clearWhen()
        ignoreParsed = false
    }

    func toggle(_ item: TodoItem) {
        todos.toggle(item.id)
        if !item.isDone { show(Toast(text: "已完成「\(item.title)」", undoID: item.id)) }
    }

    func undo(_ id: String) {
        todos.store.uncomplete(id)
        toast = nil
    }

    func delete(_ item: TodoItem) {
        todos.store.delete(item.id)
        show(Toast(text: "已删除「\(item.title)」", undoID: nil))
        lastDeleted = item
    }

    private(set) var lastDeleted: TodoItem?

    func restoreDeleted() {
        guard let item = lastDeleted else { return }
        todos.store.add(item)
        lastDeleted = nil
        toast = nil
    }

    func postpone(_ item: TodoItem, by interval: TimeInterval?) {
        todos.store.update(item.id) {
            if let interval {
                $0.due = max($0.due ?? Date(), Date()).addingTimeInterval(interval)
                $0.dueHasTime = true
            } else {
                // 推到明天：保留原来的钟点
                let cal = Calendar.current
                let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
                if let due = $0.due, $0.dueHasTime {
                    $0.due = cal.date(bySettingHour: cal.component(.hour, from: due), minute: cal.component(.minute, from: due),
                                      second: 0, of: tomorrow)
                } else {
                    $0.due = tomorrow
                    $0.dueHasTime = false
                }
            }
        }
    }

    func save(_ item: TodoItem) {
        todos.store.update(item.id) { $0 = item }
        editing = nil
    }

    func deleteEditing(_ item: TodoItem) {
        editing = nil
        delete(item)
    }

    func open(_ item: TodoItem) {
        guard let link = item.link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    private func show(_ t: Toast) {
        toast = t
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}

// MARK: - 待办页

struct TodoPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: TodoListModel
    @State private var showDone = false

    var body: some View {
        // 每分钟刷新一次，「今天 15:00」「已过期」这些字跟着时间变
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let s = model.sections
            Page(title: "待办", subtitle: subtitle(s, now: context.date)) {
                TodoInput(model: model)

                if s.today.isEmpty && s.later.isEmpty && s.done.isEmpty {
                    EmptyTodos()
                } else {
                    if !s.today.isEmpty || s.later.isEmpty {
                        TodoGroup(title: "今天", items: s.today, model: model, empty: "今天的都做完啦 🎉")
                    }
                    if !s.later.isEmpty {
                        LaterGroup(items: s.later, model: model)
                    }
                    if !s.done.isEmpty {
                        doneSection(s.done)
                    }
                }
            }
        }
    }

    private func subtitle(_ s: TodoQuery.Sections, now: Date) -> String {
        let day = TodoFormat.weekdayDate(now)
        return s.today.isEmpty ? "\(day) · 今天没有要做的" : "\(day) · 今天还有 \(s.today.count) 件"
    }

    private func doneSection(_ done: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showDone.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.hebiuSystem(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showDone ? 90 : 0))
                    Text("已完成 \(done.count)").font(.hebiuSystem(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            if showDone {
                TodoGroup(title: nil, items: done, model: model)
            }
        }
    }
}

/// 加待办的输入框：页面的主角。可以直接写「明天下午三点 xxx」，也可以点下面的快捷按钮选时间
struct TodoInput: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: TodoListModel
    var placeholder = "加一条，比如：明天 10:00 交周报"
    var autoFocus = true
    /// 主页上只在打字时露出快捷按钮，待办页一直显示
    var alwaysShowQuick = true
    @FocusState private var focused: Bool
    @State private var showCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.hebiuSystem(size: 18))
                    .foregroundStyle(Theme.accent)
                TextField(placeholder, text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.hebiuSystem(size: 15))
                    .focused($focused)
                    .onSubmit { model.submit() }
                if let when = model.draftWhen {
                    HStack(spacing: 4) {
                        Image(systemName: model.draftRepeats ? "repeat" : "alarm").font(.hebiuSystem(size: 11, weight: .semibold))
                        Text(when).font(.hebiuSystem(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
                        Button { model.clearWhen() } label: { Image(systemName: "xmark").font(.hebiuSystem(size: 9, weight: .bold)) }
                            .buttonStyle(.plain)
                            .help(model.whenFromText ? "不要这个时间，整句当标题" : "不定时间")
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    .fixedSize()
                }
                if !model.draft.isEmpty {
                    Button("添加") { model.submit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(focused ? Theme.accent.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: focused ? 1.5 : 1))

            if alwaysShowQuick || focused || !model.draft.isEmpty {
                quickRow.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear { if autoFocus { focused = true } }
        .onChange(of: model.focusTick) { _ in focused = true }
    }

    /// 今天 今晚 明天 这周末 下周一 📅 🔁
    private var quickRow: some View {
        HStack(spacing: 6) {
            ForEach(QuickWhen.allCases.filter { $0.available() }) { q in
                let due = q.due()
                ChoiceChip(title: q.title, selected: model.picked.map { $0.date == due.date && $0.hasTime == due.hasTime } ?? false) {
                    model.picked = due
                    focused = true
                }
            }
            ChoiceChip(title: "选日期", icon: "calendar", selected: false) { showCalendar = true }
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                WhenPicker(initial: model.picked?.date, initialHasTime: model.picked?.hasTime ?? false) { picked in
                    model.picked = picked
                    showCalendar = false
                    focused = true
                }
            }
            Menu {
                ForEach(Array(QuickWhen.repeatChoices(for: model.picked?.date).enumerated()), id: \.offset) { _, rule in
                    Button(rule?.display ?? "不重复") { model.pickedRule = rule }
                }
            } label: {
                Label(model.pickedRule?.display ?? "重复", systemImage: "repeat").font(.hebiuSystem(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(model.pickedRule == nil ? Color.secondary.opacity(0.1) : Theme.accent.opacity(0.14)))
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }
}

/// 一个可选的小胶囊：选中时实心粉色
struct ChoiceChip: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let title: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.hebiuSystem(size: 11)) }
                Text(title)
            }
                .font(.hebiuSystem(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .monospacedDigit()
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(selected ? Theme.accent : Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// 几点：全天 09:00 14:00 18:00 20:00，不在里面的钟点单独显示一个，「其他…」打开选时间
struct HourChips: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    /// nil 是全天
    let time: (hour: Int, minute: Int)?
    let onPick: ((hour: Int, minute: Int)?) -> Void
    let onOther: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ChoiceChip(title: "全天", selected: time == nil) { onPick(nil) }
            ForEach(QuickWhen.hours, id: \.hour) { h in
                ChoiceChip(title: String(format: "%02d:%02d", h.hour, h.minute), selected: time.map { $0 == h } ?? false) { onPick(h) }
            }
            if let t = time, !QuickWhen.hours.contains(where: { $0 == t }) {
                ChoiceChip(title: String(format: "%02d:%02d", t.hour, t.minute), selected: true) { onOther() }
            }
            ChoiceChip(title: "其他…", selected: false, action: onOther)
        }
    }
}

/// 以后的待办：按日子分小段（明天、周五、11月6日……），收在一张卡片里
struct LaterGroup: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let items: [TodoItem]
    @ObservedObject var model: TodoListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "以后", trailing: "\(items.count)")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.title) { i, day in
                        if i > 0 { Divider() }
                        Text(day.title).font(.hebiuSystem(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { j, item in
                            if j > 0 { Divider().padding(.leading, 46) }
                            TodoRow(item: item, model: model)
                        }
                    }
                }
            }
        }
    }

    private var days: [(title: String, items: [TodoItem])] {
        var out: [(String, [TodoItem])] = []
        for item in items {
            let title = item.due.map { TodoFormat.describe($0, hasTime: false) } ?? "没有日期"
            if out.last?.0 == title { out[out.count - 1].1.append(item) } else { out.append((title, [item])) }
        }
        return out
    }
}

/// 一组待办，收在一张卡片里
struct TodoGroup: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let title: String?
    let items: [TodoItem]
    @ObservedObject var model: TodoListModel
    var empty: String? = nil
    var limit: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { SectionLabel(text: title, trailing: items.isEmpty ? nil : "\(items.count)") }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if items.isEmpty, let empty {
                        Text(empty).font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    let shown = limit.map { Array(items.prefix($0)) } ?? items
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 46) }
                        TodoRow(item: item, model: model)
                    }
                }
            }
        }
    }
}

struct TodoRow: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let item: TodoItem
    @ObservedObject var model: TodoListModel
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { model.toggle(item) } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.hebiuSystem(size: 18))
                    .foregroundStyle(item.isDone ? Theme.accent : Color.secondary.opacity(0.7))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isDone ? "取消完成" : "完成")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.hebiuSystem(size: 14))
                    .strikethrough(item.isDone, color: .secondary)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(item.title)
                if let detail { Text(detail).font(.hebiuStyle(.caption)).foregroundStyle(.secondary).lineLimit(1) }
            }

            Spacer(minLength: 8)

            if hovering {
                if item.link != nil {
                    iconButton("arrow.up.right.square", "打开链接") { model.open(item) }
                }
                iconButton("pencil", "编辑") { model.editing = item }
                if !item.isDone {
                    Menu {
                        Button("推迟 1 小时") { model.postpone(item, by: 3600) }
                        Button("推迟到明天") { model.postpone(item, by: nil) }
                    } label: { Image(systemName: "clock.arrow.circlepath").font(.hebiuSystem(size: 13)) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .foregroundStyle(.secondary).help("推迟")
                }
                iconButton("trash", "删除") { model.delete(item) }
            }
            if let chip = timeChip { chip }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.editing = item }
        .popover(isPresented: Binding(get: { model.editing?.id == item.id }, set: { if !$0 { model.editing = nil } }),
                 arrowEdge: .trailing) {
            TodoEditor(item: item, onSave: model.save, onCancel: { model.editing = nil }, onDelete: { model.deleteEditing(item) })
        }
        .contextMenu {
            Button("编辑…") { model.editing = item }
            if !item.isDone {
                Button("推迟 1 小时") { model.postpone(item, by: 3600) }
                Button("推迟到明天") { model.postpone(item, by: nil) }
            }
            if item.link != nil { Button("打开链接") { model.open(item) } }
            Divider()
            Button("删除", role: .destructive) { model.delete(item) }
        }
    }

    private func iconButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.hebiuSystem(size: 13)) }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(help)
    }

    /// 第二行：来源、备注
    private var detail: String? {
        var parts: [String] = []
        if item.source != TodoSource.manual && item.source != TodoSource.cli { parts.append(TodoSource.displayName(item.source)) }
        if !item.note.isEmpty { parts.append(item.note) }
        if let doneAt = item.doneAt { parts.append("完成于 " + TodoFormat.describe(doneAt, hasTime: true)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 右边的时间小标签：过期标红，其余粉色
    private var timeChip: AnyView? {
        guard let due = item.due, !item.isDone else { return nil }
        let overdue = TodoQuery.isOverdue(item)
        let color = overdue ? Theme.overdue : Theme.accent
        return AnyView(
            HStack(spacing: 4) {
                if let rule = RepeatRule(item.repeatRule) {
                    Image(systemName: "repeat").font(.hebiuSystem(size: 9, weight: .bold))
                    Text(rule.display + " ·")
                }
                Text((overdue ? "已过 " : "") + TodoFormat.describe(due, hasTime: item.dueHasTime))
            }
                .font(.hebiuSystem(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.12)))
        )
    }
}

private struct EmptyTodos: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    var body: some View {
        VStack(spacing: 10) {
            PetThumb(frame: "chin", size: 120)
            Text("还没有待办").font(.hebiuStyle(.headline))
            Text("在上面写一句，到点了\(Her.she)会喊你").font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct ToastBar: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let toast: TodoListModel.Toast
    @ObservedObject var model: TodoListModel

    var body: some View {
        HStack(spacing: 16) {
            Text(toast.text).font(.hebiuStyle(.callout)).lineLimit(1)
            Button("撤销") {
                if let id = toast.undoID { model.undo(id) } else { model.restoreDeleted() }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.6)))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// 编辑一条（从那一条旁边弹出）：内容、哪天、几点、重复、备注、删除
struct TodoEditor: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @State var item: TodoItem
    let onSave: (TodoItem) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    @State private var day: Date?
    /// nil 是全天
    @State private var time: (hour: Int, minute: Int)?
    @State private var rule: RepeatRule?
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("要做什么", text: $item.title, axis: .vertical)
                .textFieldStyle(.plain).font(.hebiuSystem(size: 15)).lineLimit(1...5)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.6)))

            field("什么时候") {
                HStack(spacing: 6) {
                    ChoiceChip(title: "不提醒", selected: day == nil) { day = nil }
                    ForEach([QuickWhen.today, .tomorrow, .nextMonday]) { q in
                        let d = q.due().date
                        ChoiceChip(title: q.title, selected: day.map { Calendar.current.isDate($0, inSameDayAs: d) } ?? false) { day = d }
                    }
                    ChoiceChip(title: dayIsOther ? TodoFormat.describe(day!, hasTime: false) : "选日期", icon: "calendar", selected: dayIsOther) {
                        showPicker = true
                    }
                    .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                        WhenPicker(initial: pickedDate, initialHasTime: time != nil) { picked in
                            let cal = Calendar.current
                            day = cal.startOfDay(for: picked.date)
                            time = picked.hasTime ? (cal.component(.hour, from: picked.date), cal.component(.minute, from: picked.date)) : nil
                            showPicker = false
                        }
                    }
                }
            }
            if day != nil {
                field("几点") {
                    HourChips(time: time, onPick: { time = $0 }, onOther: { showPicker = true })
                }
            }
            field("重复") {
                Picker("", selection: $rule) {
                    ForEach(Array(repeatChoices.enumerated()), id: \.offset) { _, r in
                        Text(r?.display ?? "不重复").tag(r)
                    }
                }
                .labelsHidden().fixedSize()
            }
            TextField("备注（可以不写）", text: $item.note, axis: .vertical)
                .textFieldStyle(.plain).font(.hebiuStyle(.callout)).lineLimit(1...4)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            if item.source != TodoSource.manual && item.source != TodoSource.cli && item.source != TodoSource.agent {
                Text("这条是\(TodoSource.displayName(item.source))同步来的，在那边改了会覆盖这里").font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
            }
            HStack {
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(Theme.overdue)
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 400)
        .tint(Theme.accent)
        .onAppear(perform: load)
    }

    /// 现在选的日子和钟点合成一个时间（给选时间的弹窗定位用）
    private var pickedDate: Date? {
        guard let day else { return nil }
        return QuickWhen.set(day, hour: time?.hour, minute: time?.minute ?? 0).date
    }

    /// 能选的重复；已经设了的规则就算和选的日子对不上也留在里面
    private var repeatChoices: [RepeatRule?] {
        var list = QuickWhen.repeatChoices(for: day)
        if let rule, !list.contains(rule) { list.append(rule) }
        return list
    }

    /// 选的日子不是快捷按钮里那几天
    private var dayIsOther: Bool {
        guard let day else { return false }
        return ![QuickWhen.today, .tomorrow, .nextMonday].contains { Calendar.current.isDate($0.due().date, inSameDayAs: day) }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
            content()
        }
    }

    private func load() {
        let cal = Calendar.current
        day = item.due.map { cal.startOfDay(for: $0) }
        rule = RepeatRule(item.repeatRule)
        guard let due = item.due, item.dueHasTime else { return }
        time = (cal.component(.hour, from: due), cal.component(.minute, from: due))
    }

    private func save() {
        var out = item
        out.title = out.title.trimmingCharacters(in: .whitespacesAndNewlines)
        out.note = out.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = Calendar.current
        if var day {
            // 选了每周几、每月几号但日子对不上：从这天往后找第一次
            if let rule, !rule.matches(day) { day = rule.next(after: day, hour: nil, minute: 0) ?? day }
            let picked = QuickWhen.set(day, hour: time?.hour, minute: time?.minute ?? 0)
            out.due = picked.date
            out.dueHasTime = picked.hasTime
        } else if let rule {
            out.due = rule.next(after: cal.startOfDay(for: Date()).addingTimeInterval(-1), hour: nil, minute: 0)
            out.dueHasTime = false
        } else {
            out.due = nil
            out.dueHasTime = false
        }
        out.repeatRule = rule?.text
        onSave(out)
    }
}
