import SwiftUI

struct MarkdownReadingView: View {
    let text: String
    let onChange: (String) -> Void
    var baseDirectory: URL? = nil
    private var blocks: [MarkdownBlock] { MarkdownDocument.parse(text) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(blocks) { block in content(block).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
            .padding(.horizontal, 28).padding(.vertical, 18)
        }.tint(.accentColor)
    }
    private func inline(_ source: String) -> Text {
        let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        return parsed.map(Text.init) ?? Text(source)
    }
    @ViewBuilder private func content(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph(let value): inline(value)
        case .heading(let level, let value):
            inline(value).font(.system(size: level == 1 ? 21 : level == 2 ? 18 : 16, weight: .bold)).padding(.top, level == 1 ? 0 : 6)
        case .code(let language, let value):
            VStack(alignment: .leading, spacing: 8) {
                if !language.isEmpty { Text(language).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).textCase(.uppercase) }
                ScrollView(.horizontal) { Text(value).font(.system(size: 12, design: .monospaced)).fixedSize(horizontal: true, vertical: false) }
            }.padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
        case .quote(let value):
            HStack(alignment: .top, spacing: 12) { RoundedRectangle(cornerRadius: 2).fill(.tertiary).frame(width: 3); inline(value).foregroundStyle(.secondary) }.fixedSize(horizontal: false, vertical: true)
        case .list(let marker, let value, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 10) { Text(marker).foregroundStyle(Color.accentColor).frame(minWidth: 15, alignment: .trailing); inline(value) }.padding(.leading, CGFloat(depth) * 18)
        case .task(let checked, let value, let depth, let offset):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    let ns = text as NSString
                    guard offset < ns.length, [" ", "x", "X"].contains(ns.substring(with: NSRange(location: offset, length: 1))) else { return }
                    onChange(ns.replacingCharacters(in: NSRange(location: offset, length: 1), with: checked ? " " : "x"))
                } label: { Image(systemName: checked ? "checkmark.square.fill" : "square").font(.system(size: 15)) }
                .buttonStyle(.plain).foregroundStyle(checked ? Color.accentColor : .secondary)
                .accessibilityLabel(value).accessibilityValue(checked ? "Complete" : "Incomplete").help("Toggle task")
                inline(value).strikethrough(checked).foregroundStyle(checked ? .secondary : .primary)
            }.padding(.leading, CGFloat(depth) * 18)
        case .table(let headers, let rows, let alignments):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    tableRow(headers, alignments: alignments, header: true)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in tableRow(row, alignments: alignments, header: false) }
                }.overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
            }
        case .image(let alt, let destination):
            if let url = URL(string: destination), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel(alt) }
                    else if phase.error != nil { Label(alt.isEmpty ? "Image unavailable" : alt, systemImage: "photo").foregroundStyle(.secondary) }
                    else { ProgressView().frame(height: 60) }
                }
            } else if let directory = baseDirectory,
                      let url = MarkdownAssets.resolve(destination, relativeTo: directory), url.isFileURL,
                      let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel(alt)
            } else { Label(alt.isEmpty ? destination : alt, systemImage: "photo").foregroundStyle(.secondary) }
        case .rule: Divider().padding(.vertical, 5)
        }
    }
    private func tableRow(_ values: [String], alignments: [MarkdownBlock.ColumnAlignment], header: Bool) -> some View {
        GridRow {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                inline(value).fontWeight(header ? .semibold : .regular)
                    .frame(minWidth: 85, maxWidth: 240, alignment: alignments[index] == .center ? .center : alignments[index] == .trailing ? .trailing : .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(header ? Color.primary.opacity(0.055) : .clear)
                    .overlay(Rectangle().stroke(.quaternary, lineWidth: 0.5))
            }
        }
    }
}
