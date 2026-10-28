import HebiuKit
import Foundation

/// 开机自启：在 ~/Library/LaunchAgents 放一个启动项，登录后自动打开；
/// 程序意外崩溃会被系统拉起，从菜单「退出」（正常退出）则不会
enum LoginItem {
    static let label = Bundle.main.bundleIdentifier ?? "io.github.hebiu"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func enable() {
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            Log.write("login item enabled: \(exe)")
        } catch {
            Log.write("login item enable failed: \(error)")
        }
    }

    static func disable() {
        try? FileManager.default.removeItem(at: plistURL)
        Log.write("login item disabled")
    }
}
