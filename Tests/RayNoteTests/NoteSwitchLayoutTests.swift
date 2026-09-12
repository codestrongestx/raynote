import AppKit
import XCTest
@testable import RayNote

final class NoteSwitchLayoutTests: XCTestCase {
    @MainActor func testSwitchingLongShortAndEmptyNotesKeepsWindowAndRestoresViewport() throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 520, height: 480), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.hasVerticalScroller = true
        let editor = NoteTextView(frame: scroll.bounds)
        editor.isRichText = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize = NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        scroll.documentView = editor
        window.contentView = scroll
        let longID = UUID(), shortID = UUID(), emptyID = UUID()
        let long = String(repeating: "A **formatted** paragraph with 中文 👋.\n", count: 100)
        var writes = 0
        func model(_ id: UUID, _ text: String, source: Bool = false) -> MarkdownEditor {
            MarkdownEditor(noteID: id, text: text, source: source, onChange: { _ in writes += 1 })
        }
        let coordinator = MarkdownEditor.Coordinator(model(longID, long))
        coordinator.editor = editor; editor.delegate = coordinator
        coordinator.update(from: model(longID, long))
        editor.setSelectedRange(NSRange(location: 12, length: 5))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        let origin = scroll.contentView.bounds.origin
        XCTAssertGreaterThan(origin.y, 0)
        let frame = window.frame
        for _ in 0..<3 {
            coordinator.update(from: model(shortID, "Short note"))
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
            XCTAssertEqual(window.frame, frame)
            coordinator.update(from: model(emptyID, ""))
            XCTAssertEqual(window.frame, frame)
            coordinator.update(from: model(longID, long))
            XCTAssertEqual(window.frame, frame)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 12, length: 5))
            XCTAssertEqual(scroll.contentView.bounds.origin.y, origin.y, accuracy: 1)
        }
        coordinator.update(from: model(longID, long, source: true))
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(editor.string, long)
        XCTAssertEqual(writes, 0, "Loading and restyling notes must not save intermediate text")
    }
}
