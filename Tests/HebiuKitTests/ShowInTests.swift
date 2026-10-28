import Foundation
import Testing
@testable import HebiuKit

@Suite struct ShowInTests {
    let own = "io.github.hebiu"

    @Test func 三种模式() {
        #expect(ShowIn(showIn: "all").allows(frontmost: "com.jetbrains.pycharm", own: own))
        let apps = ShowIn(showIn: "apps", apps: "dev.warp.Warp-Stable, com.google.Chrome")
        #expect(apps.allows(frontmost: "dev.warp.Warp-Stable", own: own))
        #expect(!apps.allows(frontmost: "com.jetbrains.pycharm", own: own))
        #expect(apps.allows(frontmost: own, own: own))
        // 一个都没选：哪里都不显示（hebiu 自己的窗口除外）
        #expect(!ShowIn(showIn: "apps").allows(frontmost: "dev.warp.Warp-Stable", own: own))
        let popup = ShowIn(showIn: "popup")
        #expect(!popup.allows(frontmost: "dev.warp.Warp-Stable", own: own))
        #expect(popup.allows(frontmost: own, own: own))
    }

    @Test func 读写_旧写法_有事时出来() {
        let old = ShowIn(showIn: "dev.warp.Warp-Stable,com.google.Chrome")
        #expect(old.mode == .apps && old.appsText == "com.google.Chrome,dev.warp.Warp-Stable")
        #expect(ShowIn(showIn: "popup").pop == ShowIn.defaultPop)
        let p = ShowIn(showIn: "popup", pop: "todo,claude,nonsense")
        #expect(p.pop == [.todo, .claude] && p.popText == "todo,claude")
        #expect(ShowIn(showIn: "popup", pop: "").pop.isEmpty)
        #expect(ShowIn.PopKind.todo.waitsForClick && !ShowIn.PopKind.claude.waitsForClick)
    }
}
