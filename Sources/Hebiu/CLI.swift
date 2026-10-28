import AppKit
import HebiuKit

/// 带参数运行时是命令行工具：hebiu done、hebiu todo add "明天 10:00 交周报"……
/// 改待办的命令都放进收件箱交给桌宠处理，命令行自己只读不写 todo.json
enum CLI {
    static let usage = """
    用法：
      hebiu <动作>                    让\(Her.she)做个动作，如 done / error / pat / love（hebiu actions 看全部）
      hebiu say <一句话>               和\(Her.she)说话（要先打开 AI 大脑），等\(Her.she)回答后打印出来
      hebiu todo                      列出没完成的待办
      hebiu todo add <一句话>          加一条，时间自动识别：hebiu todo add 明天 10:00 交周报
      hebiu todo done <id或标题里的字>  打勾
      hebiu todo undo <id或标题里的字>  取消打勾
      hebiu todo rm <id或标题里的字>    删除
      hebiu todo all                  列出全部（含已完成）
      hebiu todo json                 以 JSON 输出全部（给脚本用）
      hebiu todo open                 打开待办窗口
      hebiu note <一句话>              记一条随手记；hebiu note 看最近的，hebiu note find 关键词 找
      hebiu habit                     看今天的习惯；hebiu habit done 喝水 打卡
      hebiu photo                     弹一张你们的合照（要先在「我们」页选文件夹）
      hebiu focus [分钟]               开始一个番茄（默认按设置，25 分钟）；hebiu focus stop 结束
      hebiu memory                    看\(Her.she)记得的事（对你的了解 + 最近的日记）
      hebiu memory sync               补整理没写的日记、周记、月记
      hebiu diary                     现在就写今天的日记
      hebiu source                    列出数据来源
      hebiu source run <名字>          立刻同步一次（脚本来源会打印结果）
      hebiu open                      打开主窗口；hebiu open-todos / open-actions / open-settings … 打开某一页
      hebiu settings                  打开设置页
      hebiu version                   版本号
    """

    /// 返回 nil 表示不是命令行调用，继续启动桌宠
    static func run(_ args: [String]) -> Int32? {
        guard let first = args.first, !first.hasPrefix("-") else { return nil }
        Paths.prepare()
        // 提示里的「她 / 它」跟着形象走
        let settings = Config()
        settings.load()
        Character.load(settings.settings.character, quiet: true)
        switch first {
        case "help", "--help":
            print(usage)
        case "version":
            print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
        case "actions":
            print((Character.pack.actions.keys.sorted() + ["idle"]).joined(separator: " "))
        case "todo":
            return todo(Array(args.dropFirst()))
        case "say":
            return say(args.dropFirst().joined(separator: " "))
        case "source", "sources":
            return source(Array(args.dropFirst()))
        case "memory":
            if args.dropFirst().first == "sync" { sendEvent("memory-sync"); print("让\(Her.she)去整理了，结果在「\(Her.she)记得的事」页") } else { printMemory() }
        case "focus":
            let arg = args.dropFirst().first ?? ""
            if arg == "stop" { sendEvent("focus-stop"); print("番茄钟结束了") }
            else if let m = Int(arg), m > 0 { sendEvent("focus-\(m)"); print("开始专心 \(m) 分钟") }
            else { sendEvent("focus"); print("开始专心") }
        case "note", "notes":
            let rest = Array(args.dropFirst())
            let f = DateFormatter()
            f.dateFormat = "M/d HH:mm"
            if rest.isEmpty || rest.first == "find" {
                let list = rest.isEmpty ? Array(NoteStore().notes.prefix(10)) : NoteStore().search(rest.dropFirst().joined(separator: " "))
                if list.isEmpty { print(rest.isEmpty ? "还没有随手记" : "没找到") }
                for n in list { print("\(f.string(from: n.createdAt))  \(n.text)") }
            } else {
                guard petIsRunning() else { fail("hebiu 没在运行"); return 1 }
                do { try TodoInbox.post(.init(op: "note", text: rest.joined(separator: " "))) } catch { fail("写入收件箱失败：\(error)"); return 1 }
                print("记下啦")
            }
        case "habit", "habits":
            let store = HabitStore()
            let args = Array(args.dropFirst())
            if args.first == "done", args.count > 1 {
                guard let h = store.find(args.dropFirst().joined(separator: " ")) else { fail("没有这个习惯"); return 1 }
                sendEvent("habit-\(h.id)")
                print("\(h.emoji) \(h.title) 打卡（再运行一次是取消）")
            } else {
                let today = store.today()
                if today.isEmpty { print("今天没有要打卡的习惯") }
                for item in today { print("\(item.done ? "[x]" : "[ ]") \(item.habit.emoji) \(item.habit.title)  连续 \(store.streak(item.habit.id)) 天") }
            }
        case "diary":
            sendEvent("diary")
            print("\(Her.she)去写今天的日记了，写好后 hebiu memory 能看到")
        default:
            sendEvent(first)
        }
        return 0
    }

