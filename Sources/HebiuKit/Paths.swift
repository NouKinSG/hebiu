import Foundation

/// 运行时数据都放在 ~/.hebiu，程序升级不会覆盖用户改过的配置。
/// 设置环境变量 HEBIU_HOME 可以换一个目录（测试用，不碰真实数据）
public enum Paths {
    public static var dataDir: URL = {
        if let custom = ProcessInfo.processInfo.environment["HEBIU_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        // 跑单元测试时（swift test）一律用临时目录，日志也不会写进真实的 ~/.hebiu
        let process = ProcessInfo.processInfo.processName
        if process.contains("testing-helper") || process.contains("xctest") || Bundle.main.bundlePath.hasSuffix(".xctest") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-tests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hebiu", isDirectory: true)
    }()
    public static var events: URL { dataDir.appendingPathComponent("events") }
    public static var config: URL { dataDir.appendingPathComponent("hebiu.md") }
    public static var log: URL { dataDir.appendingPathComponent("hebiu.log") }
    public static var todo: URL { dataDir.appendingPathComponent("todo.json") }
    public static var state: URL { dataDir.appendingPathComponent("state.json") }
    /// AI 大脑的对话记录和账本
    public static var agentDir: URL { dataDir.appendingPathComponent("agent", isDirectory: true) }
    /// 她的人设
    public static var persona: URL { dataDir.appendingPathComponent("persona.md") }
    public static var backup: URL { dataDir.appendingPathComponent("backup", isDirectory: true) }
    /// 命令行和数据来源往这里放文件，桌宠读进待办
    public static var inbox: URL { dataDir.appendingPathComponent("inbox", isDirectory: true) }
    /// 数据来源脚本放这里（每个来源一个可执行文件）
    public static var sources: URL { dataDir.appendingPathComponent("sources", isDirectory: true) }

    public static func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: events.path) {
            fm.createFile(atPath: events.path, contents: nil)
        }
    }
}

public enum Log {
    private static let maxBytes: UInt64 = 256 * 1024

    public static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = Paths.log
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size > maxBytes {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
