import Foundation

/// 读取 ~/.hebiu/hebiu.md 里的台词。格式：
///   ## lines
///   ### done
///   - 搞定啦！biu～
/// 文件缺失或写错时用内置默认台词，不影响程序运行
public final class Config {
    public init() {}

    public private(set) var lines: [String: [String]] = Config.defaultLines
    public private(set) var settings = Settings()

    /// hebiu.md 里 dates 和 settings 两节的内容
    public struct Settings: Equatable {
        public var together: DateComponents?          // 在一起的日子（年月日）
        public var birthday: DateComponents?          // 她的生日（月日）
        public var photos = ""                        // 合照文件夹，如 ~/Pictures/我们；空表示不用
        public var restMinutes = 120                  // 连续工作多久提醒休息，0 关闭
        public var nightHour = 23                     // 几点以后算深夜，0 关闭
        public var followCursor = true                // 闲着时身子往鼠标那边歪一点
        public var sleepMinutes = 2                   // 不动电脑多久她就睡着，0 不睡
        public var focusMinutes = 25                  // 番茄钟专心几分钟
        public var breakMinutes = 5                   // 专心完休息几分钟，0 不休息
        public var moodAskHour = 21                   // 几点还没记心情就问一句，0 不问
        public var weatherCity = ""                   // 天气查哪个城市；空表示不查（不联网）
        public var quietHours = ""                    // 安静时段，如 12:00-13:30,22:30-08:00；空表示没有
        public var character = "default"              // 用哪个形象包（Resources/characters 或 ~/.hebiu/characters 里的文件夹名）
        public var peek = false                       // 藏起来时在屏幕边露个头（不是任何地方模式时）
        public var showIn = ShowIn()                  // 在哪显示：任何地方，或只在选中的 App 里
        public var morningSummary = true              // 每天第一次用电脑时说今天有哪些待办
        public var eveningReminder: DateComponents? = DateComponents(hour: 18, minute: 0)   // 下班前提醒没做完的，nil 关闭
        public var notify = true                      // 待办到点时也发系统通知
        public var tapTalkEvery = 10                  // 点她大约几次说一句台词；0 不说，1 每次都说
        public var userPronoun = "TA"                // AI 提示词里怎么称呼用户（第三人称）：他 / 她 / TA
        public var agentEnabled = false               // AI 大脑开关；关着时 hebiu 完全离线
        public var agentBudget: Decimal = 30          // AI 大脑每月花费上限（元）
        public var agentHotkey = "ctrl+alt+h"         // 呼出对话浮窗的全局快捷键
        public var agentProactive = true              // 早上、下班、休息、深夜提醒由 AI 结合当天的事来说
        public var agentLines = true                  // 每天让 AI 给各个动作写一批新台词
        public var agentShareSources = false          // 允许她看日历、GitLab 等来源的待办（会发给 DeepSeek）
        public var agentMemory = true                 // 她记住你：每晚写日记、更新对你的了解
        public var agentActivity = true               // 记忆里带上用 Claude 的时间和次数（不含项目和内容）
        public var talk = true                        // 她说话；关掉后不弹气泡，只保留待办到点提醒
        /// 数据来源 → 多少分钟同步一次；没写或 0 表示关闭
        public var sources: [String: Int] = [:]
        public init() {}
    }

    public var together: DateComponents? { settings.together }
    public var birthday: DateComponents? { settings.birthday }
    public var restMinutes: Int { settings.restMinutes }
    public var nightHour: Int { settings.nightHour }

    /// 默认台词：启动时换成形象包里的；没有形象包时用这份。hebiu.md 里某个事件写了台词就只用写的
    public static var defaultLines: [String: [String]] = builtinLines
    /// AI 提示词里怎么称呼用户（user_pronoun），读设置时更新
    public static var he = "TA"

