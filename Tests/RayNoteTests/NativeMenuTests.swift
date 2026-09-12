import AppKit
import XCTest
@testable import RayNote

final class NativeMenuTests: XCTestCase {
    @MainActor func testMenuFormattingDispatchAndResponderValidation() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = originalMenu }
        let delegate = AppDelegate(store: NoteStore(directory: directory))
        delegate.window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        delegate.window.isReleasedWhenClosed = false
        defer { delegate.window.close() }
        let editor = NoteTextView(frame: delegate.window.contentView!.bounds)
        editor.isRichText = false; editor.string = "Menu test"
        delegate.window.contentView = editor
        delegate.window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 4))
        delegate.buildMenu()
        let context = delegate.noteActionsMenu()
        XCTAssertEqual(context.items.compactMap { $0.representedObject as? String }, ["show", "new", "search", "pin", "fit", "source", "reading", "formatbar", "import", "export", "settings", "quit"])
        XCTAssertEqual(context.item(withTitle: "Keep on Top")?.state, UserDefaults.standard.bool(forKey: "keepOnTop") ? .on : .off)
        let menu = try XCTUnwrap(NSApp.mainMenu)
        XCTAssertEqual(menu.items.map(\.title), ["RayNote", "File", "Edit", "Format", "View"])
        let format = try XCTUnwrap(menu.item(withTitle: "Format")?.submenu)
        let bold = try XCTUnwrap(format.item(withTitle: "Bold"))
        XCTAssertTrue(delegate.validateMenuItem(bold))
        format.performActionForItem(at: format.index(of: bold))
        XCTAssertEqual(editor.string, "**Menu** test")
        let edit = try XCTUnwrap(menu.item(withTitle: "Edit")?.submenu)
        XCTAssertEqual(edit.item(withTitle: "Paste")?.action, #selector(NSText.paste(_:)))
        XCTAssertEqual(edit.item(withTitle: "Paste")?.keyEquivalent, "v")
        let field = NSTextView(frame: editor.bounds)
        delegate.window.contentView = field
        delegate.window.makeFirstResponder(field)
        XCTAssertFalse(delegate.validateMenuItem(bold), "Formatting must not target a search or settings field")
    }
}
