import Foundation

/// 每晚整理记忆：补写没写的日记、顺手改写「对你的了解」，过完一周压成周记、过完一个月压成月记
extension AgentSession {
    public struct ConsolidateResult: Equatable {
        public var diaries: [String] = []
        public var weekly: String?
        public var monthly: String?
        public var failed = false

        public var wroteSomething: Bool { !diaries.isEmpty || weekly != nil || monthly != nil }
    }

    /// 按顺序做完该做的；中途请求失败就停下，下次再接着做
    public func consolidate() async -> ConsolidateResult {
        var result = ConsolidateResult()
        guard memoryEnabled() else { return result }
        for day in memory.pendingDiaryDays(now: now()) {
            switch await writeDiary(day) {
            case .wrote: result.diaries.append(day)
            case .nothing: break
            case .failed: result.failed = true; return result
            }
            memory.markDiaryDone(day)
        }
        if let week = memory.pendingWeek(now: now()) {
            let diaries = week.days.compactMap { d in memory.text(.diary, d).map { "\(d)：\($0)" } }
            if !diaries.isEmpty {
                guard let summary = await summarize("这一周（\(week.key)）的日记", diaries.joined(separator: "\n")) else {
                    result.failed = true
                    return result
                }
                memory.save(.weekly, week.key, text: summary)
                result.weekly = week.key
            }
            memory.markWeekDone(week.key)
        }
        if let month = memory.pendingMonth(now: now()) {
            let weeks = memory.entries(.weekly).filter { w in
                MemoryDay.weekDays(of: AgentSession.mondayOf(w.key) ?? "").contains { $0.hasPrefix(month) }
            }.reversed().map { "\($0.key)：\($0.text)" }
            let diaries = memory.entries(.diary).filter { $0.key.hasPrefix(month) }.reversed().map { "\($0.key)：\($0.text)" }
            let material = weeks.isEmpty ? diaries : weeks
            if !material.isEmpty {
                guard let summary = await summarize("这个月（\(month)）的周记和日记", material.joined(separator: "\n")) else {
                    result.failed = true
                    return result
                }
                memory.save(.monthly, month, text: summary)
                result.monthly = month
            }
            memory.markMonthDone(month)
        }
        return result
    }

    /// 一周回顾里「让她写一段」：这周的数字 + 这周的日记，3～5 句
    public func writeWeekReview(_ review: WeekReview) async -> String? {
        let diaries = review.days.compactMap { d in memory.text(.diary, d).map { "\(d)：\($0)" } }
        let material = review.material + (diaries.isEmpty ? "" : "\n\n这周的日记：\n" + diaries.joined(separator: "\n"))
        return await summarize("\(Config.he)这一周（\(review.key)）的情况", material)
    }

    /// 现在就写今天的日记（不记成已整理，明天会按全天重写一遍）；今天还没什么事时返回 nil
    public func writeTodayDiary() async -> Bool? {
        guard memoryEnabled() else { return false }
        switch await writeDiary(MemoryDay.of(now())) {
        case .wrote: return true
        case .nothing: return nil
        case .failed: return false
        }
    }

    enum DiaryOutcome { case wrote, nothing, failed }

    /// 写一天的日记并改写「对你的了解」；那天什么都没发生就不请求
    func writeDiary(_ day: String) async -> DiaryOutcome {
        guard let material = await dayMaterial(day) else { return .nothing }
        guard ledger.withinBudget(budget(), now: now()), let key = keyProvider() else { return .failed }
        let facts = memory.facts()
        let messages: [[String: Any]] = [
            ["role": "system", "content": "你是住在\(Config.he)电脑桌面上的桌宠（你是谁、什么性格、和\(Config.he)什么关系，看下面的人设），每晚睡前写日记，顺便整理你对\(Config.he)的了解。\n\n" + persona()],
            ["role": "user", "content": """
            下面是 \(day) 这一天的事：
            \(material)

            你现在对\(Config.he)的了解：
            \(facts.isEmpty ? "（还没有）" : facts.map { "- \($0)" }.joined(separator: "\n"))

            请做两件事，只输出一个 JSON 对象 {"diary": "...", "facts": ["...", ...]}：
            1. diary：用你的口吻写这天的日记，3～5 句、不超过 150 字：\(Config.he)做了什么、聊了什么、心情怎样、有什么要记着的。只写上面出现过的事，不要编。
            2. facts：改写后的完整「了解」列表。规则：
               - 只留以后用得上的、比较稳定的事：喜好、习惯和作息、在意的人和日子、正在忙的事、说过的愿望
               - 每条一句话，用「\(Config.he)」开头，不超过 40 个字；最多 \(AgentMemory.maxFacts) 条
               - 和原来重复的合并；过时的改掉或删掉（比如做完了的事改成「做完了」）；今天没提到的旧条目原样保留
               - 具体哪天要做的事、某条待办的进度不记（待办清单已经管着）；一次性的小事不记
               - 密码、账号、钱数、公司客户和内部信息不记
               - 宁缺毋滥：这天没有新的了解，就把原来的列表原样返回
               例：✓「\(Config.he)常写代码到半夜，要催\(Config.he)睡」✓「\(Config.he)妈妈的生日是 3 月 8 日」✓「\(Config.he)最近在给我做记忆功能」
                   ✗「\(Config.he)明天三点要给妈妈打电话」✗「\(Config.he)今天交完周报了」（这些是待办，不是了解）
            """],
        ]
        guard let reply = try? await client.chat(messages: messages, tools: [], key: key, json: true) else { return .failed }
        ledger.record(reply.usage, model: DeepSeekClient.model, at: now(), purpose: .memory)
        guard let parsed = AgentSession.parseDiary(reply.content) else { return .failed }
        memory.save(.diary, day, text: parsed.diary)
        // 模型偶尔会把旧的一股脑丢掉：一条都没返回时保留原来的
        if !(parsed.facts.isEmpty && !facts.isEmpty) { memory.saveFacts(parsed.facts) }
        Log.write("memory diary \(day): \(parsed.diary.count) chars, \(parsed.facts.count) facts")
        return .wrote
    }

