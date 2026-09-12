import AppKit
import SwiftUI
import XCTest
@testable import RayNote

final class FormatBarTests: XCTestCase {
    @MainActor func testReferenceWindowFixture() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.update("# Meeting Notes 14/11\n\n1. Samuel to design landing page\n2. Pedro to plan launch campaign\n3. Bruno to go over")
        let delegate = AppDelegate(store: store)
        let suite = "RayNoteFixture-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "formatBarVisible")
        defer { defaults.removePersistentDomain(forName: suite) }
        delegate.window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 210), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        delegate.window.isReleasedWhenClosed = false
        defer { delegate.window.close() }
        for dark in [false, true] {
            for width in [380.0, 410.0] {
                let view = NSHostingView(rootView: NotesView(store: store, delegate: delegate).defaultAppStorage(defaults).environment(\.colorScheme, dark ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
                view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                view.frame = NSRect(x: 0, y: 0, width: width, height: 210)
                delegate.window.setContentSize(view.frame.size)
                delegate.window.contentView = view
                view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(view.fittingSize.width, width)
                if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
                    let target = URL(fileURLWithPath: folder, isDirectory: true)
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let name = "reference-window-" + (dark ? "dark" : "light") + (width == 380 ? "-minimum" : "") + ".png"
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent(name))
                }
            }
        }
        XCTAssertEqual(store.selected?.title, "Meeting Notes 14/11")
    }
    @MainActor func testFormatBarFitsMinimumWindowWidth() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            let view = NSHostingView(rootView: FormatBar(editing: true, onFormat: { _ in }, onClose: {})
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            view.frame = NSRect(x: 0, y: 0, width: 380, height: 34)
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(view.fittingSize.width, 380)
            if let folder = ProcessInfo.processInfo.environment["RAYNOTE_RENDER_DIR"] {
                let target = URL(fileURLWithPath: folder, isDirectory: true)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: target.appendingPathComponent(dark ? "format-bar-dark.png" : "format-bar-light.png"))
            }
        }
    }
}
