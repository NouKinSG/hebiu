import Foundation

/// 会话持久化。实现持有完整列表，`append` 后立即落盘（或保存在内存）。
public protocol SessionStore: AnyObject {
    func load() throws -> [FocusSession]
    func append(_ session: FocusSession) throws
}

/// `{"version":1,"sessions":[…]}` 形式的 JSON 文件存储。
///
/// - 文件不存在 → 空列表。
/// - 无法解析或版本未知 → 原文件改名为 `sessions.corrupt-<yyyyMMdd-HHmmss>.json`
///   留底，从空列表开始；绝不覆盖原文件。
/// - 文件存在但读不出（权限等）→ `load` 抛错；此时 `append` 也抛错且不写入，
///   记录暂存在内存，等文件能读时并入并落盘。
/// - 每次 `append` 整份原子写入；写入失败时记录仍留在内存，下次成功写入时一并落盘。
public final class FileSessionStore: SessionStore {
    private struct Envelope: Codable {
        let version: Int
        let sessions: [FocusSession]
    }

    static let currentVersion = 1

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusOnYourself", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    public let url: URL
    /// 最近一次损坏留底的路径。
    public private(set) var lastBackupURL: URL?

    private let now: () -> Date
    private var cache: [FocusSession]?
    /// 文件暂时读不出（权限等）时先存在这里，等能读时并入并落盘。
    private var pending: [FocusSession] = []

    public init(url: URL, now: @escaping () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    public func load() throws -> [FocusSession] {
        if let cache { return cache }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            cache = []
            return []
        }

        let data = try Data(contentsOf: url)
        if let envelope = try? Self.decoder.decode(Envelope.self, from: data),
           envelope.version == Self.currentVersion {
            cache = envelope.sessions
            return envelope.sessions
        }

        try backUpUnreadableFile()
        cache = []
        return []
    }

    public func append(_ session: FocusSession) throws {
        pending.append(session)
        // 读不出时绝不写入，以免覆盖原文件；记录留在 pending 等下次。
        var sessions = try load()
        sessions.append(contentsOf: pending)
        pending.removeAll()
        cache = sessions

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(Envelope(version: Self.currentVersion, sessions: sessions))
        try data.write(to: url, options: .atomic)
    }

    private func backUpUnreadableFile() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())

        let directory = url.deletingLastPathComponent()
        var backup = directory.appendingPathComponent("sessions.corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: backup.path) {
            backup = directory.appendingPathComponent(
                "sessions.corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json"
            )
        }
        try FileManager.default.moveItem(at: url, to: backup)
        lastBackupURL = backup
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// 仅存在内存里的存储，用于测试与演示模式。
public final class InMemorySessionStore: SessionStore {
    private var sessions: [FocusSession]

    public init(seed: [FocusSession] = []) {
        self.sessions = seed
    }

    public func load() throws -> [FocusSession] {
        sessions
    }

    public func append(_ session: FocusSession) throws {
        sessions.append(session)
    }
}
