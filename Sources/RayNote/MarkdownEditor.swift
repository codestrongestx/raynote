import AppKit
import SwiftUI

extension Notification.Name {
    static let formatNote = Notification.Name("formatNote")
}

struct MarkdownEditor: NSViewRepresentable {
    var noteID: UUID
    var text: String
    var source: Bool
    var onChange: (String) -> Void
    var onPasteImage: ((Data) -> String?)? = nil
    var baseDirectory: URL? = nil
    var actionsMenu: (() -> NSMenu)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = NoteTextView()
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = true
        editor.allowsUndo = true
        editor.onPasteImage = onPasteImage
        editor.actionsMenu = actionsMenu
        editor.baseDirectory = baseDirectory
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 20, height: 13)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        context.coordinator.editor = editor
        DispatchQueue.main.async { [weak editor] in
            if let editor, editor.window?.isKeyWindow == true, editor.window?.attachedSheet == nil { editor.window?.makeFirstResponder(editor) }
        }
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .formatNote, object: nil, queue: .main) { [weak editor] notification in
            guard let marker = notification.object as? String else { return }
            editor?.format(marker)
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(from: self)
    }
    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var editor: NoteTextView?
        var observer: NSObjectProtocol?
        var selections: [UUID: NSRange] = [:]
        var scrollPositions: [UUID: NSPoint] = [:]
        private var applyingModel = false
        var loaded = false
        func update(from next: MarkdownEditor) {
            guard let editor else { parent = next; return }
            let switched = parent.noteID != next.noteID
            let oldOrigin = editor.enclosingScrollView?.contentView.bounds.origin ?? .zero
            if switched {
                selections[parent.noteID] = editor.selectedRange()
                scrollPositions[parent.noteID] = oldOrigin
            }
            parent = next
            editor.onPasteImage = next.onPasteImage
            editor.actionsMenu = next.actionsMenu
            editor.baseDirectory = next.baseDirectory
            let changed = editor.string != next.text || switched
            applyingModel = true
            if changed {
                let selection = switched || !loaded ? selections[next.noteID] ?? NSRange(location: 0, length: 0) : editor.selectedRange()
                editor.string = next.text
                if switched || !loaded { editor.undoManager?.removeAllActions() }
                editor.setSelectedRange(NSRange(location: min(selection.location, next.text.utf16.count), length: min(selection.length, max(0, next.text.utf16.count - selection.location))))
            }
            applyingModel = false
            loaded = true
            style()
            if changed, let scroll = editor.enclosingScrollView {
                // Restore the viewport only after syntax projection and text layout finish.
                let origin = switched ? scrollPositions[next.noteID] ?? .zero : oldOrigin
                let proposed = NSRect(origin: origin, size: scroll.contentView.bounds.size)
                scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(proposed).origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        init(_ parent: MarkdownEditor) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        func textDidChange(_ notification: Notification) {
            guard let editor, !applyingModel else { return }
            parent.onChange(editor.string)
            style()
        }
        private var styling = false
        private struct StyleKey: Equatable {
            let noteID: UUID
            let text: String
            let source: Bool
            let activeLine: NSRange
            let width: CGFloat
            let directory: URL?
        }
        private var lastStyle: StyleKey?
        func textViewDidChangeSelection(_ notification: Notification) { style() }
        func style() {
            guard let editor, !styling, !applyingModel, !editor.hasMarkedText() else { return }
            let text = editor.string as NSString
            let selected = editor.selectedRange()
            let activeLine = !parent.source && NSMaxRange(selected) <= text.length ? text.lineRange(for: selected) : NSRange(location: 0, length: 0)
            let key = StyleKey(noteID: parent.noteID, text: editor.string, source: parent.source, activeLine: activeLine, width: editor.textContainer?.containerSize.width ?? editor.bounds.width, directory: editor.baseDirectory)
            guard key != lastStyle else { return }
            styling = true
            LiveMarkdown.style(editor, sourceMode: parent.source)
            lastStyle = key
            if let layout = editor.layoutManager, let container = editor.textContainer {
                layout.ensureLayout(for: container)

            }
            styling = false
        }

    }
}

