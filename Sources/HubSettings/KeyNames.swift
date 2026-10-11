import AppKit
import Carbon.HIToolbox

/// Сочетания клавиш знаками macOS (⌃⌥S) и модификаторы в том виде, в каком их хранят приложения набора:
/// control, option, command, shift.
enum KeyNames {
    private static let order: [(name: String, glyph: String, flag: NSEvent.ModifierFlags)] = [
        ("control", "⌃", .control), ("option", "⌥", .option), ("shift", "⇧", .shift), ("command", "⌘", .command),
    ]

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> [String] {
        order.filter { flags.contains($0.flag) }.map(\.name)
    }

    static func shortcut(keyCode: Int, modifiers: [String]) -> String {
        order.filter { modifiers.contains($0.name) }.map(\.glyph).joined() + key(keyCode)
    }

    /// То же сочетание по клавишам: ["⌃", "⌥", "S"].
    static func keys(keyCode: Int, modifiers: [String]) -> [String] {
        order.filter { modifiers.contains($0.name) }.map(\.glyph) + [key(keyCode)]
    }

    /// F1-F20: их можно назначить без модификатора.
    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ].reduce(into: Set<Int>()) { $0.insert(Int($1)) }

    private static let special: [Int: String] = [
        kVK_Space: "Пробел", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Буква клавиши по латинской раскладке: код 1 - это S, какая бы раскладка ни была включена.
    static func key(_ code: Int) -> String {
        if let name = special[code] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "#\(code)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(code),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
