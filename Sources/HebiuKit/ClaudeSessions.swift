import Foundation

/// 事件文件里的一行：「时间戳 事件 sid=会话 proj=项目」，后两项新版钩子才有
public struct ClaudeEventLine: Equatable {
    public var time: Date?
    public var name: String
    public var session: String?
    public var project: String?
    /// 哪个编程助手发来的：claude / codex（旧的钩子不带，算 claude）
    public var tool = "claude"

    public init?(_ line: Substring) {
        let parts = line.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return nil }
        if let ts = TimeInterval(parts[0]), parts.count >= 2 {
            time = Date(timeIntervalSince1970: ts)
            name = parts[1].lowercased()
            var fields: [String: String] = [:]
            for p in parts.dropFirst(2) {
                let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2, !kv[1].isEmpty { fields[kv[0]] = kv[1] }
            }
            session = fields["sid"]
            project = fields["proj"]
            tool = fields["src"] ?? "claude"
        } else {
            name = parts[parts.count - 1].lowercased()
        }
        guard !name.isEmpty else { return nil }
    }
}

/// 同时开好几个 Claude 会话时，分清哪个是你正在看的（前台：最近发过消息的那个），后台的动静怎么处理
public final class ClaudeSessions {
    public enum State: String {
        case working, waiting, done, error, idle
    }

    public struct Session: Equatable {
        public var id: String
        public var project: String
        public var state: State
        public var lastAt: Date
    }

    /// 桌宠该怎么反应
    public enum Reaction: Equatable {
        /// 照常演（前台会话，或者分不清是哪个会话的旧钩子）
        case play
        /// 后台会话做完了
        case backgroundDone(project: String)
        /// 后台会话要你确认
        case backgroundWaiting(project: String)
        /// 后台的其他动静：不打扰
        case ignore
    }

    public private(set) var sessions: [String: Session] = [:]
    /// 你最近发消息的那个会话
    public private(set) var foreground: String?

    public init() {}

    public func note(_ e: ClaudeEventLine, now: Date = Date()) -> Reaction {
        guard let sid = e.session else { return .play }
        prune(now: now)
        var s = sessions[sid] ?? Session(id: sid, project: e.project ?? "Claude", state: .idle, lastAt: now)
        if let p = e.project { s.project = p }
        s.lastAt = now
        let isForeground: Bool
        switch e.name {
        case "working":
            s.state = .working
            foreground = sid
            isForeground = true
        default:
            if foreground == nil { foreground = sid }
            isForeground = foreground == sid
            switch e.name {
            case "done": s.state = .done
            case "wait": s.state = .waiting
            case "error": s.state = s.state == .working ? .working : .error   // 工具失败不代表整轮结束
            case "nudge": s.state = .done
            case "hello": s.state = .idle
            default: break
            }
        }
        sessions[sid] = s
        if isForeground { return .play }
        switch e.name {
        case "done": return .backgroundDone(project: label(sid))
        case "wait": return .backgroundWaiting(project: label(sid))
        case "hello": return activeOthers(except: sid) ? .ignore : .play
        default: return .ignore
        }
    }

    /// 同一个项目开了几个会话时加序号：my-app②
    public func label(_ sid: String) -> String {
        guard let s = sessions[sid] else { return "Claude" }
        let same = sessions.values.filter { $0.project == s.project }.sorted { $0.id < $1.id }
        guard same.count > 1, let i = same.firstIndex(where: { $0.id == sid }) else { return s.project }
        let marks = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
        return s.project + (i < marks.count ? marks[i] : "\(i + 1)")
    }

    public var working: Int { sessions.values.filter { $0.state == .working }.count }
    public var waiting: Int { sessions.values.filter { $0.state == .waiting }.count }

    /// 「2 个在跑 · 1 个等你」；没有分会话的信息时 nil
    public var summary: String? {
        guard !sessions.isEmpty else { return nil }
        var parts: [String] = []
        if working > 0 { parts.append("\(working) 个在跑") }
        if waiting > 0 { parts.append("\(waiting) 个等你") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 两小时没动静的会话当关掉了
    private func prune(now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastAt) < 7200 }
        if let f = foreground, sessions[f] == nil { foreground = nil }
    }

    private func activeOthers(except sid: String) -> Bool {
        sessions.values.contains { $0.id != sid && ($0.state == .working || $0.state == .waiting) }
    }
}
