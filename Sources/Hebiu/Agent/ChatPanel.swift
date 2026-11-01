import AppKit
import HebiuKit
import SwiftUI

/// 和她说话的浮窗：出现在她头顶，回车发送，Esc 收起
final class ChatPanelController {
    private let agent: AgentController
    private var panel: NSPanel?
    var anchor: () -> NSRect = { .zero }          // 她的窗口在屏幕上的位置
    var openSettings: (() -> Void)?

    init(agent: AgentController) {
        self.agent = agent
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil {
            let p = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.contentViewController = NSHostingController(rootView: ChatBubbleView(agent: agent, close: { [weak self] in self?.hide() },
                                                                                     openSettings: { [weak self] in self?.openSettings?() }))
            panel = p
        }
        guard let panel else { return }
        panel.setContentSize(panel.contentViewController?.view.fittingSize ?? NSSize(width: 380, height: 160))
        // 放在她头顶，靠右对齐；放不下就放左边
        let pet = anchor()
        let screen = NSScreen.screens.first { $0.frame.intersects(pet) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: pet.maxX - panel.frame.width, y: pet.minY + pet.height * 0.78)
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - panel.frame.width - 8)
        origin.y = min(origin.y, screen.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

/// 能接收键盘输入的浮窗（无边框的面板默认不能成为键盘焦点）
private final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct ChatBubbleView: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    let close: () -> Void
    let openSettings: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if agent.thinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(Her.she)在想…").foregroundStyle(.secondary)
                }
            } else if let reply = agent.lastReply {
                Text(reply.text).font(.hebiuSystem(size: 14)).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(reply.changes.enumerated()), id: \.offset) { i, change in
                    HStack(spacing: 6) {
                        Image(systemName: agent.undone.contains(i) ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                            .foregroundStyle(agent.undone.contains(i) ? Color.secondary : Theme.accent)
                        Text(agent.undone.contains(i) ? "已撤销：\(change.summary)" : change.summary)
                            .font(.hebiuStyle(.caption)).foregroundStyle(.secondary).strikethrough(agent.undone.contains(i))
                        Spacer()
                        if !agent.undone.contains(i) {
                            Button("撤销") { agent.undo(i) }.buttonStyle(.borderless).font(.hebiuStyle(.caption)).foregroundStyle(Theme.accent)
                        }
                    }
                }
                ForEach(reply.pendingDeletes) { pending in
                    DeleteConfirmRow(agent: agent, pending: pending)
                }
                if reply.failure == .noKey || reply.failure == .badKey || reply.failure == .overBudget {
                    Button("去设置") { openSettings() }.controlSize(.small)
                }
            }
            if agent.draft.isEmpty && !agent.thinking && agent.enabled {
                QuickAsks(agent: agent)
            }
            HStack(spacing: 8) {
                TextField("跟\(Her.she)说点什么…", text: $agent.draft)
                    .textFieldStyle(.plain)
                    .font(.hebiuSystem(size: 14))
                    .focused($focused)
                    .onSubmit { agent.send() }
                    .disabled(agent.thinking)
                MicButton(agent: agent, voice: agent.voice)
                Text("回车发送").font(.hebiuStyle(.caption2)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.accent.opacity(0.7) : Color(nsColor: .separatorColor)))
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
        .tint(Theme.accent)
        .onAppear { focused = true }
        .onExitCommand { close() }
    }
}

/// 她提出要删一条待办：你点「删除」才真删
struct DeleteConfirmRow: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    let pending: AgentTools.PendingDelete

    var body: some View {
        HStack(spacing: 6) {
            switch agent.deleteDecisions[pending.id] {
            case true?:
                Image(systemName: "trash.circle").foregroundStyle(.secondary)
                Text("删了「\(pending.title)」").font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                Spacer()
            case false?:
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                Text("没删「\(pending.title)」").font(.hebiuStyle(.caption)).foregroundStyle(.secondary)
                Spacer()
            case nil:
                Image(systemName: "trash.circle.fill").foregroundStyle(.red)
                Text("删掉「\(pending.title)」？").font(.hebiuStyle(.caption))
                Spacer()
                Button("算了") { agent.decideDelete(pending, delete: false) }.buttonStyle(.borderless).font(.hebiuStyle(.caption))
                Button("删除") { agent.decideDelete(pending, delete: true) }.buttonStyle(.borderless).font(.hebiuStyle(.caption)).foregroundStyle(.red)
            }
        }
    }
}

/// 麦克风：点一下开始说，停顿一会儿自动发送；说着的时候再点一下只停下不发送
struct MicButton: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    @ObservedObject var voice: VoiceInput

    var body: some View {
        Button {
            voice.toggle()
        } label: {
            Image(systemName: voice.state == .listening ? "waveform.circle.fill" : "mic")
                .font(.hebiuSystem(size: 15))
                .foregroundStyle(voice.state == .listening ? Theme.accent : Color.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(agent.thinking)
        .help(help)
    }

    private var help: String {
        if case let .denied(reason) = voice.state { return reason }
        if voice.state == .listening { return "在听…停顿一会儿就发送；再点一下只停下" }
        return voice.onDevice ? "说话（在本机识别）" : "说话（用苹果的语音识别服务）"
    }
}

/// 一排常问的话，点一下就发
struct QuickAsks: View {
    @ObservedObject private var appTypography = TypographySettings.shared
    @ObservedObject var agent: AgentController
    static let asks = ["今天先做什么？", "帮我排一下今天", "这周过得怎么样？", "我有点累", "讲个笑话哄我"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuickAsks.asks, id: \.self) { ask in
                    Button(ask) { agent.say(ask) }
                        .buttonStyle(.plain)
                        .font(.hebiuStyle(.caption))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.accent.opacity(0.1)))
                }
            }
        }
    }
}
