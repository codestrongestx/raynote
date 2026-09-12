import CoreGraphics
import ImageIO
import XCTest
@testable import RayNote

final class MarkdownAssetsTests: XCTestCase {
    private func makeImage(at url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let target = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(target, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(target))
    }
    func testImportAndExportKeepImageBytesAndMarkdownPortable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original", isDirectory: true)
        let library = root.appendingPathComponent("library", isDirectory: true)
        let exported = root.appendingPathComponent("export", isDirectory: true)
        for folder in [original, library, exported] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let image = original.appendingPathComponent("my photo.png")
        try makeImage(at: image)
        let source = original.appendingPathComponent("note.md")
        let text = "# Photos 👋\n\n![Example](<my photo.png>)\n\nAgain: ![Same](my%20photo.png)\n\nKeep **everything** else.\n"
        try text.write(to: source, atomically: true, encoding: .utf8)
        if let folder = ProcessInfo.processInfo.environment["RAYNOTE_ASSET_FIXTURE_DIR"] {
            let output = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try Data(contentsOf: image).write(to: output.appendingPathComponent("my photo.png"))
            try text.write(to: output.appendingPathComponent("image-note.md"), atomically: true, encoding: .utf8)
        }
        let imported = try MarkdownAssets.importDocument(at: source, into: library)
        XCTAssertTrue(imported.warnings.isEmpty)
        let references = MarkdownAssets.references(in: imported.text)
        XCTAssertEqual(references.count, 2)
        XCTAssertEqual(references[0].destination, references[1].destination)
        XCTAssertTrue(imported.text.hasSuffix("Keep **everything** else.\n"))
        let copied = try XCTUnwrap(MarkdownAssets.resolve(references[0].destination, relativeTo: library))
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: image))
        let destination = exported.appendingPathComponent("My note.md")
        XCTAssertTrue(try MarkdownAssets.exportDocument(imported.text, from: library, to: destination).isEmpty)
        let output = try String(contentsOf: destination, encoding: .utf8)
        let outputReference = try XCTUnwrap(MarkdownAssets.references(in: output).first)
        let outputImage = try XCTUnwrap(MarkdownAssets.resolve(outputReference.destination, relativeTo: exported))
        XCTAssertEqual(try Data(contentsOf: outputImage), try Data(contentsOf: image))
        XCTAssertFalse(output.contains(library.path))
    }
    func testCodeEscapesAndRemoteImagesRemainUnchanged() {
        let text = "```md\n![Code](sample.png)\n```\n`![Inline](sample.png)`\n\\![Escaped](sample.png)\n![Remote](https://example.com/pic.png)"
        let refs = MarkdownAssets.references(in: text)
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs.first?.destination, "https://example.com/pic.png")
    }
    func testMissingAndNonImageFilesAreReportedWithoutRewriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not an image".write(to: root.appendingPathComponent("fake.png"), atomically: true, encoding: .utf8)
        let text = "![Missing](missing.png)\n![Fake](fake.png)\n![Remote](https://example.com/x.png)"
        let source = root.appendingPathComponent("note.md")
        try text.write(to: source, atomically: true, encoding: .utf8)
        let result = try MarkdownAssets.importDocument(at: source, into: root.appendingPathComponent("library"))
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.warnings.count, 2)
    }
    func testReadingParserRecognizesAngleDestinationAndTitle() {
        let block = MarkdownDocument.parse("![Photo](<my photo.png> \"A caption\")").first
        XCTAssertEqual(block?.kind, .image(alt: "Photo", destination: "<my photo.png>"))
    }
}
