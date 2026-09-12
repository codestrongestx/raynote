import AppKit
import XCTest
@testable import RayNote

final class LargeMarkdownTests: XCTestCase {
    @MainActor func testCursorMotionReusesProjectionButTextAndLineChangesRefreshIt() throws {
        _ = NSApplication.shared
        let text = "# Heading\n\n**Bold** line\n"
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        editor.string = text
        let parent = MarkdownEditor(noteID: UUID(), text: text, source: false, onChange: { _ in })
        let coordinator = MarkdownEditor.Coordinator(parent)
        coordinator.editor = editor
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.style()
        var edits = 0
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: editor.textStorage, queue: .main) { _ in edits += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.style()
        XCTAssertEqual(edits, 0, "Cursor movement within the active line must not rewrite the entire attributed document")
        editor.setSelectedRange(NSRange(location: 14, length: 0))
        coordinator.style()
        XCTAssertGreaterThan(edits, 0)
        XCTAssertTrue(editor.markdownGlyphs.hidden.contains(0), "Leaving the heading must hide its marker")
        editor.string = "## Changed\n"
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        coordinator.style()
        let font = try XCTUnwrap(editor.textStorage?.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 18)
        coordinator.parent.source = true
        coordinator.style()
        XCTAssertTrue(editor.markdownGlyphs.hidden.isEmpty)
    }
    func testLargeDocumentKeepsEveryBlockAndSourceRange() {
        let unit = "## Entry 👋\nA paragraph with **bold** and _italic_.\n- [ ] Follow up\n> Remember this\n\n"
        let source = String(repeating: unit, count: 2500)
        let start = ContinuousClock.now
        let blocks = MarkdownDocument.parse(source)
        print("Large Markdown parse: \(start.duration(to: .now)), \(source.utf8.count) bytes")
        XCTAssertEqual(blocks.count, 10000)
        XCTAssertEqual(blocks.filter { if case .task = $0.kind { return true }; return false }.count, 2500)
        XCTAssertEqual(blocks.last?.range.location, source.utf16.count - "\n\n".utf16.count - "> Remember this".utf16.count)
        for block in blocks {
            XCTAssertLessThanOrEqual(NSMaxRange(block.range), source.utf16.count)
        }
    }
}
