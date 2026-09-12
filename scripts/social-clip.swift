import AppKit
import SwiftUI

/// A silent product demo rendered from RayNote's actual native views with synthetic data.
@main enum SocialClip {
    static let fps = 30
    static let duration = 21
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = NoteStore(directory: temporary)
        store.update("# Weekend ideas\n\n")
        let firstID = store.selectedID!
        store.create(text: "# One good idea\n\nStart small. Keep going.\n\nYour next chapter can start with a note.\n")
        let secondID = store.selectedID!
        store.select(firstID)
        let suiteName = "RayNoteVideo-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "formatBarVisible")
        defaults.set(true, forKey: "keepOnTop")
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delegate = AppDelegate(store: store)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 360), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        delegate.window = panel
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        defer { panel.close() }
        let body = Array("- [ ] Build something small\n- [ ] Keep it simple\n- [ ] Share it with the world\n\n> Good ideas deserve a little space.\n")
        var cachedKey = "", cached: NSImage?, previous: NSImage?
        var transitionStart = -10.0
        func findEditor(_ view: NSView) -> NoteTextView? {
            if let editor = view as? NoteTextView { return editor }
            return view.subviews.lazy.compactMap(findEditor).first
        }
        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, width: CGFloat = 960, centered: Bool = false) {
            let style = NSMutableParagraphStyle(); style.alignment = centered ? .center : .left
            (text as NSString).draw(in: NSRect(x: x, y: y, width: width, height: size * 1.8), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
        }
        for frame in 0..<(fps * duration) {
            try autoreleasepool {
                let t = Double(frame) / Double(fps)
                let typed = min(body.count, max(0, Int((t - 2) / 6 * Double(body.count))))
                var text = "# Weekend ideas\n\n" + String(body.prefix(typed))
                if t >= 8.5 { text = text.replacingOccurrences(of: "- [ ] Build", with: "- [x] Build") }
                if t >= 9.5 { text = text.replacingOccurrences(of: "- [ ] Keep", with: "- [x] Keep") }
                let second = t >= 15 && t < 17
                let light = t >= 11.5
                let id = second ? secondID : firstID
                let key = "\(id)-\(light)-\(text)"
                if key != cachedKey {
                    let crossfade = cached != nil && ((t >= 11.5 && t < 11.54) || (t >= 15 && t < 15.04) || (t >= 17 && t < 17.04))
                    previous = crossfade ? cached : nil
                    if crossfade { transitionStart = t }
                    store.select(id)
                    if !second && store.selected?.text != text { store.update(text) }
                    let appearance = NSAppearance(named: light ? .aqua : .darkAqua)!
                    panel.appearance = appearance
                    let content = NSHostingView(rootView: NotesView(store: store, delegate: delegate)
                        .defaultAppStorage(defaults).environment(\.colorScheme, light ? .light : .dark))
                    panel.contentView = content
                    panel.setContentSize(NSSize(width: 480, height: 360))
                    content.layoutSubtreeIfNeeded()
                    if let editor = findEditor(content) {
                        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                        (editor.delegate as? MarkdownEditor.Coordinator)?.style()
                    }
                    content.layoutSubtreeIfNeeded()
                    let chrome = content.superview!
                    chrome.layoutSubtreeIfNeeded()
                    let rep = chrome.bitmapImageRepForCachingDisplay(in: chrome.bounds)!
                    appearance.performAsCurrentDrawingAppearance { chrome.cacheDisplay(in: chrome.bounds, to: rep) }
                    let image = NSImage(size: chrome.bounds.size); image.addRepresentation(rep)
                    cached = image; cachedKey = key
                }
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1080, pixelsHigh: 1080, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                let bounds = NSRect(x: 0, y: 0, width: 1080, height: 1080)
                NSGradient(starting: NSColor(srgbRed: 0.035, green: 0.055, blue: 0.09, alpha: 1), ending: NSColor(srgbRed: 0.12, green: 0.17, blue: 0.23, alpha: 1))!.draw(in: bounds, angle: 55)
                let muted = NSColor(srgbRed: 0.67, green: 0.74, blue: 0.82, alpha: 1)
                label("RAYNOTE  /  macOS", x: 64, y: 996, size: 20, color: muted, weight: .semibold)
                let title: String, subtitle: String
                switch t {
                case ..<2: title = "Your floating notepad."; subtitle = "RayNote. Markdown notes above your work."
                case ..<8.5: title = "Keep notes on top."; subtitle = "Pin your Markdown pad above other windows."
                case ..<11.5: title = "Work. Check. Keep going."; subtitle = "Your checklist stays in sight while you work."
                case ..<15: title = "Make it feel at home."; subtitle = "Dark, light, or follow your Mac."
                case ..<18: title = "Keep your space."; subtitle = "Switch notes. Your window stays put."
                default: title = "Float above your work."; subtitle = "Native macOS. Local Markdown. MIT licensed."
                }
                label(title, x: 64, y: 897, size: 54, color: .white, weight: .bold)
                label(subtitle, x: 66, y: 853, size: 27, color: muted)
                let enter = min(1, t / 0.65)
                let eased = 1 - pow(1 - enter, 3)
                // An explicitly illustrative workspace provides context for the native floating panel.
                let workspace = NSRect(x: 60, y: 255, width: 900, height: 530)
                NSColor(srgbRed: 0.17, green: 0.21, blue: 0.27, alpha: 1).setFill()
                NSBezierPath(roundedRect: workspace, xRadius: 16, yRadius: 16).fill()
                label("SAMPLE WORKSPACE", x: 84, y: 720, size: 19, color: muted, weight: .semibold)
                label("Project brief", x: 84, y: 653, size: 28, color: .white, weight: .semibold, width: 240)
                label("A small idea.", x: 84, y: 570, size: 22, color: muted, width: 185)
                label("A useful tool.", x: 84, y: 536, size: 22, color: muted, width: 185)
                label("Make room", x: 84, y: 458, size: 22, color: muted, width: 185)
                label("for your work.", x: 84, y: 424, size: 22, color: muted, width: 185)
                for line in 0..<3 {
                    NSColor.white.withAlphaComponent(0.10).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 84, y: 370 - line * 22, width: 140 - line * 20, height: 6), xRadius: 3, yRadius: 3).fill()
                }
                let rect = NSRect(x: 285, y: 190 - (1 - eased) * 30, width: 735, height: 551.25)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 35; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
                NSColor.black.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
                NSGraphicsContext.restoreGraphicsState()
                let transition = min(1, max(0, (t - transitionStart) / 0.45))
                if let previous, transition < 1 { previous.draw(in: rect, from: .zero, operation: .sourceOver, fraction: eased) }
                cached?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: eased * (previous == nil ? 1 : transition))
                label(t >= 18 ? "github.com/codestrongestx/raynote" : "A floating Markdown notepad for macOS.", x: 60, y: 104, size: 28, color: .white, weight: .medium, centered: true)
                label("Native RayNote UI · Sample workspace", x: 60, y: 59, size: 17, color: muted, centered: true)
                NSColor.white.withAlphaComponent(0.13).setFill()
                NSBezierPath(roundedRect: NSRect(x: 64, y: 35, width: 952, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
                NSColor(srgbRed: 0.5, green: 0.73, blue: 1, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 64, y: 35, width: 952 * CGFloat(t / 21), height: 3), xRadius: 1.5, yRadius: 1.5).fill()
                NSGraphicsContext.restoreGraphicsState()
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(String(format: "%04d.png", frame)))
            }
        }
    }
}
