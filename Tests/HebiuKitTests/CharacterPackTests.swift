import Foundation
import Testing
@testable import HebiuKit

@Suite struct CharacterPackTests {
    private var repoCharacters: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/characters")
    }

    @Test func 自带的形象包都能读_帧图齐全() throws {
        let all = CharacterLibrary.available(bundled: repoCharacters)
        #expect(!all.isEmpty)
        for (name, dir) in all {
            let pack = try CharacterPack.load(from: dir)
            #expect(pack.id == name)
            #expect(!pack.actions.isEmpty && !pack.taps.isEmpty)
            #expect(pack.missingFrames(available: CharacterLibrary.frameNames(in: dir)).isEmpty, "\(name) 缺帧")
            // Claude 和提醒用到的动作都有
            for needed in ["hello", "working", "wait", "done", "error", "remind", pack.annoyed, pack.rightClick, pack.doubleClick] {
                #expect(pack.actions[needed] != nil, "\(name) 缺动作 \(needed)")
            }
        }
    }

    @Test func 自己的形象包盖过自带的_读写一致() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("chars-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var pack = CharacterPack(name: "小云", pronoun: "它", callsUser: "你", summary: "一朵云", persona: "你是一朵云",
                                 lines: ["hello": ["嗨"]], actions: ["hello": .init(hold: "idle", holdSeconds: 2, line: "hello")],
                                 taps: [.init(action: "hello", weight: 1)], annoyed: "hello", rightClick: "hello", doubleClick: "hello",
                                 idle: .init(), expressions: [], catalog: [])
        try pack.save(to: tmp.appendingPathComponent("cloud"))
        let again = try CharacterPack.load(from: tmp.appendingPathComponent("cloud"))
        pack.id = "cloud"
        #expect(again == pack)
        #expect(again.missingFrames(available: ["idle", "blink"]).isEmpty)
        #expect(again.missingFrames(available: []) == ["blink", "idle"])
        #expect(CharacterLibrary.resolve("nope", bundled: tmp, fallback: "cloud")?.pack.name == "小云")
    }
}
