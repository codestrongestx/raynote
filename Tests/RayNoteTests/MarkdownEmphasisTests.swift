import AppKit
import XCTest
@testable import RayNote

final class MarkdownEmphasisTests: XCTestCase {
    func testNestedAndTripleEmphasisKeepUTF16Ranges() {
        let text = "👋 **bold *italic*** and ___both___"
        let spans = MarkdownEmphasis.parse(text)
        XCTAssertEqual(spans.count, 4)
        XCTAssertEqual(spans.filter(\.strong).count, 2)
        XCTAssertTrue(spans.contains { (text as NSString).substring(with: $0.content) == "italic" && !$0.strong })
        for span in spans {
            XCTAssertEqual((text as NSString).substring(with: span.opening), (text as NSString).substring(with: span.closing))
        }
    }
    func testLiteralAndIntrawordUnderscoresStayVisible() {
        for text in ["file_name_suffix", "_ space_", "**unclosed", "\\*escaped*", "_one\ntwo_"] {
            XCTAssertTrue(MarkdownEmphasis.parse(text).isEmpty, text)
        }
        let text = "**literal** _italic_"
        XCTAssertEqual(MarkdownEmphasis.parse(text, excluding: IndexSet(integersIn: 0..<11)).count, 1)
        XCTAssertEqual(MarkdownEmphasis.parse("one*two*three").count, 1)
    }
    @MainActor func testLiveTraitsComposeWithHeadingsAndLeaveCodeLiteral() throws {
        _ = NSApplication.shared
        let text = "# _Heading_\n\n***Both*** and **bold `code`** and file_name_suffix\n\nEnd"
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        editor.string = text
        editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        func font(_ word: String) throws -> NSFont {
            try XCTUnwrap(editor.textStorage?.attribute(.font, at: (text as NSString).range(of: word).location, effectiveRange: nil) as? NSFont)
        }
        let heading = try font("Heading")
        XCTAssertEqual(heading.pointSize, 21)
        XCTAssertTrue(NSFontManager.shared.traits(of: heading).contains(.italicFontMask))
        let both = NSFontManager.shared.traits(of: try font("Both"))
        XCTAssertTrue(both.contains(.italicFontMask)); XCTAssertTrue(both.contains(.boldFontMask))
        let code = try font("code")
        XCTAssertEqual(code.pointSize, 13)
        XCTAssertFalse(NSFontManager.shared.traits(of: code).contains(.boldFontMask))
        XCTAssertEqual(editor.string, text)
        if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            editor.appearance = NSAppearance(named: .darkAqua)
            editor.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
            editor.textContainerInset = NSSize(width: 20, height: 13)
            let bitmap = try XCTUnwrap(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
            editor.cacheDisplay(in: editor.bounds, to: bitmap)
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("nested-emphasis.png"))
        }
        editor.setSelectedRange(NSRange(location: (text as NSString).range(of: "Both").location, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        let delimiter = (text as NSString).range(of: "***")
        XCTAssertFalse(editor.markdownGlyphs.hidden.contains(delimiter.location))
    }
}
