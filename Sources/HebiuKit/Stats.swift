import Foundation

/// 小统计：每天摸了她几下、陪你干完几次活、完成几件待办、几个番茄、聊了几句。
/// 存在 ~/.hebiu/stats.json，只有桌宠写；按天记，凌晨 4 点换天（和她的日记一致）
public final class Stats {
    public enum Counter: String, Codable, CaseIterable {
        case taps           // 摸了她几下
        case claudeDone     // 陪你用 Claude 干完几次活
        case todosDone      // 完成几件待办
        case focus          // 专心完成几个番茄
        case chats          // 跟她说了几句
        case photos         // 看了几张合照
    }

    public typealias Day = [Counter: Int]

    struct Body: Codable {
        var days: [String: [String: Int]] = [:]
        var focusSessionIDs: Set<UUID>?
    }

    public let url: URL
    private var body = Body()
    private var saveScheduled = false

    public init(url: URL = Paths.dataDir.appendingPathComponent("stats.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(Body.self, from: data) { body = b }
    }

    public func bump(_ counter: Counter, by n: Int = 1, now: Date = Date()) {
        let day = MemoryDay.of(now)
        body.days[day, default: [:]][counter.rawValue, default: 0] += n
        scheduleSave()
    }

    /// Count each completed focus session once, including a recovered completion.
    @discardableResult
    public func recordFocusCompletion(id: UUID, at date: Date) throws -> Bool {
        var ids = body.focusSessionIDs ?? []
        guard ids.insert(id).inserted else { return false }
        let previous = body
        body.focusSessionIDs = ids
        body.days[MemoryDay.of(date), default: [:]][Counter.focus.rawValue, default: 0] += 1
        do { try write() } // Session ID and counter must survive together.
        catch { body = previous; throw error }
        return true
    }

    public func day(_ date: Date = Date()) -> Day {
        decode(body.days[MemoryDay.of(date)] ?? [:])
    }

    public func total() -> Day {
        body.days.values.reduce(into: Day()) { sum, d in
            for (k, v) in decode(d) { sum[k, default: 0] += v }
        }
    }

    /// 从第一次有记录到现在一共几天
    public var firstDay: String? { body.days.keys.min() }

    private func decode(_ raw: [String: Int]) -> Day {
        raw.reduce(into: Day()) { out, kv in if let c = Counter(rawValue: kv.key) { out[c] = kv.value } }
    }

    /// 摸她这种一秒好几下的不必每下都写盘，攒一秒写一次
    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.save() }
    }

    public func save() {
        saveScheduled = false
        try? write()
    }

    private func write() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(body).write(to: url, options: .atomic)
    }
}
