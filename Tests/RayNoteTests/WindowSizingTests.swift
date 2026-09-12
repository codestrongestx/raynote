import AppKit
import XCTest
@testable import RayNote

final class WindowSizingTests: XCTestCase {
    @MainActor func testContentSizingKeepsWidthAndTopAndCapsLongNotes() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let delegate = AppDelegate(store: NoteStore(directory: directory))
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        delegate.window = NSPanel(contentRect: NSRect(x: screen.minX + 40, y: screen.minY + 40, width: 540, height: 400), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        delegate.window.isReleasedWhenClosed = false
        defer { delegate.window.close() }
        let original = delegate.window.frame
        delegate.fitWindow(to: 100)
        XCTAssertEqual(delegate.window.frame.width, original.width)
        XCTAssertEqual(delegate.window.frame.height, 210)
        XCTAssertEqual(delegate.window.frame.maxY, original.maxY, accuracy: 1)
        delegate.fitWindow(to: 100_000)
        XCTAssertLessThanOrEqual(delegate.window.frame.height, min(720, screen.height * 0.8) + 1)
        XCTAssertGreaterThanOrEqual(delegate.window.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(delegate.window.frame.maxY, screen.maxY)
    }
}
