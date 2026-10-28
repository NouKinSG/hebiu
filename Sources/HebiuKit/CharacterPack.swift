import Foundation

/// 形象包：一个角色的全部「样子」——名字和称呼、人设、默认台词、动作表、点她时的反应。
/// 一个文件夹一个形象：character.json + frames/*.webp（或 png）。
/// 程序自带的在 App 包的 Resources/characters/ 里，自己做的放 ~/.hebiu/characters/，同名的以自己的为准
public struct CharacterPack: Codable, Equatable {
    /// 动作里的一步：显示哪一帧、停多久、换帧时的小效果（pop 弹一下 / kick 后坐力 / squish 往下缩 / sway 左右摇）
    public struct Step: Codable, Equatable {
        public var frame: String
        public var seconds: Double
        public var effect: String?

        public init(frame: String, seconds: Double, effect: String? = nil) {
            self.frame = frame
            self.seconds = seconds
            self.effect = effect
        }
    }

    /// 一个动作：先依次播 steps，再停在 hold 上；loop 不为空时停住后循环播放，直到下一个动作
    public struct Action: Codable, Equatable {
        public var steps: [Step]
        public var hold: String
        /// nil：一直停到下一个动作
        public var holdSeconds: Double?
        public var holdEffect: String?
        public var loop: [Step]
        /// 说哪一组台词（lines 里的键）；nil 不说话
        public var line: String?

        public init(steps: [Step] = [], hold: String, holdSeconds: Double? = nil, holdEffect: String? = "pop",
                    loop: [Step] = [], line: String? = nil) {
            self.steps = steps
            self.hold = hold
            self.holdSeconds = holdSeconds
            self.holdEffect = holdEffect
            self.loop = loop
            self.line = line
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            steps = try c.decodeIfPresent([Step].self, forKey: .steps) ?? []
            hold = try c.decode(String.self, forKey: .hold)
            holdSeconds = try c.decodeIfPresent(Double.self, forKey: .holdSeconds)
            holdEffect = try c.decodeIfPresent(String.self, forKey: .holdEffect) ?? "pop"
            loop = try c.decodeIfPresent([Step].self, forKey: .loop) ?? []
            line = try c.decodeIfPresent(String.self, forKey: .line)
        }

        /// 用到的所有帧
        public var frames: [String] { steps.map(\.frame) + [hold] + loop.map(\.frame) }
    }

    /// 点她时的一种反应和出现的权重
    public struct Tap: Codable, Equatable {
        public var action: String
        public var weight: Int

        public init(action: String, weight: Int) {
            self.action = action
            self.weight = weight
        }
    }

    /// 「动作」页上的一格
    public struct CatalogItem: Codable, Equatable {
        public var action: String
        public var title: String
        public var when: String
        public var thumb: String

        public init(action: String, title: String, when: String, thumb: String) {
            self.action = action
            self.title = title
            self.when = when
            self.thumb = thumb
        }
    }

    public struct CatalogGroup: Codable, Equatable {
        public var title: String
        public var items: [CatalogItem]

        public init(title: String, items: [CatalogItem]) {
            self.title = title
            self.items = items
        }
    }

    /// 闲着时：平常站哪一帧、眨眼帧、偶尔做的小动作、睡着和被吵醒
    public struct Idle: Codable, Equatable {
        public var frame: String
        public var blink: String?
        public var fidgets: [String]
        public var sleep: String
        public var startle: String
        public var wake: String

        public init(frame: String = "idle", blink: String? = "blink", fidgets: [String] = [], sleep: String = "idle",
                    startle: String = "idle", wake: String = "idle") {
            self.frame = frame
            self.blink = blink
            self.fidgets = fidgets
            self.sleep = sleep
            self.startle = startle
            self.wake = wake
        }
    }

    /// 当前形象怎么被称呼（她 / 他 / 它），核心库里的提示文字用；加载形象时设置
    public static var she = "它"

    /// 文件夹名，加载时填
    public var id: String = ""
    /// 角色的名字（界面、菜单、提示词里用）
    public var name: String
    /// 界面上怎么称呼她：她 / 他 / 它
    public var pronoun: String
    /// 她怎么称呼用户（写进提示词）：你 / 他
    public var callsUser: String
    /// 一句话介绍（设置页、形象列表里显示）
    public var summary: String
    /// 默认人设（用户在「人设」页改过就用改过的）
    public var persona: String
    /// 默认台词：动作的 line 键 → 几句
    public var lines: [String: [String]]
    /// 动作表：动作名 → 怎么演。Claude、陪伴提醒、待办这些事件按名字找动作（hello / working / wait / done / error / remind / rest / night……）
    public var actions: [String: Action]
    /// 点她时随机挑的反应
    public var taps: [Tap]
    /// 戳太多时的动作
    public var annoyed: String
    /// 右键、双击固定的反应
    public var rightClick: String
    public var doubleClick: String
    public var idle: Idle
    /// AI 回答时能选的表情（动作名）；空就用 taps 里的
    public var expressions: [String]
    public var catalog: [CatalogGroup]

    enum CodingKeys: String, CodingKey {
        case name, pronoun, callsUser, summary, persona, lines, actions, taps, annoyed, rightClick, doubleClick, idle, expressions, catalog
    }

