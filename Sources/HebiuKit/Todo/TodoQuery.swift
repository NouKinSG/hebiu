import Foundation

/// 待办怎么分组、怎么排序；窗口、命令行、提醒都用这一份规则
public enum TodoQuery {
    public struct Sections: Equatable {
        /// 今天要做的：没写时间的、今天的、已经过期没做的
        public var today: [TodoItem]
        /// 以后的
        public var later: [TodoItem]
        /// 已完成，最近完成的在前
        public var done: [TodoItem]

        public init(today: [TodoItem], later: [TodoItem], done: [TodoItem]) {
            self.today = today
            self.later = later
            self.done = done
        }
    }

    public static func sections(_ items: [TodoItem], now: Date = Date(), calendar cal: Calendar = .current) -> Sections {
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let open = sorted(items.filter { !$0.isDone })
        return Sections(
            today: open.filter { ($0.due ?? .distantPast) < tomorrow },
            later: open.filter { ($0.due ?? .distantPast) >= tomorrow },
            done: items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        )
    }

    /// 有时间的按时间先后，没时间的排在后面按添加先后
    public static func sorted(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x == y ? a.createdAt < b.createdAt : x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    /// 过期没做的：有钟点的过了时间，只有日期的过了那一天
    public static func isOverdue(_ item: TodoItem, now: Date = Date(), calendar cal: Calendar = .current) -> Bool {
        guard !item.isDone, let due = item.due else { return false }
        return item.dueHasTime ? due < now : due < cal.startOfDay(for: now)
    }
}
