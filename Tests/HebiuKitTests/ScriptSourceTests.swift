import Foundation
import Testing
@testable import HebiuKit

private func script(_ body: String) throws -> (URL, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hebiu-src-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("demo.sh")
    try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, dir)
}

struct ScriptSourceTests {
    @Test func 正常输出数组() throws {
        let (url, dir) = try script("""
        echo '[{"id":"a","title":"Review A","link":"https://x/1"},{"id":2,"title":"开会","due":"2026-10-26 10:00"},{"title":"只有日期","due":"2026-10-27"}]'
        """)
        defer { try? FileManager.default.removeItem(at: dir) }
        let items = try ScriptSource.run(url, name: "demo")
        #expect(items.map(\.id) == ["a", "2", "只有日期"])
        #expect(items[0].link == "https://x/1")
        #expect(items[1].due == date("2026-10-26 10:00") && items[1].dueHasTime)
        #expect(items[2].due == date("2026-10-27") && !items[2].dueHasTime)
    }

    @Test func 输出items对象和ISO时间() throws {
        let items = try ScriptSource.parse(Data(#"{"items":[{"id":"x","title":"T","due":"2026-10-26T02:00:00Z"}]}"#.utf8))
        #expect(items.first?.due == ISO8601DateFormatter().date(from: "2026-10-26T02:00:00Z"))
    }

    @Test func 能拿到环境变量() throws {
        let (url, dir) = try script(#"echo "[{\"id\":\"1\",\"title\":\"$HEBIU_SOURCE\"}]""#)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try ScriptSource.run(url, name: "我的来源").first?.title == "我的来源")
    }

    @Test func 输出很多也能读全() throws {
        let (url, dir) = try script(#"python3 -c 'import json; print(json.dumps([{"id": str(i), "title": "x" * 200} for i in range(3000)]))'"#)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try ScriptSource.run(url, name: "big").count == 3000)
    }

    @Test func 好几个同时跑互不影响() throws {
        let runs = (0..<8).map { i in try! script(#"sleep 0.3; echo "[{\"id\":\"\#(i)\",\"title\":\"t\"}]""#) }
        defer { runs.forEach { try? FileManager.default.removeItem(at: $0.1) } }
        var ids = [String?](repeating: nil, count: runs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: runs.count) { i in
            let id = try? ScriptSource.run(runs[i].0, name: "p\(i)").first?.id
            lock.lock(); ids[i] = id; lock.unlock()
        }
        #expect(ids == (0..<8).map { String($0) })
    }

    @Test func 失败退出码() throws {
        let (url, dir) = try script("echo 'glab 没登录' >&2; exit 3")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: ScriptSource.Failure.self) { try ScriptSource.run(url, name: "demo") }
        do { _ = try ScriptSource.run(url, name: "demo") } catch {
            #expect("\(error)".contains("glab 没登录"))
        }
    }

    @Test func 超时会被结束() throws {
        let (url, dir) = try script("sleep 30")
        defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date()
        #expect(throws: ScriptSource.Failure.self) { try ScriptSource.run(url, name: "demo", timeout: 1) }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func 输出不是JSON或缺标题() {
        #expect(throws: ScriptSource.Failure.self) { try ScriptSource.parse(Data("hello".utf8)) }
        #expect(throws: ScriptSource.Failure.self) { try ScriptSource.parse(Data(#"[{"id":"1"}]"#.utf8)) }
        #expect(throws: ScriptSource.Failure.self) { try ScriptSource.parse(Data(#"{"x":1}"#.utf8)) }
    }

    @Test func 列出已安装的来源() throws {
        let (url, dir) = try script("echo []")
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not executable".write(to: dir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        #expect(ScriptSource.installed(in: dir).mapValues(\.lastPathComponent) == ["demo": url.lastPathComponent])
    }
}
