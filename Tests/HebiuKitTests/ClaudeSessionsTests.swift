import Foundation
import Testing
@testable import HebiuKit

@Suite struct ClaudeSessionsTests {
    private func e(_ s: String) -> ClaudeEventLine { ClaudeEventLine(Substring(s))! }

    @Test func 解析新旧两种写法() {
        let new = e("1792982947 done sid=abcd1234 proj=hebiu")
        #expect(new.name == "done" && new.session == "abcd1234" && new.project == "hebiu")
        #expect(e("1792982947 working").session == nil)
        #expect(e("pat").name == "pat")
        #expect(e("1792982947 wait sid= proj=").session == nil)
    }

    @Test func 分得清是_Claude_还是_Codex() {
        #expect(e("1792982947 done sid=abcd1234 proj=hebiu src=codex").tool == "codex")
        #expect(e("1792982947 done sid=abcd1234 proj=hebiu src=claude").tool == "claude")
        #expect(e("1792982947 done sid=abcd1234 proj=hebiu").tool == "claude")
        #expect(e("1792982947 done sid=abcd1234 proj=hebiu src=codex").name == "done")
    }

    @Test func 前台照常演_后台做完不打断_后台等你照样喊() {
        let c = ClaudeSessions()
        let t = date("2026-10-26 10:00")
        #expect(c.note(e("1 working sid=A proj=hebiu"), now: t) == .play)
        #expect(c.note(e("1 working sid=B proj=my-app"), now: t) == .play)   // 你刚给 B 发了消息，B 是前台
        #expect(c.foreground == "B")
        #expect(c.note(e("1 done sid=A proj=hebiu"), now: t) == .backgroundDone(project: "hebiu"))
        #expect(c.note(e("1 error sid=A proj=hebiu"), now: t) == .ignore)
        #expect(c.note(e("1 wait sid=A proj=hebiu"), now: t) == .backgroundWaiting(project: "hebiu"))
        #expect(c.note(e("1 done sid=B proj=my-app"), now: t) == .play)
        #expect(c.summary == "1 个等你")
        #expect(c.note(e("1 done"), now: t) == .play)                                    // 旧钩子分不清，照常
    }

    @Test func 同项目加序号_新开会话别人在忙时不打招呼_两小时没动静清掉() {
        let c = ClaudeSessions()
        let t = date("2026-10-26 10:00")
        _ = c.note(e("1 working sid=A proj=wy"), now: t)
        _ = c.note(e("1 hello sid=B proj=wy"), now: t)
        #expect(c.label("A") == "wy①" && c.label("B") == "wy②")
        #expect(c.note(e("1 hello sid=C proj=x"), now: t) == .ignore)
        #expect(c.summary == "1 个在跑")
        _ = c.note(e("1 hello sid=D proj=y"), now: date("2026-10-26 12:30"))
        #expect(c.sessions.keys.sorted() == ["D"])
        #expect(c.foreground == "D")
    }
}
