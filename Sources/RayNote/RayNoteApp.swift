import SwiftUI
import AppKit
import Carbon
import UniformTypeIdentifiers

extension Notification.Name { static let noteCommand = Notification.Name("noteCommand") }

@main enum RayNoteApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        // A separately signed QA bundle can opt into an isolated library without
        // touching the production app's notes or UserDefaults domain.
        let library = (Bundle.main.object(forInfoDictionaryKey: "RayNoteLibraryDirectory") as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
        let delegate = AppDelegate(store: NoteStore(directory: library))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let store: NoteStore
    init(store: NoteStore? = nil) { self.store = store ?? NoteStore(); super.init() }
    var window: NSPanel!
    var statusItem: NSStatusItem!
    private lazy var hotkey = GlobalHotKey { [weak self] in self?.toggle() }
    private var previousApplication: NSRunningApplication?
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["keepOnTop": true, "appearance": "system", "formatBarVisible": true])
        NSApp.setActivationPolicy(.regular)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 410, height: 300), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.title = "RayNote"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = UserDefaults.standard.bool(forKey: "keepOnTop") ? .floating : .normal
        applyAppearance(UserDefaults.standard.string(forKey: "appearance") ?? "system")
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 380, height: 210)
        window.backgroundColor = NSColor.windowBackgroundColor
        window.contentView = NSHostingView(rootView: NotesView(store: store, delegate: self))
        window.setFrameAutosaveName("RayNoteWindow")
        if !window.setFrameUsingName("RayNoteWindow") { window.center() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "RayNote")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "RayNote — click to show or hide; right-click for options"
        buildMenu()
        registerHotkey()
        show()
    }
    func buildMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title); item.submenu = menu; main.addItem(item); return menu
        }
        func command(_ menu: NSMenu, _ title: String, _ key: String, _ value: String, _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: #selector(menuCommand(_:)), keyEquivalent: key)
            item.target = self; item.representedObject = value; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
        }
        let app = submenu("RayNote")
        let about = NSMenuItem(title: "About RayNote", action: #selector(about), keyEquivalent: ""); about.target = self; app.addItem(about)
        command(app, "Settings…", ",", "settings")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit RayNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        command(file, "New Note", "n", "new")
        command(file, "Search Notes…", "p", "search")
        file.addItem(.separator())
        command(file, "Import Markdown…", "o", "import")
        command(file, "Export Markdown…", "e", "export", [.command, .shift])
        command(file, "Hide Notes", "w", "hide")
        let edit = submenu("Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; edit.insertItem(redo, at: 1)
        edit.addItem(.separator())
        for (title, key, action, modifiers): (String, String, NSTextFinder.Action, NSEvent.ModifierFlags) in [
            ("Find in Note…", "f", .showFindInterface, .command),
            ("Find Next", "g", .nextMatch, .command),
            ("Find Previous", "g", .previousMatch, [.command, .shift]),
            ("Find and Replace…", "f", .showReplaceInterface, [.command, .option])
        ] {
            let item = NSMenuItem(title: title, action: #selector(findInNote(_:)), keyEquivalent: key)
            item.target = self
            item.tag = action.rawValue; item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        let format = submenu("Format")
        for (title, key, marker) in [("Bold", "b", "**"), ("Italic", "i", "*"), ("Inline Code", "e", "`"), ("Link", "l", "link"), ("Toggle Task", "\r", "toggleTask")] {
            command(format, title, key, "format:" + marker)
        }
        for (title, key, marker) in [("Heading 1", "1", "# "), ("Heading 2", "2", "## "), ("Heading 3", "3", "### "), ("Code Block", "c", "codeblock")] {
            command(format, title, key, "format:" + marker, [.command, .option])
        }
        for (title, key, marker) in [("Strikethrough", "s", "~~"), ("Quote", "b", "> "), ("Numbered List", "7", "1. "), ("Bullet List", "8", "- "), ("Checklist", "9", "- [ ] ")] {
            command(format, title, key, "format:" + marker, [.command, .shift])
        }
        let view = submenu("View")
        let shortcut = GlobalShortcut.saved
        command(view, "Show / Hide Notes", shortcut.key.lowercased(), "toggle", shortcut.eventModifiers)
        command(view, "Fit Window to Note", "", "fit")
        command(view, "Actions", "k", "actions")
        command(view, "Toggle Format Bar", "f", "formatbar", [.command, .shift])
        command(view, "Toggle Markdown Source", "m", "source", [.command, .shift])
        command(view, "Toggle Reading View", "p", "reading", [.command, .shift])
        command(view, "Keyboard Shortcuts", "/", "help")
        NSApp.mainMenu = main
    }
    @objc func menuCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        if command.hasPrefix("format:"), let editor = window.firstResponder as? NoteTextView {
            editor.format(String(command.dropFirst(7))); return
        }
        switch command {
        case "toggle": toggle()
        case "show": show()
        case "hide": hide()
        case "fit": fitWindowToCurrentNote()
        case "pin":
            let pinned = !UserDefaults.standard.bool(forKey: "keepOnTop")
            UserDefaults.standard.set(pinned, forKey: "keepOnTop")
            window.level = pinned ? .floating : .normal
        case "quit": NSApp.terminate(nil)
        case "import": importNotes()
        case "export": exportNote()
        default: show(); NotificationCenter.default.post(name: .noteCommand, object: command)
        }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(findInNote(_:)) { return window?.attachedSheet == nil && noteEditor != nil }
        guard let command = item.representedObject as? String else { return true }
        if command == "toggle" { return true }
        if command == "fit" { return window?.attachedSheet == nil && noteEditor != nil }
        if command.hasPrefix("format:") { return window?.firstResponder is NoteTextView && window?.attachedSheet == nil }
        return window?.attachedSheet == nil
    }
    private var noteEditor: NoteTextView? {
        func search(_ view: NSView) -> NoteTextView? {
            if let editor = view as? NoteTextView { return editor }
            return view.subviews.lazy.compactMap(search).first
        }
        return window?.contentView.flatMap(search)
    }
    @objc func findInNote(_ sender: NSMenuItem) {
        guard window?.attachedSheet == nil, let editor = noteEditor else { return }
        // The find field has its own text editor; search the note even while it has focus.
        window.makeFirstResponder(editor)
        editor.performTextFinderAction(sender)
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RayNote", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Native Markdown notes. No account. No note limit.")]) }
    func show() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = app }
        if !window.isVisible { store.refreshFromDisk() }
        NSApp.activate(ignoringOtherApps: true)
        // Reopening the app must not steal keyboard focus from an import/export sheet.
        if window.attachedSheet == nil { window.makeKeyAndOrderFront(nil) }
    }
    @objc func hideFromMenu(_ sender: Any?) { hide() }
    func hide() {
        window.orderOut(nil)
        previousApplication?.activate(options: [])
    }
    func fitWindowToCurrentNote() {
        guard let editor = noteEditor, window.attachedSheet == nil,
              let layout = editor.layoutManager, let container = editor.textContainer else { return }
        layout.ensureLayout(for: container)
        fitWindow(to: max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY) + editor.textContainerInset.height * 2)
    }
    func fitWindow(to editorHeight: CGFloat) {
        let available = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = min(max(210, ceil(editorHeight + 32 + (UserDefaults.standard.object(forKey: "formatBarVisible") as? Bool == false ? 0 : 34))), min(720, available.height * 0.8))
        guard abs(window.frame.height - height) > 1 else { return }
        var frame = window.frame
        frame.origin.y = max(available.minY, min(available.maxY, frame.maxY) - height)
        frame.size.height = height
        window.setFrame(frame, display: true, animate: false)
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.refreshFromDisk() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.retryAll()
        guard !store.unrecoverableIDs.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Some edits are only in memory"
        alert.informativeText = "\(store.unrecoverableIDs.count) note(s) couldn't be saved or backed up. Keep RayNote open to export them or fix the storage problem."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !window.isVisible { show() }
        else { sender.activate(ignoringOtherApps: true) }
        return true
    }
    @objc func toggle() {
        if window.isVisible && window.isKeyWindow { hide() } else { show() }
    }
    func noteActionsMenu() -> NSMenu {
        let menu = NSMenu(title: "RayNote")
        for (title, command) in [(window?.isVisible == true ? "Hide Notes" : "Show Notes", window?.isVisible == true ? "hide" : "show"), ("New Note", "new"), ("Search Notes…", "search"), ("Keep on Top", "pin"), ("Fit Window to Note", "fit"), ("", ""), ("Markdown Source / Live Preview", "source"), ("Reading View / Editor", "reading"), ("Show / Hide Format Bar", "formatbar"), ("", ""), ("Import Markdown…", "import"), ("Export Markdown…", "export"), ("Settings…", "settings"), ("", ""), ("Quit RayNote", "quit")] {
            if command.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(menuCommand(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = command
            if command == "pin" { item.state = UserDefaults.standard.bool(forKey: "keepOnTop") ? .on : .off }
            menu.addItem(item)
        }
        return menu
    }
    @objc func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSEvent.modifierFlags.contains(.control) {
            guard let button = statusItem.button else { return }
            noteActionsMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
            return
        }
        if NSEvent.modifierFlags.contains(.option) { store.create(); show() }
        else { toggle() }
    }
    func registerHotkey() {
        if let error = setShortcut(.saved) { store.error = error }
    }
    func setShortcut(_ shortcut: GlobalShortcut) -> String? {
        let result = hotkey.replace(with: shortcut)
        guard result == noErr else {
            return "\(shortcut.label) is unavailable (\(result)). " + (hotkey.current == nil ? "Open RayNote from the menu bar and choose another shortcut in Settings." : "Try another shortcut. Your previous shortcut has been kept.")
        }
        shortcut.save(); buildMenu()
        return nil
    }
    func applyAppearance(_ value: String) {
        window.appearance = value == "dark" ? NSAppearance(named: .darkAqua) : value == "light" ? NSAppearance(named: .aqua) : nil
    }
    func importNotes() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]; panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                do {
                    let imported = try MarkdownAssets.importDocument(at: url, into: self.store.directory)
                    self.store.create(text: imported.text)
                    if !imported.warnings.isEmpty { self.store.notice = "Some image files could not be imported: " + imported.warnings.joined(separator: ", ") }
                } catch { self.store.error = error.localizedDescription }
            }
        }
    }
    func exportNote() {
        guard let note = store.selected else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = String(note.title.prefix(80)).replacingOccurrences(of: "/", with: "-") + ".md"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard let self else { return }
            do {
                let warnings = try MarkdownAssets.exportDocument(note.text, from: self.store.directory, to: url)
                if !warnings.isEmpty { self.store.notice = "Exported Markdown, but some images could not be copied: " + warnings.joined(separator: ", ") }
            } catch { self.store.error = error.localizedDescription }
        }
    }
}

