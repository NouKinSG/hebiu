import Foundation

/// 收件箱：命令行和数据来源把要做的事放进 ~/.hebiu/inbox/，由桌宠统一写进待办。
///
/// - 一次性命令：inbox/*.json，处理完就删
///   {"op": "add", "text": "明天 10:00 交周报"}
///   {"op": "add", "title": "交周报", "due": "2026-10-26T10:00:00+08:00", "note": "…", "link": "…"}
///   {"op": "done" | "undo" | "delete", "match": "周报"}     match 可以是待办 id，也可以是标题里的字
/// - 来源快照：inbox/sources/<来源名>.json，每次同步整份覆盖，桌宠按快照对账（见 TodoStore.reconcile）
///   {"source": "gitlab", "items": [{"id": "mr-123", "title": "Review: …", "link": "…"}]}
public final class TodoInbox {
    public struct Command: Codable {
        public var op: String
        public var text: String?
        public var title: String?
        public var due: Date?
        public var dueHasTime: Bool?
        public var note: String?
        public var link: String?
        public var match: String?
        public var source: String?

        public init(op: String, text: String? = nil, title: String? = nil, due: Date? = nil, dueHasTime: Bool? = nil,
                    note: String? = nil, link: String? = nil, match: String? = nil, source: String? = nil) {
            self.op = op
            self.text = text
            self.title = title
            self.due = due
            self.dueHasTime = dueHasTime
            self.note = note
            self.link = link
            self.match = match
            self.source = source
        }
    }

    public struct Snapshot: Codable {
        public var source: String
        public var items: [SourceItem]
        public init(source: String, items: [SourceItem]) {
            self.source = source
            self.items = items
        }
    }

    /// 处理结果，给桌宠决定要不要说点什么
    public enum Outcome: Equatable {
        case added(TodoItem)
        case completed(TodoItem)
        case reopened(TodoItem)
        case deleted(String)
        case synced(source: String, added: Int, updated: Int, removed: Int)
        /// 命令行 hebiu say：交给 AI 大脑
        case say(String)
        /// 命令行 hebiu note：记一条随手记
        case note(String)
        case failed(String)
    }

    public let dir: URL
    private let store: TodoStore
    private var snapshotStamps: [String: Date] = [:]

    public init(dir: URL = Paths.inbox, store: TodoStore) {
        self.dir = dir
        self.store = store
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("sources"), withIntermediateDirectories: true)
    }

    /// 处理收件箱里所有新东西
    @discardableResult
    public func process(now: Date = Date()) -> [Outcome] {
        processCommands(now: now) + processSnapshots(now: now)
    }

    private func processCommands(now: Date) -> [Outcome] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var outcomes: [Outcome] = []
        for file in files {
            defer { try? fm.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let command = try? TodoStore.decoder.decode(Command.self, from: data) else {
                quarantine(file)
                outcomes.append(.failed("看不懂的文件：\(file.lastPathComponent)"))
                continue
            }
            outcomes.append(apply(command, now: now))
        }
        return outcomes
    }

    /// 坏文件挪到 inbox/bad/ 留着排查，不反复报错
    private func quarantine(_ file: URL) {
        let bad = dir.appendingPathComponent("bad", isDirectory: true)
        try? FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: file, to: bad.appendingPathComponent(file.lastPathComponent))
        Log.write("inbox: bad file \(file.lastPathComponent)")
    }

    public func apply(_ c: Command, now: Date = Date()) -> Outcome {
        let source = c.source ?? TodoSource.cli
        switch c.op {
        case "say":
            guard let text = c.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .failed("要说什么？") }
            return .say(text)
        case "note":
            guard let text = c.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return .failed("要记什么？") }
            return .note(text)
        case "add":
            if let text = c.text, let item = store.add(text: text, source: source, now: now) {
                return .added(item)
            }
            guard let title = c.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .failed("待办没有内容")
            }
            let item = store.add(TodoItem(title: title, note: c.note ?? "", due: c.due, dueHasTime: c.dueHasTime ?? (c.due != nil),
                                          createdAt: now, source: source, link: c.link))
            return .added(item)
        case "done", "undo", "delete":
            guard let match = c.match, !match.isEmpty else { return .failed("没说是哪一条") }
            let found: TodoItem?
            switch c.op {
            case "undo": found = store.findDone(matching: match)
            case "delete": found = store.findOpen(matching: match) ?? store.findDone(matching: match)
            default: found = store.findOpen(matching: match)
            }
            guard let item = found else { return .failed("找不到或不止一条：\(match)") }
            switch c.op {
            case "done":
                store.complete(item.id, at: now)
                return .completed(store.item(item.id) ?? item)
            case "undo":
                store.uncomplete(item.id)
                return .reopened(store.item(item.id) ?? item)
            default:
                store.delete(item.id)
                return .deleted(item.title)
            }
        default:
            return .failed("不认识的操作：\(c.op)")
        }
    }

    /// 来源快照只在文件变了时处理
    private func processSnapshots(now: Date) -> [Outcome] {
        let fm = FileManager.default
        let sourcesDir = dir.appendingPathComponent("sources", isDirectory: true)
        let files = ((try? fm.contentsOfDirectory(at: sourcesDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
        var outcomes: [Outcome] = []
        for file in files {
            let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let stamp, snapshotStamps[file.lastPathComponent] != stamp else { continue }
            snapshotStamps[file.lastPathComponent] = stamp
            guard let data = try? Data(contentsOf: file),
                  let snapshot = try? TodoStore.decoder.decode(Snapshot.self, from: data) else {
                outcomes.append(.failed("来源文件看不懂：\(file.lastPathComponent)"))
                Log.write("inbox: bad snapshot \(file.lastPathComponent)")
                continue
            }
            let r = store.reconcile(source: snapshot.source, snapshot: snapshot.items, now: now)
            outcomes.append(.synced(source: snapshot.source, added: r.added, updated: r.updated, removed: r.removed))
        }
        return outcomes
    }

    // MARK: - 写入（命令行、来源用）

    private static var sequence = 0
    private static let sequenceLock = NSLock()

    /// 放一条命令进收件箱。先写临时名再改名，桌宠不会读到写了一半的文件
    public static func post(_ command: Command, dir: URL = Paths.inbox) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 微秒时间 + 进程内递增序号：同一时刻连发的命令也按发送顺序处理
        sequenceLock.lock()
        sequence += 1
        let seq = sequence
        sequenceLock.unlock()
        let micros = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let name = String(format: "%016llu-%04d-%@.json", micros, seq % 10000, String(UUID().uuidString.prefix(6)))
        let tmp = dir.appendingPathComponent(".\(name)")
        try TodoStore.encoder.encode(command).write(to: tmp)
        try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(name))
    }

    /// 写一份来源快照（整份覆盖）
    public static func publish(_ snapshot: Snapshot, dir: URL = Paths.inbox) throws {
        let sourcesDir = dir.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let safe = snapshot.source.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        try TodoStore.encoder.encode(snapshot).write(to: sourcesDir.appendingPathComponent("\(safe).json"), options: .atomic)
    }
}
