import AppKit
import HebiuKit
import SwiftUI

/// 主窗口里的页面。加新功能：在这里加一个 case，归到某个分组里，再写一个页面
enum MainPage: String, CaseIterable, Identifiable {
    case home, chat, todos, habits, notes, review, actions, lines, us, persona, memory, sources, brain, tasks, claude, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "主页"
        case .chat: return "聊天"
        case .persona: return "人设"
        case .memory: return "\(Her.she)记得的事"
        case .brain: return "AI 大脑"
        case .tasks: return "定时让\(Her.she)做"
        case .todos: return "待办"
        case .habits: return "习惯"
        case .notes: return "随手记"
        case .review: return "回顾"
        case .actions: return "动作"
        case .lines: return "台词"
        case .us: return "我们"
        case .sources: return "数据来源"
        case .claude: return "Claude / Codex"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .persona: return "person.text.rectangle"
        case .memory: return "book.closed"
        case .brain: return "brain"
        case .tasks: return "alarm"
        case .todos: return "checklist"
        case .habits: return "flame"
        case .notes: return "note.text"
        case .review: return "chart.bar.xaxis"
        case .actions: return "figure.wave"
        case .lines: return "text.bubble"
        case .us: return "heart"
        case .sources: return "tray.and.arrow.down"
        case .claude: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    /// 侧边栏分组：天天用的放「日常」，和她有关的放「她」，接外面数据的放「连接」，设一次就不管的放「设置」
    static let sidebar: [(title: String, pages: [MainPage])] = [
        ("日常", [.home, .chat, .todos, .habits, .notes, .review]),
        ("\(Her.she)", [.actions, .lines, .persona, .memory, .us]),
        ("连接", [.brain, .tasks, .sources, .claude]),
    ]
}

final class MainNavigation: ObservableObject {
    @Published var page: MainPage = .home
}

struct MainView: View {
    @ObservedObject var nav: MainNavigation
    @ObservedObject var todos: TodoListModel
    @ObservedObject var settings: SettingsModel
    @ObservedObject var agent: AgentController

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(nav: nav, todayCount: todos.sections.today.count)
                .frame(width: 200)
                .background(VisualEffect(material: .sidebar))
            Divider()
            detail
                .padding(.top, 12)        // 让开透明标题栏
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .tint(Theme.accent)
        // 打勾、删除后的「撤销」和编辑弹窗放在窗口层，主页和待办页都能用
        .overlay(alignment: .bottom) {
            if let toast = todos.toast {
                ToastBar(toast: toast, model: todos).padding(.bottom, 20).padding(.leading, 200)
            }
        }
        .animation(.easeOut(duration: 0.2), value: todos.toast)
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.page {
        case .home: HomePage(todos: todos, settings: settings, nav: nav)
        case .chat: ChatPage(agent: agent, nav: nav)
        case .persona: PersonaPage()
        case .memory: MemoryPage(agent: agent, settings: settings, nav: nav)
        case .brain: BrainPage(agent: agent, settings: settings)
        case .tasks: TasksPage(agent: agent, nav: nav)
        case .todos: TodoPage(model: todos)
        case .habits: HabitsPage(settings: settings)
        case .notes: NotesPage(settings: settings)
        case .review: ReviewPage(settings: settings, agent: agent)
        case .actions: ActionsPage(model: settings)
        case .lines: LinesPage(model: settings)
        case .us: UsPage(model: settings)
        case .sources: SourcesPage(model: settings)
        case .claude: ClaudePage(model: settings)
        case .settings: SettingsPage(model: settings)
        }
    }
}

/// 侧边栏：头像 + 分组 + 底部设置。选中的一项用浅粉底
private struct Sidebar: View {
    @ObservedObject var nav: MainNavigation
    let todayCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PetThumb(frame: "idle", size: 32)
                Text(Her.name).font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 46)                 // 红绿灯按钮下面
            .padding(.bottom, 14)

            ForEach(MainPage.sidebar, id: \.title) { group in
                Text(group.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                ForEach(group.pages) { page in
                    SidebarRow(page: page, selected: nav.page == page, badge: page == .todos && todayCount > 0 ? todayCount : nil) {
                        nav.page = page
                    }
                }
            }
            Spacer()
            Divider().padding(.horizontal, 12)
            SidebarRow(page: .settings, selected: nav.page == .settings, badge: nil) { nav.page = .settings }
                .padding(.vertical, 8)
        }
    }
}

private struct SidebarRow: View {
    let page: MainPage
    let selected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Theme.accent : Color.secondary)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : Color.primary)
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(selected ? Theme.accent : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Theme.accent.opacity(0.15) : (hovering ? Color.primary.opacity(0.05) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

/// macOS 侧边栏的半透明材质
private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// 唯一的主窗口；菜单、气泡、命令行都通过它打开某一页。
/// 关掉窗口时连界面一起释放，平时只剩桌宠本身的内存
final class MainWindowController: NSObject, NSWindowDelegate {
    let nav = MainNavigation()
    let todos: TodoListModel
    let settings: SettingsModel
    private var window: NSWindow?

    let agent: AgentController

    init(todoCoordinator: TodoCoordinator, config: Config, host: SettingsHost, agent: AgentController) {
        todos = TodoListModel(todos: todoCoordinator)
        settings = SettingsModel(config: config, host: host)
        self.agent = agent
        super.init()
    }

    func close() { window?.performClose(nil) }

    func windowWillClose(_ notification: Notification) {
        settings.saveNow()
        DispatchQueue.main.async {
            self.window?.contentViewController = nil
            self.window = nil
        }
    }

    func show(_ page: MainPage? = nil, focusInput: Bool = false) {
        if let page { nav.page = page }
        todos.reload()
        settings.reload()
        if window == nil {
            let root = MainView(nav: nav, todos: todos, settings: settings, agent: agent)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "Hebiu"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 900, height: 640))
            w.contentMinSize = NSSize(width: 760, height: 520)
            w.setFrameAutosaveName("HebiuMainWindow")
            if !w.setFrameUsingName("HebiuMainWindow") { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // 系统会自动把光标放进第一个输入框；只有「快速加待办」和待办页才要它
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if focusInput { self.todos.focusTick += 1 } else if self.nav.page != .todos { self.window?.makeFirstResponder(nil) }
        }
    }

    /// 待办变了
    func refreshTodos() { todos.reload() }

    /// 菜单里改了大小、勿扰等
    func refreshHostState() {
        guard window?.isVisible == true else { return }
        settings.reloadHostState()
    }

    func refreshSources() { settings.sourceTick += 1 }
}
