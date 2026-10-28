import HebiuKit
import SwiftUI

/// 她 → 她记得的事：对你的了解、日记、周记月记；都能改、能删
struct MemoryPage: View {
    @ObservedObject var agent: AgentController
    @ObservedObject var settings: SettingsModel
    @ObservedObject var nav: MainNavigation
    @State private var newFact = ""
    @State private var showAllDiaries = false

    var body: some View {
        Page(title: "\(Her.she)记得的事", subtitle: "\(Her.she)每晚写日记，慢慢记下对你的了解。不对的可以改，删掉的\(Her.she)就真的忘了") {
            if !agent.enabled {
                Card {
                    HStack {
                        Text("记忆要用到 AI 大脑，先在「连接 → AI 大脑」里打开。").font(.callout)
                        Spacer()
                        Button("去打开") { nav.page = .brain }.buttonStyle(.borderedProminent)
                    }
                }
            }

            group("开关") {
                SettingRow(title: "\(Her.she)记住你", detail: "每晚回顾当天的聊天，写一篇日记，更新对你的了解；聊天时会带上这些。关掉后不再整理，也不再带上，已记下的保留") {
                    Toggle("", isOn: $settings.agentMemory).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "日记里带上你写代码的时间", detail: "只用 Claude 钩子记下的时间和次数（几点到几点、干完几次活），不含项目和内容", sub: true) {
                    Toggle("", isOn: $settings.agentActivity).labelsHidden().toggleStyle(.switch)
                }
                .disabled(!settings.agentMemory)
                Divider()
                HStack(spacing: 8) {
                    if agent.consolidating { ProgressView().controlSize(.small) }
                    Text(agent.consolidating ? "\(Her.she)在翻今天的事…" : agent.memoryMessage ?? "每天凌晨 4 点后整理前一天；电脑没开就在下次打开时补上")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("写今天的日记") { agent.writeTodayDiary() }
                        .controlSize(.small).disabled(agent.consolidating || !agent.memoryOn)
                    Button("补整理") { agent.consolidateIfNeeded() }
                        .controlSize(.small).disabled(agent.consolidating || !agent.memoryOn)
                }
            }

            group("对你的了解", trailing: "\(agent.facts.count) / \(AgentMemory.maxFacts)") {
                if agent.facts.isEmpty {
                    Text("还没有。多和\(Her.she)聊聊，或者直接告诉\(Her.she)「记住，我……」").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(agent.facts.enumerated()), id: \.element) { i, fact in
                    if i > 0 { Divider() }
                    FactRow(fact: fact, onSave: { agent.updateFact(fact, to: $0) }, onDelete: { agent.forgetFact(fact) })
                }
                Divider()
                HStack(spacing: 8) {
                    TextField("告诉\(Her.she)一件事，比如：不吃香菜", text: $newFact)
                        .textFieldStyle(.plain)
                        .onSubmit(add)
                    Button("记下", action: add).controlSize(.small).disabled(newFact.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !agent.summaries.isEmpty {
                group("周记和月记") {
                    ForEach(Array(agent.summaries.enumerated()), id: \.element.id) { i, entry in
                        if i > 0 { Divider() }
                        EntryRow(entry: entry) { agent.deleteEntry(entry) }
                    }
                }
            }

            group("日记", trailing: agent.diaries.isEmpty ? nil : "\(agent.diaries.count) 篇") {
                if agent.diaries.isEmpty {
                    Text("还没有日记。今晚过后\(Her.she)会写第一篇，也可以点上面的「写今天的日记」先看看").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let shown = showAllDiaries ? agent.diaries : Array(agent.diaries.prefix(14))
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, entry in
                    if i > 0 { Divider() }
                    EntryRow(entry: entry) { agent.deleteEntry(entry) }
                }
                if agent.diaries.count > 14 && !showAllDiaries {
                    Divider()
                    Button("显示全部 \(agent.diaries.count) 篇") { showAllDiaries = true }.buttonStyle(.link)
                }
            }

            Text("都存在 ~/.hebiu/agent/memory/，聊天时只带上「了解」和最近几天的日记").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { agent.reloadMemory() }
    }

    private func add() {
        let text = newFact.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        agent.addFact(text)
        newFact = ""
    }

    private func group<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title, trailing: trailing)
            Card { VStack(spacing: 10) { content() } }
        }
    }
}

private struct FactRow: View {
    let fact: String
    let onSave: (String) -> Void
    let onDelete: () -> Void
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 10) {
            if editing {
                TextField("", text: $draft).textFieldStyle(.roundedBorder)
                    .onSubmit { onSave(draft); editing = false }
                Button("好") { onSave(draft); editing = false }.controlSize(.small)
            } else {
                Text(fact).frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { draft = fact; editing = true }
                Button { draft = fact; editing = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help("改一下")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("让\(Her.she)忘掉")
            }
        }
    }
}

private struct EntryRow: View {
    let entry: AgentMemory.Entry
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                .monospacedDigit().frame(width: 84, alignment: .leading)
            Text(entry.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("删掉这篇")
        }
    }

    private var label: String {
        switch entry.kind {
        case .diary:
            let parts = entry.key.split(separator: "-")
            return parts.count == 3 ? "\(Int(parts[1]) ?? 0) 月 \(Int(parts[2]) ?? 0) 日" : entry.key
        case .weekly: return "第 \(Int(entry.key.suffix(2)) ?? 0) 周"
        case .monthly:
            let parts = entry.key.split(separator: "-")
            return parts.count == 2 ? "\(parts[0]) 年 \(Int(parts[1]) ?? 0) 月" : entry.key
        }
    }
}
