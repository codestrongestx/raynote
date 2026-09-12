import AppKit
import XCTest
@testable import RayNote

final class LiveMarkdownTests: XCTestCase {
    @MainActor private func editor(_ text: String) -> NoteTextView {
        _ = NSApplication.shared
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 460))
        view.isRichText = false; view.allowsUndo = true
        view.textContainerInset = NSSize(width: 24, height: 16)
        view.textContainer?.widthTracksTextView = true
        view.string = text
        return view
    }
    @MainActor func testProjectionKeepsSourceAndHidesOnlyMarkdownGlyphs() throws {
        let text = "# Hello 👋\n\nThis is **bold** and `code`.\n\nEditing here"
        let view = editor(text)
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        let layout = try XCTUnwrap(view.layoutManager)
        layout.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: text.utf16.count))
        XCTAssertEqual(view.string, text)
        XCTAssertTrue(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: 0)).contains(.null))
        let bold = (text as NSString).range(of: "**bold**")
        XCTAssertTrue(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: bold.location)).contains(.null))
        XCTAssertFalse(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: bold.location + 2)).contains(.null))
        XCTAssertEqual(view.selectedRange().location, text.utf16.count)
        LiveMarkdown.style(view, sourceMode: true)
        layout.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: text.utf16.count))
        XCTAssertFalse(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: 0)).contains(.null))
        XCTAssertEqual(view.string, text)
    }
    @MainActor func testActiveLineRevealsSyntaxAndFencedCodeIsLiteral() {
        let text = "# Heading\n\n```md\n# literal **text**\n```"
        let view = editor(text)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        XCTAssertFalse(view.markdownGlyphs.hidden.contains(0))
        XCTAssertTrue(view.markdownGlyphs.hidden.isEmpty)
        let literal = (text as NSString).range(of: "# literal")
        let font = view.textStorage?.attribute(.font, at: literal.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 13)
    }
    @MainActor func testInlineCodeAndEscapedSyntaxDoNotGainFormatting() {
        let text = "`**literal**` and \\*escaped*\n\nend"
        let view = editor(text)
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        XCTAssertTrue(view.markdownGlyphs.hidden.contains(0))
        XCTAssertFalse(view.markdownGlyphs.hidden.contains(1))
        let escaped = (text as NSString).range(of: "*escaped*")
        XCTAssertFalse(view.markdownGlyphs.hidden.contains(escaped.location))
    }
    @MainActor func testLiveTaskHitTestingAndUndoKeepOriginalMarkdown() throws {
        let text = "# Tasks 👋\n\n- [ ] Buy milk\n\nEditing here"
        let view = editor(text)
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.makeFirstResponder(view)
        defer { window.close() }
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        let task = try XCTUnwrap(view.liveTasks.first)
        let rect = try XCTUnwrap(view.taskRect(task))
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        XCTAssertTrue(view.toggleTask(at: NSPoint(x: rect.midX, y: rect.midY)))
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, text.replacingOccurrences(of: "[ ]", with: "[x]"))
        XCTAssertEqual(view.selectedRange().location, text.utf16.count)
        undo.undo()
        XCTAssertEqual(view.string, text)
    }
    @MainActor func testLiveEditorFixture() throws {
        let text = "# Meeting Notes 14/11\n\n1. Samuel to design landing page\n2. Pedro to plan launch campaign\n3. Bruno to go over the details\n\n- [ ] Review the next iteration\n- [x] Keep every note locally\n\n**Native editing**, with `Markdown` and [links](https://example.com).\n\n"
        let view = editor(text)
        view.drawsBackground = true
        view.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        view.appearance = NSAppearance(named: .darkAqua)
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(representation.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("markdown-live-dark.png"))
        }
    }

    @MainActor func testCodePanelsPreserveWhitespaceAndResetInSourceMode() throws {
        let text = "# Code 👋\n\n```swift\nlet greeting = \"Hello 👋\"\n\n\tprint(greeting)\n```\n\nAfter the block"
        let view = editor(text)
        view.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(view, sourceMode: false)
        let range = try XCTUnwrap(view.liveCodeBlocks.first)
        let rect = try XCTUnwrap(view.codeBlockRect(range))
        XCTAssertGreaterThan(rect.height, 90)
        XCTAssertEqual(rect.width, view.textContainer?.containerSize.width)
        let blank = (text as NSString).range(of: "\n\n\t").location + 1
        let font = view.textStorage?.attribute(.font, at: blank, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 13, "Blank code lines retain their full height")
        XCTAssertEqual(view.string, text)
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            view.drawsBackground = true
            view.appearance = NSAppearance(named: appearance)
            view.backgroundColor = name == "dark" ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
                let url = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("code-panel-\(name).png"))
            }
        }
        LiveMarkdown.style(view, sourceMode: true)
        XCTAssertTrue(view.liveCodeBlocks.isEmpty)
        XCTAssertEqual(view.string, text)
    }
}