final class NoteTextView: NSTextView {
    var actionsMenu: (() -> NSMenu)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = (super.menu(for: event)?.copy() as? NSMenu) ?? NSMenu()
        if let actions = actionsMenu?() {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for item in actions.items {
                actions.removeItem(item)
                menu.addItem(item)
            }
        }
        return menu
    }

    private var widthRefreshPending = false
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        guard widthChanged, !widthRefreshPending else { return }
        widthRefreshPending = true
        // SwiftUI assigns the scroll view's real width after its first update.
        // Reproject after layout so images/tables don't keep zero-width geometry
        // until the next selection or text change. Avoid reentering TextKit layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.widthRefreshPending = false
            (self.delegate as? MarkdownEditor.Coordinator)?.style()
        }
    }
    var baseDirectory: URL?
    let imagePreviews = LocalImagePreviewCache()
    var liveImages: [LiveImagePreview] = []
    var liveTableRows: [LiveTableRow] = []
    func tableRowRect(_ row: LiveTableRow) -> NSRect? {
        guard row.range.location < string.utf16.count, let layout = layoutManager else { return nil }
        let line = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: row.range.location), effectiveRange: nil)
        return NSRect(x: textContainerOrigin.x + 5, y: textContainerOrigin.y + line.minY, width: row.width, height: row.height)
    }
    @discardableResult func revealTable(at point: NSPoint) -> Bool {
        guard let row = liveTableRows.first(where: { tableRowRect($0)?.contains(point) == true }) else { return false }
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: row.range.location, length: 0))
        return true
    }
    func imageRect(_ preview: LiveImagePreview) -> NSRect? {
        guard preview.range.location < string.utf16.count, let layout = layoutManager else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: preview.range.location)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return NSRect(origin: NSPoint(x: textContainerOrigin.x + 5, y: textContainerOrigin.y + line.minY + 8), size: preview.size)
    }
    @discardableResult func revealImage(at point: NSPoint) -> Bool {
        guard let preview = liveImages.first(where: { imageRect($0)?.contains(point) == true }) else { return false }
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: preview.range.location + 2, length: 0))
        return true
    }
    var onPasteImage: ((Data) -> String?)?
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + (onPasteImage == nil ? [] : [.png, .tiff])
    }
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .png || type == .tiff else { return super.readSelection(from: pboard, type: type) }
        guard let data = pboard.data(forType: type), let markdown = onPasteImage?(data) else { return false }
        let source = string as NSString, selection = selectedRange()
        let before = source.substring(to: selection.location)
        let after = source.substring(from: NSMaxRange(selection))
        let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let trailing = after.hasPrefix("\n\n") ? "" : after.hasPrefix("\n") ? "\n" : "\n\n"
        breakUndoCoalescing()
        insertText(leading + markdown + trailing, replacementRange: selection)
        breakUndoCoalescing()
        return true
    }
    let markdownGlyphs = MarkdownGlyphDelegate()
    var liveTasks: [LiveTask] = []
    var liveCodeBlocks: [NSRange] = []
    var liveQuotes: [NSRange] = []
    var liveRules: [NSRange] = []

    func codeBlockRect(_ range: NSRange) -> NSRect? {
        guard range.length > 0, NSMaxRange(range) <= string.utf16.count,
              let layout = layoutManager, let container = textContainer else { return nil }
        let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
        rect.origin.x = textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y - 3
        rect.size.width = container.containerSize.width
        rect.size.height += 6
        return rect
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for row in liveTableRows {
            guard let frame = tableRowRect(row), frame.intersects(rect) else { continue }
            if row.header { NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill(); frame.fill() }
            let width = row.width / CGFloat(row.cells.count)
            for (column, cell) in row.cells.enumerated() {
                let cellRect = NSRect(x: frame.minX + CGFloat(column) * width + 8, y: frame.minY + 8, width: max(1, width - 16), height: row.height - 16)
                cell.draw(with: cellRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
                NSColor.separatorColor.setFill()
                NSRect(x: frame.minX + CGFloat(column) * width, y: frame.minY, width: 0.5, height: frame.height).fill()
            }
            NSColor.separatorColor.setFill()
            NSRect(x: frame.maxX - 0.5, y: frame.minY, width: 0.5, height: frame.height).fill()
            NSRect(x: frame.minX, y: frame.maxY - 0.5, width: frame.width, height: 0.5).fill()
        }
        for preview in liveImages {
            guard let frame = imageRect(preview), frame.intersects(rect) else { continue }
            if let image = imagePreviews.image(for: preview) {
                image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            } else {
                ("Image unavailable" as NSString).draw(at: frame.origin, withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor])
            }
        }
        for range in liveCodeBlocks {
            guard let panel = codeBlockRect(range), panel.intersects(rect) else { continue }
            NSColor.quaternaryLabelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: panel, xRadius: 7, yRadius: 7).fill()
        }
        for range in liveQuotes {
            guard let panel = codeBlockRect(range), panel.intersects(rect) else { continue }
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: textContainerOrigin.x + 6, y: panel.minY + 3, width: 2, height: max(2, panel.height - 6)), xRadius: 1, yRadius: 1).fill()
        }
        guard let layout = layoutManager else { return }
        for range in liveRules where range.location < string.utf16.count {
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let rule = NSRect(x: textContainerOrigin.x + 5, y: textContainerOrigin.y + line.midY,
                              width: max(0, (textContainer?.containerSize.width ?? 0) - 10), height: 1)
            if rule.intersects(rect) { NSColor.separatorColor.setFill(); rule.fill() }
        }
    }

    func taskRect(_ task: LiveTask) -> NSRect? {
        guard let layout = layoutManager, task.bodyOffset < (string as NSString).length else { return nil }
        let glyph = layout.glyphIndexForCharacter(at: task.bodyOffset)
        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return NSRect(x: textContainerOrigin.x + task.indent + 5,
                      y: textContainerOrigin.y + fragment.minY + 3, width: 13, height: 13)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for task in liveTasks {
            guard let rect = taskRect(task), rect.intersects(dirtyRect) else { continue }
            let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            if task.checked { NSColor.controlAccentColor.setFill(); path.fill() }
            else { NSColor.secondaryLabelColor.setStroke(); path.lineWidth = 1.2; path.stroke() }
            if task.checked {
                let check = NSBezierPath()
                check.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
                check.line(to: NSPoint(x: rect.minX + 5.5, y: rect.maxY - 3))
                check.line(to: NSPoint(x: rect.maxX - 2.5, y: rect.minY + 3))
                check.lineWidth = 1.5; NSColor.white.setStroke(); check.stroke()
            }
        }
    }
    @discardableResult func toggleTask(at point: NSPoint) -> Bool {
        guard let task = liveTasks.first(where: { taskRect($0)?.insetBy(dx: -4, dy: -4).contains(point) == true }) else { return false }
        let selection = selectedRange()
        insertText(task.checked ? " " : "x", replacementRange: NSRange(location: task.checkOffset, length: 1))
        setSelectedRange(selection)
        return true
    }
    override func mouseDown(with event: NSEvent) {
        if revealTable(at: convert(event.locationInWindow, from: nil)) { return }
        if revealImage(at: convert(event.locationInWindow, from: nil)) { return }
        if toggleTask(at: convert(event.locationInWindow, from: nil)) { return }
        super.mouseDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if let scroll = enclosingScrollView, scroll.isFindBarVisible {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.hideFindInterface.rawValue
            performTextFinderAction(item)
            window?.makeFirstResponder(self)
            return
        }
        if !NSApp.sendAction(#selector(AppDelegate.hideFromMenu(_:)), to: NSApp.delegate, from: self) { window?.orderOut(nil) }
    }

    private func apply(_ edit: MarkdownEdit) {
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(edit.selection)
        window?.makeFirstResponder(self)
    }
    func format(_ marker: String) {
        breakUndoCoalescing()
        apply(MarkdownEditing.format(marker, text: string, selection: selectedRange()))
        breakUndoCoalescing()
    }
    override func insertNewline(_ sender: Any?) {
        apply(MarkdownEditing.newline(text: string, selection: selectedRange()))
    }
    override func insertTab(_ sender: Any?) {
        apply(MarkdownEditing.indent(text: string, selection: selectedRange(), outdent: false))
    }
    override func insertBacktab(_ sender: Any?) {
        apply(MarkdownEditing.indent(text: string, selection: selectedRange(), outdent: true))
    }
}
