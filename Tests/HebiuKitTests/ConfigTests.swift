import Foundation
import Testing
@testable import HebiuKit

@Suite(.serialized) struct ConfigTests {
    @Test func 合照文件夹路径可以带空格() throws {
        try withTempHome { _ in
            try """
            ## dates
            - photos: ~/Pictures/我们 的照片    合照文件夹
            ## settings
            - rest_minutes: 90    说明文字
            """.write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.settings.photos == "~/Pictures/我们 的照片")
            #expect(PhotoAlbum.folder(from: config.settings.photos)?.path.hasSuffix("/Pictures/我们 的照片") == true)
            #expect(config.restMinutes == 90)
        }
    }

    @Test func 首次运行生成模板并使用默认值() throws {
        try withTempHome { _ in
            let config = Config()
            config.load()
            #expect(FileManager.default.fileExists(atPath: Paths.config.path))
            #expect(config.restMinutes == 120)
            #expect(config.nightHour == 23)
            #expect(config.together == nil)
            #expect(config.lines["done"] == Config.defaultLines["done"])
        }
    }

    @Test func 读取日期设置和台词_值后面可以跟说明文字() throws {
        try withTempHome { _ in
            try """
            ## dates
            - together: 2025-03-14
            - birthday: 05-20
            ## settings
            - rest_minutes: 90    说明文字
            - night_hour: 22
            ## lines
            ### done
            - 好耶
            - 收工
            """.write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.together == DateComponents(year: 2025, month: 3, day: 14))
            #expect(config.birthday == DateComponents(month: 5, day: 20))
            #expect(config.restMinutes == 90)
            #expect(config.nightHour == 22)
            #expect(config.lines["done"] == ["好耶", "收工"])
            #expect(config.lines["pat"] == Config.defaultLines["pat"])   // 没写的沿用默认
        }
    }

    @Test func 待办提醒的开关和时间() throws {
        try withTempHome { _ in
            try "## settings\n- morning_summary: off\n- evening_reminder: 17:30\n- notify: 关\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.settings.morningSummary == false)
            #expect(config.settings.eveningReminder == DateComponents(hour: 17, minute: 30))
            #expect(config.settings.notify == false)
            try "## settings\n- evening_reminder: off\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            config.load()
            #expect(config.settings.eveningReminder == nil)
            #expect(config.settings.morningSummary == true)
        }
    }

    @Test func AI_提到用户时用哪个字_默认_TA_能存能读() throws {
        try withTempHome { _ in
            let config = Config()
            config.load()
            #expect(config.settings.userPronoun == "TA" && Config.he == "TA")
            var settings = config.settings
            settings.userPronoun = "他"
            config.save(settings, lines: config.lines)
            config.load()
            #expect(config.settings.userPronoun == "他" && Config.he == "他")
            #expect(AgentTools.noteDefinitions.description.contains("他的随手记"))
            Config.he = "TA"
        }
    }

    @Test func 数据来源开关() throws {
        try withTempHome { _ in
            try "## sources\n- calendar: 5    说明\n- reminders: on\n- gitlab-review: off\n- mine: abc\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.settings.sources == ["calendar": 5, "reminders": 10, "gitlab-review": 0, "mine": 0])
        }
    }

    @Test func 旧版本写进文件的默认台词当成没写_用新的内置台词() throws {
        try withTempHome { _ in
            try "## lines\n### pat\n- 嘿嘿～再摸一下\n### poke\n- 我自己写的\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.lines["pat"] == Config.defaultLines["pat"])
            #expect(config.lines["poke"] == ["我自己写的"])
            #expect(config.customLineKeys == ["poke"])
        }
    }

    @Test func 保存时和内置一样的台词不写进文件() throws {
        try withTempHome { _ in
            let config = Config()
            config.load()
            config.save(Config.Settings(), lines: ["pat": Config.defaultLines["pat"]!, "love": ["只说这一句"]])
            let text = try String(contentsOf: Paths.config, encoding: .utf8)
            #expect(!text.contains("头发要被你揉乱啦"))
            #expect(text.contains("- 只说这一句"))
            config.load()
            #expect(config.lines["pat"] == Config.defaultLines["pat"])
            #expect(config.lines["love"] == ["只说这一句"])
        }
    }

    @Test func 短时间内不重复同一句() throws {
        try withTempHome { _ in
            let config = Config()
            config.load()
            let pool = Config.defaultLines["pat"]!
            var said: [String] = []
            for _ in 0..<pool.count / 2 { said.append(config.randomLine(for: "pat")!) }
            #expect(Set(said).count == said.count)
        }
    }

    @Test func AI台词只补充没自己写过的事件() throws {
        try withTempHome { _ in
            try "## lines\n### poke\n- 我自己写的\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            config.setAILines(["pat": ["AI 写的摸头"], "poke": ["AI 写的坏笑"]])
            var pats = Set<String>()
            for _ in 0..<60 { if let l = config.randomLine(for: "pat") { pats.insert(l) } }
            #expect(pats.contains("AI 写的摸头"))
            #expect(pats.isSuperset(of: Set(Config.defaultLines["pat"]!)))   // 内置的也还在
            for _ in 0..<10 { #expect(config.randomLine(for: "poke") == "我自己写的") }
        }
    }

    @Test func 日期写错当没写() throws {
        try withTempHome { _ in
            try "## dates\n- together: 2025-13-40\n- birthday: abc\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.together == nil)
            #expect(config.birthday == nil)
        }
    }

    @Test func 在一起当天算第一天() throws {
        try withTempHome { _ in
            try "## dates\n- together: 2025-01-01\n".write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            #expect(config.daysTogether(on: date("2025-01-01")) == 1)
            #expect(config.daysTogether(on: date("2025-04-10")) == 100)
            #expect(config.daysTogether(on: date("2024-12-31")) == nil)
        }
    }

    @Test func 旧配置补上缺失小节_已有内容不变() throws {
        try withTempHome { _ in
            let old = "## lines\n\n### done\n- 我自己写的\n"
            try old.write(to: Paths.config, atomically: true, encoding: .utf8)
            let config = Config()
            config.load()
            let text = try String(contentsOf: Paths.config, encoding: .utf8)
            #expect(text.hasPrefix(old))
            #expect(text.contains("## dates") && text.contains("## settings") && text.contains("## sources") && text.contains("### rest"))
            #expect(config.lines["done"] == ["我自己写的"])
        }
    }

    @Test func 保存后再读回来一致() throws {
        try withTempHome { _ in
            let config = Config()
            config.load()
            var settings = Config.Settings()
            settings.together = DateComponents(year: 2024, month: 2, day: 9)
            settings.birthday = DateComponents(month: 11, day: 3)
            settings.restMinutes = 45
            settings.nightHour = 0
            settings.morningSummary = false
            settings.eveningReminder = DateComponents(hour: 17, minute: 45)
            settings.notify = false
            settings.agentEnabled = true
            settings.agentBudget = 12.5
            settings.agentHotkey = "cmd+shift+j"
            settings.sources = ["calendar": 10, "my-script": 30, "gitlab-review": 0, "reminders": 0]
            config.save(settings, lines: ["done": ["耶"], "custom": ["自定义"]])
            let again = Config()
            again.load()
            #expect(again.together == DateComponents(year: 2024, month: 2, day: 9))
            #expect(again.birthday == DateComponents(month: 11, day: 3))
            #expect(again.restMinutes == 45)
            #expect(again.nightHour == 0)
            #expect(again.settings == settings)
            #expect(again.lines["done"] == ["耶"])
            #expect(again.lines["custom"] == ["自定义"])
        }
    }

    @Test func 台词里的天数占位符会被替换() throws {
        try withTempHome { _ in
            let config = Config()
            config.load()
            config.save(Config.Settings(), lines: ["together": ["第 {days} 天"]])
            #expect(config.randomLine(for: "together") == "第 ? 天")
        }
    }
}

struct HotkeySpecTests {
    @Test func 解析快捷键() {
        #expect(HotkeySpec("ctrl+alt+h")?.display == "⌃⌥H")
        #expect(HotkeySpec("cmd+shift+space")?.display == "⇧⌘空格")
        #expect(HotkeySpec("h") == nil)             // 没有修饰键
        #expect(HotkeySpec("shift+h") == nil)       // 只有 shift 会和打字冲突
        #expect(HotkeySpec("ctrl+alt+") == nil)
    }
}
