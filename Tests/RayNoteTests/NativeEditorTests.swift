import AppKit
import SwiftUI
import XCTest
@testable import RayNote

final class NativeEditorTests: XCTestCase {
    @MainActor func testFormattingUsesNativeUndoAndRedo() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = NoteTextView(frame: window.contentView!.bounds)
        editor.isRichText = false; editor.allowsUndo = true
        window.contentView = editor
        window.makeFirstResponder(editor)
        editor.string = "Hello 👋"
        editor.setSelectedRange(NSRange(location: 6, length: 2))
        let undo = try XCTUnwrap(editor.undoManager)
        undo.beginUndoGrouping(); editor.format("**"); undo.endUndoGrouping()
        XCTAssertEqual(editor.string, "Hello **👋**")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 8, length: 2))
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(editor.string, "Hello 👋")
        undo.redo()
        XCTAssertEqual(editor.string, "Hello **👋**")
        window.close()
    }
    @MainActor func testNativeClipboardReadAndListContinuation() {
        _ = NSApplication.shared
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        editor.isRichText = false
        let board = NSPasteboard(name: .init("RayNoteTest-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("- [x] Unicode 👋", forType: .string)
        XCTAssertTrue(editor.readSelection(from: board, type: .string))
        XCTAssertEqual(editor.string, "- [x] Unicode 👋")
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.insertNewline(nil)
        XCTAssertEqual(editor.string, "- [x] Unicode 👋\n- [ ] ")
    }
    @MainActor func testReadingViewCanRenderFixture() throws {
        _ = NSApplication.shared
        let text = "# Meeting Notes\n\nA **native** notebook with [links](https://example.com).\n\n## Today\n- [ ] Review the design\n- [x] Save notes locally\n\n| Feature | Status |\n| :--- | ---: |\n| Markdown | Ready |\n| Storage | Local |\n\n```swift\nlet idea = \"Write it down\"\n```"
        let view = NSHostingView(rootView: MarkdownReadingView(text: text, onChange: { _ in }).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        view.frame = NSRect(x: 0, y: 0, width: 540, height: 560)
        view.appearance = NSAppearance(named: .darkAqua)
        view.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        XCTAssertGreaterThan(representation.pixelsWide, 0)
        if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(representation.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("markdown-reading-dark.png"))
        }
    }
}
