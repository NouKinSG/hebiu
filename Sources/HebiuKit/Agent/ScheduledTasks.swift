import Foundation

/// 定时让她做的事：「每天早上 8 点用一句话鼓励我」「每周五下午 6 点帮我总结这周」。
/// 到点了她结合今天的情况说一句（要打开 AI 大脑）
public struct ScheduledTask: Codable, Identifiable, Equatable {
    public var id: String
    /// 让她做什么（原话去掉时间）
    public var prompt: String
    public var rule: String
    /// HH:mm
    public var time: String
    public var enabled: Bool
    /// 最后一次做是哪天（yyyy-MM-dd，自然日）
    public var lastRun: String?

    public init(id: String = "s_" + UUID().uuidString.prefix(8).lowercased(), prompt: String, rule: String, time: String,
                enabled: Bool = true, lastRun: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.rule = rule
        self.time = time
        self.enabled = enabled
        self.lastRun = lastRun
    }

    public var repeatRule: RepeatRule { RepeatRule(rule) ?? .daily }
    public var detail: String { "\(repeatRule.display) \(time)" }

    /// 「每天早上8点 用一句话鼓励我」；没说重复就是每天，没说钟点认不出
    public static func parse(_ text: String, now: Date = Date()) -> ScheduledTask? {
        var rest = text
        var rule = RepeatRule.daily
        if let r = RepeatRule.extract(text) {
            rule = r.rule
            rest = r.rest
        }
        guard let p = TimeParser.parse(rest, now: now), p.hasTime, let due = p.due else { return nil }
        let prompt = p.title.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。：:").union(.whitespaces))
        guard !prompt.isEmpty else { return nil }
        let cal = Calendar.current
        return ScheduledTask(prompt: prompt, rule: rule.text,
                             time: String(format: "%02d:%02d", cal.component(.hour, from: due), cal.component(.minute, from: due)))
    }
}

/// ~/.hebiu/agent/tasks.json
public final class ScheduledTaskStore {
    public let url: URL
    public private(set) var tasks: [ScheduledTask] = []
    public var onChange: (() -> Void)?

    public init(url: URL = Paths.agentDir.appendingPathComponent("tasks.json")) {
        self.url = url
        tasks = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([ScheduledTask].self, from: $0) } ?? []
    }

    @discardableResult
    public func add(_ task: ScheduledTask) -> ScheduledTask {
        tasks.append(task)
        save()
        return task
    }

    public func delete(_ id: String) {
        tasks.removeAll { $0.id == id }
        save()
    }

    public func setEnabled(_ id: String, _ on: Bool) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].enabled = on
        save()
    }

    /// 到点该做的：今天符合规则、过了钟点不到两小时、今天还没做过。返回后记成做过
    public func due(now: Date = Date(), calendar cal: Calendar = .current) -> [ScheduledTask] {
        let today = MemoryDay.formatter.string(from: now)
        let minutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var out: [ScheduledTask] = []
        for i in tasks.indices where tasks[i].enabled && tasks[i].lastRun != today && tasks[i].repeatRule.matches(now, calendar: cal) {
            let p = tasks[i].time.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2 else { continue }
            let target = p[0] * 60 + p[1]
            guard minutes >= target, minutes < target + 120 else { continue }
            tasks[i].lastRun = today
            out.append(tasks[i])
        }
        if !out.isEmpty { save() }
        return out
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? e.encode(tasks) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }
}