    public init(name: String, pronoun: String, callsUser: String, summary: String, persona: String,
                lines: [String: [String]], actions: [String: Action], taps: [Tap], annoyed: String,
                rightClick: String, doubleClick: String, idle: Idle, expressions: [String], catalog: [CatalogGroup]) {
        self.name = name
        self.pronoun = pronoun
        self.callsUser = callsUser
        self.summary = summary
        self.persona = persona
        self.lines = lines
        self.actions = actions
        self.taps = taps
        self.annoyed = annoyed
        self.rightClick = rightClick
        self.doubleClick = doubleClick
        self.idle = idle
        self.expressions = expressions
        self.catalog = catalog
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        pronoun = try c.decodeIfPresent(String.self, forKey: .pronoun) ?? "它"
        callsUser = try c.decodeIfPresent(String.self, forKey: .callsUser) ?? "你"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        persona = try c.decodeIfPresent(String.self, forKey: .persona) ?? ""
        lines = try c.decodeIfPresent([String: [String]].self, forKey: .lines) ?? [:]
        actions = try c.decodeIfPresent([String: Action].self, forKey: .actions) ?? [:]
        taps = try c.decodeIfPresent([Tap].self, forKey: .taps) ?? []
        annoyed = try c.decodeIfPresent(String.self, forKey: .annoyed) ?? "annoyed"
        rightClick = try c.decodeIfPresent(String.self, forKey: .rightClick) ?? taps.first?.action ?? "idle"
        doubleClick = try c.decodeIfPresent(String.self, forKey: .doubleClick) ?? taps.first?.action ?? "idle"
        idle = try c.decodeIfPresent(Idle.self, forKey: .idle) ?? Idle()
        expressions = try c.decodeIfPresent([String].self, forKey: .expressions) ?? []
        catalog = try c.decodeIfPresent([CatalogGroup].self, forKey: .catalog) ?? []
    }

    // MARK: - 派生

    /// 点她相关的所有动作（含戳太多、右键、双击）
    public var tapActions: Set<String> {
        Set(taps.map(\.action)).union([annoyed, rightClick, doubleClick])
    }

    /// 给 AI 选的表情
    public var expressionChoices: [String] {
        expressions.isEmpty ? taps.map(\.action) : expressions
    }

    /// 动作表里用到、但图片里没有的帧（形象包检查用）
    public func missingFrames(available: Set<String>) -> [String] {
        var used = Set(actions.values.flatMap(\.frames))
        used.formUnion([idle.frame, idle.sleep, idle.startle, idle.wake] + (idle.blink.map { [$0] } ?? []))
        used.formUnion(catalog.flatMap { $0.items.map(\.thumb) })
        return used.subtracting(available).sorted()
    }

    // MARK: - 读写

    public static let fileName = "character.json"
    public static let framesDir = "frames"

    public static func load(from dir: URL) throws -> CharacterPack {
        let data = try Data(contentsOf: dir.appendingPathComponent(fileName))
        var pack = try JSONDecoder().decode(CharacterPack.self, from: data)
        pack.id = dir.lastPathComponent
        return pack
    }

    public func save(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try e.encode(self).write(to: dir.appendingPathComponent(CharacterPack.fileName), options: .atomic)
    }
}

/// 找形象包：自带的（App 包里）+ 自己的（~/.hebiu/characters），同名以自己的为准
public enum CharacterLibrary {
    public static var userDir: URL { Paths.dataDir.appendingPathComponent("characters", isDirectory: true) }

    /// 所有能用的形象包文件夹：名字 → 路径
    public static func available(bundled: URL?) -> [String: URL] {
        var out: [String: URL] = [:]
        for root in [bundled, userDir].compactMap({ $0 }) {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            for n in names where FileManager.default.fileExists(atPath: root.appendingPathComponent(n).appendingPathComponent(CharacterPack.fileName).path) {
                out[n] = root.appendingPathComponent(n)
            }
        }
        return out
    }

    /// 按名字找；找不到就用 fallback；再找不到就随便一个
    public static func resolve(_ name: String, bundled: URL?, fallback: String = "default") -> (pack: CharacterPack, dir: URL)? {
        let all = available(bundled: bundled)
        for candidate in [name, fallback] + all.keys.sorted() {
            guard let dir = all[candidate] else { continue }
            do {
                return (try CharacterPack.load(from: dir), dir)
            } catch {
                Log.write("character \(candidate) unreadable: \(error.localizedDescription)")
            }
        }
        return nil
    }

    /// 帧图在哪：自己的文件夹里有 frames/ 就用自己的，没有就用自带的同名形象包的（只改了动作表的情况）
    public static func framesDir(for dir: URL, bundled: URL?) -> URL {
        let own = dir.appendingPathComponent(CharacterPack.framesDir)
        if FileManager.default.fileExists(atPath: own.path) { return own }
        if let bundled {
            let other = bundled.appendingPathComponent(dir.lastPathComponent).appendingPathComponent(CharacterPack.framesDir)
            if FileManager.default.fileExists(atPath: other.path) { return other }
        }
        return own
    }

    /// 改过的动作表存成自己的一份（~/.hebiu/characters/<名字>/character.json），自带的不动
    public static func saveOverride(_ pack: CharacterPack) throws {
        try pack.save(to: userDir.appendingPathComponent(pack.id))
    }

    /// 恢复成自带的：删掉自己那份动作表（自己放进去的图片留着）
    public static func removeOverride(_ id: String) {
        try? FileManager.default.removeItem(at: userDir.appendingPathComponent(id).appendingPathComponent(CharacterPack.fileName))
    }

    /// 是不是改过（有自己的一份）
    public static func hasOverride(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: userDir.appendingPathComponent(id).appendingPathComponent(CharacterPack.fileName).path)
    }

    /// 文件夹里有哪些帧（不带扩展名）
    public static func frameNames(in dir: URL, bundled: URL? = nil) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: framesDir(for: dir, bundled: bundled).path)) ?? []
        return Set(names.filter { ["webp", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
            .map { ($0 as NSString).deletingPathExtension })
    }
}
