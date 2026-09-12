import AppKit
import XCTest
@testable import RayNote

final class QuoteRenderingTests: XCTestCase {
    func testSpacedRulesTakePrecedenceOverListsAndFencesStayLiteral() {
        let blocks = MarkdownDocument.parse("* * *\n- - -\n___\n\n- ordinary list\n\n```md\n---\n```\n")
        XCTAssertEqual(blocks.filter { if case .rule = $0.kind { return true }; return false }.count, 3)
        XCTAssertEqual(blocks.filter { if case .list = $0.kind { return true }; return false }.count, 1)
        XCTAssertEqual(blocks.filter { if case .code = $0.kind { return true }; return false }.count, 1)
    }
    @MainActor func testQuotesAndRulesRenderWithoutChangingSource() throws {
        _ = NSApplication.shared
        let text = "# Notes\n\n> A **quote** with Unicode 👋\n> A second line that wraps when the note becomes narrower.\n\n---\n\nEditing here"
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 320))
        editor.textContainerInset = NSSize(width: 20, height: 13)
        editor.string = text
        editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        XCTAssertEqual(editor.liveQuotes.count, 1)
        XCTAssertEqual(editor.liveRules.count, 1)
        let marker = (text as NSString).range(of: ">")
        XCTAssertTrue(editor.markdownGlyphs.hidden.contains(marker.location))
        let rule = (text as NSString).range(of: "---")
        XCTAssertTrue(editor.markdownGlyphs.hidden.contains(rule.location + 1))
        let quote = try XCTUnwrap(editor.liveQuotes.first)
        XCTAssertGreaterThan(try XCTUnwrap(editor.codeBlockRect(quote)).height, 40)
        XCTAssertEqual(editor.string, text)
        if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for dark in [false, true] {
                editor.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                editor.backgroundColor = dark ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white
                let bitmap = try XCTUnwrap(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
                editor.cacheDisplay(in: editor.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(dark ? "quote-dark.png" : "quote-light.png"))
            }
        }
        editor.setSelectedRange(NSRange(location: marker.location + 3, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        XCTAssertFalse(editor.markdownGlyphs.hidden.contains(marker.location))
        LiveMarkdown.style(editor, sourceMode: true)
        XCTAssertTrue(editor.liveQuotes.isEmpty); XCTAssertTrue(editor.liveRules.isEmpty)
        XCTAssertEqual(editor.string, text)
    }
}
