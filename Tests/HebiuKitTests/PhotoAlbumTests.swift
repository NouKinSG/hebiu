import Foundation
import Testing
@testable import HebiuKit

@Suite struct PhotoAlbumTests {
    @Test func 只挑图片_含子文件夹_不马上重复() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("album-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("2025 夏天"), withIntermediateDirectories: true)
        for name in ["a.jpg", "b.PNG", "2025 夏天/c.heic", "d.mov", "notes.txt", ".hidden.jpg"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }
        let album = PhotoAlbum(folder: dir)
        #expect(Set(album.photos().map(\.lastPathComponent)) == ["a.jpg", "b.PNG", "c.heic"])
        let first = album.random()
        #expect(album.random() != first)
        #expect(PhotoAlbum(folder: nil).random() == nil)
    }
}
