import Foundation
@testable import HebiuKit

/// 每个测试用一个新的临时目录当 ~/.hebiu，跑完删掉，不碰真实数据
func withTempHome<T>(_ body: (URL) throws -> T) rethrows -> T {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let old = Paths.dataDir
    Paths.dataDir = dir
    defer {
        Paths.dataDir = old
        try? FileManager.default.removeItem(at: dir)
    }
    return try body(dir)
}

func date(_ text: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = text.count > 10 ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
    return f.date(from: text)!
}
