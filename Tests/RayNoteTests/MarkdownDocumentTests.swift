import XCTest
@testable import RayNote

final class MarkdownDocumentTests: XCTestCase {
    func testRenderedBlocksKeepExactTaskSourceOffset() {
        let source = "# Hello 👋\n\n- [ ] 中文 task\n- [X] done\n"
        let blocks = MarkdownDocument.parse(source)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].kind, .heading(1, "Hello 👋"))
        guard case .task(let checked, let text, _, let offset) = blocks[1].kind else { return XCTFail("Expected task") }
        XCTAssertFalse(checked)
        XCTAssertEqual(text, "中文 task")
        let changed = (source as NSString).replacingCharacters(in: NSRange(location: offset, length: 1), with: "x")
        XCTAssertEqual(changed, "# Hello 👋\n\n- [x] 中文 task\n- [X] done\n")
    }
    func testCodeFenceDoesNotRenderMarkdownInsideAndAllowsLongerFence() {
        let blocks = MarkdownDocument.parse("````markdown\n# source\n```\n- [ ] literal\n````\n# Heading")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .code(language: "markdown", text: "# source\n```\n- [ ] literal"))
        XCTAssertEqual(blocks[1].kind, .heading(1, "Heading"))
    }
    func testUnclosedCodeFenceKeepsContent() {
        XCTAssertEqual(MarkdownDocument.parse("~~~\nhello\nworld").first?.kind, .code(language: "", text: "hello\nworld"))
    }
    func testTableAlignmentsAndEscapedPipes() {
        let source = "| Name | Count |\n| :--- | ---: |\n| a\\|b | `x|y` |\n"
        let blocks = MarkdownDocument.parse(source)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .table(headers: ["Name", "Count"], rows: [["a\\|b", "`x|y`"]], alignments: [.leading, .trailing]))
    }
    func testIncompleteTableRemainsText() {
        let blocks = MarkdownDocument.parse("A | B\n-- | --\nX | Y")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.first?.kind, .paragraph("A | B"))
    }
    func testCRLFTaskOffsets() {
        let source = "👋\r\n- [ ] next\r\n"
        guard case .task(_, _, _, let offset) = MarkdownDocument.parse(source)[1].kind else { return XCTFail("Expected task") }
        XCTAssertEqual((source as NSString).substring(with: NSRange(location: offset - 1, length: 3)), "[ ]")
    }
}
