import Foundation

/// 已知的数据来源：名字、说明、默认多久同步一次（分钟）
public enum SourceCatalog {
    public struct Entry {
        public let name: String
        public let title: String
        public let detail: String
        public let defaultMinutes: Int
        /// 内置（程序里实现）还是脚本（~/.hebiu/sources/ 里）
        public let builtIn: Bool
    }

    public static let known: [Entry] = [
        Entry(name: "calendar", title: "Mac 日历", detail: "今天和明天的会议，开始前 5 分钟提醒", defaultMinutes: 10, builtIn: true),
        Entry(name: "reminders", title: "Mac 提醒事项", detail: "没完成的提醒（手机上加的也会同步过来）", defaultMinutes: 10, builtIn: true),
        Entry(name: "gitlab-review", title: "GitLab review", detail: "等你 review 的 MR（用本机已登录的 glab，只读）", defaultMinutes: 15, builtIn: false),
    ]

    public static func entry(_ name: String) -> Entry? { known.first { $0.name == name } }
}
