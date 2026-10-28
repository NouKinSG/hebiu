import Foundation
import Testing
@testable import HebiuKit

struct AgentPrivacyTests {
    @Test func 只发自己加的待办_只发标题和时间() {
        let now = date("2026-10-23 14:30")
        let items = [
            TodoItem(id: "a", title: "给妈妈打电话", note: "私人备注", due: date("2026-10-24 15:00"), dueHasTime: true, source: TodoSource.manual),
            TodoItem(id: "b", title: "交周报", source: TodoSource.cli),
            TodoItem(id: "c", title: "她加的", source: TodoSource.agent),
            TodoItem(id: "d", title: "周会 10:00 开始", source: "calendar"),
            TodoItem(id: "e", title: "Review：xxx", source: "gitlab-review", link: "https://gitlab.example.com/mr/1"),
            TodoItem(id: "f", title: "自写脚本", source: "my-script"),
        ]
        let shared = AgentPrivacy.share(items, now: now)
        #expect(shared.map(\.id) == ["a", "b", "c"])
        #expect(shared[0] == .init(id: "a", title: "给妈妈打电话", due: "明天 15:00"))
        let json = String(decoding: try! JSONEncoder().encode(shared), as: UTF8.self)
        #expect(!json.contains("私人备注") && !json.contains("gitlab.example.com") && !json.contains("周会"))
    }

    @Test func 钥匙串存取删_用测试专用的服务名() {
        let secrets = AgentSecrets(service: "io.github.hebiu.test-\(UUID().uuidString)", account: "test")
        defer { secrets.delete() }
        #expect(secrets.load() == nil)
        #expect(secrets.save("  sk-test-1234abcd  "))
        #expect(secrets.load() == "sk-test-1234abcd")
        #expect(secrets.save("sk-test-new-5678"))                 // 覆盖
        #expect(secrets.load() == "sk-test-new-5678")
        #expect(secrets.delete())
        #expect(secrets.load() == nil)
    }

    @Test func 只显示末四位() {
        #expect(AgentSecrets.masked("sk-abcdef123456") == "•••• 3456")
        #expect(AgentSecrets.masked(nil) == "未填写")
    }
}
