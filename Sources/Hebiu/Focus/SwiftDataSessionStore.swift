import FocusCore
import Foundation
import SwiftData

/// 基于 SwiftData 的会话存储。
///
/// - 数据库：`<directory>/FocusOnYourself.store`（加 `-wal` / `-shm`）。
/// - 打不开时保留原文件，本次退回内存库，下次启动重试。无法确认损坏时不自动搬移。
///   任何情况下都不覆盖、不删除用户原文件。
/// - 读取按 `startedAt` 升序、按 `id` 去重（无唯一约束，为以后同步防重复）。
@MainActor
final class SwiftDataSessionStore: @preconcurrency SessionStore {
    static let fileName = "FocusOnYourself.store"

    let container: ModelContainer?
    /// 是否落盘。退回内存库时为 false：写入随进程消失，调用方不能据此做「一次性」的事（如导入后改名 JSON）。
    let isPersistent: Bool

    private var memorySessions: [FocusCore.FocusSession] = []

    init(container: ModelContainer?, isPersistent: Bool) {
        self.container = container
        self.isPersistent = isPersistent
    }

    // MARK: - 会话存储

    func load() throws -> [FocusCore.FocusSession] {
        guard let context = container?.mainContext else { return memorySessions }
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
        guard let context = container?.mainContext else {
            var ids = Set(memorySessions.map(\.id))
            memorySessions.append(contentsOf: sessions.filter { ids.insert($0.id).inserted })
            return
        }
        let existing = try context.fetch(FetchDescriptor<SessionRecord>())
        var ids = Set(existing.map(\.id))
        for session in sessions where ids.insert(session.id).inserted {
            context.insert(SessionRecord(session))
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    // MARK: - 创建存储

    static func inMemory(makeContainer: (() throws -> ModelContainer)? = nil) -> SwiftDataSessionStore {
        do {
            let container: ModelContainer
            if let makeContainer { container = try makeContainer() }
            else {
                let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, migrationPlan: FocusMigrationPlan.self, configurations: configuration)
            }
            return SwiftDataSessionStore(container: container, isPersistent: false)
        } catch {
            // 连内存数据库也不可用时使用普通数组；调用方仍将待写入记录保留到下次启动。
            NSLog("专注内存数据库不可用，改用临时记录：\(error)")
            return SwiftDataSessionStore(container: nil, isPersistent: false)
        }
    }

    static func openOnDisk(directory: URL) -> SwiftDataSessionStore {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let container = try makeContainer(url: directory.appendingPathComponent(fileName))
            return SwiftDataSessionStore(container: container, isPersistent: true)
        } catch {
            // SwiftData 包装错误无法可靠区分损坏、锁冲突和权限错误。保守保留主库及 WAL/SHM，
            // 不自动重建，避免一次暂时故障让历史消失。
            NSLog("专注数据库暂不可用，原文件保留，下次启动重试：\(error)")
            return inMemory()
        }
    }

    // MARK: - 内部实现

    private static var schema: Schema { Schema(versionedSchema: FocusSchemaV1.self) }

    private static func makeContainer(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, migrationPlan: FocusMigrationPlan.self, configurations: configuration)
        // 立即读一次，确保底层 SQLite 真的可用（损坏文件有时在首次读取时才报错）
        _ = try container.mainContext.fetchCount(FetchDescriptor<SessionRecord>())
        return container
    }

}
