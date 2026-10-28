import Foundation

/// 随手记的一条：一个想法、一个地址、一句想记住的话
public struct Note: Codable, Identifiable, Equatable {
    public var id: String
    public var text: String
    public var createdAt: Date
    /// 谁记的：manual 窗口 / cli 命令行 / agent 聊天里她记的
    public var source: String

    public init(id: String = "n_" + UUID().uuidString.prefix(10).lowercased(), text: String, createdAt: Date = Date(),
                source: String = TodoSource.manual) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.source = source
    }

    /// 句子里的 #标签
    public var tags: [String] {
        let ns = text as NSString
        let regex = try? NSRegularExpression(pattern: "#([^\\s#，。,.!！?？]+)")
        return regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) } ?? []
    }
}

/// 随手记：~/.hebiu/notes.json，新的在前；只有桌宠写
public final class NoteStore {
    public let url: URL
    public private(set) var notes: [Note] = []
    public var onChange: (() -> Void)?

    public init(url: URL = Paths.dataDir.appendingPathComponent("notes.json")) {
        self.url = url
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        notes = (try? Data(contentsOf: url)).flatMap { try? d.decode([Note].self, from: $0) } ?? []
    }

    @discardableResult
    public func add(_ text: String, source: String = TodoSource.manual, now: Date = Date()) -> Note? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let note = Note(text: t, createdAt: now, source: source)
        notes.insert(note, at: 0)
        save()
        return note
    }

    public func update(_ id: String, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { notes.remove(at: i) } else { notes[i].text = t }
        save()
    }

    public func delete(_ id: String) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// 关键词（空格隔开）：对上的词越多越靠前，一样多时新的在前
    public func search(_ query: String, limit: Int = 8) -> [Note] {
        let words = query.split(whereSeparator: { $0.isWhitespace || $0 == "，" || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return Array(notes.prefix(limit)) }
        let scored = notes.compactMap { n -> (Note, Int)? in
            let hits = words.filter { n.text.localizedCaseInsensitiveContains($0) }.count
            return hits > 0 ? (n, hits) : nil
        }
        return Array(scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.createdAt > $1.0.createdAt }.map(\.0).prefix(limit))
    }

    /// 某一天记的（写日记用，凌晨 4 点换天）
    public func notes(on day: String) -> [Note] {
        let range = MemoryDay.range(day)
        return notes.filter { range.contains($0.createdAt) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(notes) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }
}
