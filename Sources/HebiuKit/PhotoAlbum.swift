import Foundation

/// 你们的合照：从你选的一个本机文件夹里随机挑一张（含子文件夹）。只在本机看，不发给任何地方
public final class PhotoAlbum {
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp", "gif", "tiff"]
    public static let maxFiles = 5000

    public let folder: URL?
    private var files: [URL] = []
    private var scannedAt = Date.distantPast
    /// 最近看过的，不马上重复
    private var recent: [URL] = []

    public init(folder: URL?) {
        self.folder = folder
    }

    /// 文件夹里的照片；5 分钟内重复问不重新扫
    public func photos(now: Date = Date()) -> [URL] {
        guard let folder else { return [] }
        if now.timeIntervalSince(scannedAt) > 300 {
            files = PhotoAlbum.scan(folder)
            scannedAt = now
        }
        return files
    }

    public func random(now: Date = Date()) -> URL? {
        let all = photos(now: now)
        guard !all.isEmpty else { return nil }
        let fresh = all.filter { !recent.contains($0) }
        let pick = (fresh.isEmpty ? all : fresh).randomElement()!
        recent.append(pick)
        if recent.count > min(20, all.count / 2) { recent.removeFirst() }
        return pick
    }

    static func scan(_ folder: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in e where extensions.contains(url.pathExtension.lowercased()) {
            out.append(url)
            if out.count >= maxFiles { break }
        }
        return out
    }

    /// 「~/Pictures/我们」这样的写法转成路径
    public static func folder(from text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return URL(fileURLWithPath: (t as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// 照片的日子：拍摄时间读不到就用文件的创建时间
    public static func date(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}
