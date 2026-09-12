import AppKit

struct LiveTableRow {
    let range: NSRange
    let cells: [NSAttributedString]
    let height: CGFloat
    let width: CGFloat
    let header: Bool
}

@MainActor enum MarkdownTablePreview {
    static func rows(block: MarkdownBlock, source: NSString, width: CGFloat) -> (rows: [LiveTableRow], separator: NSRange)? {
        guard case .table(let headers, let body, let alignments) = block.kind, !headers.isEmpty, width > 0 else { return nil }
        let lines = source.substring(with: block.range).components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        var offset = block.range.location
        let ranges = lines.map { line -> NSRange in
            defer { offset += line.utf16.count + 1 }
            return NSRange(location: offset, length: line.utf16.count)
        }
        let cellWidth = width / CGFloat(headers.count)
        let rows = ([headers] + body).enumerated().map { index, values -> LiveTableRow in
            let cells = values.enumerated().map { column, text in
                inline(text, header: index == 0, alignment: alignments[column])
            }
            let height = cells.map { $0.boundingRect(with: NSSize(width: max(1, cellWidth - 16), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height }.max() ?? 18
            return LiveTableRow(range: ranges[index == 0 ? 0 : index + 1], cells: cells, height: max(34, ceil(height) + 16), width: width, header: index == 0)
        }
        return (rows, ranges[1])
    }
    private static func inline(_ text: String, header: Bool, alignment: MarkdownBlock.ColumnAlignment) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment == .center ? .center : alignment == .trailing ? .right : .left
        style.lineBreakMode = .byWordWrapping
        let result = NSMutableAttributedString(string: "")
        let value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in value.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) : NSFont.systemFont(ofSize: 14)
            if header || intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: style]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: String(value[run.range].characters), attributes: attributes))
        }
        return result
    }
}