    private static func printMemory() {
        let memory = AgentMemory()
        let facts = memory.facts()
        print("对你的了解（\(facts.count)）：")
        print(facts.isEmpty ? "  （还没有）" : facts.map { "  - \($0)" }.joined(separator: "\n"))
        let diaries = memory.entries(.diary).prefix(5)
        print("\n最近的日记：")
        print(diaries.isEmpty ? "  （还没有）" : diaries.map { "  \($0.key)  \($0.text)" }.joined(separator: "\n"))
    }

    static func sendEvent(_ event: String) {
        let line = "\(Int(Date().timeIntervalSince1970)) \(event)\n"
        if let handle = try? FileHandle(forWritingTo: Paths.events) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }

    private static func source(_ args: [String]) -> Int32 {
        let config = Config()
        config.load()
        let scripts = ScriptSource.installed()
        guard args.first == "run", args.count > 1 else {
            let names = SourceCatalog.known.map(\.name) + scripts.keys.filter { SourceCatalog.entry($0) == nil }.sorted()
            for name in names {
                let minutes = config.settings.sources[name] ?? 0
                let state = minutes > 0 ? "每 \(minutes) 分钟" : "关闭"
                let entry = SourceCatalog.entry(name)
                let missing = entry?.builtIn == false && scripts[name] == nil ? "（脚本没装）" : ""
                print("\(name)  \(state)  \(entry.map { "\($0.title)：\($0.detail)" } ?? "自己写的来源")\(missing)")
            }
            return 0
        }
        let name = args[1]
        if SourceCatalog.entry(name)?.builtIn == true {
            sendEvent("sync-\(name)")      // 日历、提醒事项要用桌宠的系统权限，交给它去同步
            print("已让 hebiu 同步 \(name)")
            return 0
        }
        guard let url = scripts[name] else { fail("~/.hebiu/sources/ 里没有 \(name)"); return 1 }
        do {
            let items = try ScriptSource.run(url, name: name)
            try TodoInbox.publish(.init(source: name, items: items))
            print("\(name)：\(items.count) 条")
            for item in items { print("  - \(item.title)" + (item.due.map { "  " + TodoFormat.describe($0, hasTime: item.dueHasTime) } ?? "")) }
            return 0
        } catch {
            fail("\(name) 失败：\(error)")
            return 1
        }
    }

