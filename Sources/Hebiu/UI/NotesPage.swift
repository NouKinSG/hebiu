import AppKit
import HebiuKit
import SwiftUI

/// 日常 → 随手记：一行字记下来，按天分组，能搜、能改、能删
struct NotesPage: View {
    @ObservedObject var settings: SettingsModel
    @State private var draft = ""
    @State private var query = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        Page(title: "随手记", subtitle: "想法、地址、书名、灵感，一句话记下来。问\(Her.she)「我之前记的那个…」\(Her.she)会帮你翻") {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil").foregroundStyle(Theme.accent)
                TextField("记点什么…（回车保存，可以加 #标签）", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 15)).lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit(save)
                if !draft.isEmpty { Button("记下", action: save).buttonStyle(.borderedProminent).controlSize(.small) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .stroke(inputFocused ? Theme.accent.opacity(0.7) : Color(nsColor: .separatorColor).opacity(0.6)))

            let all = settings.notes?.notes ?? []
            if !all.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("找一找", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(all.count) 条").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            let shown = query.trimmingCharacters(in: .whitespaces).isEmpty ? all : (settings.notes?.search(query, limit: 200) ?? [])
            if all.isEmpty {
                Text("还没有随手记。终端里也能记：hebiu note 想买的书：《置身事内》").font(.callout).foregroundStyle(.secondary)
            } else if shown.isEmpty {
                Text("没找到").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(groups(shown), id: \.title) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: group.title, trailing: "\(group.notes.count)")
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.notes.enumerated()), id: \.element.id) { i, note in
                                if i > 0 { Divider().padding(.leading, 14) }
                                NoteRow(note: note, settings: settings)
                            }
                        }
                    }
                }
            }
        }
    }

    private func save() {
        guard settings.notes?.add(draft) != nil else { return }
        draft = ""
        settings.objectWillChange.send()
    }

    /// 按天分组：今天、昨天、10月20日……
    private func groups(_ notes: [Note]) -> [(title: String, notes: [Note])] {
        var out: [(String, [Note])] = []
        for n in notes {
            let title = TodoFormat.describe(n.createdAt, hasTime: false)
            if out.last?.0 == title { out[out.count - 1].1.append(n) } else { out.append((title, [n])) }
        }
        return out
    }
}

private struct NoteRow: View {
    let note: Note
    @ObservedObject var settings: SettingsModel
    @State private var editing = false
    @State private var draft = ""
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(time).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .leading).padding(.top, 2)
            if editing {
                TextField("", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...8)
                    .onSubmit(commit)
                Button("好", action: commit).controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if note.source == TodoSource.agent {
                        Text("\(Her.she)帮你记的").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string) } label: {
                        Image(systemName: "doc.on.doc")
                    }.help("复制")
                    Button { draft = note.text; editing = true } label: { Image(systemName: "pencil") }.help("改一下")
                    Button { settings.notes?.delete(note.id); settings.objectWillChange.send() } label: { Image(systemName: "trash") }.help("删掉")
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var time: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: note.createdAt)
    }

    private func commit() {
        settings.notes?.update(note.id, text: draft)
        editing = false
        settings.objectWillChange.send()
    }
}
