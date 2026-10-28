import Foundation

/// 一条待办
public struct TodoItem: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var note: String
    /// 提醒时间；dueHasTime 为 false 时只有日期（如「明天 交周报」），不到点喊，只在当天的汇总里提
    public var due: Date?
    public var dueHasTime: Bool
    public var createdAt: Date
    public var doneAt: Date?
    /// 从哪来：manual（待办窗口）、cli（命令行）、calendar、gitlab……
    public var source: String
    /// 来源里的唯一标识，同一来源再次同步时靠它认出是同一条
    public var externalID: String?
    /// 点开能跳转的地址（MR、会议链接等）
    public var link: String?
    /// 到点提醒已经喊过的时间，避免重复喊；改了提醒时间会清空
    public var remindedAt: Date?
    /// 重复规则（RepeatRule 的文字形式）；打勾后自动生成下一次
    public var repeatRule: String?
    /// 由哪一条重复待办生成的（取消打勾时把它生成的下一次删掉）
    public var repeatOf: String?

    public var isDone: Bool { doneAt != nil }

    public init(id: String = TodoItem.newID(), title: String, note: String = "", due: Date? = nil, dueHasTime: Bool = false,
                createdAt: Date = Date(), doneAt: Date? = nil, source: String = TodoSource.manual,
                externalID: String? = nil, link: String? = nil, remindedAt: Date? = nil,
                repeatRule: String? = nil, repeatOf: String? = nil) {
        self.id = id
        self.title = title
        self.note = note
        self.due = due
        self.dueHasTime = dueHasTime
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.source = source
        self.externalID = externalID
        self.link = link
        self.remindedAt = remindedAt
        self.repeatRule = repeatRule
        self.repeatOf = repeatOf
    }

    public static func newID() -> String {
        "t_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }

    // 旧版本文件里缺的字段给默认值，新增字段时不用迁移
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        dueHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? (due != nil)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? TodoSource.manual
        externalID = try c.decodeIfPresent(String.self, forKey: .externalID)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        remindedAt = try c.decodeIfPresent(Date.self, forKey: .remindedAt)
        repeatRule = try c.decodeIfPresent(String.self, forKey: .repeatRule)
        repeatOf = try c.decodeIfPresent(String.self, forKey: .repeatOf)
    }
}

public enum TodoSource {
    public static let manual = "manual"
    public static let cli = "cli"
    /// AI 大脑（和她聊天时）加的
    public static let agent = "agent"

    /// 来源的显示名；没登记的来源直接显示原名
    public static func displayName(_ source: String) -> String {
        ["manual": "手动", "cli": "命令行", "agent": "\(CharacterPack.she)加的", "calendar": "日历", "reminders": "提醒事项", "gitlab": "GitLab"][source] ?? source
    }
}
