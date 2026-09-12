import XCTest
import Combine
@testable import RayNote

final class NoteStoreTests: XCTestCase {
    @MainActor func testUnchangedRefreshDoesNotPublishButSameTimestampEditsDo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let ids = (0..<100).map { _ in UUID() }
        for id in ids {
            let path = directory.appendingPathComponent(id.uuidString).appendingPathExtension("md")
            try "Original".write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: path.path)
        }
        let store = NoteStore(directory: directory)
        var publications = 0
        let subscription = store.$notes.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        for _ in 0..<3 { try store.reload() }
        XCTAssertEqual(publications, 0)
        let changedID = ids[0]
        let changedPath = store.url(for: changedID)
        try "External".write(to: changedPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: changedPath.path)
        try store.reload()
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(store.notes.first(where: { $0.id == changedID })?.text, "External")
        try FileManager.default.removeItem(at: changedPath)
        try store.reload()
        XCTAssertEqual(publications, 2)
        XCTAssertEqual(store.notes.count, 99)
        XCTAssertFalse(store.notes.contains(where: { $0.id == changedID }))
    }
    @MainActor func testMarkdownPersistsAndRestoresWithoutLoss() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        let markdown = "# 中文 👋\n\n- [ ] task\n\n```swift\nlet x = 1\n```\n"
        store.update(markdown)
        let id = try XCTUnwrap(store.selectedID)
        XCTAssertEqual(try String(contentsOf: store.url(for: id), encoding: .utf8), markdown)
        let reloaded = NoteStore(directory: directory)
        XCTAssertEqual(reloaded.notes.first?.text, markdown)
        store.deleteSelected()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: id).path))
        store.restoreDeleted()
        XCTAssertEqual(store.notes.first(where: { $0.id == id })?.text, markdown)
    }
    @MainActor func testNoFiveNoteLimitAndLargeNoteRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NoteStore(directory: directory)
        for i in 0..<100 { store.create(text: "# Note \(i)") }
        let large = String(repeating: "Markdown 📝\n", count: 100_000)
        store.update(large)
        let reloaded = NoteStore(directory: directory)
        XCTAssertEqual(reloaded.notes.count, 101)
        XCTAssertTrue(reloaded.notes.contains { $0.text == large })
    }
    func testTitle() {
        XCTAssertEqual(Note(id: UUID(), text: "\n## My note\nbody", modified: Date()).title, "My note")
        XCTAssertEqual(Note(id: UUID(), text: "", modified: Date()).title, "Untitled Note")
    }
}
