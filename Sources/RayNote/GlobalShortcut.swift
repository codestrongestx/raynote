import AppKit
import Carbon
import SwiftUI

struct GlobalShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String
    static let standard = GlobalShortcut(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(controlKey | optionKey), key: "N")
    var label: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + key
    }
    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }
    static var saved: GlobalShortcut {
        guard let data = UserDefaults.standard.data(forKey: "globalShortcut"), let value = try? JSONDecoder().decode(Self.self, from: data), value.keyCode < 128,
              value.modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else { return .standard }
        return value
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "globalShortcut") }
    static func from(event: NSEvent) -> GlobalShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              let key = event.charactersIgnoringModifiers, key.count == 1,
              key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).contains($0) }) else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key.uppercased())
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: GlobalShortcut
    var onRecord: (GlobalShortcut) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button; button.action = #selector(RecorderButton.record)
        button.setAccessibilityLabel("Global shortcut")
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut = shortcut; button.onRecord = onRecord
        if !button.recording { button.title = shortcut.label }
    }
    final class RecorderButton: NSButton {
        var shortcut = GlobalShortcut.standard
        var onRecord: ((GlobalShortcut) -> Void)?
        var recording = false
        override var acceptsFirstResponder: Bool { true }
        @objc func record() { recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
        override func resignFirstResponder() -> Bool { recording = false; title = shortcut.label; return super.resignFirstResponder() }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event); return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt16(kVK_Escape) { recording = false; title = shortcut.label; return }
            guard let value = GlobalShortcut.from(event: event) else { title = "Use ⌃, ⌥ or ⌘ + a key"; return }
            recording = false
            onRecord?(value)
            title = shortcut.label
        }
    }
}
