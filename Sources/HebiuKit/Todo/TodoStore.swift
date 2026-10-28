import Foundation

/// 待办存储：~/.hebiu/todo.json。只有桌宠程序自己写这个文件，
/// 命令行和数据来源都通过收件箱（TodoInbox）交给它，避免两个进程同时写坏文件
public final class TodoStore {
    public static let schemaVersion = 1
    /// 已完成的待办保留几天
    public static let keepDoneDays = 7

    private struct FileBody: Codable {
        var version: Int
        var items: [TodoItem]
    }

    public let url: URL
    private let backupDir: URL
    public private(set) var items: [TodoItem] = []
    /// 内容变了（增删改、从磁盘重新读到新内容）时调用
    public var onChange: (() -> Void)?
    /// 一条待办从没完成变成完成时调用（窗口、命令行、她打勾都算）
    public var onCompleted: ((TodoItem) -> Void)?
    private var lastWrite: Date?

    public init(url: URL = Paths.todo, backupDir: URL = Paths.backup) {
        self.url = url
        self.backupDir = backupDir
        load()
    }

    // MARK: - 读写

    public func load() {
        load(keepOnFailure: false)
    }

    /// keepOnFailure：运行中重新读到坏文件时，保留内存里最后一份好的并写回去（坏文件挪到一边留着）
    private func load(keepOnFailure: Bool) {
        guard let data = try? Data(contentsOf: url) else {
            if !keepOnFailure { items = [] }
            lastWrite = modificationDate()
            return
        }
        do {
            let body = try TodoStore.decoder.decode(FileBody.self, from: data)
            if body.version > TodoStore.schemaVersion {
                Log.write("todo.json version \(body.version) is newer than this app (\(TodoStore.schemaVersion)), reading anyway")
            }
            items = body.items
        } catch {
            // 文件坏了：先挪到一边留证据，不覆盖，从空列表开始
            let broken = url.deletingLastPathComponent().appendingPathComponent("todo.broken-\(TodoStore.stamp()).json")
            try? FileManager.default.moveItem(at: url, to: broken)
            Log.write("todo.json unreadable (\(error)), moved to \(broken.lastPathComponent)")
            if keepOnFailure {
                save()
                return
            }
            items = []
        }
        lastWrite = modificationDate()
    }

    /// 文件还不存在就写一个空的（监听文件变化需要文件先存在）
    public func ensureFile() {
        if !FileManager.default.fileExists(atPath: url.path) { save() }
    }

    /// 文件被手动改过（不是自己写的）就重新读
    @discardableResult
    public func reloadIfChangedOnDisk() -> Bool {
        let m = modificationDate()
        guard m != lastWrite else { return false }
        load(keepOnFailure: true)
        onChange?()
        return true
    }

