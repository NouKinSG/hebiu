import HebiuKit
import SwiftUI

/// 编辑一个动作：先做哪几下、最后停在哪一帧、停多久、说哪组台词、点她时出现得多不多；「试一下」马上演
struct ActionEditor: View {
    let event: String
    @ObservedObject var model: SettingsModel
    let onClose: () -> Void

    @State private var action: CharacterPack.Action
    @State private var title: String
    @State private var when: String
    @State private var weight: Int
    @State private var holdForever: Bool
    @State private var saveError: String?

    static let effects: [(String?, String)] = [(nil, "无"), ("pop", "弹一下"), ("kick", "后坐力"), ("squish", "往下缩"), ("sway", "左右摇")]

    init(event: String, model: SettingsModel, onClose: @escaping () -> Void) {
        self.event = event
        self.model = model
        self.onClose = onClose
        let pack = Character.pack
        let a = pack.actions[event] ?? CharacterPack.Action(hold: pack.idle.frame, holdSeconds: 2)
        let item = pack.catalog.flatMap(\.items).first { $0.action == event }
        _action = State(initialValue: a)
        _title = State(initialValue: item?.title ?? event)
        _when = State(initialValue: item?.when ?? "")
        _weight = State(initialValue: pack.taps.first { $0.action == event }?.weight ?? 0)
        _holdForever = State(initialValue: a.holdSeconds == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                PetThumb(frame: action.hold, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("名字", text: $title).textFieldStyle(.plain).font(.system(size: 20, weight: .bold))
                    TextField("什么时候出现，比如：点\(Her.she)", text: $when).textFieldStyle(.plain).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(event).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("先做这几下", detail: "按顺序播，每一下停多久；可以一下都没有") {
                        ForEach(Array(action.steps.enumerated()), id: \.offset) { i, _ in
                            StepRow(step: $action.steps[i], onRemove: { action.steps.remove(at: i) },
                                    onUp: i > 0 ? { action.steps.swapAt(i, i - 1) } : nil)
                        }
                        Button { action.steps.append(.init(frame: action.hold, seconds: 0.6)) } label: {
                            Label("加一下", systemImage: "plus")
                        }.buttonStyle(.borderless).foregroundStyle(Theme.accent)
                    }

                    section("最后停在", detail: holdForever ? "一直停到下一个动作" : "停一会儿，然后回到平时的样子") {
                        HStack(spacing: 12) {
                            FramePicker(frame: $action.hold)
                            Toggle("一直停着", isOn: $holdForever).toggleStyle(.checkbox)
                            if !holdForever {
                                SecondsField(seconds: Binding(get: { action.holdSeconds ?? 2 }, set: { action.holdSeconds = $0 }), range: 0.5...60)
                            }
                            EffectPicker(effect: $action.holdEffect)
                            Spacer()
                        }
                    }

                    if !action.loop.isEmpty {
                        section("停住后循环播", detail: "比如敲键盘：这几下一直循环，直到下一个动作") {
                            ForEach(Array(action.loop.enumerated()), id: \.offset) { i, _ in
                                StepRow(step: $action.loop[i], onRemove: { action.loop.remove(at: i) }, onUp: nil)
                            }
                        }
                    }

                    section("说什么", detail: "台词在「台词」页改") {
                        Picker("", selection: $action.line) {
                            Text("不说话").tag(String?.none)
                            ForEach(lineKeys, id: \.self) { k in
                                Text(lineEvents.first { $0.key == k }.map { "\($0.name)（\(k)）" } ?? k).tag(String?.some(k))
                            }
                        }
                        .labelsHidden().fixedSize()
                    }

                    section("点\(Her.she)时出现", detail: weight == 0 ? "不会随机出现" : "数字越大越常出现；现在所有反应加起来是 \(totalWeight)") {
                        HStack {
                            Slider(value: Binding(get: { Double(weight) }, set: { weight = Int($0.rounded()) }), in: 0...30)
                                .frame(width: 260)
                            Text(weight == 0 ? "不出现" : "\(weight)").monospacedDigit().foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 440)

            if let saveError { Text(saveError).font(.caption).foregroundStyle(Theme.overdue) }
            HStack {
                Button { model.previewAction(edited) } label: { Label("试一下", systemImage: "play.fill") }
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 640)
        .tint(Theme.accent)
    }

    private var edited: CharacterPack.Action {
        var a = action
        if holdForever { a.holdSeconds = nil }
        return a
    }

    private var lineKeys: [String] { Character.pack.lines.keys.sorted() }

    private var totalWeight: Int {
        Character.pack.taps.filter { $0.action != event }.reduce(weight) { $0 + $1.weight }
    }

    private func save() {
        var pack = Character.pack
        pack.actions[event] = edited
        // 动作页上的名字和说明
        if let g = pack.catalog.firstIndex(where: { $0.items.contains { $0.action == event } }),
           let i = pack.catalog[g].items.firstIndex(where: { $0.action == event }) {
            pack.catalog[g].items[i].title = title
            pack.catalog[g].items[i].when = when
            pack.catalog[g].items[i].thumb = edited.hold
        }
        // 点她时的概率
        pack.taps.removeAll { $0.action == event }
        if weight > 0 { pack.taps.append(.init(action: event, weight: weight)) }
        do {
            try Character.save(pack)
            model.characterChanged()
            onClose()
        } catch {
            saveError = "没存上：\(error.localizedDescription)"
        }
    }

    private func section<Content: View>(_ title: String, detail: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
    }
}

private struct StepRow: View {
    @Binding var step: CharacterPack.Step
    let onRemove: () -> Void
    let onUp: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            FramePicker(frame: $step.frame)
            SecondsField(seconds: $step.seconds, range: 0.05...10)
            EffectPicker(effect: $step.effect)
            Spacer()
            if let onUp { Button(action: onUp) { Image(systemName: "arrow.up") }.buttonStyle(.borderless).help("往前挪") }
            Button(action: onRemove) { Image(systemName: "minus.circle") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("去掉这一下")
        }
    }
}

/// 选一帧：点开是这个形象所有帧的缩略图
struct FramePicker: View {
    @Binding var frame: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                PetThumb(frame: frame, size: 38)
                Text(frame).font(.callout.monospaced()).foregroundStyle(.primary)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 8), count: 6), spacing: 8) {
                    ForEach(Character.frameNames, id: \.self) { name in
                        Button { frame = name; open = false } label: {
                            VStack(spacing: 2) {
                                PetThumb(frame: name, size: 60)
                                Text(name).font(.system(size: 10).monospaced()).lineLimit(1)
                            }
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8).fill(name == frame ? Theme.accent.opacity(0.2) : Color.clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .frame(width: 540, height: 360)
        }
    }
}

private struct SecondsField: View {
    @Binding var seconds: Double
    let range: ClosedRange<Double>

    var body: some View {
        Stepper(value: $seconds, in: range, step: seconds < 1 ? 0.05 : 0.5) {
            Text(String(format: "%.2g 秒", seconds)).monospacedDigit().frame(width: 58, alignment: .trailing)
        }
        .fixedSize()
    }
}

private struct EffectPicker: View {
    @Binding var effect: String?

    var body: some View {
        Picker("", selection: $effect) {
            ForEach(ActionEditor.effects, id: \.1) { e in Text(e.1).tag(e.0) }
        }
        .labelsHidden().fixedSize()
        .help("换到这一帧时的小效果")
    }
}
