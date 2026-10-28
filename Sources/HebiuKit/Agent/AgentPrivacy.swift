import Foundation

/// 发给 DeepSeek 之前的过滤：只有你自己加的待办可以发，日历、GitLab 等来源的一律不发；
/// 发也只发标题和时间，备注、链接不发
public enum AgentPrivacy {
    /// 你自己加的：手动、命令行、她加的
    public static let ownSources: Set<String> = [TodoSource.manual, TodoSource.cli, TodoSource.agent]
    /// 设置里打开「允许她看日历、GitLab 来的待办」时为 true
    public static var shareSourceItems = false

    public static func isOwn(_ item: TodoItem) -> Bool { ownSources.contains(item.source) }

    public static func isShareable(_ item: TodoItem) -> Bool {
        isShareable(item, includeSources: shareSourceItems)
    }

    public static func isShareable(_ item: TodoItem, includeSources: Bool) -> Bool {
        isOwn(item) || includeSources
    }

    /// 发给模型的一条待办：只有 id、标题、中文时间
    public struct SharedTodo: Codable, Equatable {
        public let id: String
        public let title: String
        public let due: String?
        /// 来源不是自己加的时写来源名（日历、GitLab…），模型据此知道时间改不了
        public var from: String? = nil
    }

    public static func share(_ items: [TodoItem], now: Date = Date(), includeSources: Bool = shareSourceItems) -> [SharedTodo] {
        items.filter { isShareable($0, includeSources: includeSources) }.map { item in
            SharedTodo(id: item.id, title: item.title,
                       due: item.due.map { TodoFormat.describe($0, hasTime: item.dueHasTime, now: now) },
                       from: isOwn(item) ? nil : TodoSource.displayName(item.source))
        }
    }
}
