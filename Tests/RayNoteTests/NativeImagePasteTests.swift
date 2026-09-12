import AppKit
import XCTest
@testable import RayNote

final class NativeImagePasteTests: XCTestCase {
    @MainActor func testImagePasteSavesPortableBytesAndSupportsUndo() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(directory: folder)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) } }
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let board = NSPasteboard(name: .init("ImagePasteTest-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setData(data, forType: .png)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NoteTextView(frame: window.contentView!.bounds)
        editor.isRichText = false; editor.allowsUndo = true
        editor.onPasteImage = store.pasteImage
        window.contentView = editor; window.makeFirstResponder(editor)
        editor.string = "Before 👋 after"
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        let undo = try XCTUnwrap(editor.undoManager)
        undo.beginUndoGrouping()
        XCTAssertTrue(editor.readSelection(from: board))
        undo.endUndoGrouping()
        let pasted = editor.string
        XCTAssertTrue(pasted.hasPrefix("Before 👋\n\n![Image]"))
        XCTAssertTrue(pasted.hasSuffix("\n\n after"))
        let reference = try XCTUnwrap(MarkdownAssets.references(in: pasted).first)
        let image = try XCTUnwrap(MarkdownAssets.resolve(reference.destination, relativeTo: folder))
        XCTAssertEqual(try Data(contentsOf: image), data)
        XCTAssertTrue(MarkdownDocument.parse(pasted).contains { if case .image = $0.kind { return true }; return false })
        undo.undo(); XCTAssertEqual(editor.string, "Before 👋 after")
        undo.redo(); XCTAssertEqual(editor.string, pasted)
        XCTAssertEqual(try Data(contentsOf: image), data, "Undo must retain attachments needed by redo")
        let exported = folder.appendingPathComponent("export.md")
        XCTAssertTrue(try MarkdownAssets.exportDocument(pasted, from: folder, to: exported).isEmpty)
        let tiff = try XCTUnwrap(bitmap.tiffRepresentation)
        board.clearContents(); board.setData(tiff, forType: .tiff)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        XCTAssertTrue(editor.readSelection(from: board))
        let tiffReference = try XCTUnwrap(MarkdownAssets.references(in: editor.string).last)
        let tiffURL = try XCTUnwrap(MarkdownAssets.resolve(tiffReference.destination, relativeTo: folder))
        XCTAssertEqual(try Data(contentsOf: tiffURL), tiff)
        let attachments = folder.appendingPathComponent("Attachments")
        try FileManager.default.moveItem(at: attachments, to: folder.appendingPathComponent("SavedAttachments"))
        try Data("blocked directory".utf8).write(to: attachments)
        let beforeFailure = editor.string, selectionBeforeFailure = editor.selectedRange()
        XCTAssertFalse(editor.readSelection(from: board), "An attachment-write failure must not insert a broken reference")
        XCTAssertEqual(editor.string, beforeFailure)
        XCTAssertEqual(editor.selectedRange(), selectionBeforeFailure)
        XCTAssertNotNil(store.error)
    }
    @MainActor func testInvalidImageLeavesTextAndSelectionUnchanged() throws {
        let editor = NoteTextView(frame: .zero)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(directory: folder)
        editor.onPasteImage = store.pasteImage
        editor.string = "Keep this"; editor.setSelectedRange(NSRange(location: 0, length: 4))
        let board = NSPasteboard(name: .init("InvalidImage-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setData(Data("not an image".utf8), forType: .png)
        XCTAssertFalse(editor.readSelection(from: board, type: .png))
        XCTAssertEqual(editor.string, "Keep this")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 4))
        XCTAssertNotNil(store.error)
    }
}
