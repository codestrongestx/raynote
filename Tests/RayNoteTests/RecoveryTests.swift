import XCTest
@testable import RayNote

final class RecoveryTests: XCTestCase {
    @MainActor func testFailedWriteSurvivesSwitchReloadAndRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: directory.appendingPathExtension("recovery")) }
        var fail = false
        let store = NoteStore(directory: directory) { text, path in
            if fail && path.deletingLastPathComponent().path == directory.path { throw CocoaError(.fileWriteNoPermission) }
            try text.write(to: path, atomically: true, encoding: .utf8)
        }
        store.update("# Original")
        let id = try XCTUnwrap(store.selectedID)
        fail = true
        store.update("# Unsaved 👋\nNever lose this")
        XCTAssertTrue(store.unsavedIDs.contains(id))
        XCTAssertTrue(store.unrecoverableIDs.isEmpty)
        try store.reload()
        XCTAssertEqual(store.selected?.text, "# Unsaved 👋\nNever lose this")
        store.create(text: "Another draft")
        store.select(id)
        XCTAssertNotNil(store.error)
        let restarted = NoteStore(directory: directory)
        XCTAssertEqual(restarted.notes.first(where: { $0.id == id })?.text, "# Unsaved 👋\nNever lose this")
        XCTAssertTrue(restarted.unsavedIDs.isEmpty)
        XCTAssertEqual(try String(contentsOf: restarted.url(for: id), encoding: .utf8), "# Unsaved 👋\nNever lose this")
    }
    @MainActor func testExternalEditIsPreservedBeforeLocalSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.update("Original")
        let id = try XCTUnwrap(store.selectedID)
        try "External version 👋".write(to: store.url(for: id), atomically: true, encoding: .utf8)
        store.update("My local edit")
        XCTAssertEqual(store.selected?.text, "My local edit")
        let conflict = try XCTUnwrap(store.notes.first { $0.text == "External version 👋" })
        XCTAssertNotEqual(conflict.id, id)
        XCTAssertEqual(try String(contentsOf: store.url(for: conflict.id), encoding: .utf8), "External version 👋")
        XCTAssertEqual(try String(contentsOf: store.url(for: id), encoding: .utf8), "My local edit")
    }
    @MainActor func testDeleteRefusesAnUnrecoverableDraftAndRetrySavesAll() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: directory.appendingPathExtension("recovery")) }
        var fail = false
        let store = NoteStore(directory: directory) { text, path in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try text.write(to: path, atomically: true, encoding: .utf8)
        }
        let id = try XCTUnwrap(store.selectedID)
        fail = true
        store.update("Keep this draft")
        store.deleteSelected()
        XCTAssertEqual(store.selected?.text, "Keep this draft")
        XCTAssertTrue(store.unrecoverableIDs.contains(id))
        store.create(text: "Second draft")
        XCTAssertEqual(store.unsavedIDs.count, 2)
        fail = false; store.retryAll()
        XCTAssertTrue(store.unsavedIDs.isEmpty)
        XCTAssertTrue(store.unrecoverableIDs.isEmpty)
        XCTAssertEqual(try String(contentsOf: store.url(for: id), encoding: .utf8), "Keep this draft")
    }
    @MainActor func testOneUnreadableNoteDoesNotHideTheLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        store.update("Readable")
        try Data([0xFF, 0xFE, 0xFF]).write(to: store.url(for: UUID()))
        let reopened = NoteStore(directory: directory)
        XCTAssertEqual(reopened.notes.count, 1)
        XCTAssertEqual(reopened.notes.first?.text, "Readable")
        XCTAssertNotNil(reopened.error)
    }
    @MainActor func testRecoveryDoesNotOverwriteAnExternalChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: directory.appendingPathExtension("recovery")) }
        var fail = false
        let store = NoteStore(directory: directory) { text, path in
            if fail && path.deletingLastPathComponent().path == directory.path { throw CocoaError(.fileWriteNoPermission) }
            try text.write(to: path, atomically: true, encoding: .utf8)
        }
        store.update("Baseline")
        let id = try XCTUnwrap(store.selectedID)
        fail = true; store.update("Recovered local work")
        try "Outside work".write(to: store.url(for: id), atomically: true, encoding: .utf8)
        let reopened = NoteStore(directory: directory)
        XCTAssertTrue(reopened.notes.contains { $0.text == "Outside work" })
        XCTAssertEqual(reopened.notes.first(where: { $0.id == id })?.text, "Recovered local work")
    }
}