    /// 放进收件箱交给桌宠，等对话记录里出现她的回答（最多 40 秒）
    private static func say(_ text: String) -> Int32 {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { fail("要说什么？例：hebiu say 我今天还有什么事"); return 1 }
        guard petIsRunning() else { fail("hebiu 没在运行"); return 1 }
        let log = AgentChatLog()
        let before = log.all().count
        do { try TodoInbox.post(.init(op: "say", text: text)) } catch { fail("写入收件箱失败：\(error)"); return 1 }
        let deadline = Date().addingTimeInterval(40)
        var printed = 0
        while Date() < deadline {
            let new = log.all().dropFirst(before)
            let actions = new.filter { $0.role == "action" }
            for line in actions.dropFirst(printed) { print("  ✓ \(line.content)") }
            printed = actions.count
            if let answer = new.last(where: { $0.role == "assistant" || $0.role == "error" }) {
                print(answer.content)
                return answer.role == "error" ? 1 : 0
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        let config = Config()
        config.load()
        fail(config.settings.agentEnabled ? "等了 40 秒没回答，看看 ~/.hebiu/hebiu.log" : "AI 大脑没打开：hebiu open-brain")
        return 1
    }

    private static func todo(_ args: [String]) -> Int32 {
        let sub = args.first ?? "list"
        let rest = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        switch sub {
        case "list", "ls":
            printList(includeDone: false)
        case "all":
            printList(includeDone: true)
        case "json":
            let items = TodoStore.readItems()
            if let data = try? JSONSerialization.data(withJSONObject: (try? JSONSerialization.jsonObject(with: TodoStore.encode(items))) ?? [],
                                                      options: [.prettyPrinted, .withoutEscapingSlashes]) {
                print(String(decoding: data, as: UTF8.self))
            }
        case "open":
            sendEvent("todo")
        case "add":
            guard !rest.isEmpty, let parsed = TodoStore.parse(rest) else { fail("要加什么？例：hebiu todo add 明天 10:00 交周报"); return 1 }
            return post(.init(op: "add", text: rest)) { _ in
                let when = parsed.due.map { "（\(parsed.rule.map { $0.display + "，下一次 " } ?? "")\(TodoFormat.describe($0, hasTime: parsed.hasTime))）" } ?? ""
                return "已加：\(parsed.title)\(when)"
            }
        case "done", "undo", "rm", "delete":
            guard !rest.isEmpty else { fail("要\(sub)哪一条？写 id 或标题里的字"); return 1 }
            let op = sub == "rm" ? "delete" : sub
            return post(.init(op: op, match: rest)) { items in
                let verb = ["done": "已完成", "undo": "已取消打勾", "delete": "已删除"][op] ?? op
                // 桌宠处理完后再查一次，确认真的变了
                switch op {
                case "done": return items.contains { $0.isDone && ($0.id == rest || $0.title.contains(rest)) } ? "\(verb)：\(rest)" : nil
                case "undo": return items.contains { !$0.isDone && ($0.id == rest || $0.title.contains(rest)) } ? "\(verb)：\(rest)" : nil
                default: return "\(verb)：\(rest)"
                }
            }
        default:
            fail("不认识 todo \(sub)\n\n\(usage)")
            return 1
        }
        return 0
    }

    /// 放进收件箱，等桌宠处理（最多 3 秒）；桌宠没开就提示开了以后会处理
    private static func post(_ command: TodoInbox.Command, confirm: ([TodoItem]) -> String?) -> Int32 {
        do {
            try TodoInbox.post(command)
        } catch {
            fail("写入收件箱失败：\(error)")
            return 1
        }
        guard petIsRunning() else {
            print("hebiu 没在运行，已放进收件箱，打开后会处理")
            return 0
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let pending = ((try? FileManager.default.contentsOfDirectory(atPath: Paths.inbox.path)) ?? []).filter { $0.hasSuffix(".json") }
            if pending.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if let message = confirm(TodoStore.readItems()) {
            print(message)
            return 0
        }
        fail("没找到，或者有不止一条对得上（hebiu todo 看 id，用 id 更准）")
        return 1
    }

    private static func petIsRunning() -> Bool {
        let id = Bundle.main.bundleIdentifier ?? "io.github.hebiu"
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.processIdentifier != getpid() }
    }

    private static func printList(includeDone: Bool) {
        let items = TodoStore.readItems().filter { includeDone || !$0.isDone }
        guard !items.isEmpty else { print(includeDone ? "没有待办" : "没有待办，全部搞定啦"); return }
        for item in TodoQuery.sorted(items) {
            let box = item.isDone ? "[x]" : "[ ]"
            let when = item.due.map { "  " + TodoFormat.describe($0, hasTime: item.dueHasTime) } ?? ""
            let from = ([TodoSource.manual, TodoSource.cli].contains(item.source) ? "" : "  · \(TodoSource.displayName(item.source))")
                + (RepeatRule(item.repeatRule).map { "  🔁 \($0.display)" } ?? "")
            print("\(box) \(item.title)\(when)\(from)  (\(item.id))")
        }
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
