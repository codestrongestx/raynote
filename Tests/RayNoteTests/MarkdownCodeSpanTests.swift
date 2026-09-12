import AppKit
import XCTest
@testable import RayNote

final class MarkdownCodeSpanTests: XCTestCase {
    func testExactRunsEscapesPaddingAndUnicode() {
        for (text, expected) in [("`` a ` b ``", ["a ` b"]), ("`a``", []), ("``a`", []), ("\\`literal`", []), ("`a\\`", ["a\\"]), ("👋 `` `中文` ``", ["`中文`"]), ("`  `", ["  "]), ("` a ` and `b`", ["a", "b"]), ("`a\nb`", [])] {
            XCTAssertEqual(MarkdownCodeSpan.parse(text).map { (text as NSString).substring(with: $0.content) }, expected, text)
        }
    }
    func testFormattingRoundTripWithEmbeddedDelimitersAndSpaces() {
        for content in ["a ` b", "`edge", "edge`", "a `` b", " both spaces ", "  ", "👋 `中文`"] {
            let original = "Before " + content + " after"
            let selection = NSRange(location: 7, length: content.utf16.count)
            let edit = MarkdownEditing.format("`", text: original, selection: selection)
            let formatted = edit.applying(to: original)
            let span = MarkdownCodeSpan.parse(formatted).first
            XCTAssertEqual(span?.content, edit.selection, content)
            let reverse = MarkdownEditing.format("`", text: formatted, selection: edit.selection)
            XCTAssertEqual(reverse.applying(to: formatted), original, content)
            XCTAssertEqual(reverse.selection, selection)
        }
    }
    func testSelectingWholeCodeSpanRemovesItsDelimiters() {
        let text = "`` `edge` ``"
        let edit = MarkdownEditing.format("`", text: text, selection: NSRange(location: 0, length: text.utf16.count))
        XCTAssertEqual(edit.applying(to: text), "`edge`")
        XCTAssertEqual(edit.selection, NSRange(location: 0, length: 6))
    }
    @MainActor func testLiveRenderingAndAssetsRespectEmbeddedBackticks() throws {
        _ = NSApplication.shared
        let text = "`` a ` **literal** ![example](missing.png) ``\n\nEditing"
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        view.string = text
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        XCTAssertEqual(view.string, text)
        XCTAssertTrue(view.markdownGlyphs.hidden.contains(0))
        XCTAssertTrue(view.markdownGlyphs.hidden.contains(2))
        let literal = (text as NSString).range(of: "**literal**")
        XCTAssertFalse(view.markdownGlyphs.hidden.contains(literal.location))
        let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: literal.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertTrue(MarkdownAssets.references(in: text).isEmpty)
        XCTAssertEqual(MarkdownAssets.references(in: "\\`![actual](image.png)`").count, 1)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        XCTAssertFalse(view.markdownGlyphs.hidden.contains(0))
    }
}