    private func save() {
        backupOncePerDay()
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try TodoStore.encoder.encode(FileBody(version: TodoStore.schemaVersion, items: items))
            try data.write(to: url, options: .atomic)
            lastWrite = modificationDate()
        } catch {
            Log.write("todo save failed: \(error)")
        }
        onChange?()
    }

    /// 每天第一次写之前，把当前文件复制一份到 backup/，保留最近 14 份
    private func backupOncePerDay() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let day = TodoStore.dayStamp()
        let target = backupDir.appendingPathComponent("todo-\(day).json")
        guard !fm.fileExists(atPath: target.path) else { return }
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: url, to: target)
        let old = ((try? fm.contentsOfDirectory(atPath: backupDir.path)) ?? [])
            .filter { $0.hasPrefix("todo-") && $0.hasSuffix(".json") }.sorted().dropLast(14)
        for name in old { try? fm.removeItem(at: backupDir.appendingPathComponent(name)) }
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - 增删改查

    public func item(_ id: String) -> TodoItem? { items.first { $0.id == id } }

    @discardableResult
    public func add(_ item: TodoItem) -> TodoItem {
        items.append(item)
        save()
        return item
    }

    /// 按一句话添加，自动识别里面的时间（「明天 10:00 交周报」）
    @discardableResult
    public func add(text: String, source: String = TodoSource.manual, now: Date = Date()) -> TodoItem? {
        guard let parsed = TodoStore.parse(text, now: now) else { return nil }
        return add(TodoItem(title: parsed.title, due: parsed.due, dueHasTime: parsed.hasTime, createdAt: now, source: source,
                            repeatRule: parsed.rule?.text))
    }

    /// 一句话 → 标题、第一次的时间、重复规则（「每周五下午五点 交周报」）
    public static func parse(_ text: String, now: Date = Date(), calendar cal: Calendar = .current)
        -> (title: String, due: Date?, hasTime: Bool, rule: RepeatRule?)? {
        guard let (rule, rest) = RepeatRule.extract(text) else {
            return TimeParser.parse(text, now: now, calendar: cal).map { ($0.title, $0.due, $0.hasTime, nil) }
        }
        guard let parsed = TimeParser.parse(rest, now: now, calendar: cal) else { return nil }
        let hour = parsed.hasTime ? parsed.due.map { cal.component(.hour, from: $0) } : nil
        let minute = parsed.hasTime ? parsed.due.map { cal.component(.minute, from: $0) } ?? 0 : 0
        // 只有日期时今天也算；有钟点时要晚于现在
        let after = hour == nil ? cal.startOfDay(for: now).addingTimeInterval(-1) : now
        let due = rule.next(after: after, hour: hour, minute: minute, calendar: cal)
        return (parsed.title, due, hour != nil, rule)
    }

    /// 改一条；改了提醒时间就重新提醒
    public func update(_ id: String, _ change: (inout TodoItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items[i]
        change(&item)
        if item.due != items[i].due || item.dueHasTime != items[i].dueHasTime { item.remindedAt = nil }
        guard item != items[i] else { return }
        items[i] = item
        save()
    }

    public func complete(_ id: String, at now: Date = Date(), calendar cal: Calendar = .current) {
        guard let before = item(id), before.doneAt == nil else { return }
        update(id) { $0.doneAt = now }
        if let after = item(id) { onCompleted?(after) }
        scheduleNext(after: before, now: now, calendar: cal)
    }

    /// 重复待办打勾后，排上下一次（已经排过就不重复排）
    private func scheduleNext(after done: TodoItem, now: Date, calendar cal: Calendar) {
        guard let rule = RepeatRule(done.repeatRule), !items.contains(where: { $0.repeatOf == done.id }) else { return }
        let hour = done.dueHasTime ? done.due.map { cal.component(.hour, from: $0) } : nil
        let minute = done.dueHasTime ? done.due.map { cal.component(.minute, from: $0) } ?? 0 : 0
        // 拖了几天才打勾的，下一次从今天往后排；只有日期的从明天起排
        var from = max(done.due ?? now, now)
        if hour == nil { from = cal.startOfDay(for: from) }
        guard let due = rule.next(after: from, hour: hour, minute: minute, calendar: cal) else { return }
        add(TodoItem(title: done.title, note: done.note, due: due, dueHasTime: hour != nil, createdAt: now, source: done.source,
                     repeatRule: done.repeatRule, repeatOf: done.id))
    }

    public func uncomplete(_ id: String) {
        update(id) { $0.doneAt = nil }
        // 打勾时排上的下一次，还没做的话一起撤掉
        for next in items where next.repeatOf == id && !next.isDone { delete(next.id) }
    }

    public func delete(_ id: String) {
        let before = items.count
        items.removeAll { $0.id == id }
        if items.count != before { save() }
    }

    public func markReminded(_ ids: [String], at now: Date = Date()) {
        guard !ids.isEmpty else { return }
        for i in items.indices where ids.contains(items[i].id) { items[i].remindedAt = now }
        save()
    }

    /// 已完成超过 keepDoneDays 天的删掉
    public func purgeOldDone(now: Date = Date()) {
        let limit = now.addingTimeInterval(-Double(TodoStore.keepDoneDays) * 86400)
        let before = items.count
        items.removeAll { ($0.doneAt ?? .distantFuture) < limit }
        if items.count != before { save() }
    }

    /// 按标题找没完成的（命令行「hebiu todo done 开会」用）：先找完全相同的，再找包含的；找到多条就返回 nil 让调用方报错
    public func findOpen(matching text: String) -> TodoItem? {
        if let byID = items.first(where: { $0.id == text }) { return byID }
        let open = items.filter { !$0.isDone }
        let exact = open.filter { $0.title == text }
        if exact.count == 1 { return exact[0] }
        let partial = open.filter { $0.title.localizedCaseInsensitiveContains(text) }
        return partial.count == 1 ? partial[0] : nil
    }

    /// 按标题找已完成的（取消打勾、删除用），规则同 findOpen
    public func findDone(matching text: String) -> TodoItem? {
        if let byID = items.first(where: { $0.id == text }) { return byID }
        let done = items.filter(\.isDone)
        let exact = done.filter { $0.title == text }
        if exact.count == 1 { return exact[0] }
        let partial = done.filter { $0.title.localizedCaseInsensitiveContains(text) }
        return partial.count == 1 ? partial[0] : nil
    }

    // MARK: - 数据来源对账

    /// 用某个来源的最新快照更新列表：新的加进来，有变化的更新，来源里已经没有、又还没完成的删掉（比如 MR 已合并）。
    /// 已完成的不会因为来源里还有就重新出现。返回 (新增, 更新, 删除) 条数
    @discardableResult
    public func reconcile(source: String, snapshot: [SourceItem], now: Date = Date()) -> (added: Int, updated: Int, removed: Int) {
        var added = 0, updated = 0, removed = 0
        let incomingIDs = Set(snapshot.map(\.id))
        for s in snapshot {
            if let i = items.firstIndex(where: { $0.source == source && $0.externalID == s.id }) {
                var item = items[i]
                guard !item.isDone else { continue }
                item.title = s.title
                item.note = s.note ?? item.note
                item.link = s.link
                if item.due != s.due || item.dueHasTime != s.dueHasTime {
                    item.due = s.due
                    item.dueHasTime = s.dueHasTime
                    item.remindedAt = nil
                }
                if item != items[i] { items[i] = item; updated += 1 }
            } else {
                items.append(TodoItem(title: s.title, note: s.note ?? "", due: s.due, dueHasTime: s.dueHasTime,
                                      createdAt: now, source: source, externalID: s.id, link: s.link))
                added += 1
            }
        }
        let before = items.count
        items.removeAll { $0.source == source && !$0.isDone && !incomingIDs.contains($0.externalID ?? "") }
        removed = before - items.count
        if added + updated + removed > 0 { save() }
        return (added, updated, removed)
    }

    // MARK: - 工具

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    static func dayStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}

/// 数据来源交过来的一条
public struct SourceItem: Codable, Equatable {
    public var id: String
    public var title: String
    public var due: Date?
    public var dueHasTime: Bool
    public var note: String?
    public var link: String?

    public init(id: String, title: String, due: Date? = nil, dueHasTime: Bool = true, note: String? = nil, link: String? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.dueHasTime = dueHasTime
        self.note = note
        self.link = link
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? (due != nil)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        link = try c.decodeIfPresent(String.self, forKey: .link)
    }
}

extension TodoStore {
    /// 只读地读一遍（命令行用）：文件坏了也不挪动、不备份
    public static func readItems(url: URL = Paths.todo) -> [TodoItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        struct Body: Decodable { var items: [TodoItem] }
        return (try? decoder.decode(Body.self, from: data))?.items ?? []
    }

    public static func encode(_ items: [TodoItem]) -> Data {
        (try? encoder.encode(items)) ?? Data("[]".utf8)
    }
}
