import Foundation

/// DeepSeek 价格（元 / 百万 tokens），官方调价时只改这里
public struct AgentPricing: Equatable {
    public var cacheHit: Decimal
    public var cacheMiss: Decimal
    public var output: Decimal

    /// deepseek-flash 高峰价；空闲时段半价
    public static let deepseekFlash = AgentPricing(cacheHit: Decimal(string: "0.04")!, cacheMiss: 2, output: 8)

    /// 北京时间周一至周五 9–12 点、14–18 点为高峰；法定节假日也按高峰算（多算不少算）
    public static func isPeak(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let weekday = cal.component(.weekday, from: date)      // 1 周日 … 7 周六
        guard (2...6).contains(weekday) else { return false }
        let hour = cal.component(.hour, from: date)
        return (9..<12).contains(hour) || (14..<18).contains(hour)
    }

    public func cost(_ usage: AgentUsage, at date: Date) -> Decimal {
        let perToken = Decimal(1) / 1_000_000
        let raw = (Decimal(usage.promptCacheHitTokens) * cacheHit + Decimal(usage.promptCacheMissTokens) * cacheMiss
            + Decimal(usage.completionTokens) * output) * perToken
        return AgentPricing.isPeak(date) ? raw : raw / 2
    }
}

/// 一次请求的用量，字段和 DeepSeek 返回的 usage 对应
public struct AgentUsage: Codable, Equatable {
    public var promptCacheHitTokens: Int
    public var promptCacheMissTokens: Int
    public var completionTokens: Int

    public init(promptCacheHitTokens: Int, promptCacheMissTokens: Int, completionTokens: Int) {
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
        self.completionTokens = completionTokens
    }

    enum CodingKeys: String, CodingKey {
        case promptCacheHitTokens = "prompt_cache_hit_tokens"
        case promptCacheMissTokens = "prompt_cache_miss_tokens"
        case completionTokens = "completion_tokens"
    }
}

/// 账本：~/.hebiu/agent/usage.jsonl，一行一次请求，只追加
public final class AgentLedger {
    public struct Entry: Codable, Equatable {
        public var time: Date
        public var model: String
        public var usage: AgentUsage
        public var costCNY: Decimal
        /// 花在哪：chat 聊天 / talk 主动说话 / lines 写台词 / memory 记忆；早期的记录没有
        public var purpose: String?

        enum CodingKeys: String, CodingKey {
            case time, model, usage, purpose
            case costCNY = "cost_cny"
        }
    }

    public enum Purpose: String, CaseIterable {
        case chat, talk, lines, memory

        public var title: String {
            switch self {
            case .chat: return "聊天"
            case .talk: return "主动说话"
            case .lines: return "写台词"
            case .memory: return "记忆"
            }
        }
    }

    /// 一天花了多少，按用途分
    public struct DaySpend: Equatable {
        public var day: Date
        public var total: Decimal
        public var byPurpose: [Purpose: Decimal]
        public var requests: Int
    }

    public let url: URL
    private let pricing: AgentPricing

    public init(url: URL = Paths.agentDir.appendingPathComponent("usage.jsonl"), pricing: AgentPricing = .deepseekFlash) {
        self.url = url
        self.pricing = pricing
    }

    /// 记一笔，返回这笔多少钱
    @discardableResult
    public func record(_ usage: AgentUsage, model: String, at date: Date = Date(), purpose: Purpose = .chat) -> Decimal {
        let cost = pricing.cost(usage, at: date)
        let entry = Entry(time: date, model: model, usage: usage, costCNY: cost, purpose: purpose.rawValue)
        guard var line = try? AgentLedger.encoder.encode(entry) else { return cost }
        line.append(0x0A)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
        return cost
    }

    public func entries() -> [Entry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? AgentLedger.decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    /// 某个自然月（本机时区）一共花了多少
    public func total(monthOf date: Date = Date(), calendar cal: Calendar = .current) -> Decimal {
        let target = cal.dateComponents([.year, .month], from: date)
        return entries().filter { cal.dateComponents([.year, .month], from: $0.time) == target }.reduce(0) { $0 + $1.costCNY }
    }

    public func total(dayOf date: Date = Date(), calendar cal: Calendar = .current) -> Decimal {
        entries().filter { cal.isDate($0.time, inSameDayAs: date) }.reduce(0) { $0 + $1.costCNY }
    }

    /// 最近 n 个自然日（含今天），旧的在前；没花钱的日子也列出来
    public func daily(last n: Int = 7, now: Date = Date(), calendar cal: Calendar = .current) -> [DaySpend] {
        let today = cal.startOfDay(for: now)
        let days = (0..<n).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        var out = days.map { DaySpend(day: $0, total: 0, byPurpose: [:], requests: 0) }
        for e in entries() {
            guard let i = days.firstIndex(where: { cal.isDate(e.time, inSameDayAs: $0) }) else { continue }
            let p = e.purpose.flatMap(Purpose.init(rawValue:)) ?? .chat
            out[i].total += e.costCNY
            out[i].byPurpose[p, default: 0] += e.costCNY
            out[i].requests += 1
        }
        return out
    }

    /// 本月还能不能用
    public func withinBudget(_ budget: Decimal, now: Date = Date()) -> Bool {
        total(monthOf: now) < budget
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
