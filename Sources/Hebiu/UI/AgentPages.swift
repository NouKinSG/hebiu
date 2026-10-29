import AppKit
import HebiuKit
import SwiftUI

/// 日常 → 聊天：全部对话记录 + 输入框
struct ChatPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    @ObservedObject var nav: MainNavigation

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("聊天").font(.hebiuSystem(size: 26, weight: .bold))
                            Text(agent.enabled ? "跟\(Her.she)说一句，\(Her.she)会帮你记待办、查待办，也会陪你聊" : "AI 大脑还没打开")
                                .font(.hebiuStyle(.callout)).foregroundStyle(.secondary)
                        }
                        if !agent.enabled {
                            Card {
                                HStack {
                                    Text("在「连接 → AI 大脑」里填好 DeepSeek 的 key 并打开，就能和\(Her.she)聊天了。").font(.hebiuStyle(.callout))
                                    Spacer()
                                    Button("去打开") { nav.page = .brain }.buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        ForEach(agent.lines) { line in
                            ChatLineView(line: line).id(line.id)
                        }
                        if let pending = agent.lastReply?.pendingDeletes, !pending.isEmpty, !agent.thinking {
                            VStack(spacing: 8) {
                                ForEach(pending) { DeleteConfirmRow(agent: agent, pending: $0) }
                            }
                            .padding(.leading, 50).frame(maxWidth: 420)
                        }
                        if agent.thinking {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(Her.she)在想…").foregroundStyle(.secondary) }
                                .id("thinking")
                        }
                    }
                    .frame(maxWidth: Theme.contentWidth, alignment: .leading)
                    .padding(Theme.pagePadding)
                    .frame(maxWidth: .infinity)
                }
                .onAppear { proxy.scrollTo(agent.lines.last?.id, anchor: .bottom) }
                .onChange(of: agent.lines.count) { _ in withAnimation { proxy.scrollTo(agent.lines.last?.id, anchor: .bottom) } }
            }
            Divider()
            if agent.enabled && agent.draft.isEmpty && !agent.thinking {
                QuickAsks(agent: agent).padding(.horizontal, Theme.pagePadding).padding(.top, 10)
            }
            HStack(spacing: 10) {
                TextField("跟\(Her.she)说点什么…（快捷键随时呼出：\(HotkeySpec(agent.hotkeyText)?.display ?? "")）", text: $agent.draft)
                    .textFieldStyle(.plain).font(.hebiuSystem(size: 14))
                    .onSubmit { agent.send() }
                    .disabled(agent.thinking)
                MicButton(agent: agent, voice: agent.voice)
                Button("发送") { agent.send() }.buttonStyle(.borderedProminent).disabled(agent.draft.isEmpty || agent.thinking)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 14)
        }
    }
}

private struct ChatLineView: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let line: AgentChatLog.Line

    var body: some View {
        switch line.role {
        case "user":
            HStack {
                Spacer(minLength: 80)
                Text(line.content)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(0.18)))
            }
        case "assistant":
            HStack(alignment: .top, spacing: 10) {
                PetThumb(frame: thumb, size: 40)
                Text(line.content)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                Spacer(minLength: 80)
            }
        default:
            Label(line.content, systemImage: line.role == "error" ? "exclamationmark.circle" : "checkmark.circle")
                .font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                .padding(.leading, 50)
        }
    }

    /// 回答时配的表情，用对应的帧当头像
    private var thumb: String {
        ["tap_bliss": "bliss", "tap_grin": "grin", "tap_nuzzle": "nuzzle", "tap_surprised": "surprised", "tap_blush": "blush",
         "love": "heart", "poke": "poke", "pout": "pout", "cheer": "cheer", "sleepy": "sleepy", "pat": "pat"][line.expression ?? ""] ?? "idle"
    }
}

