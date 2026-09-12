import XCTest
@testable import RayNote

final class MarkdownEditingTests: XCTestCase {
    func testToggleTaskPreservesCursorAndCanCreateTask() {
        let text = "👋\n- [ ] task"
        let selection = NSRange(location: text.utf16.count, length: 0)
        let checked = MarkdownEditing.format("toggleTask", text: text, selection: selection)
        XCTAssertEqual(checked.applying(to: text), "👋\n- [x] task")
        XCTAssertEqual(checked.selection, selection)
        let unchecked = MarkdownEditing.format("toggleTask", text: checked.applying(to: text), selection: selection)
        XCTAssertEqual(unchecked.applying(to: checked.applying(to: text)), text)
        XCTAssertEqual(MarkdownEditing.format("toggleTask", text: "task", selection: NSRange(location: 4, length: 0)).replacement, "- [ ] task")
    }
    func testParagraphCommandRemovesBlockFormatting() {
        let edit = MarkdownEditing.format("paragraph", text: "## Heading", selection: NSRange(location: 10, length: 0))
        XCTAssertEqual(edit.replacement, "Heading")
        XCTAssertEqual(edit.selection.location, 7)
    }
    func testInlineTogglePreservesUnicodeAndSelection() {
        let original = "Hello 👋 中文"
        let selection = (original as NSString).range(of: "👋 中文")
        let bold = MarkdownEditing.format("**", text: original, selection: selection)
        let formatted = bold.applying(to: original)
        XCTAssertEqual(formatted, "Hello **👋 中文**")
        XCTAssertEqual((formatted as NSString).substring(with: bold.selection), "👋 中文")
        let unbold = MarkdownEditing.format("**", text: formatted, selection: bold.selection)
        XCTAssertEqual(unbold.applying(to: formatted), original)
        XCTAssertEqual(unbold.selection, selection)
    }
    func testWholeSpanToggleAndEmptyToggle() {
        let unbold = MarkdownEditing.format("**", text: "**hello**", selection: NSRange(location: 0, length: 9))
        XCTAssertEqual(unbold.replacement, "hello")
        let insertion = MarkdownEditing.format("`", text: "hi ", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(insertion.applying(to: "hi "), "hi ``")
        XCTAssertEqual(insertion.selection, NSRange(location: 4, length: 0))
        let removal = MarkdownEditing.format("`", text: "hi ``", selection: insertion.selection)
        XCTAssertEqual(removal.applying(to: "hi ``"), "hi ")
    }
    func testBlockConversionAndToggleExcludeUnselectedLine() {
        let text = "# One\n- Two\nThree"
        let selection = NSRange(location: 0, length: 12)
        let list = MarkdownEditing.format("1. ", text: text, selection: selection)
        XCTAssertEqual(list.applying(to: text), "1. One\n2. Two\nThree")
        let plain = MarkdownEditing.format("1. ", text: list.applying(to: text), selection: list.selection)
        XCTAssertEqual(plain.applying(to: list.applying(to: text)), "One\nTwo\nThree")
    }
    func testHeadingConversionKeepsCursorAtContent() {
        let edit = MarkdownEditing.format("## ", text: "# title", selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(edit.replacement, "## title")
        XCTAssertEqual(edit.selection.location, 8)
    }
    func testListContinuationAndExit() {
        for (text, expected) in [("- [x] done", "- [x] done\n- [ ] "), ("  9. nine", "  9. nine\n  10. "), ("- ", ""), ("> quote", "> quote\n> ")] {
            let edit = MarkdownEditing.newline(text: text, selection: NSRange(location: text.utf16.count, length: 0))
            XCTAssertEqual(edit.applying(to: text), expected)
        }
    }
    func testReturnBeforeListMarkerAndInsideFence() {
        let text = "- task"
        XCTAssertEqual(MarkdownEditing.newline(text: text, selection: NSRange(location: 0, length: 0)).applying(to: text), "\n- task")
        let code = "```markdown\n- example"
        XCTAssertEqual(MarkdownEditing.newline(text: code, selection: NSRange(location: code.utf16.count, length: 0)).applying(to: code), code + "\n")
        XCTAssertFalse(MarkdownEditing.insideFence(text: "```\nx\n```\n- hi", offset: 14))
    }
    func testIndentRoundTripAndFinalLineBoundary() {
        let text = "one\ntwo\nthree"
        let edit = MarkdownEditing.indent(text: text, selection: NSRange(location: 0, length: 8), outdent: false)
        XCTAssertEqual(edit.applying(to: text), "  one\n  two\nthree")
        let reverse = MarkdownEditing.indent(text: edit.applying(to: text), selection: edit.selection, outdent: true)
        XCTAssertEqual(reverse.applying(to: edit.applying(to: text)), text)
    }
    func testCodeBlockHandlesEmbeddedFenceAndSurroundingText() {
        let text = "before ``` after"
        let edit = MarkdownEditing.format("codeblock", text: text, selection: NSRange(location: 7, length: 3))
        XCTAssertEqual(edit.applying(to: text), "before \n````\n```\n````\n after")
        XCTAssertEqual((edit.applying(to: text) as NSString).substring(with: edit.selection), "```")
    }
    func testLinkSelectsDestination() {
        let edit = MarkdownEditing.format("link", text: "RayNote", selection: NSRange(location: 0, length: 7))
        XCTAssertEqual(edit.replacement, "[RayNote](https://)")
        XCTAssertEqual((edit.replacement as NSString).substring(with: edit.selection), "https://")
    }
}