struct NotesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: NoteStore
    let delegate: AppDelegate
    @State private var switcher = false
    @State private var query = ""
    @State private var searchIndex = 0
    @State private var source = false
    @State private var reading = false
    @AppStorage("keepOnTop") private var pinned = true
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("formatBarVisible") private var formatBarVisible = true
    @State private var shortcut = GlobalShortcut.saved
    @State private var shortcutError: String?
    @State private var settings = false
    @State private var actions = false
    @State private var help = false
    @FocusState private var searchFocused: Bool
    private var matches: [Note] { store.notes.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }.sorted { $0.modified > $1.modified } }
    var body: some View {
        VStack(spacing: 0) {
            windowHeader
            if let error = store.error {
                HStack { Image(systemName: "exclamationmark.triangle"); Text(error).textSelection(.enabled); Button("Retry Save") { store.retryAll() } }
                    .font(.caption).foregroundStyle(.red).padding(10)
            }
            if let notice = store.notice {
                HStack { Text(notice); Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notice") }
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
            if let note = store.selected {
                if reading {
                    MarkdownReadingView(text: note.text, onChange: store.update, baseDirectory: store.directory)
                } else {
                MarkdownEditor(noteID: note.id, text: note.text, source: source, onChange: store.update, onPasteImage: store.pasteImage, baseDirectory: store.directory, actionsMenu: { delegate.noteActionsMenu() })
                    .overlay(alignment: .topLeading) {
                        if note.text.isEmpty { Text("Start writing…").font(.system(size: 15)).foregroundStyle(.tertiary).padding(.leading, 25).padding(.top, 14).allowsHitTesting(false) }
                    }
                }
            } else { ContentUnavailableView("No Note Selected", systemImage: "note.text", description: Text("Create a note with ⌘N")) }
            if formatBarVisible {
                FormatBar(editing: !reading, onFormat: { NotificationCenter.default.post(name: .formatNote, object: $0) }, onClose: { formatBarVisible = false })
            }
        }
        .background {
            Rectangle().fill(.regularMaterial)
                .overlay {
                    if colorScheme == .dark {
                        LinearGradient(stops: [.init(color: .black.opacity(0.25), location: 0), .init(color: .black.opacity(0.7), location: 0.5), .init(color: .black.opacity(0.8), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $switcher) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search notes…", text: $query).textFieldStyle(.plain).focused($searchFocused)
                        .onChange(of: query) { _, _ in searchIndex = 0 }
                        .onKeyPress(.downArrow) { searchIndex = min(searchIndex + 1, max(0, matches.count - 1)); return .handled }
                        .onKeyPress(.upArrow) { searchIndex = max(0, searchIndex - 1); return .handled }
                        .onSubmit { if matches.indices.contains(searchIndex) { store.select(matches[searchIndex].id); switcher = false } }
                    Button("Done") { switcher = false }.keyboardShortcut(.cancelAction)
                }.padding(18)
                Divider()
                ScrollViewReader { proxy in
                List(Array(matches.enumerated()), id: \.element.id) { index, note in
                    Button { store.select(note.id); switcher = false } label: {
                        HStack { Image(systemName: "note.text").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 4) { Text(note.title).lineLimit(1); Text(note.modified, style: .relative).font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.selectedID == note.id { Image(systemName: "checkmark").foregroundStyle(.secondary) } }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .listRowBackground(index == searchIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                    .id(note.id)
                }.overlay { if matches.isEmpty { Text("No matching notes").foregroundStyle(.secondary) } }
                .onChange(of: searchIndex) { _, value in if matches.indices.contains(value) { proxy.scrollTo(matches[value].id) } }
                }
                Divider()
                HStack { Text("\(store.notes.count) notes").foregroundStyle(.secondary); Spacer(); Button("New Note  ⌘N") { newNote(); switcher = false } }.font(.caption).padding(14)
            }.frame(width: 440, height: 380).onAppear { searchIndex = 0; searchFocused = true }
        }
        .sheet(isPresented: $help) {
            ShortcutReferenceView(sections: NSApp.mainMenu.map(ShortcutReferenceSection.from(menu:)) ?? [], onDone: { help = false })
        }
        .sheet(isPresented: $settings) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.title2.bold())
                HStack { Text("Show / hide notes"); Spacer(); ShortcutRecorder(shortcut: shortcut) { value in
                    shortcutError = delegate.setShortcut(value)
                    if shortcutError == nil { shortcut = value }
                }.frame(width: 190, height: 28) }
                Text("Click the shortcut, then press a key with Control, Option or Command. Escape cancels.").font(.caption).foregroundStyle(.secondary)
                if let shortcutError { Text(shortcutError).font(.caption).foregroundStyle(.red) }
                Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
                Toggle("Keep notes above other windows", isOn: $pinned)
                Text("Window size stays the same across notes. Drag an edge to resize it.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Reset Shortcut") { shortcutError = delegate.setShortcut(.standard); if shortcutError == nil { shortcut = .standard } }; Spacer(); Button("Done") { settings = false }.keyboardShortcut(.defaultAction) }
            }.padding(26).frame(width: 410)
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteCommand)) { notification in
            switch notification.object as? String {
            case "new": newNote()
            case "search": query = ""; switcher = true
            case "actions": actions.toggle()
            case "source": source.toggle(); reading = false
            case "reading": reading.toggle()
            case "help": help = true
            case "formatbar": formatBarVisible.toggle()
            case "settings": settings = true
            default: break
            }
        }
        .onChange(of: appearance) { _, value in delegate.applyAppearance(value) }
        .onChange(of: pinned) { _, value in delegate.window.level = value ? .floating : .normal }
        .onExitCommand { delegate.hide() }
    }
    private var windowHeader: some View {
            ZStack {
                Button { query = ""; switcher.toggle() } label: { Text(store.selected?.title ?? "RayNote").lineLimit(1).frame(maxWidth: .infinity) }
                    .buttonStyle(.plain).padding(.horizontal, 125).help("Switch note (⌘P)").keyboardShortcut("p")
                HStack(spacing: 11) {
                    Spacer()
                    Button { pinned.toggle() } label: { Image(systemName: pinned ? "pin.fill" : "pin") }
                        .help(pinned ? "Stop Keeping on Top" : "Keep on Top").accessibilityLabel("Keep on Top")
                    Button { actions.toggle() } label: { Image(systemName: "command") }.keyboardShortcut("k").help("Actions (⌘K)")
                        .popover(isPresented: $actions, arrowEdge: .bottom) { actionMenu }
                    Button { query = ""; switcher.toggle() } label: { Image(systemName: "note.text") }.help("Browse notes (⌘P)")
                    Button { newNote() } label: { Image(systemName: "plus") }.keyboardShortcut("n").help("New note (⌘N)")
                }.padding(.trailing, 10)
            }.font(.system(size: 13)).foregroundStyle(.secondary).buttonStyle(.plain).frame(height: 32)
            .contextMenu {
                Button("New Note") { newNote() }
                Button("Search Notes…") { switcher = true }
                Toggle("Keep on Top", isOn: $pinned)
                Divider()
                Button("Settings…") { settings = true }
                Button("Hide Notes") { delegate.hide() }
            }
    }
    private func newNote() { reading = false; store.create() }
    var actionMenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            action("New Note", icon: "plus", shortcut: "⌘N") { newNote() }
            action("Search Notes", icon: "magnifyingglass", shortcut: "⌘P") { switcher = true }
            action(pinned ? "Stop Keeping on Top" : "Keep on Top", icon: "pin") { pinned.toggle(); delegate.window.level = pinned ? .floating : .normal }
            action(formatBarVisible ? "Hide Format Bar" : "Show Format Bar", icon: "textformat", shortcut: "⇧⌘F") { formatBarVisible.toggle() }
            action(source ? "Live Markdown" : "Markdown Source", icon: "chevron.left.forwardslash.chevron.right", shortcut: "⇧⌘M") { source.toggle(); reading = false }
            action(reading ? "Edit Markdown" : "Reading View", icon: reading ? "pencil" : "eye", shortcut: "⌘⇧P") { reading.toggle() }
            if !reading {
                action("Code Block", icon: "curlybraces") { NotificationCenter.default.post(name: .formatNote, object: "codeblock") }
            }
            Divider().padding(.vertical, 5)
            action("Import Markdown…", icon: "square.and.arrow.down") { delegate.importNotes() }
            action("Export Markdown…", icon: "square.and.arrow.up") { delegate.exportNote() }
            action("Copy Markdown", icon: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.selected?.text ?? "", forType: .string) }
            action("Show Notes in Finder", icon: "folder") { NSWorkspace.shared.open(store.directory) }
            Divider().padding(.vertical, 5)
            action("Delete Note", icon: "trash") { store.deleteSelected() }
            action("Restore Deleted Notes", icon: "arrow.uturn.backward") { store.restoreDeleted() }
            Divider().padding(.vertical, 5)
            action("Keyboard Shortcuts", icon: "keyboard", shortcut: "⌘/") { help = true }
            action("Settings", icon: "gearshape") { settings = true }
            action("Quit RayNote", icon: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }.padding(10).frame(width: 260)
    }
    func action(_ title: String, icon: String, shortcut: String = "", perform: @escaping () -> Void) -> some View {
        Button { actions = false; perform() } label: { HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); Text(shortcut).foregroundStyle(.tertiary) }.font(.system(size: 12)).padding(7).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}
