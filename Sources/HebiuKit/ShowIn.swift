import Foundation

/// 她在哪显示：任何地方 / 只在选中的 App 在最前面时 / 平时不显示。
/// 后两种模式下，选中的那几类「有事」时也会出来
public struct ShowIn: Equatable {
    public enum Mode: String, CaseIterable {
        case everywhere = "all"
        case apps
        case popup
    }

    /// 什么事会让她出来
    public enum PopKind: String, CaseIterable {
        case todo, habit, date, task, focus, claude, chat

        public var title: String {
            switch self {
            case .todo: return "待办到点"
            case .habit: return "习惯提醒"
            case .date: return "重要日子"
            case .task: return "定时让\(CharacterPack.she)做"
            case .focus: return "番茄钟"
            case .claude: return "Claude 做完或报错"
            case .chat: return "\(CharacterPack.she)回答你"
            }
        }

        /// 要等你点她才回去的（提醒类）；其余露个脸几秒就回去
        public var waitsForClick: Bool { [.todo, .habit, .date, .task, .focus].contains(self) }
    }

    public static let defaultPop: Set<PopKind> = [.todo, .habit, .date, .task, .focus, .chat]

    public var mode: Mode
    public var apps: Set<String>
    public var pop: Set<PopKind>

    public init(mode: Mode = .everywhere, apps: Set<String> = [], pop: Set<PopKind> = ShowIn.defaultPop) {
        self.mode = mode
        self.apps = apps
        self.pop = pop
    }

    public var everywhere: Bool { mode == .everywhere }

    /// hebiu.md：show_in 写 all / apps / popup（旧写法直接写 App 标识也认），show_apps、pop_out 用逗号隔开
    public init(showIn: String, apps appsText: String = "", pop popText: String? = nil) {
        func list(_ s: String) -> [String] { s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        let t = showIn.trimmingCharacters(in: .whitespaces)
        if let m = Mode(rawValue: t) {
            mode = m
            apps = Set(list(appsText))
        } else if t.isEmpty {
            mode = .everywhere
            apps = Set(list(appsText))
        } else {
            mode = .apps
            apps = Set(list(t) + list(appsText))
        }
        pop = popText.map { Set(list($0).compactMap(PopKind.init(rawValue:))) } ?? ShowIn.defaultPop
    }

    public var modeText: String { mode.rawValue }
    public var appsText: String { apps.sorted().joined(separator: ",") }
    public var popText: String { PopKind.allCases.filter(pop.contains).map(\.rawValue).joined(separator: ",") }

    /// 最前面是这个 App 时平时要不要显示；hebiu 自己（主窗口、对话框）总是显示
    public func allows(frontmost bundleID: String?, own: String?) -> Bool {
        switch mode {
        case .everywhere: return true
        case .apps:
            guard let bundleID else { return false }
            return bundleID == own || apps.contains(bundleID)
        case .popup:
            return bundleID != nil && bundleID == own
        }
    }
}