/// 连接 → AI 大脑：开关、key、花费、隐私说明
struct BrainPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    @ObservedObject var settings: SettingsModel
    @State private var keyInput = ""
    @State private var keyMessage: String?

    var body: some View {
        Page(title: "AI 大脑", subtitle: "用你自己的 DeepSeek 账号，让\(Her.she)听懂你说的话") {
            group("开关") {
                SettingRow(title: "打开 AI 大脑", detail: "关掉后 hebiu 完全不联网，其余功能照常") {
                    Toggle("", isOn: $settings.agentEnabled).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "呼出快捷键", detail: "随时按下，\(Her.she)头顶弹出对话框；写法如 ctrl+alt+h") {
                    TextField("", text: $settings.agentHotkey).frame(width: 140).multilineTextAlignment(.trailing)
                }
            }

            group("\(Her.she)会主动") {
                SettingRow(title: "提醒时结合今天的事说", detail: "早上汇总、下班前、休息、深夜这几句由 AI 来说；失败时用固定台词") {
                    Toggle("", isOn: $settings.agentProactive).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingRow(title: "每天写一批新台词", detail: agent.linesDay.map { "今天的已写好（\($0)）；你自己写过的台词不受影响" } ?? "还没写过；你自己写过的台词不受影响") {
                    HStack {
                        Button(agent.writingLines ? "写台词中…" : "现在写一批") { agent.writeLinesIfNeeded(force: true) }
                            .controlSize(.small).disabled(agent.writingLines || !settings.agentEnabled)
                        Toggle("", isOn: $settings.agentLines).labelsHidden().toggleStyle(.switch)
                    }
                }
            }

            group("DeepSeek key") {
                SettingRow(title: "当前", detail: "存在系统钥匙串里，不写进任何文件") {
                    Text(agent.keyMasked).foregroundStyle(.secondary).monospacedDigit()
                }
                Divider()
                HStack(spacing: 8) {
                    SecureField("粘贴新的 key（sk-…）", text: $keyInput).textFieldStyle(.roundedBorder)
                    Button("保存") {
                        keyMessage = agent.saveKey(keyInput) ? "已保存" : "保存失败"
                        keyInput = ""
                        agent.refreshBalance()
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("删除", role: .destructive) { agent.deleteKey(); keyMessage = "已删除" }
                }
                if let keyMessage { Text(keyMessage).font(.hebiuStyle(.caption)).foregroundStyle(.secondary) }
            }

            group("花费") {
                SettingRow(title: "本月已花", detail: "按 DeepSeek 官方价格逐笔记账") {
                    Text("¥ \(format(agent.monthSpent))").font(.hebiuSystem(size: 18, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Divider()
                SpendWeekChart(week: agent.week)
                Divider()
                SettingRow(title: "每月上限", detail: "到了上限\(Her.she)就不再调用，下个月自动恢复") {
                    Stepper("¥ \(Int(settings.agentBudget))", value: $settings.agentBudget, in: 1...500, step: 5).fixedSize()
                }
                Divider()
                SettingRow(title: "账户余额") {
                    HStack {
                        Text(agent.balance.map { "¥ \($0)" } ?? "—").monospacedDigit().foregroundStyle(.secondary)
                        Button("刷新") { agent.refreshBalance() }.controlSize(.small)
                    }
                }
            }

            group("会发给 DeepSeek 的内容") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("你跟\(Her.she)说的话、\(Her.she)的人设", systemImage: "checkmark.circle").foregroundStyle(.primary)
                    Label("你自己加的待办：只有标题和时间", systemImage: "checkmark.circle").foregroundStyle(.primary)
                    Label("今天的习惯和打卡、今天的心情、快到的重要日子；填了城市时的天气", systemImage: "checkmark.circle").foregroundStyle(.primary)
                    Label("随手记：让\(Her.she)记、让\(Her.she)找时发那几条；打开记忆时，写日记会发当天记的", systemImage: "checkmark.circle").foregroundStyle(.primary)
                    if settings.agentMemory {
                        Label("\(Her.she)记下的对你的了解、最近几天的日记；每晚写日记时发当天的聊天" + (settings.agentActivity ? "和写代码的时间" : ""),
                              systemImage: "checkmark.circle").foregroundStyle(.primary)
                    }
                    if settings.agentShareSources {
                        Label("日历、提醒事项、GitLab 等来源的待办：标题和时间", systemImage: "checkmark.circle").foregroundStyle(.primary)
                    } else {
                        Label("日历、提醒事项、GitLab 等来源的待办：不发", systemImage: "xmark.circle").foregroundStyle(.secondary)
                    }
                    Label("待办备注、链接、合照、key、文件：不发", systemImage: "xmark.circle").foregroundStyle(.secondary)
                }
                .font(.hebiuStyle(.callout))
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                SettingRow(title: "允许\(Her.she)看日历、GitLab 来的待办",
                           detail: "打开后\(Her.she)能回答「今天有什么会」、帮你打勾；这些标题会发给 DeepSeek，涉及公司数据，先确认公司允许。时间\(Her.she)改不了") {
                    Toggle("", isOn: $settings.agentShareSources).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        .onAppear { agent.reload(); agent.refreshBalance() }
    }

    private func format(_ d: Decimal) -> String {
        let n = NSDecimalNumber(decimal: d)
        let f = NumberFormatter()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: n) ?? "0.00"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            Card { VStack(spacing: 10) { content() } }
        }
    }
}

/// 她 → 人设：她怎么说话
struct PersonaPage: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @State private var text = AgentPersona.load()
    @State private var saved = false

    var body: some View {
        Page(title: "人设", subtitle: "\(Her.she)怎么说话、有什么口头禅、怎么叫你。和\(Her.she)聊天时会带上") {
            TextEditor(text: $text)
                .font(.hebiuSystem(size: 14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 320)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
            HStack {
                Button("恢复默认") { text = AgentPersona.defaultText }
                Spacer()
                if saved { Text("已保存").font(.hebiuStyle(.caption)).foregroundStyle(.secondary) }
                Button("保存") {
                    try? FileManager.default.createDirectory(at: Paths.dataDir, withIntermediateDirectories: true)
                    try? text.write(to: Paths.persona, atomically: true, encoding: .utf8)
                    saved = true
                }
                .buttonStyle(.borderedProminent)
            }
            Text("存在 ~/.hebiu/persona.md，也可以直接改这个文件").font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
        }
    }
}

/// 近 7 天每天花了多少，按用途叠起来；同一个颜色深浅区分用途
struct SpendWeekChart: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    let week: [AgentLedger.DaySpend]
    private let height: CGFloat = 90

    private static func shade(_ p: AgentLedger.Purpose) -> Double {
        switch p {
        case .chat: return 1
        case .talk: return 0.7
        case .lines: return 0.45
        case .memory: return 0.25
        }
    }

    var body: some View {
        let peak = max(week.map { NSDecimalNumber(decimal: $0.total).doubleValue }.max() ?? 0, 0.0001)
        let total = week.reduce(Decimal(0)) { $0 + $1.total }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("近 7 天").font(.hebiuStyle(.body))
                Spacer()
                Text("共 ¥ \(money(total))").font(.hebiuStyle(.callout)).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week, id: \.day) { day in
                    VStack(spacing: 4) {
                        Text(day.total > 0 ? money(day.total) : "")
                            .font(.hebiuSystem(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                        VStack(spacing: 0) {
                            ForEach(AgentLedger.Purpose.allCases.reversed(), id: \.self) { p in
                                let v = NSDecimalNumber(decimal: day.byPurpose[p] ?? 0).doubleValue
                                if v > 0 {
                                    Rectangle().fill(Theme.accent.opacity(SpendWeekChart.shade(p)))
                                        .frame(height: max(2, height * v / peak))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .background(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08)).frame(height: day.total > 0 ? 0 : 2)
                        }
                        Text(label(day.day)).font(.hebiuStyle(.caption2)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height + 34, alignment: .bottom)
            HStack(spacing: 14) {
                ForEach(AgentLedger.Purpose.allCases, id: \.self) { p in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(SpendWeekChart.shade(p))).frame(width: 10, height: 10)
                        Text(p.title).font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private func label(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "今天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "EEE"
        return f.string(from: day)
    }

    private func money(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = d < Decimal(string: "0.1")! ? 3 : 2
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "0"
    }
}
