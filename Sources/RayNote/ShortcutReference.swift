import AppKit
import SwiftUI

struct ShortcutReferenceSection: Identifiable {
    var id: String { title }
    let title: String
    let entries: [Entry]
    struct Entry: Identifiable {
        var id: String { title + keys }
        let title: String
        let keys: String
    }
    @MainActor static func from(menu: NSMenu) -> [Self] {
        menu.items.compactMap { item in
            guard let submenu = item.submenu else { return nil }
            let entries = submenu.items.compactMap { command -> Entry? in
                guard !command.keyEquivalent.isEmpty else { return nil }
                var keys = ""
                for (flag, glyph): (NSEvent.ModifierFlags, String) in [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] {
                    if command.keyEquivalentModifierMask.contains(flag) { keys += glyph }
                }
                switch command.keyEquivalent {
                case "\r": keys += "↩"
                case "\t": keys += "⇥"
                case " ": keys += "Space"
                default: keys += command.keyEquivalent.uppercased()
                }
                return Entry(title: command.title, keys: keys)
            }
            return entries.isEmpty ? nil : Self(title: item.title, entries: entries)
        }
    }
    static let editing = Self(title: "While Editing", entries: [
        Entry(title: "Continue or finish a list", keys: "↩"),
        Entry(title: "Indent / outdent lines", keys: "⇥ / ⇧⇥"),
        Entry(title: "Close find bar, then hide notes", keys: "Esc"),
        Entry(title: "Choose a note in search", keys: "↑ / ↓ / ↩")
    ])
}

struct ShortcutReferenceView: View {
    let sections: [ShortcutReferenceSection]
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(sections + [.editing]) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title).font(.headline).foregroundStyle(.secondary)
                            ForEach(section.entries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(entry.title).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.keys).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                                }.font(.system(size: 13))
                            }
                        }
                    }
                }.padding(.trailing, 8)
            }
            HStack { Spacer(); Button("Done", action: onDone).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420, height: 520).onExitCommand(perform: onDone)
    }
}
