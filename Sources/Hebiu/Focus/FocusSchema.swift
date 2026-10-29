import FocusCore
import Foundation
import SwiftData

/// SwiftData 模式 V1。按 CloudKit 规则设计：所有字段有默认值、无唯一约束、无关系，
/// 下一期开启 iCloud 同步时无需改结构。新增字段时加 V2 并在 `FocusMigrationPlan` 里写迁移。
enum FocusSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [SessionRecord.self] }

    @Model
    final class SessionRecord {
        var id: UUID = UUID()
        var title: String = ""
        var modeRaw: String = TimerMode.countdown.rawValue
        var startedAt: Date = Date.distantPast
        var endedAt: Date = Date.distantPast
        var focusedSeconds: Double = 0
        var plannedSeconds: Double? = nil
        var outcomeRaw: String = SessionOutcome.completed.rawValue

        init(
            id: UUID,
            title: String,
            modeRaw: String,
            startedAt: Date,
            endedAt: Date,
            focusedSeconds: Double,
            plannedSeconds: Double?,
            outcomeRaw: String
        ) {
            self.id = id
            self.title = title
            self.modeRaw = modeRaw
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.focusedSeconds = focusedSeconds
            self.plannedSeconds = plannedSeconds
            self.outcomeRaw = outcomeRaw
        }
    }
}

typealias SessionRecord = FocusSchemaV1.SessionRecord

enum FocusMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FocusSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

extension SessionRecord {
    convenience init(_ session: FocusCore.FocusSession) {
        self.init(
            id: session.id,
            title: session.title,
            modeRaw: session.mode.rawValue,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            focusedSeconds: session.focusedSeconds,
            plannedSeconds: session.plannedSeconds,
            outcomeRaw: session.outcome.rawValue
        )
    }

    /// 读出时容错：认不出的枚举值回退为倒计时 / 完成，不因一条脏数据崩溃。
    var session: FocusCore.FocusSession {
        FocusCore.FocusSession(
            id: id,
            title: title,
            mode: TimerMode(rawValue: modeRaw) ?? .countdown,
            startedAt: startedAt,
            endedAt: endedAt,
            focusedSeconds: focusedSeconds,
            plannedSeconds: plannedSeconds,
            outcome: SessionOutcome(rawValue: outcomeRaw) ?? .completed
        )
    }
}
