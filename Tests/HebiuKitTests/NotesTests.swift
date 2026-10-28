import Foundation
import Testing
@testable import HebiuKit

@Suite struct NotesTests {
    @Test func 记_搜_改_删_标签() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = NoteStore(url: url)
        s.add("想买的书：《置身事内》 #书单", now: date("2026-10-20 10:00"))
        s.add("小满面馆 在公司楼下 #吃的", now: date("2026-10-25 12:00"))
        s.add("  ", now: date("2026-10-25 13:00"))
        #expect(s.notes.count == 2)
        #expect(s.notes.first?.text.hasPrefix("小满") == true)              // 新的在前
        #expect(s.notes.first?.tags == ["吃的"])
        #expect(s.search("书单 面馆").count == 2)
        #expect(s.search("置身事内 书单").first?.tags == ["书单"])
        #expect(s.search("火锅").isEmpty)
        #expect(s.notes(on: "2026-10-25").count == 1)
        let id = s.notes[0].id
        s.update(id, text: "小满面馆 #吃的 #常去")
        #expect(NoteStore(url: url).notes.first?.tags == ["吃的", "常去"])
        s.update(id, text: "")
        #expect(s.notes.count == 1)
    }

    @Test func 工具_记下可撤销_能搜到() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("notes-tools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TodoStore(url: dir.appendingPathComponent("todo.json"), backupDir: dir.appendingPathComponent("b"))
        let notes = NoteStore(url: dir.appendingPathComponent("notes.json"))
        let tools = AgentTools(store: store, notes: notes)
        let (_, change) = tools.execute(name: "save_note", arguments: #"{"text":"WiFi 密码在冰箱上"}"#)
        #expect(notes.notes.first?.source == TodoSource.agent)
        #expect(tools.execute(name: "search_notes", arguments: #"{"query":"WiFi"}"#).result.contains("冰箱"))
        tools.undo(change!)
        #expect(notes.notes.isEmpty)
        #expect(tools.definitions.contains { (($0["function"] as? [String: Any])?["name"] as? String) == "save_note" })
    }
}
