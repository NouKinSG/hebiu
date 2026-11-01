import AppKit
import HebiuKit
import SwiftUI

/// 数据来源：每个来源一张卡，开关、同步间隔、上次结果
struct SourcesPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: SettingsModel

    var body: some View {
        Page(title: "数据来源", subtitle: "把外面的事情自动变成待办。都只读，数据只存在这台电脑上") {
            ForEach(model.sources, id: \.name) { source in
                SourceCard(model: model, source: source)
            }
            .id(model.sourceTick)
            Text("自己写来源：任何语言写个脚本放进 ~/.hebiu/sources/，打印 JSON 就行，写法见项目里的 docs/SOURCES.md。关掉一个来源时，它带进来、还没完成的待办会一起清掉。")
                .font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

private struct SourceCard: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: SettingsModel
    let source: (name: String, title: String, detail: String, installed: Bool)

    private var icon: String {
        ["calendar": "calendar", "reminders": "checklist", "gitlab-review": "arrow.triangle.pull"][source.name] ?? "terminal"
    }

    var body: some View {
        let minutes = model.sourceMinutes[source.name] ?? 0
        let status = model.status(source.name)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.hebiuSystem(size: 16, weight: .medium))
                        .foregroundStyle(minutes > 0 ? Theme.accent : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill((minutes > 0 ? Theme.accent : Color.secondary).opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title).font(.hebiuSystem(size: 14, weight: .semibold))
                        Text(source.installed ? source.detail : "脚本没装：在项目目录运行 make install 会装上")
                            .font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { minutes > 0 }, set: { model.setSource(source.name, on: $0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(!source.installed && minutes == 0)
                }
                if minutes > 0 {
                    Divider()
                    HStack(spacing: 10) {
                        Circle().fill(status.error == nil ? Color.green : Theme.overdue).frame(width: 7, height: 7)
                        Text(statusText(status)).font(.hebiuStyle(.caption))
                            .foregroundStyle(status.error == nil ? Color.secondary : Theme.overdue).lineLimit(2)
                        Spacer()
                        Stepper("每 \(minutes) 分钟", value: Binding(get: { minutes }, set: { model.sourceMinutes[source.name] = max(1, $0) }),
                                in: 1...240, step: minutes < 10 ? 1 : 5)
                            .font(.hebiuStyle(.caption))
                            .fixedSize()
                        Button(status.running ? "同步中…" : "立即同步") { model.sync(source.name) }
                            .controlSize(.small)
                            .disabled(status.running)
                    }
                }
            }
        }
    }

    private func statusText(_ s: SourceScheduler.Status) -> String {
        if let error = s.error { return "上次失败：\(error)" }
        guard let last = s.lastRun else { return "还没同步过" }
        return "\(TodoFormat.describe(last, hasTime: true)) 同步，\(s.count) 条"
    }
}

/// Claude Code：钩子接没接上、每种事件最近一次是什么时候
struct ClaudePage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var model: SettingsModel
    @State private var copied = false

    /// 各家的哪个事件触发哪个动作（和 scripts/install-hooks.sh 一致）
    private let hooks: [(claude: String, codex: String?, event: String)] = [
        ("SessionStart", "SessionStart", "hello"),
        ("UserPromptSubmit", "UserPromptSubmit", "working"),
        ("Notification", "PermissionRequest", "wait"),
        ("Stop", "Stop", "done"),
        ("PostToolUseFailure / StopFailure", nil, "error"),
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Page(title: "Claude Code / Codex", subtitle: "Claude Code 或 Codex 干活时，\(Her.she)跟着做动作") {
                let activity = model.claudeActivity
                let last = activity.values.max()
                Card(padding: 18) {
                    HStack(spacing: 14) {
                        PetThumb(frame: last.map { context.date.timeIntervalSince($0) < 120 } == true ? "type" : "idle", size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(last == nil ? "还没收到过 Claude Code / Codex 的动静" : "已连上").font(.hebiuStyle(.headline))
                            Text(last.map { "最近一次：\(ago($0, now: context.date))" } ?? "装好钩子后，新开一个 Claude Code 或 Codex 会话就会有反应")
                                .font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                SectionLabel(text: "\(Her.she)怎么跟着它们")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(hooks.enumerated()), id: \.offset) { index, h in
                            if index > 0 { Divider().padding(.leading, 16) }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Character.title(of: h.event)).font(.hebiuSystem(size: 13, weight: .medium))
                                    Text("Claude：\(h.claude)" + (h.codex.map { "　Codex：\($0)" } ?? "")).font(.hebiuSystem(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(activity[h.event].map { ago($0, now: context.date) } ?? "还没收到")
                                    .font(.hebiuStyle(.caption)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }
                }

                SectionLabel(text: "接上或补全钩子")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("在终端运行下面这行（Claude Code 里前面加 !）。装了哪个接哪个，只追加带 #hebiu 标记的钩子，已有的不动，改之前先备份。Codex 下次打开时会问要不要信任新钩子，选信任。")
                            .font(.hebiuStyle(.callout)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(hookCommand)
                                .font(.hebiuSystem(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1).truncationMode(.middle)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                            Button(copied ? "已复制" : "复制") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(hookCommand, forType: .string)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            }
                        }
                    }
                }
            }
        }
    }

    private var hookCommand: String {
        let dir = Bundle.main.infoDictionary?["HebiuSourceDir"] as? String ?? "~/Work/personal/hebiu"
        return "\(dir)/scripts/install-hooks.sh"
    }

    private func ago(_ date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        switch s {
        case ..<60: return "刚刚"
        case ..<3600: return "\(s / 60) 分钟前"
        case ..<86400: return "\(s / 3600) 小时前"
        default: return TodoFormat.describe(date, hasTime: true)
        }
    }
}
