import AppKit
import XCTest
@testable import RayNote

final class NativeFindTests: XCTestCase {
    @MainActor func testNativeFindNavigatesUnicodeAndEscapeClosesBar() throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        let editor = NoteTextView(frame: scroll.bounds)
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.string = "👋 needle **needle** end"
        scroll.documentView = editor; window.contentView = scroll
        window.makeFirstResponder(editor)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let delegate = AppDelegate(store: NoteStore(directory: folder))
        delegate.window = window
        let board = NSPasteboard(name: .find)
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            board.clearContents()
            board.writeObjects(saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }
        func find(_ action: NSTextFinder.Action) {
            let sender = NSMenuItem(); sender.tag = action.rawValue
            delegate.findInNote(sender)
        }
        let first = (editor.string as NSString).range(of: "needle")
        editor.setSelectedRange(first)
        find(.setSearchString)
        XCTAssertEqual(board.string(forType: .string), "needle")
        find(.showFindInterface)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(scroll.isFindBarVisible)
        find(.nextMatch)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 12, length: 6))
        find(.previousMatch)
        XCTAssertEqual(editor.selectedRange(), first)
        XCTAssertEqual(editor.string, "👋 needle **needle** end")
        editor.cancelOperation(nil)
        XCTAssertFalse(scroll.isFindBarVisible)
    }
}
