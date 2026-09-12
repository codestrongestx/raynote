import AppKit
import CoreText

/// The editor always stores Markdown source. This delegate changes glyph visibility only,
/// preserving source offsets, native selection, clipboard contents, and the undo stack.
final class MarkdownGlyphDelegate: NSObject, NSLayoutManagerDelegate {
    var hidden = IndexSet()
    var bullets = IndexSet()

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes indexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        var properties = Array(UnsafeBufferPointer(start: props, count: range.length))
        var output = Array(UnsafeBufferPointer(start: glyphs, count: range.length))
        var changed = false
        for i in 0..<range.length {
            if hidden.contains(indexes[i]) { properties[i].insert(.null); changed = true }
            if bullets.contains(indexes[i]) {
                var character: UniChar = 0x2022
                var bullet: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(font as CTFont, &character, &bullet, 1) {
                    output[i] = bullet; changed = true
                }
            }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(&output, properties: &properties, characterIndexes: indexes, font: font, forGlyphRange: range)
        return range.length
    }
}

struct LiveTask {
    var bodyOffset: Int
    var checkOffset: Int
    var checked: Bool
    var indent: CGFloat
}

@MainActor enum LiveMarkdown {
    static var paragraph: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5; style.paragraphSpacing = 10
        return style
    }
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }

    static func style(_ editor: NoteTextView, sourceMode: Bool, revealSelection: Bool = true) {
        guard let storage = editor.textStorage, let layout = editor.layoutManager else { return }
        let source = editor.string as NSString
        let whole = NSRange(location: 0, length: source.length)
        let selected = editor.selectedRange()
        let active = revealSelection && selected.location <= source.length ? source.lineRange(for: selected) : NSRange(location: NSNotFound, length: 0)
        let glyphs = editor.markdownGlyphs
        layout.delegate = glyphs
        glyphs.hidden.removeAll(); glyphs.bullets.removeAll(); editor.liveTasks = []; editor.liveCodeBlocks = []
        editor.liveQuotes = []; editor.liveRules = []
        editor.liveImages = []
        editor.liveTableRows = []
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: whole)
        defer {
            storage.endEditing()
            layout.invalidateGlyphs(forCharacterRange: whole, changeInLength: 0, actualCharacterRange: nil)
            editor.typingAttributes = sourceMode ? [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph] : baseAttributes
            editor.needsDisplay = true
        }
        if sourceMode {
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: whole)
            return
        }
        func isActive(_ range: NSRange) -> Bool { active.location != NSNotFound && NSIntersectionRange(active, range).length > 0 }
        func hide(_ range: NSRange) {
            if range.length > 0 { glyphs.hidden.insert(integersIn: range.location..<NSMaxRange(range)) }
        }
        // Blank Markdown lines separate blocks, but shouldn't add a full body-text line.
        var lineOffset = 0
        for line in editor.string.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, lineOffset < source.length, !(active.location != NSNotFound && NSLocationInRange(lineOffset, active)) {
                let spacing = NSMutableParagraphStyle(); spacing.minimumLineHeight = 6; spacing.maximumLineHeight = 6
                storage.addAttributes([.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: spacing], range: NSRange(location: lineOffset, length: min(line.utf16.count + 1, source.length - lineOffset)))
            }
            lineOffset += line.utf16.count + 1
        }
        let blocks = MarkdownDocument.parse(editor.string)
        var literal = IndexSet()
        for block in blocks {
            switch block.kind {
            case .code, .table: literal.insert(integersIn: block.range.location..<NSMaxRange(block.range))
            default: break
            }
        }
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return [] }
            return regex.matches(in: editor.string, range: whole).filter { match in
                guard !literal.intersects(integersIn: match.range.location..<NSMaxRange(match.range)) else { return false }
                var preceding = match.range.location, escapes = 0
                while preceding > 0 && source.character(at: preceding - 1) == 92 { escapes += 1; preceding -= 1 }
                return escapes % 2 == 0
            }
        }
        // Inline code is literal: don't interpret formatting within its delimiters.
        for span in MarkdownCodeSpan.parse(editor.string, excluding: literal) {
            storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor], range: span.range)
            if !isActive(span.range) {
                hide(NSRange(location: span.opening.location, length: span.content.location - span.opening.location))
                hide(NSRange(location: NSMaxRange(span.content), length: NSMaxRange(span.closing) - NSMaxRange(span.content)))
            }
            literal.insert(integersIn: span.range.location..<NSMaxRange(span.range))
        }
        let emphasis = MarkdownEmphasis.parse(editor.string, excluding: literal)
        for span in emphasis where !isActive(span.range) {
            hide(span.opening); hide(span.closing)
        }
        for match in matches("~~([^~\\n]+)~~") {
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor], range: match.range)
            if !isActive(match.range) {
                hide(NSRange(location: match.range.location, length: 2))
                hide(NSRange(location: NSMaxRange(match.range) - 2, length: 2))
            }
        }
        for match in matches("(?<!!)\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)") {
            let destination = source.substring(with: match.range(at: 2))
            if let url = URL(string: destination), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                storage.addAttributes([.link: url, .foregroundColor: NSColor.systemBlue], range: match.range(at: 1))
            }
            if !isActive(match.range) {
                hide(NSRange(location: match.range.location, length: 1))
                hide(NSRange(location: NSMaxRange(match.range(at: 1)), length: NSMaxRange(match.range) - NSMaxRange(match.range(at: 1))))
            }
        }
        for block in blocks {
            let line = source.substring(with: block.range) as NSString
            switch block.kind {
            case .heading(let level, _):
                let heading = paragraph; heading.lineSpacing = 0; heading.paragraphSpacing = 6
                storage.addAttribute(.paragraphStyle, value: heading, range: block.range)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: level == 1 ? 21 : level == 2 ? 18 : 16, weight: .bold), range: block.range)
                if !isActive(block.range), let match = try? NSRegularExpression(pattern: "^ {0,3}#{1,6}[ \\t]+").firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                    hide(NSRange(location: block.range.location, length: match.range.length))
                }
            case .task(let checked, _, let depth, let offset):
                if checked { storage.addAttributes([.strikethroughStyle: 1, .foregroundColor: NSColor.secondaryLabelColor], range: block.range) }
                if !isActive(block.range) {
                    let body = offset + 3
                    hide(NSRange(location: block.range.location, length: body - block.range.location))
                    let style = paragraph; style.firstLineHeadIndent = CGFloat(depth) * 18 + 22; style.headIndent = style.firstLineHeadIndent
                    storage.addAttribute(.paragraphStyle, value: style, range: block.range)
                    editor.liveTasks.append(LiveTask(bodyOffset: body, checkOffset: offset, checked: checked, indent: CGFloat(depth) * 18))
                }
            case .list(let marker, _, let depth):
                let indentCount = (line as String).prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
                let start = block.range.location + indentCount
                let markerLength = marker == "•" ? 1 : marker.utf16.count
                storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: start, length: markerLength))
                let font = NSFont.systemFont(ofSize: 15)
                let markerWidth = (marker as NSString).size(withAttributes: [.font: font]).width
                let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
                let bodyIndent = max(20, markerWidth + spaceWidth + 4)
                if start + markerLength < NSMaxRange(block.range) {
                    storage.addAttribute(.kern, value: bodyIndent - markerWidth - spaceWidth, range: NSRange(location: start + markerLength, length: 1))
                }
                if !isActive(block.range) {
                    if indentCount > 0 { hide(NSRange(location: block.range.location, length: indentCount)) }
                    let start = block.range.location + indentCount
                    if marker == "•" { glyphs.bullets.insert(start) }
                    storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: start, length: marker == "•" ? 1 : marker.utf16.count))
                    let style = paragraph; style.firstLineHeadIndent = CGFloat(depth) * 18; style.headIndent = CGFloat(depth) * 18 + bodyIndent
                    storage.addAttribute(.paragraphStyle, value: style, range: block.range)
                }
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: block.range)
                if !isActive(block.range), let marker = try? NSRegularExpression(pattern: "^ {0,3}> ?").firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)) {
                    hide(NSRange(location: block.range.location, length: marker.range.length))
                    let quoteStyle = paragraph
                    quoteStyle.firstLineHeadIndent = 18; quoteStyle.headIndent = 18
                    quoteStyle.paragraphSpacing = 0
                    storage.addAttribute(.paragraphStyle, value: quoteStyle, range: block.range)
                    if let previous = editor.liveQuotes.last, block.range.location - NSMaxRange(previous) == 1 {
                        editor.liveQuotes[editor.liveQuotes.count - 1] = NSUnionRange(previous, block.range)
                    } else { editor.liveQuotes.append(block.range) }
                }
            case .rule:
                if !isActive(block.range) {
                    // Retain one transparent glyph so TextKit gives the divider
                    // its own line fragment instead of borrowing the previous line.
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: block.range)
                    hide(NSRange(location: block.range.location + 1, length: max(0, block.range.length - 1)))
                    editor.liveRules.append(block.range)
                }
            case .image(_, let destination):
                if !isActive(block.range), let directory = editor.baseDirectory,
                   let preview = editor.imagePreviews.preview(range: block.range, destination: destination, directory: directory,
                                                             width: (editor.textContainer?.containerSize.width ?? editor.bounds.width) - 10) {
                    let style = NSMutableParagraphStyle()
                    style.minimumLineHeight = preview.size.height + 16; style.maximumLineHeight = style.minimumLineHeight
                    storage.setAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: style], range: block.range)
                    hide(NSRange(location: block.range.location + 1, length: max(0, block.range.length - 1)))
                    editor.liveImages.append(preview)
                }
            case .table:
                if !isActive(block.range), let table = MarkdownTablePreview.rows(block: block, source: source, width: (editor.textContainer?.containerSize.width ?? editor.bounds.width) - 10) {
                    for (range, height) in table.rows.map({ ($0.range, $0.height) }) + [(table.separator, CGFloat(1))] {
                        let style = NSMutableParagraphStyle(); style.minimumLineHeight = height; style.maximumLineHeight = height
                        storage.setAttributes([.font: NSFont.systemFont(ofSize: 1), .foregroundColor: NSColor.clear, .paragraphStyle: style], range: range)
                        if range.length > 1 { hide(NSRange(location: range.location + 1, length: range.length - 1)) }
                    }
                    editor.liveTableRows += table.rows
                }
            case .code:
                // Apply last so headings, links and emphasis inside a fence remain literal.
                let codeStyle = NSMutableParagraphStyle()
                codeStyle.lineSpacing = 3
                codeStyle.firstLineHeadIndent = 10; codeStyle.headIndent = 10; codeStyle.tailIndent = -10
                codeStyle.tabStops = []
                codeStyle.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
                storage.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.textColor, .paragraphStyle: codeStyle], range: block.range)
                editor.liveCodeBlocks.append(block.range)
                // Fence markers remain selectable source, with quieter presentation.
                let opening = source.lineRange(for: NSRange(location: block.range.location, length: 0))
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSIntersectionRange(opening, block.range))
                let token = (source.substring(with: opening).trimmingCharacters(in: .whitespaces)).prefix(while: { $0 == "`" || $0 == "~" })
                if let character = token.first, let closing = try? NSRegularExpression(pattern: "^ {0,3}" + NSRegularExpression.escapedPattern(for: String(character)) + "{\(token.count),}[ \\t]*\\r?$", options: .anchorsMatchLines) {
                    for fence in closing.matches(in: editor.string, range: block.range) {
                        storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fence.range)
                    }
                }
            default: break
            }
        }
        // Compose traits after block fonts, preserving heading size and nested emphasis.
        for span in emphasis {
            storage.enumerateAttribute(.font, in: span.content) { value, range, _ in
                guard let font = value as? NSFont else { return }
                let styled = NSFontManager.shared.convert(font, toHaveTrait: span.strong ? .boldFontMask : .italicFontMask)
                let editable = IndexSet(integersIn: range.location..<NSMaxRange(range)).subtracting(literal)
                for run in editable.rangeView {
                    storage.addAttribute(.font, value: styled, range: NSRange(location: run.lowerBound, length: run.count))
                }
            }
        }
    }
}
