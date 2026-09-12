import AppKit
import ImageIO
import XCTest
@testable import RayNote

final class LocalImagePreviewTests: XCTestCase {
    @MainActor func testLocalImageRendersWithoutReplacingMarkdownAndRevealsOnEdit() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 800, height: 480))
        context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 240, width: 400, height: 240))
        let image = try XCTUnwrap(context.makeImage())
        let url = folder.appendingPathComponent("preview.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let text = "# Images\n\n![Preview](preview.png)\n\nKeep writing below."
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))
        editor.minSize = .zero
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 20, height: 13)
        editor.baseDirectory = folder; editor.string = text
        editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        let preview = try XCTUnwrap(editor.liveImages.first)
        XCTAssertLessThanOrEqual(preview.size.width, 340)
        XCTAssertEqual(preview.size.width / preview.size.height, 800.0 / 480.0, accuracy: 0.001)
        XCTAssertNotNil(editor.imagePreviews.image(for: preview))
        let rect = try XCTUnwrap(editor.imageRect(preview))
        XCTAssertGreaterThan(rect.height, 100)
        XCTAssertEqual(editor.string, text)
        let coordinator = MarkdownEditor.Coordinator(MarkdownEditor(noteID: UUID(), text: text, source: false, onChange: { _ in }, baseDirectory: folder))
        coordinator.editor = editor; editor.delegate = coordinator
        coordinator.style()
        editor.setFrameSize(NSSize(width: 250, height: 400))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let resized = try XCTUnwrap(editor.liveImages.first)
        XCTAssertLessThan(resized.size.width, preview.size.width, "A width change must update the preview without a cursor click")
        editor.setFrameSize(NSSize(width: 380, height: 400))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        if let output = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
            editor.appearance = NSAppearance(named: .darkAqua)
            editor.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
            let bitmap = try XCTUnwrap(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
            editor.cacheDisplay(in: editor.bounds, to: bitmap)
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("local-image-editor.png"))
        }
        XCTAssertTrue(editor.revealImage(at: NSPoint(x: rect.midX, y: rect.midY)))
        XCTAssertEqual(editor.selectedRange().location, preview.range.location + 2)
        LiveMarkdown.style(editor, sourceMode: false)
        XCTAssertTrue(editor.liveImages.isEmpty)
        XCTAssertFalse(editor.markdownGlyphs.hidden.contains(preview.range.location + 2))
        LiveMarkdown.style(editor, sourceMode: true)
        XCTAssertTrue(editor.liveImages.isEmpty)
        XCTAssertEqual(editor.string, text)
    }
    @MainActor func testMissingAndRemoteImagesRemainSource() {
        let editor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
        let text = "![Missing](missing.png)\n\n![Remote](https://example.com/image.png)\n\nEnd"
        editor.baseDirectory = FileManager.default.temporaryDirectory
        editor.string = text; editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        LiveMarkdown.style(editor, sourceMode: false)
        XCTAssertTrue(editor.liveImages.isEmpty)
        XCTAssertTrue(editor.markdownGlyphs.hidden.isEmpty)
        XCTAssertEqual(editor.string, text)
    }
}
