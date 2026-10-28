import Carbon
import HebiuKit

/// 全局快捷键（系统热键接口，不需要辅助功能权限）。同一时间只注册一个
final class GlobalHotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private static weak var current: GlobalHotkey?

    /// 注册成功返回 true；被别的程序占了等情况返回 false
    @discardableResult
    func register(_ spec: HotkeySpec, action: @escaping () -> Void) -> Bool {
        unregister()
        guard let code = GlobalHotkey.keyCodes[spec.key] else { return false }
        self.action = action
        GlobalHotkey.current = self
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotkey.current?.action?() }
            return noErr
        }, 1, &type, nil, &handler)
        var mods: UInt32 = 0
        if spec.control { mods |= UInt32(controlKey) }
        if spec.option { mods |= UInt32(optionKey) }
        if spec.command { mods |= UInt32(cmdKey) }
        if spec.shift { mods |= UInt32(shiftKey) }
        let id = EventHotKeyID(signature: OSType(0x48454249), id: 1)     // 'HEBI'
        let status = RegisterEventHotKey(UInt32(code), mods, id, GetApplicationEventTarget(), 0, &ref)
        Log.write("hotkey \(spec.display): \(status == noErr ? "registered" : "failed \(status)")")
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }

    deinit { unregister() }

    private static let keyCodes: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space,
    ]
}
