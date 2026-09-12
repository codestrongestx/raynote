import AppKit
import SwiftUI

/// Reproducible native UI renders containing only the sample note below.
@main enum ReadmeImages {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = NoteStore(directory: temporary)
        store.update("""
        # A little room to think

        Your ideas. Your Markdown. Your Mac.

        ## Make space for good work

        - [x] Capture the first spark
        - [x] Keep everything in plain text
        - [ ] Turn a small idea into something real

        > Keep your notes close. Keep your flow.

        ## A plan, in a few lines

        | Chapter | Status |
        | :--- | :--- |
        | An idea | Captured |
        | A first draft | In progress |
        | The next step | Yours |

        """)
        let suiteName = "RayNoteReadme-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "formatBarVisible")
        defaults.set(true, forKey: "keepOnTop")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delegate = AppDelegate(store: store)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 470), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        delegate.window = panel
        defer { panel.close() }
        for dark in [true, false] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            panel.appearance = appearance
            let content = NSHostingView(rootView: NotesView(store: store, delegate: delegate)
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, dark ? .dark : .light))
            panel.contentView = content
            panel.setContentSize(NSSize(width: 480, height: 470))
            content.layoutSubtreeIfNeeded()
            func findEditor(_ view: NSView) -> NoteTextView? {
                if let editor = view as? NoteTextView { return editor }
                return view.subviews.lazy.compactMap(findEditor).first
            }
            if let editor = findEditor(content) {
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                (editor.delegate as? MarkdownEditor.Coordinator)?.style()
            }
            content.layoutSubtreeIfNeeded()
            let chrome = content.superview!
            chrome.layoutSubtreeIfNeeded()
            let bitmap = chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds)!
            appearance.performAsCurrentDrawingAppearance { chrome.cacheDisplay(in: chrome.bounds, to: bitmap) }
            let data = bitmap.representation(using: .png, properties: [:])!
            try data.write(to: output.appendingPathComponent(dark ? "raynote-dark.png" : "raynote-light.png"))
        }
    }
}
