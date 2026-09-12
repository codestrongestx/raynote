import Foundation
import Combine

struct Note: Identifiable, Equatable, Codable {
    var id: UUID
    var text: String
    var modified: Date
    var title: String {
        var start = text.startIndex
        while start < text.endIndex {
            let end = text[start...].firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[start..<end].trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: "# *\t"))
                return clean.isEmpty ? "Untitled Note" : clean
            }
            if end == text.endIndex { break }
            start = text.index(after: end)
        }
        return "Untitled Note"
    }
}

@MainActor final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedID: UUID?
    @Published var error: String?
    @Published var notice: String?
    @Published var lastSaved: Date?
    @Published private(set) var unsavedIDs: Set<UUID> = []
    private(set) var unrecoverableIDs: Set<UUID> = []
    let directory: URL
    let recoveryDirectory: URL
    private let preferences: UserDefaults?
    private let writeFile: (String, URL) throws -> Void
    /// The exact version last read or written, used to detect external edits before saving.
    private var diskVersions: [UUID: String] = [:]
    private var saveErrors: [UUID: String] = [:]
    var selected: Note? { notes.first { $0.id == selectedID } }

    init(directory: URL? = nil, writeFile: @escaping (String, URL) throws -> Void = { try $0.write(to: $1, atomically: true, encoding: .utf8) }) {
        preferences = directory == nil ? .standard : nil
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RayNote/Notes", isDirectory: true)
        recoveryDirectory = self.directory.appendingPathExtension("recovery")
        self.writeFile = writeFile
        let saved = preferences?.string(forKey: "selectedNote").flatMap(UUID.init(uuidString:))
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            try reload()
        } catch { self.error = error.localizedDescription }
        recoverDrafts()
        if notes.isEmpty && error == nil { create() }
        selectedID = notes.contains(where: { $0.id == saved }) ? saved : notes.first?.id
    }

    /// Refreshes clean notes from disk while retaining every unsaved in-memory draft.
    func reload() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        var loaded: [UUID: Note] = [:]
        let previousNotes = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var warnings: [String] = []
        for file in files where file.pathExtension.lowercased() == "md" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date()
                loaded[id] = Note(id: id, text: text, modified: modified)
                if !unsavedIDs.contains(id) { diskVersions[id] = text }
            } catch {
                warnings.append(file.lastPathComponent)
                // One unreadable note must not hide the rest of the library or erase a loaded copy.
                if let previous = previousNotes[id] { loaded[id] = previous }
            }
        }
        for note in notes where unsavedIDs.contains(note.id) { loaded[note.id] = note }
        // Equal timestamps are common after importing/copying files. Keep their order
        // deterministic so an unchanged refresh does not invalidate the entire UI.
        let refreshed = loaded.values.sorted {
            $0.modified == $1.modified ? $0.id.uuidString < $1.id.uuidString : $0.modified > $1.modified
        }
        if notes != refreshed { notes = refreshed }
        diskVersions = diskVersions.filter { loaded[$0.key] != nil }
        if !notes.contains(where: { $0.id == selectedID }) { selectedID = notes.first?.id }
        if !warnings.isEmpty { error = "Couldn't read \(warnings.count) note file(s). The files have been left untouched: \(warnings.joined(separator: ", "))" }
    }
    func refreshFromDisk() {
        do { try reload() } catch { self.error = "Couldn't refresh notes: \(error.localizedDescription)" }
    }
    func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("md") }
    private func recoveryURL(_ id: UUID) -> URL { recoveryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    func select(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        selectedID = id; preferences?.set(id.uuidString, forKey: "selectedNote")
    }
    func create(text: String = "") {
        let note = Note(id: UUID(), text: text, modified: Date())
        notes.insert(note, at: 0); select(note.id)
        save(note.id)
    }
    func update(_ text: String) {
        guard let id = selectedID, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text; notes[index].modified = Date()
        save(id)
    }
    func pasteImage(_ data: Data) -> String? {
        do { return try MarkdownAssets.storePastedImage(data, in: directory) }
        catch { self.error = "Couldn't save the pasted image. Your note is unchanged. \(error.localizedDescription)"; return nil }
    }

    private struct Recovery: Codable {
        var note: Note
        var diskVersion: String?
    }
    private func save(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        unsavedIDs.insert(id)
        do {
            let path = url(for: id)
            if FileManager.default.fileExists(atPath: path.path) {
                let current = try String(contentsOf: path, encoding: .utf8)
                if current != diskVersions[id] && current != note.text {
                    // Preserve the external version as its own ordinary Markdown note before replacing it.
                    let conflict = Note(id: UUID(), text: current, modified: Date())
                    try writeFile(current, url(for: conflict.id))
                    notes.append(conflict); diskVersions[conflict.id] = current
                    diskVersions[id] = current
                    notice = "An outside edit was preserved as a separate note. Both versions are in your library."
                }
            }
            try writeFile(note.text, path)
            // If an older recovery file cannot be removed, keep the save pending so it cannot
            // unexpectedly resurrect stale text on the next launch.
            if FileManager.default.fileExists(atPath: recoveryURL(id).path) { try FileManager.default.removeItem(at: recoveryURL(id)) }
            diskVersions[id] = note.text
            unsavedIDs.remove(id); unrecoverableIDs.remove(id); saveErrors.removeValue(forKey: id)
            lastSaved = Date()
            error = saveErrors.isEmpty ? nil : "\(saveErrors.count) note(s) still need saving. Retry Save will retry all drafts."
        } catch {
            saveErrors[id] = error.localizedDescription
            do {
                try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
                let recovery = Recovery(note: note, diskVersion: diskVersions[id])
                let data = try JSONEncoder().encode(recovery)
                try writeFile(String(decoding: data, as: UTF8.self), recoveryURL(id))
                unrecoverableIDs.remove(id)
                self.error = "Couldn't save \(note.title). A recovery draft is on disk. \(error.localizedDescription)"
            } catch {
                unrecoverableIDs.insert(id)
                self.error = "\(unsavedIDs.count) note(s) couldn't be saved; \(unrecoverableIDs.count) draft(s) exist only in memory. Keep RayNote open and export your notes."
            }
        }
    }
    func retryAll() {
        for id in Array(unsavedIDs) { save(id) }
    }
    private func recoverDrafts() {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                do {
                    let record = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: file))
                    if let index = notes.firstIndex(where: { $0.id == record.note.id }) { notes[index] = record.note }
                    else { notes.insert(record.note, at: 0) }
                    diskVersions[record.note.id] = record.diskVersion
                    unsavedIDs.insert(record.note.id)
                } catch { self.error = "A recovery file couldn't be read and was left untouched: \(file.lastPathComponent)" }
            }
            if !unsavedIDs.isEmpty { notice = "Recovered \(unsavedIDs.count) unsaved draft(s)."; retryAll() }
        } catch { self.error = "Couldn't open recovery drafts: \(error.localizedDescription)" }
    }
    func deleteSelected() {
        guard let id = selectedID else { return }
        if unsavedIDs.contains(id) { save(id) }
        guard !unsavedIDs.contains(id) else { return } // Never delete a draft that has not reached its note file.
        do {
            let trash = directory.appendingPathComponent("Recently Deleted", isDirectory: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url(for: id), to: trash.appendingPathComponent(id.uuidString).appendingPathExtension("md"))
            notes.removeAll { $0.id == id }; diskVersions.removeValue(forKey: id)
            selectedID = notes.first?.id
            if let selectedID { select(selectedID) }
            if notes.isEmpty { create() }
        } catch { self.error = error.localizedDescription }
    }
    func restoreDeleted() {
        do {
            let trash = directory.appendingPathComponent("Recently Deleted")
            guard FileManager.default.fileExists(atPath: trash.path) else { notice = "No deleted notes to restore."; return }
            let files = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "md" {
                var destination = directory.appendingPathComponent(file.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) { destination = url(for: UUID()) }
                try FileManager.default.moveItem(at: file, to: destination)
            }
            try reload()
        } catch { self.error = error.localizedDescription }
    }
}
