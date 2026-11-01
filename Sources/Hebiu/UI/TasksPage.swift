import HebiuKit
import SwiftUI

/// 连接 → 定时让她做：到点了她结合今天的情况去做一件事
struct TasksPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    @ObservedObject var nav: MainNavigation
    @State private var draft = ""
    @State private var hint: String?
    @State private var trying: String?
    @State private var results: [String: String] = [:]
    @State private var tick = 0

    private let examples = ["每天早上8点 用一句话鼓励我", "每周五下午6点 帮我总结这周", "每天晚上11点 催我睡觉，说句晚安",
                            "工作日中午12点 提醒我起来吃饭走走"]

    var body: some View {
        Page(title: "定时让\(Her.she)做", subtitle: "到点了\(Her.she)结合今天的待办、天气、心情去做，说给你听；也可以在聊天里说「每天早上8点…」") {
            if !agent.enabled {
                Card {
                    HStack {
                        Text("要用到 AI 大脑，先去打开。").font(.hebiuStyle(.callout))
                        Spacer()
                        Button("去打开") { nav.page = .brain }.buttonStyle(.borderedProminent)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        TextField("什么时候 + 让\(Her.she)做什么，如：每天早上8点 用一句话鼓励我", text: $draft)
                            .textFieldStyle(.plain).onSubmit(add)
                        Button("加上", action: add).controlSize(.small).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let hint {
                        Text(hint).font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                    } else if let t = ScheduledTask.parse(draft) {
                        Label("\(t.detail) · \(t.prompt)", systemImage: "alarm").font(.hebiuStyle(.caption)).foregroundStyle(Theme.accent)
                    }
                    HStack(spacing: 6) {
                        Text("试试：").font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                        ForEach(examples, id: \.self) { e in
                            Button(e) { draft = e }.buttonStyle(.borderless).font(.hebiuStyle(.caption)).foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            let list = agent.tasks.tasks
            if list.isEmpty {
                Text("还没有定时任务").font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
            }
            ForEach(list) { task in
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "alarm").foregroundStyle(task.enabled ? Theme.accent : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.prompt)
                                Text(task.detail + (task.lastRun.map { " · 上次 \(MonthDay.text($0))" } ?? "")).font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if trying == task.id { ProgressView().controlSize(.small) }
                            Button("现在试一下") { tryNow(task) }.controlSize(.small).disabled(!agent.enabled || trying != nil)
                            Toggle("", isOn: Binding(get: { task.enabled }, set: { agent.tasks.setEnabled(task.id, $0); tick += 1 }))
                                .labelsHidden().toggleStyle(.switch)
                            Button { agent.tasks.delete(task.id); tick += 1 } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                        }
                        if let r = results[task.id] {
                            HStack(alignment: .top, spacing: 10) {
                                PetThumb(frame: "wave", size: 32)
                                Text(r).font(.hebiuStyle(.callout)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                            .padding(.leading, 28)
                        }
                    }
                }
            }
            .id(tick)
        }
    }

    private func add() {
        guard let t = ScheduledTask.parse(draft) else { hint = "没认出几点做：写成「每天早上8点 让\(Her.she)做什么」"; return }
        agent.tasks.add(t)
        draft = ""
        hint = nil
        tick += 1
    }

    private func tryNow(_ task: ScheduledTask) {
        trying = task.id
        agent.runTask(task) { text in
            trying = nil
            results[task.id] = text ?? "没成功（网络或额度），等会儿再试"
        }
    }
}
