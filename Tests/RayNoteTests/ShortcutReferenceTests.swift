import AppKit
import SwiftUI
import XCTest
@testable import RayNote

final class ShortcutReferenceTests: XCTestCase {
    @MainActor func testReferenceReflectsMenuBindingsAndRenders() throws {
        _ = NSApplication.shared
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let delegate = AppDelegate(store: NoteStore(directory: directory))
        delegate.buildMenu()
        let menu = try XCTUnwrap(NSApp.mainMenu)
        let sections = ShortcutReferenceSection.from(menu: menu)
        let entries = sections.flatMap(\.entries)
        XCTAssertEqual(entries.first { $0.title == "Heading 2" }?.keys, "⌥⌘2")
        XCTAssertEqual(entries.first { $0.title == "Toggle Task" }?.keys, "⌘↩")
        XCTAssertEqual(entries.first { $0.title == "Find and Replace…" }?.keys, "⌥⌘F")
        XCTAssertEqual(entries.first { $0.title == "Find Previous" }?.keys, "⇧⌘G")
        XCTAssertEqual(entries.first { $0.title == "Keyboard Shortcuts" }?.keys, "⌘/")
        let binding = try XCTUnwrap(menu.item(withTitle: "View")?.submenu?.item(withTitle: "Show / Hide Notes"))
        binding.keyEquivalent = "j"; binding.keyEquivalentModifierMask = [.control, .shift]
        XCTAssertEqual(ShortcutReferenceSection.from(menu: menu).flatMap(\.entries).first { $0.title == "Show / Hide Notes" }?.keys, "⌃⇧J")
        let view = NSHostingView(rootView: ShortcutReferenceView(sections: sections, onDone: {}).environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 420, height: 520)
        view.layoutSubtreeIfNeeded()
        if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("shortcut-reference.png"))
        }
    }
}
