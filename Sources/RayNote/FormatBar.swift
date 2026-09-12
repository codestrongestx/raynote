import SwiftUI

struct FormatBar: View {
    var editing: Bool
    var onFormat: (String) -> Void
    var onClose: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            HeadingMenu(enabled: editing, onFormat: onFormat).frame(width: 40, height: 26)
            item("bold", "**", "Bold (⌘B)")
            item("italic", "*", "Italic (⌘I)")
            item("strikethrough", "~~", "Strikethrough (⇧⌘S)")
            item("chevron.left.forwardslash.chevron.right", "`", "Inline code (⌘E)")
            item("link", "link", "Link (⌘L)")
            item("curlybraces.square", "codeblock", "Code block (⌥⌘C)")
            item("text.quote", "> ", "Blockquote (⇧⌘B)")
            item("list.number", "1. ", "Ordered list (⇧⌘7)")
            item("list.bullet", "- ", "Bullet list (⇧⌘8)")
            item("checklist", "- [ ] ", "Task list (⇧⌘9)")
            Spacer().frame(width: 12)
            Rectangle().fill(.quaternary).frame(width: 1, height: 20).padding(.horizontal, 4)
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
                .buttonStyle(.plain).help("Hide format bar (⇧⌘F)").accessibilityLabel("Hide format bar")
        }
        .foregroundStyle(.secondary).padding(.leading, 24).padding(.trailing, 8).frame(height: 34)
    }
    private func item(_ icon: String, _ marker: String, _ label: String) -> some View {
        Button { onFormat(marker) } label: {
            Group {
                if marker == "`" { CodeFormatSymbol(block: false).frame(width: 18, height: 18) }
                else if marker == "codeblock" { CodeFormatSymbol(block: true).frame(width: 18, height: 18) }
                else { Image(systemName: icon).font(.system(size: 15, weight: .medium)) }
            }.frame(maxWidth: .infinity, minHeight: 26)
        }
            .buttonStyle(FormatButtonStyle()).disabled(!editing).help(label).accessibilityLabel(label)
    }
}
private struct CodeFormatSymbol: View {
    var block: Bool
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * proxy.size.width, y: y * proxy.size.height) }
                if block {
                    path.move(to: point(0.15, 0.53)); path.addLine(to: point(0.15, 0.83))
                    path.addQuadCurve(to: point(0.24, 0.92), control: point(0.15, 0.92))
                    path.addLine(to: point(0.80, 0.92))
                    path.addQuadCurve(to: point(0.89, 0.83), control: point(0.89, 0.92))
                    path.addLine(to: point(0.89, 0.19))
                    path.addQuadCurve(to: point(0.80, 0.10), control: point(0.89, 0.10))
                    path.move(to: point(0.23, 0.12)); path.addLine(to: point(0.09, 0.25)); path.addLine(to: point(0.23, 0.38))
                    path.move(to: point(0.44, 0.12)); path.addLine(to: point(0.58, 0.25)); path.addLine(to: point(0.44, 0.38))
                } else {
                    path.move(to: point(0.34, 0.30)); path.addLine(to: point(0.12, 0.50)); path.addLine(to: point(0.34, 0.70))
                    path.move(to: point(0.66, 0.30)); path.addLine(to: point(0.88, 0.50)); path.addLine(to: point(0.66, 0.70))
                }
            }.stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
private struct FormatButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isEnabled && (configuration.isPressed || isHovered) ? Color.primary.opacity(configuration.isPressed ? 0.16 : 0.10) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .onHover { isHovered = $0 }
    }
}

private struct HeadingMenu: NSViewRepresentable {
    var enabled: Bool
    var onFormat: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFormat: onFormat) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "H", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false; button.font = .systemFont(ofSize: 17, weight: .medium)
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 7, weight: .bold))
        button.imagePosition = .imageTrailing; button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel("Paragraph style")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { button.isEnabled = enabled; context.coordinator.onFormat = onFormat }
    final class Coordinator: NSObject {
        var onFormat: (String) -> Void
        init(onFormat: @escaping (String) -> Void) { self.onFormat = onFormat }
        @objc func open(_ sender: NSButton) {
            let menu = NSMenu()
            for (title, marker) in [("Paragraph", "paragraph"), ("Heading 1  ⌥⌘1", "# "), ("Heading 2  ⌥⌘2", "## "), ("Heading 3  ⌥⌘3", "### ")] {
                let item = NSMenuItem(title: title, action: #selector(select(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = marker; menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
        }
        @objc func select(_ sender: NSMenuItem) { if let marker = sender.representedObject as? String { onFormat(marker) } }
    }
}