    /// 这一天的材料：聊天、她帮着做的事、完成的待办、用 Claude 的时间；都没有就返回 nil
    func dayMaterial(_ day: String) async -> String? {
        let range = MemoryDay.range(day)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        var parts: [String] = []

        let chat = chatLog.lines(in: range).compactMap { line -> String? in
            switch line.role {
            case "user": return "[\(f.string(from: line.time))] \(Config.he)：\(line.content)"
            case "assistant": return "[\(f.string(from: line.time))] 你：\(line.content)"
            case "action": return "[\(f.string(from: line.time))] （你帮\(Config.he)\(line.content)）"
            default: return nil
            }
        }
        if !chat.isEmpty {
            // 太长只留最后一段，控制花费
            var text = chat.suffix(150).joined(separator: "\n")
            if text.count > 6000 { text = String(text.suffix(6000)) }
            parts.append("你们的聊天：\n" + text)
        }

        var done: [String] = []
        await onMain {
            done = self.store.items
                .filter { AgentPrivacy.isShareable($0) && ($0.doneAt.map(range.contains) ?? false) }
                .map(\.title)
        }
        if !done.isEmpty { parts.append("\(Config.he)完成的待办：" + done.prefix(20).joined(separator: "、")) }
        var habitsDone: [String] = []
        await onMain { habitsDone = self.habits?.done(on: day).map(\.title) ?? [] }
        if !habitsDone.isEmpty { parts.append("\(Config.he)打卡的习惯：" + habitsDone.joined(separator: "、")) }
        var mood: Mood?
        await onMain { mood = self.moods?.mood(on: day) }
        if let mood { parts.append("\(Config.he)记的心情：\(mood.emoji)\(mood.name)" + (mood.note.isEmpty ? "" : "，\(mood.note)")) }
        var noted: [String] = []
        await onMain { noted = self.notes?.notes(on: day).map(\.text) ?? [] }
        if !noted.isEmpty { parts.append("\(Config.he)随手记下的：\n" + noted.prefix(20).map { "- " + String($0.prefix(120)) }.joined(separator: "\n")) }

        if activityEnabled(), let activity = ClaudeActivity.of(day: day, events: events).summary {
            parts.append("\(Config.he)" + activity)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// 把一段日记压成 3～5 句的总结
    func summarize(_ what: String, _ material: String) async -> String? {
        guard ledger.withinBudget(budget(), now: now()), let key = keyProvider() else { return nil }
        let messages: [[String: Any]] = [
            ["role": "system", "content": "你是住在\(Config.he)电脑桌面上的桌宠（你是谁、什么性格、和\(Config.he)什么关系，看下面的人设）。\n\n" + persona()],
            ["role": "user", "content": """
            下面是\(what)：
            \(material)

            用你的口吻把它总结成 3～5 句、不超过 150 字：\(Config.he)主要忙了什么、状态怎样、发生了哪些值得记住的事。只写里面出现过的事。
            只输出一个 JSON 对象 {"summary": "..."}。
            """],
        ]
        guard let reply = try? await client.chat(messages: messages, tools: [], key: key, json: true) else { return nil }
        ledger.record(reply.usage, model: DeepSeekClient.model, at: now(), purpose: .memory)
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(reply.content.utf8))) as? [String: Any],
              let summary = (obj["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty
        else { return nil }
        return summary
    }

    static func parseDiary(_ text: String) -> (diary: String, facts: [String])? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let diary = (obj["diary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !diary.isEmpty
        else { return nil }
        let facts = (obj["facts"] as? [String] ?? []).filter { !AgentMemory.isDated($0) }
        return (diary, AgentMemory.clean(facts))
    }

    /// 2026-W43 → 那周周一
    static func mondayOf(_ weekKey: String) -> String? {
        let parts = weekKey.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1].dropFirst()) else { return nil }
        var c = DateComponents()
        c.yearForWeekOfYear = year
        c.weekOfYear = week
        c.weekday = 2
        c.hour = 12
        guard let d = MemoryDay.calendar.date(from: c) else { return nil }
        return MemoryDay.formatter.string(from: d)
    }
}
