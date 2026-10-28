import Foundation

/// 外部数据来源：~/.hebiu/sources/ 里的一个可执行文件（任何语言都行）。
/// 约定：运行后往标准输出打印 JSON，可以是数组，也可以是 {"items": [...]}，每条：
///   {"id": "来源里的唯一标识", "title": "…", "due": "2026-10-26T10:00:00+08:00", "note": "…", "link": "https://…"}
/// due 可以省略，也可以写「2026-10-26 10:00」「2026-10-26」；退出码不是 0 算失败，失败时不改动已有待办
public enum ScriptSource {
    public enum Failure: Error, CustomStringConvertible {
        case exit(Int32, String)
        case timeout
        case badOutput(String)

        public var description: String {
            switch self {
            case let .exit(code, err): return "退出码 \(code)" + (err.isEmpty ? "" : "：\(err)")
            case .timeout: return "超时"
            case let .badOutput(why): return "输出看不懂：\(why)"
            }
        }
    }

    /// 来源目录里的可执行文件，名字去掉扩展名（gitlab-review.sh → gitlab-review）
    public static func installed(in dir: URL = Paths.sources) -> [String: URL] {
        let fm = FileManager.default
        var out: [String: URL] = [:]
        for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where !url.lastPathComponent.hasPrefix(".") && fm.isExecutableFile(atPath: url.path) {
            out[url.deletingPathExtension().lastPathComponent] = url
        }
        return out
    }

    /// 运行一次，返回解析好的条目。会阻塞，放到后台线程调用
    public static func run(_ executable: URL, name: String, timeout: TimeInterval = 60) throws -> [SourceItem] {
        let process = Process()
        process.executableURL = executable
        var env = ProcessInfo.processInfo.environment
        env["HEBIU_HOME"] = Paths.dataDir.path
        env["HEBIU_SOURCE"] = name
        // 开机自启时 PATH 只有系统目录，补上常见的安装位置，脚本里才找得到 glab、python3 这些
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        process.environment = env
        // 输出写进临时文件、跑完再读：不占后台线程，输出再多也不会因为管道塞满卡住
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-source-\(UUID().uuidString)")
        let outURL = tmp.appendingPathExtension("out"), errURL = tmp.appendingPathExtension("err")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw Failure.timeout
        }
        let outData = (try? Data(contentsOf: outURL)) ?? Data()
        let errData = (try? Data(contentsOf: errURL)) ?? Data()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData.prefix(500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.exit(process.terminationStatus, message)
        }
        return try parse(outData)
    }

    /// 解析脚本输出
    public static func parse(_ data: Data) throws -> [SourceItem] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            let head = String(decoding: data.prefix(80), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.badOutput(head.isEmpty ? "什么都没输出" : "不是 JSON（\(head)…）")
        }
        let rows: [[String: Any]]
        if let array = json as? [[String: Any]] {
            rows = array
        } else if let object = json as? [String: Any], let items = object["items"] as? [[String: Any]] {
            rows = items
        } else {
            throw Failure.badOutput("要是数组或 {\"items\": [...]}")
        }
        return try rows.enumerated().map { index, row in
            guard let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                throw Failure.badOutput("第 \(index + 1) 条没有 title")
            }
            let id = (row["id"] as? String) ?? (row["id"] as? NSNumber)?.stringValue ?? title
            let due = parseDate(row["due"] as? String)
            return SourceItem(id: id, title: title, due: due?.date, dueHasTime: due?.hasTime ?? false,
                              note: row["note"] as? String, link: row["link"] as? String)
        }
    }

    /// ISO 8601、「2026-10-26 10:00」或「2026-10-26」
    static func parseDate(_ text: String?) -> (date: Date, hasTime: Bool)? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: text) { return (d, true) }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: text) { return (d, true) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for (format, hasTime) in [("yyyy-MM-dd HH:mm", true), ("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd", false)] {
            f.dateFormat = format
            if let d = f.date(from: text) { return (d, hasTime) }
        }
        return nil
    }
}
