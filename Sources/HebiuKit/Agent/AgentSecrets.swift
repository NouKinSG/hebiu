import Foundation

/// DeepSeek API key 存在 macOS 钥匙串里，经系统自带的 security 命令读写。
/// 不直接用钥匙串接口：hebiu 每次重新编译签名都会变，直接读会每次弹窗要求授权
public struct AgentSecrets {
    public let service: String
    public let account: String

    /// 钥匙串里的服务名：跟着 App 标识走（build 时的 BUNDLE_ID）
    public static var defaultService: String { (Bundle.main.bundleIdentifier ?? "io.github.hebiu") + ".deepseek" }

    public init(service: String = AgentSecrets.defaultService, account: String = "deepseek") {
        self.service = service
        self.account = account
    }

    public static let shared = AgentSecrets()

    /// 读 key；没有返回 nil。结果不缓存，每次发请求时现读
    public func load() -> String? {
        let r = Self.run(["find-generic-password", "-s", service, "-a", account, "-w"])
        guard r.status == 0 else { return nil }
        let key = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// 保存（已有就覆盖）
    @discardableResult
    public func save(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        let r = Self.run(["add-generic-password", "-U", "-s", service, "-a", account, "-l", "hebiu DeepSeek API key", "-w", key])
        if r.status != 0 { Log.write("agent key save failed: \(r.status)") }
        return r.status == 0
    }

    @discardableResult
    public func delete() -> Bool {
        Self.run(["delete-generic-password", "-s", service, "-a", account]).status == 0
    }

    /// 页面上只显示末四位
    public static func masked(_ key: String?) -> String {
        guard let key, key.count > 4 else { return "未填写" }
        return "•••• " + key.suffix(4)
    }

    private static func run(_ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
