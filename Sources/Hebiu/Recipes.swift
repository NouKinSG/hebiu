import HebiuKit
import Foundation

enum Effect: String {
    case pop       // 切换时轻轻弹一下
    case kick      // 开火后坐力
    case squish    // 被摸头往下缩
    case sway      // 左右摇摆（打招呼）
}

struct Step {
    let frame: String
    let seconds: Double
    var effect: Effect? = nil
}

/// 一个事件的完整表演：先依次播 steps，再停在 hold 上；loop 不为空时停住后循环播放直到下一个事件
struct Recipe {
    var steps: [Step] = []
    var hold: String
    var holdSeconds: Double? = nil     // nil：一直停到下一个事件
    var holdEffect: Effect? = .pop
    var loop: [Step] = []
    var line: String? = nil            // 气泡台词的 key（对应 hebiu.md 里的 ### 小节）

    init(_ a: CharacterPack.Action) {
        steps = a.steps.map { Step(frame: $0.frame, seconds: $0.seconds, effect: $0.effect.flatMap(Effect.init(rawValue:))) }
        hold = a.hold
        holdSeconds = a.holdSeconds
        holdEffect = a.holdEffect.flatMap(Effect.init(rawValue:))
        loop = a.loop.map { Step(frame: $0.frame, seconds: $0.seconds, effect: $0.effect.flatMap(Effect.init(rawValue:))) }
        line = a.line
    }
}

/// 界面上怎么称呼她、她叫什么：跟着形象包走（她 / 他 / 它）
enum Her {
    static var she: String { CharacterPack.she }
    static var name: String { Character.pack.name }
}

/// 现在用的形象包：动作表、帧图、点她的反应、默认台词和人设都从这里来
enum Character {
    private(set) static var pack = CharacterPack(name: "Hebiu", pronoun: "它", callsUser: "你", summary: "", persona: AgentPersona.builtinText,
                                                 lines: Config.builtinLines, actions: [:], taps: [], annoyed: "annoyed",
                                                 rightClick: "poke", doubleClick: "love", idle: .init(), expressions: [], catalog: [])
    private(set) static var dir: URL?
    private(set) static var recipes: [String: Recipe] = [:]

    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("characters") }
    static var framesDir: URL? { dir.map { CharacterLibrary.framesDir(for: $0, bundled: bundled) } }
    /// 现在这个形象有哪些帧（编辑器里选图用）
    static var frameNames: [String] { dir.map { CharacterLibrary.frameNames(in: $0, bundled: bundled).sorted() } ?? [] }

    /// 改了动作表：存成自己的一份，马上生效
    static func save(_ edited: CharacterPack) throws {
        try CharacterLibrary.saveOverride(edited)
        load(edited.id)
    }

    static func resetToBundled() {
        CharacterLibrary.removeOverride(pack.id)
        load(pack.id)
    }

    static var isEdited: Bool { CharacterLibrary.hasOverride(pack.id) }

    /// 读形象包，并把台词、人设、AI 表情这些默认值换成它的
    @discardableResult
    static func load(_ name: String, quiet: Bool = false) -> Bool {
        guard let found = CharacterLibrary.resolve(name, bundled: bundled) else {
            Log.write("no character pack found")
            return false
        }
        pack = found.pack
        CharacterPack.she = pack.pronoun
        dir = found.dir
        recipes = pack.actions.mapValues(Recipe.init)
        if !pack.lines.isEmpty { Config.defaultLines = pack.lines }
        if !pack.persona.isEmpty { AgentPersona.defaultText = pack.persona }
        AgentTools.expressions = pack.expressionChoices
        let missing = pack.missingFrames(available: CharacterLibrary.frameNames(in: found.dir, bundled: bundled))
        if !quiet { Log.write("character \(pack.id) loaded: \(recipes.count) actions" + (missing.isEmpty ? "" : ", missing frames: \(missing.joined(separator: " "))")) }
        return true
    }

    /// 点她相关的动作（勿扰时也响应、打断敲键盘后会接着敲）
    static var tapEvents: Set<String> { pack.tapActions }

    /// 动作在「动作」页上的名字，没登记就用动作名
    static func title(of action: String) -> String {
        pack.catalog.flatMap(\.items).first { $0.action == action }?.title ?? action
    }
}

enum Recipes {
    static var all: [String: Recipe] { Character.recipes }

    /// 勿扰模式下仍然响应的事件：都是用户主动点她、或者她到点要喊你的
    static var allowedWhenQuiet: Set<String> { Character.tapEvents.union(["remind", "focus_start", "focus_done", "rest_done"]) }

    /// 打断敲键盘后会回去接着敲的事件
    static var resumesWorking: Set<String> { Character.tapEvents.union(["error", "rest", "night"]) }
}

/// 动作库：页面上怎么分组、叫什么、什么时候会出现、用哪一帧当缩略图（形象包里配）
enum ActionCatalog {
    struct Action: Identifiable {
        let event: String
        let title: String
        let when: String
        let thumb: String
        var id: String { event }
    }

    struct Group: Identifiable {
        let title: String
        let actions: [Action]
        var id: String { title }
    }

    static var groups: [Group] {
        Character.pack.catalog.map { g in
            Group(title: g.title, actions: g.items.map { Action(event: $0.action, title: $0.title, when: $0.when, thumb: $0.thumb) })
        }
    }
}
