import FocusCore
import Foundation
import SwiftData

/// 基于 SwiftData 的会话存储。
///
/// - 数据库：`<directory>/FocusOnYourself.store`（加 `-wal` / `-shm`）。
/// - 打不开时：三个文件改名为 `*.corrupt-<yyyyMMdd-HHmmss>` 留底再新建；仍失败则退回内存库。
///   任何情况下都不覆盖、不删除用户原文件。
/// - 读取按 `startedAt` 升序、按 `id` 去重（无唯一约束，为以后同步防重复）。
@MainActor
final class SwiftDataSessionStore: @preconcurrency SessionStore {
    static let fileName = "FocusOnYourself.store"

    let container: ModelContainer
    /// 本次打开时留底的损坏文件。
    private(set) var lastBackupURLs: [URL]
    /// 是否落盘。退回内存库时为 false：写入随进程消失，调用方不能据此做「一次性」的事（如导入后改名 JSON）。
    let isPersistent: Bool

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer, isPersistent: Bool, backups: [URL] = []) {
        self.container = container
        self.isPersistent = isPersistent
        self.lastBackupURLs = backups
    }

    // MARK: - SessionStore

    func load() throws -> [FocusCore.FocusSession] {
        let records = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.startedAt)]))
        var seen = Set<UUID>()
        return records.compactMap { record in
            seen.insert(record.id).inserted ? record.session : nil
        }
    }

    func append(_ session: FocusCore.FocusSession) throws {
        try append(contentsOf: [session])
    }

    /// 批量插入后只保存一次（导入用）。
    func append(contentsOf sessions: [FocusCore.FocusSession]) throws {
        guard !sessions.isEmpty else { return }
        let existing = try context.fetch(FetchDescriptor<SessionRecord>())
        var ids = Set(existing.map(\.id))
        for session in sessions where ids.insert(session.id).inserted {
            context.insert(SessionRecord(session))
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    // MARK: - Factories

    static func inMemory() -> SwiftDataSessionStore {
        // 每个实例独立命名，避免同进程内多个内存库共享数据
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        // 内存库失败只可能是模式本身有误，属于编程错误
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, migrationPlan: FocusMigrationPlan.self, configurations: configuration)
        return SwiftDataSessionStore(container: container, isPersistent: false)
    }

    static func openOnDisk(directory: URL, now: () -> Date = Date.init) -> SwiftDataSessionStore {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)

        if let container = try? makeContainer(url: url) {
            return SwiftDataSessionStore(container: container, isPersistent: true)
        }

        guard let backups = backUpStoreFiles(at: url, now: now) else {
            // 留底没能整体完成（已回滚）：原文件原样保留，这次只用内存库，绝不在它们旁边新建
            NSLog("FocusOnYourself: could not back up the unreadable session store; using memory for this run")
            return inMemory()
        }
        NSLog("FocusOnYourself: session store could not be opened; backed up \(backups.map(\.lastPathComponent))")
        if let container = try? makeContainer(url: url) {
            return SwiftDataSessionStore(container: container, isPersistent: true, backups: backups)
        }

        NSLog("FocusOnYourself: falling back to an in-memory session store for this run")
        let memory = inMemory()
        memory.lastBackupURLs = backups
        return memory
    }

    // MARK: - Private

    private static var schema: Schema { Schema(versionedSchema: FocusSchemaV1.self) }

    private static func makeContainer(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, migrationPlan: FocusMigrationPlan.self, configurations: configuration)
        // 立即读一次，确保底层 SQLite 真的可用（损坏文件有时在首次读取时才报错）
        _ = try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>())
        return container
    }

    /// 把 `.store`、`-wal`、`-shm` 作为一个整体改名留底：要么全部成功，要么一个不动。
    /// 中途失败时把已改名的文件挪回原处并返回 nil——WAL 绝不能与主库分家，
    /// 否则主库可能在缺少未检查点事务的情况下被重新打开。
    private static func backUpStoreFiles(at url: URL, now: () -> Date) -> [URL]? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        let fm = FileManager.default
        var moved: [(from: URL, to: URL)] = []
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: source.path + ".corrupt-\(stamp)")
            do {
                try fm.moveItem(at: source, to: target)
                moved.append((source, target))
            } catch {
                NSLog("FocusOnYourself: failed to back up \(source.lastPathComponent): \(error); rolling back")
                for item in moved.reversed() {
                    try? fm.moveItem(at: item.to, to: item.from)
                }
                return nil
            }
        }
        return moved.map(\.to)
    }
}