    public static let builtinLines: [String: [String]] = [
        "hello": ["来啦～今天也一起加油", "嗨！我在这儿", "开工开工～"],
        "wait": ["喂～它在等你点确认", "快来看一眼，要你点一下", "卡住啦，在等你呢"],
        "done": ["搞定啦！", "完成一件～", "又解决一个！"],
        "error": ["哎呀出错了，别急", "小问题，再来一次嘛", "晕了一下，没事的"],
        "pat": ["嘿嘿～", "被摸头啦", "舒服～"],
        "poke": ["干嘛戳我～", "嘿！", "被发现了"],
        "love": ["比心！", "喜欢你哦", "♥"],
        "tap_cheer": ["耶～", "开心！"],
        "tap_tea": ["喝口茶歇歇", "分你一口～"],
        "tap_bliss": ["好舒服～", "再来一下"],
        "tap_grin": ["嘿嘿嘿", "哈哈"],
        "tap_nuzzle": ["蹭蹭～", "贴贴"],
        "tap_surprised": ["诶？", "吓我一跳"],
        "tap_blush": ["不好意思啦", "脸红了…"],
        "annoyed": ["别戳啦！", "要被你戳扁了", "再戳就生气了"],
        "sleepy": ["好困…", "眼睛睁不开了", "哈欠～"],
        "pout": ["哼！", "不理你了", "鼓起来了"],
        "cheer": ["好耶！", "太棒啦", "冲冲冲"],
        "rest": ["已经忙好久啦，起来动一动", "喝口水、看看远处吧", "休息五分钟嘛"],
        "night": ["很晚啦，早点休息", "明天再继续吧", "该睡觉啦"],
        "together": ["今天是第 {days} 天哦", "一起走过 {days} 天啦"],
        "birthday": ["生日快乐！", "今天是特别的日子～"],
        "focus_start": ["开始专心，我安静陪你", "番茄开始！"],
        "focus_done": ["一个番茄完成！休息一下", "专心了好久，好棒"],
        "rest_done": ["休息好啦？继续吧", "回来啦～"],
    ]

    /// 旧版本生成 hebiu.md 时把当时的默认台词（每个一句）写进了文件；读到和它一模一样的，当成没写
    static let legacyDefaults: [String: [String]] = [
        "hello": ["来啦～今天也要加油鸭"], "wait": ["喂！！看我！它在等你点确认～"], "done": ["搞定啦！biu～"],
        "error": ["有 bug？一炮轰掉！"], "pat": ["嘿嘿～再摸一下"], "poke": ["略略略～"], "love": ["今天也超喜欢你"],
        "sleepy": ["都几点啦…早点睡嘛"], "pout": ["哼！"], "cheer": ["下班下班！去喝奶茶"],
        "rest": ["已经连续忙了好久啦，起来动一动、喝口水嘛"], "night": ["都几点啦…早点睡嘛，明天再写"],
        "together": ["今天是我们在一起的第 {days} 天哦"], "birthday": ["今天是我的生日！要记得哦"],
    ]

    /// 自己写过台词的事件
    public private(set) var customLineKeys: Set<String> = []
    /// AI 写的台词：只补充到你没自己写过的事件里，和内置台词混着挑
    public private(set) var aiLines: [String: [String]] = [:]

    public func setAILines(_ lines: [String: [String]]) {
        aiLines = lines
    }
    private var recentLines: [String: [String]] = [:]

