import Foundation

/// 对话记录：~/.hebiu/agent/chat.jsonl，一行一条，只追加；超过 2000 行时把较早的一半挪到 chat-<日期>.jsonl
public final class AgentChatLog {
    public struct Line: Codable, Equatable, Identifiable {
        public var time: Date
        public var role: String          // user / assistant / action / error
        public var content: String
        public var expression: String?
        public var id: String { "\(time.timeIntervalSince1970)-\(role)-\(content.hashValue)" }

        public init(time: Date, role: String, content: String, expression: String? = nil) {
            self.time = time
            self.role = role
            self.content = content
            self.expression = expression
        }
    }

    public let url: URL
    public static let maxLines = 2000

    public init(url: URL = Paths.agentDir.appendingPathComponent("chat.jsonl")) {
        self.url = url
    }

    public func append(_ line: Line) {
        guard var data = try? AgentLedger.encoder.encode(line) else { return }
        data.append(0x0A)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        rotateIfNeeded()
    }

    public func all() -> [Line] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? AgentLedger.decoder.decode(Line.self, from: Data($0.utf8)) }
    }

    /// 某段时间里的记录，连同已经挪到 chat-<日期>.jsonl 的旧记录一起找
    public func lines(in range: Range<Date>) -> [Line] {
        let dir = url.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let archives = names.filter { $0.hasPrefix("chat-") && $0.hasSuffix(".jsonl") }.sorted().map { dir.appendingPathComponent($0) }
        return (archives + [url]).flatMap { AgentChatLog(url: $0).all() }
            .filter { range.contains($0.time) }
            .sorted { $0.time < $1.time }
    }

    /// 最近 n 条你和她的对话（不含操作记录），带给模型
    public func recentConversation(_ n: Int = 20) -> [Line] {
        Array(all().filter { $0.role == "user" || $0.role == "assistant" }.suffix(n))
    }

    private func rotateIfNeeded() {
        let lines = all()
        guard lines.count > AgentChatLog.maxLines else { return }
        let half = lines.count / 2
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let archive = url.deletingLastPathComponent().appendingPathComponent("chat-\(f.string(from: Date())).jsonl")
        func write(_ part: ArraySlice<Line>, to u: URL) {
            let text = part.compactMap { try? AgentLedger.encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        write(lines[..<half], to: archive)
        write(lines[half...], to: url)
    }
}
