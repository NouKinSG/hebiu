import Foundation

/// 「ctrl+alt+h」这样的快捷键写法
public struct HotkeySpec: Equatable {
    public var control = false, option = false, command = false, shift = false
    public var key: String

    /// 认不出返回 nil：必须至少一个修饰键 + 一个字母、数字或 space
    public init?(_ text: String) {
        var key: String?
        for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "ctrl", "control", "⌃": control = true
            case "alt", "opt", "option", "⌥": option = true
            case "cmd", "command", "⌘": command = true
            case "shift", "⇧": shift = true
            default: key = part
            }
        }
        guard let k = key, k == "space" || (k.count == 1 && (k.first!.isLetter || k.first!.isNumber)),
              control || option || command else { return nil }
        self.key = k
    }

    /// 菜单里显示的样子：⌃⌥H
    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + (key == "space" ? "空格" : key.uppercased())
    }
}