    public func load() {
        if !FileManager.default.fileExists(atPath: Paths.config.path) {
            try? Config.template.write(to: Paths.config, atomically: true, encoding: .utf8)
        }
        Config.appendMissingSections()
        guard let text = try? String(contentsOf: Paths.config, encoding: .utf8) else {
            lines = Config.defaultLines
            Log.write("config unreadable (not UTF-8?), using default lines")
            return
        }
        var parsed: [String: [String]] = [:]
        var settings: [String: String] = [:]
        var sourceValues: [String: String] = [:]
        var section = ""
        var key = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") {
                key = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces).lowercased()
            } else if line.hasPrefix("## ") {
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                key = ""
            } else if line.hasPrefix("- "), section == "lines", !key.isEmpty {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { parsed[key, default: []].append(item) }
            } else if line.hasPrefix("- "), section == "dates" || section == "settings" || section == "sources" {
                // 「- key: value」，值后面可以跟空格和说明文字
                let body = line.dropFirst(2)
                guard let colon = body.firstIndex(of: ":") else { continue }
                let k = body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                var after = body[body.index(after: colon)...]
                if after.first == " " { after = after.dropFirst() }
                // 冒号后面隔了好几个空格才有字，说明值是空的、后面是说明
                let full = after.first == " " ? "" : after.trimmingCharacters(in: .whitespaces)
                // 路径、城市名里可能有空格：这两个的值到两个空格为止，其余到第一个空格为止
                let v = k == "photos" || k == "weather_city" || k == "quiet_hours"
                    ? (full.components(separatedBy: "  ").first ?? "").trimmingCharacters(in: .whitespaces)
                    : full.split(separator: " ").first.map(String.init) ?? ""
                if section == "sources" { sourceValues[k] = v } else { settings[k] = v }
            }
        }
        var parsedSettings = Settings()
        parsedSettings.together = Config.parseDate(settings["together"], withYear: true)
        parsedSettings.birthday = Config.parseDate(settings["birthday"], withYear: false)
        parsedSettings.photos = settings["photos"] ?? ""
        parsedSettings.restMinutes = settings["rest_minutes"].flatMap(Int.init) ?? 120
        parsedSettings.nightHour = settings["night_hour"].flatMap(Int.init) ?? 23
        parsedSettings.followCursor = Config.parseSwitch(settings["follow_cursor"]) ?? true
        parsedSettings.sleepMinutes = min(60, max(0, settings["sleep_minutes"].flatMap(Int.init) ?? 2))
        parsedSettings.focusMinutes = min(180, max(1, settings["focus_minutes"].flatMap(Int.init) ?? 25))
        parsedSettings.weatherCity = settings["weather_city"] ?? ""
        parsedSettings.quietHours = settings["quiet_hours"] ?? ""
        parsedSettings.character = (settings["character"] ?? "").isEmpty ? "default" : settings["character"]!
        parsedSettings.peek = Config.parseSwitch(settings["peek"]) ?? false
        parsedSettings.showIn = ShowIn(showIn: settings["show_in"] ?? "all", apps: settings["show_apps"] ?? "", pop: settings["pop_out"])
        parsedSettings.moodAskHour = min(23, max(0, settings["mood_ask"].flatMap(Int.init) ?? 21))
        parsedSettings.breakMinutes = min(60, max(0, settings["break_minutes"].flatMap(Int.init) ?? 5))
        parsedSettings.morningSummary = Config.parseSwitch(settings["morning_summary"]) ?? true
        if let evening = settings["evening_reminder"] {
            parsedSettings.eveningReminder = Config.parseSwitch(evening) == false ? nil : Config.parseClock(evening) ?? DateComponents(hour: 18, minute: 0)
        }
        parsedSettings.notify = Config.parseSwitch(settings["notify"]) ?? true
        parsedSettings.tapTalkEvery = settings["tap_talk"].flatMap(Int.init).map { max(0, $0) } ?? 10
        parsedSettings.userPronoun = (settings["user_pronoun"] ?? "").isEmpty ? "TA" : settings["user_pronoun"]!
        parsedSettings.agentEnabled = Config.parseSwitch(settings["agent"]) ?? false
        parsedSettings.agentBudget = settings["agent_budget"].flatMap { Decimal(string: $0) }.map { max(0, $0) } ?? 30
        parsedSettings.agentProactive = Config.parseSwitch(settings["agent_proactive"]) ?? true
        parsedSettings.agentLines = Config.parseSwitch(settings["agent_lines"]) ?? true
        parsedSettings.agentShareSources = Config.parseSwitch(settings["agent_share_sources"]) ?? false
        parsedSettings.agentMemory = Config.parseSwitch(settings["agent_memory"]) ?? true
        parsedSettings.agentActivity = Config.parseSwitch(settings["agent_activity"]) ?? true
        parsedSettings.talk = Config.parseSwitch(settings["talk"]) ?? true
        parsedSettings.agentHotkey = settings["agent_hotkey"].flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? "ctrl+alt+h"
        for (name, value) in sourceValues {
            if let minutes = Int(value) {
                parsedSettings.sources[name] = max(0, minutes)
            } else if Config.parseSwitch(value) == true {
                parsedSettings.sources[name] = SourceCatalog.entry(name)?.defaultMinutes ?? 15
            } else {
                parsedSettings.sources[name] = 0
            }
        }
        self.settings = parsedSettings
        Config.he = parsedSettings.userPronoun
        // 和内置台词（或旧版本写进文件的默认台词）一模一样的，当成没写
        let custom = parsed.filter { key, value in value != Config.defaultLines[key] && value != Config.legacyDefaults[key] }
        customLineKeys = Set(custom.keys)
        lines = Config.defaultLines.merging(custom) { _, user in user }
        Log.write("config loaded: \(parsed.keys.sorted())")
    }

    /// 随机挑一句；最近说过的几句先不挑（一半以内），免得老重复
    public func randomLine(for key: String) -> String? {
        var pool = lines[key] ?? []
        if !customLineKeys.contains(key), let ai = aiLines[key] { pool += ai }
        guard !pool.isEmpty else { return nil }
        let recent = recentLines[key] ?? []
        let fresh = pool.filter { !recent.contains($0) }
        guard let line = (fresh.isEmpty ? pool : fresh).randomElement() else { return nil }
        recentLines[key] = Array((recent + [line]).suffix(max(1, pool.count / 2)))
        return line.replacingOccurrences(of: "{days}", with: daysTogether().map(String.init) ?? "?")
    }

    /// 在一起第几天：在一起当天算第 1 天
    public func daysTogether(on date: Date = Date()) -> Int? {
        guard let together, let start = Calendar.current.date(from: together) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days >= 0 ? days + 1 : nil
    }

    /// 旧版本生成的配置缺少后来新增的小节时，追加到文件末尾；已有内容一个字不改
    private static func appendMissingSections() {
        guard let text = try? String(contentsOf: Paths.config, encoding: .utf8) else { return }
        var extra = ""
        if !text.contains("## dates") {
            extra += "\n## dates\n\n在一起的日子写年月日，生日写月日。不知道就先空着。\n\n- together:\n- birthday:\n"
        }
        if !text.contains("## settings") {
            extra += "\n## settings\n\n- rest_minutes: 120    连续用 Claude 多久提醒休息（分钟），0 表示关闭\n- night_hour: 23       几点以后算深夜、催你睡觉，0 表示关闭\n"
        }
        if !text.contains("## sources") {
            extra += "\n## sources\n\n数据来源：「名字: 几分钟同步一次」，off 关闭。脚本放在 ~/.hebiu/sources/，写法见项目里的 docs/SOURCES.md。\n\n"
                + sourceLines([:]) + "\n"
        }
        let newLines = ["rest", "night", "together", "birthday"].filter { !text.contains("### \($0)") }
        if !newLines.isEmpty {
            // 新台词要落在 lines 小节里：如果文件末尾不是 lines 小节，先补一个标题
            let lastSection = text.components(separatedBy: "\n").last(where: { $0.hasPrefix("## ") }) ?? ""
            if !extra.isEmpty || lastSection.trimmingCharacters(in: .whitespaces) != "## lines" { extra += "\n## lines\n" }
            for key in newLines {
                extra += "\n### \(key)\n（用内置的 \(defaultLines[key]?.count ?? 0) 句；在下面写了就只用你写的）\n"
            }
        }
        guard !extra.isEmpty, let handle = try? FileHandle(forWritingTo: Paths.config) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(extra.utf8))
        try? handle.close()
        Log.write("config: appended missing sections")
    }

    private static func sourceLines(_ sources: [String: Int]) -> String {
        let names = SourceCatalog.known.map(\.name) + sources.keys.filter { SourceCatalog.entry($0) == nil }.sorted()
        return names.map { name in
            let minutes = sources[name] ?? 0
            let value = minutes > 0 ? "\(minutes)" : "off"
            let detail = SourceCatalog.entry(name).map { "    \($0.title)：\($0.detail)" } ?? ""
            return "- \(name): \(value)\(detail)"
        }.joined(separator: "\n")
    }

    /// on / off（也认 true/false、开/关）；认不出返回 nil
    static func parseSwitch(_ text: String?) -> Bool? {
        switch text?.lowercased() {
        case "on", "true", "yes", "1", "开": return true
        case "off", "false", "no", "0", "关": return false
        default: return nil
        }
    }

    /// 「18:00」→ 18 点 0 分
    static func parseClock(_ text: String?) -> DateComponents? {
        guard let parts = text?.split(whereSeparator: { $0 == ":" || $0 == "：" }).compactMap({ Int($0) }), parts.count == 2,
              (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return DateComponents(hour: parts[0], minute: parts[1])
    }

    /// 「2025-01-01」或「01-01」；写错就当没写
    private static func parseDate(_ text: String?, withYear: Bool) -> DateComponents? {
        guard let parts = text?.split(separator: "-").compactMap({ Int($0) }) else { return nil }
        if withYear, parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) {
            return DateComponents(year: parts[0], month: parts[1], day: parts[2])
        }
        if !withYear, parts.count >= 2 {
            let (m, d) = parts.count == 3 ? (parts[1], parts[2]) : (parts[0], parts[1])
            if (1...12).contains(m), (1...31).contains(d) { return DateComponents(month: m, day: d) }
        }
        return nil
    }

    /// 台词在文件里的顺序；文件里多出来的自定义事件排在后面
    public static let lineOrder = ["hello", "wait", "done", "error", "pat", "poke", "love", "tap_cheer", "tap_tea",
                                   "tap_bliss", "tap_grin", "tap_nuzzle", "tap_surprised", "tap_blush", "annoyed",
                                   "sleepy", "pout", "cheer", "rest", "night", "together", "birthday"]

    /// 设置页保存：按模板整份重写，手动加在文件里的说明文字不保留
    public func save(_ settings: Settings, lines: [String: [String]]) {
        let custom = lines.filter { key, value in !value.isEmpty && value != Config.defaultLines[key] }
        let text = Config.render(settings, lines: custom)
        do {
            try text.write(to: Paths.config, atomically: true, encoding: .utf8)
        } catch {
            Log.write("config save failed: \(error)")
        }
        load()
    }

    private static var template: String {
        render(Settings(), lines: [:])
    }

    private static func render(_ settings: Settings, lines: [String: [String]]) -> String {
        func two(_ n: Int?) -> String { String(format: "%02d", n ?? 0) }
        let together = settings.together, birthday = settings.birthday
        let restMinutes = settings.restMinutes, nightHour = settings.nightHour
        let evening = settings.eveningReminder.map { "\(two($0.hour)):\(two($0.minute))" } ?? "off"
        let togetherText = together.map { "\($0.year ?? 0)-\(two($0.month))-\(two($0.day))" } ?? ""
        let birthdayText = birthday.map { "\(two($0.month))-\(two($0.day))" } ?? ""
        var out = """
        # hebiu 配置

        可以在菜单「设置…」里改，也可以直接改这个文件，保存后自动生效。
        每个事件下面一行一句台词，触发时随机挑一句；某个事件一句都不写，就用内置的台词。

        ## dates

        在一起的日子写年月日，生日写月日。不知道就先空着（把冒号后面删掉）。

        - together: \(togetherText)
        - birthday: \(birthdayText)
        - photos: \(settings.photos)

        ## settings

        - rest_minutes: \(restMinutes)    连续用 Claude 多久提醒休息（分钟），0 表示关闭
        - night_hour: \(nightHour)       几点以后算深夜、催你睡觉，0 表示关闭
        - follow_cursor: \(settings.followCursor ? "on" : "off")    闲着时身子往鼠标那边歪一点，像在看你
        - sleep_minutes: \(settings.sleepMinutes)    不动电脑多久\(CharacterPack.she)就睡着（动一下鼠标会吓醒），0 表示不睡
        - focus_minutes: \(settings.focusMinutes)    番茄钟专心几分钟
        - break_minutes: \(settings.breakMinutes)    专心完休息几分钟，0 表示不休息
        - mood_ask: \(settings.moodAskHour)    几点还没记心情就问你一句，0 表示不问
        - show_in: \(settings.showIn.modeText)    在哪显示\(CharacterPack.she)：all 任何地方，apps 只在 show_apps 里的 App 在最前面时，popup 平时不显示
        - character: \(settings.character)    用哪个形象（形象包文件夹名）
        - peek: \(settings.peek ? "on" : "off")    藏起来的时候在屏幕边露个头，点\(CharacterPack.she)就出来一会儿
        - show_apps: \(settings.showIn.appsText)    App 标识，逗号隔开，如 dev.warp.Warp-Stable,com.google.Chrome
        - pop_out: \(settings.showIn.popText)    不显示的时候，这些事也让\(CharacterPack.she)出来：todo 待办到点、habit 习惯、date 重要日子、task 定时任务、focus 番茄钟、claude 做完报错、chat \(CharacterPack.she)回答你
        - quiet_hours: \(settings.quietHours)    安静时段，如 12:00-13:30,22:30-08:00，这段时间\(CharacterPack.she)像开了勿扰；空着就没有
        - weather_city: \(settings.weatherCity)    天气查哪个城市（如 上海），空着不查；只把城市名发给 Open-Meteo
        - morning_summary: \(settings.morningSummary ? "on" : "off")    每天第一次用电脑时说说今天的待办
        - evening_reminder: \(evening)    这个时间以后提醒还没做完的待办，off 关闭
        - notify: \(settings.notify ? "on" : "off")    待办到点时也发系统通知
        - user_pronoun: \(settings.userPronoun)    AI 提到你时用哪个字：他 / 她 / TA
        - tap_talk: \(settings.tapTalkEvery)    点\(CharacterPack.she)大约几次说一句台词，0 不说，1 每次都说
        - agent: \(settings.agentEnabled ? "on" : "off")    AI 大脑（DeepSeek），key 在设置页填，存钥匙串
        - agent_budget: \(settings.agentBudget)    AI 大脑每月花费上限（元）
        - agent_hotkey: \(settings.agentHotkey)    和\(CharacterPack.she)说话的快捷键，如 ctrl+alt+h
        - agent_proactive: \(settings.agentProactive ? "on" : "off")    早上、下班、休息、深夜的提醒由 AI 结合当天的事来说
        - agent_lines: \(settings.agentLines ? "on" : "off")    每天让 AI 给各个动作写一批新台词（你自己写了的不受影响）
        - agent_share_sources: \(settings.agentShareSources ? "on" : "off")    允许\(CharacterPack.she)看日历、GitLab 等来源的待办（标题会发给 DeepSeek）
        - agent_memory: \(settings.agentMemory ? "on" : "off")    \(CharacterPack.she)记住你：每晚写日记、更新对你的了解（存在 ~/.hebiu/agent/memory）
        - agent_activity: \(settings.agentActivity ? "on" : "off")    日记里带上用 Claude 的时间和次数（不含项目和内容）
        - talk: \(settings.talk ? "on" : "off")    \(CharacterPack.she)说话；off 时不弹气泡，只保留待办到点提醒

        ## sources

        数据来源：「名字: 几分钟同步一次」，off 关闭。脚本放在 ~/.hebiu/sources/，写法见项目里的 docs/SOURCES.md。

        \(sourceLines(settings.sources))

        ## lines

        """
        let extra = lines.keys.filter { !lineOrder.contains($0) }.sorted()
        for key in lineOrder + extra {
            let own = lines[key] ?? []
            out += "\n### \(key)\n" + (own.isEmpty ? "（用内置的 \(defaultLines[key]?.count ?? 0) 句；在下面写了就只用你写的）\n" : own.map { "- \($0)\n" }.joined())
        }
        return out
    }
}
