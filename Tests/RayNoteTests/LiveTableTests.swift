import AppKit
import XCTest
@testable import RayNote

final class LiveTableTests: XCTestCase {
    @MainActor func testTableWrapsAndRevealsOriginalSourceOnClick() throws {
        _ = NSApplication.shared
        let text = "# Plans\n\n| Task | Status |\n| :--- | ---: |\n| **Review** the design 👋 | Ready |\n| A longer task description that should wrap | _Next_ |\n\nKeep writing"
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 420))
        editor.textContainerInset = NSSize(width: 20, height: 13)
        editor.string = text
        editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        XCTAssertEqual(editor.liveTableRows.count, 3)
        let first = try XCTUnwrap(editor.liveTableRows.first)
        let last = try XCTUnwrap(editor.liveTableRows.last)
        XCTAssertGreaterThan(last.height, first.height)
        XCTAssertEqual(editor.liveTableRows[1].cells[0].string, "Review the design 👋")
        let right = try XCTUnwrap(last.cells[1].attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(right.alignment, .right)
        XCTAssertEqual(editor.string, text)
        if let output = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for dark in [false, true] {
                editor.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                editor.backgroundColor = dark ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white
                let bitmap = try XCTUnwrap(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
                editor.cacheDisplay(in: editor.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(dark ? "table-editor-dark.png" : "table-editor-light.png"))
            }
        }
        let rect = try XCTUnwrap(editor.tableRowRect(last))
        XCTAssertTrue(editor.revealTable(at: NSPoint(x: rect.midX, y: rect.midY)))
        XCTAssertEqual(editor.selectedRange().location, last.range.location)
        LiveMarkdown.style(editor, sourceMode: false)
        XCTAssertTrue(editor.liveTableRows.isEmpty)
        XCTAssertFalse(editor.markdownGlyphs.hidden.contains(first.range.location + 1))
        LiveMarkdown.style(editor, sourceMode: true)
        XCTAssertTrue(editor.liveTableRows.isEmpty)
        XCTAssertEqual(editor.string, text)
    }
}
