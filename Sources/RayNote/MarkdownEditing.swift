import Foundation

/// A source edit and the resulting UTF-16 selection, suitable for NSTextView's undo pipeline.
struct MarkdownEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    func applying(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

enum MarkdownEditing {
    static func format(_ marker: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let selected = source.substring(with: selection)
        if marker == "paragraph" { return block("", text: text, selection: selection) }
        if marker == "toggleTask" {
            let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let value = source.substring(with: line)
            let regex = try! NSRegularExpression(pattern: "^[ \\t]*[-*+] \\[([ xX])\\] ")
            if let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) {
                let range = NSRange(location: line.location + match.range(at: 1).location, length: 1)
                return MarkdownEdit(range: range, replacement: source.substring(with: range) == " " ? "x" : " ", selection: selection)
            }
            return block("- [ ] ", text: text, selection: selection)
        }

        if ["# ", "## ", "### ", "- ", "1. ", "- [ ] ", "> "].contains(marker) {
            return block(marker, text: text, selection: selection)
        }
        if marker == "codeblock" { return codeBlock(text: text, selection: selection) }
        if marker == "link" {
            let label = selected.isEmpty ? "text" : selected
            let replacement = "[\(label)](https://)"
            return MarkdownEdit(range: selection, replacement: replacement,
                                selection: NSRange(location: selection.location + label.utf16.count + 3, length: 8))
        }
        if marker == "`", !selected.isEmpty {
            if let span = MarkdownCodeSpan.parse(text).first(where: { $0.content == selection || $0.range == selection }) {
                let content = source.substring(with: span.content)
                return MarkdownEdit(range: span.range, replacement: content, selection: NSRange(location: span.range.location, length: content.utf16.count))
            }
            let longest = selected.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let delimiter = String(repeating: "`", count: longest + 1)
            let padding = selected.hasPrefix("`") || selected.hasSuffix("`") || (selected.hasPrefix(" ") && selected.hasSuffix(" ") && selected.contains(where: { $0 != " " })) ? " " : ""
            return MarkdownEdit(range: selection, replacement: delimiter + padding + selected + padding + delimiter,
                                selection: NSRange(location: selection.location + delimiter.utf16.count + padding.utf16.count, length: selection.length))
        }
        let length = marker.utf16.count
        // Support both selecting the content and selecting the entire formatted span.
        if selected.hasPrefix(marker), selected.hasSuffix(marker), selected.utf16.count >= length * 2 {
            let inner = (selected as NSString).substring(with: NSRange(location: length, length: selected.utf16.count - length * 2))
            return MarkdownEdit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: inner.utf16.count))
        }
        if selection.location >= length, NSMaxRange(selection) + length <= source.length,
           source.substring(with: NSRange(location: selection.location - length, length: length)) == marker,
           source.substring(with: NSRange(location: NSMaxRange(selection), length: length)) == marker {
            let range = NSRange(location: selection.location - length, length: selection.length + length * 2)
            return MarkdownEdit(range: range, replacement: selected, selection: NSRange(location: range.location, length: selection.length))
        }
        return MarkdownEdit(range: selection, replacement: marker + selected + marker,
                            selection: NSRange(location: selection.location + length, length: selection.length))
    }

    /// Exclude the following line when a multi-line selection ends at its beginning.
    static func lineRange(in text: NSString, selection: NSRange) -> NSRange {
        let effective = NSRange(location: selection.location, length: max(0, selection.length - (selection.length > 0 ? 1 : 0)))
        return text.lineRange(for: effective)
    }

    private static func block(_ marker: String, text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let range = lineRange(in: source, selection: selection)
        let original = source.substring(with: range)
        let hasNewline = original.hasSuffix("\n")
        var lines = original.components(separatedBy: "\n")
        if hasNewline { lines.removeLast() }
        let prefix = try! NSRegularExpression(pattern: "^([ \\t]*)(#{1,6} |[-*+] (?:\\[[ xX]\\] )?|[0-9]+[.)] |> )?")
        let parsed = lines.map { line -> (indent: String, marker: String, body: String) in
            let value = line as NSString
            let match = prefix.firstMatch(in: line, range: NSRange(location: 0, length: value.length))!
            let old = match.range(at: 2).location == NSNotFound ? "" : value.substring(with: match.range(at: 2))
            return (value.substring(with: match.range(at: 1)), old, value.substring(from: NSMaxRange(match.range)))
        }
        func sameKind(_ value: String) -> Bool {
            if marker == "1. " { return value.first?.isNumber == true }
            if marker == "- " { return ["- ", "* ", "+ "].contains(value) }
            if marker == "- [ ] " { return value.contains("[") }
            return value == marker
        }
        let remove = parsed.allSatisfy { sameKind($0.marker) }
        let replacement = parsed.enumerated().map { index, line in
            line.indent + (remove ? "" : marker == "1. " ? "\(index + 1). " : marker) + line.body
        }.joined(separator: "\n") + (hasNewline ? "\n" : "")
        if selection.length == 0, parsed.count == 1 {
            let oldPrefix = parsed[0].indent.utf16.count + parsed[0].marker.utf16.count
            let newPrefix = parsed[0].indent.utf16.count + (remove ? 0 : marker.utf16.count)
            let offset = max(newPrefix, selection.location - range.location + newPrefix - oldPrefix)
            return MarkdownEdit(range: range, replacement: replacement, selection: NSRange(location: range.location + min(offset, replacement.utf16.count), length: 0))
        }
        return MarkdownEdit(range: range, replacement: replacement, selection: NSRange(location: range.location, length: replacement.utf16.count - (hasNewline ? 1 : 0)))
    }

    static func indent(text: String, selection: NSRange, outdent: Bool) -> MarkdownEdit {
        let source = text as NSString
        let range = lineRange(in: source, selection: selection)
        let original = source.substring(with: range)
        var lines = original.components(separatedBy: "\n")
        let trailing = original.hasSuffix("\n")
        if trailing { lines.removeLast() }
        let transformed = lines.map { line -> String in
            if !outdent { return "  " + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.dropFirst(line.prefix(2).prefix(while: { $0 == " " }).count))
        }
        let replacement = transformed.joined(separator: "\n") + (trailing ? "\n" : "")
        let cursor = max(range.location, selection.location + (transformed.first?.utf16.count ?? 0) - (lines.first?.utf16.count ?? 0))
        return MarkdownEdit(range: range, replacement: replacement,
                            selection: selection.length == 0 ? NSRange(location: cursor, length: 0) : NSRange(location: range.location, length: replacement.utf16.count - (trailing ? 1 : 0)))
    }

    static func newline(text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let range = source.lineRange(for: NSRange(location: selection.location, length: 0))
        // Only text before the caret controls continuation; splitting before a marker is a plain newline.
        let before = source.substring(with: NSRange(location: range.location, length: selection.location - range.location))
        let regex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+] (?:\\[[ xX]\\] )?|([0-9]+)([.)]) |> )")
        if !insideFence(text: text, offset: selection.location),
           let match = regex.firstMatch(in: before, range: NSRange(location: 0, length: before.utf16.count)) {
            let value = before as NSString
            let prefix = value.substring(with: match.range)
            let line = source.substring(with: range).trimmingCharacters(in: .newlines)
            if line == prefix && selection.length == 0 {
                let removed = NSRange(location: range.location, length: prefix.utf16.count)
                return MarkdownEdit(range: removed, replacement: "", selection: NSRange(location: range.location, length: 0))
            }
            var next = prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            if match.range(at: 3).location != NSNotFound, let number = Int(value.substring(with: match.range(at: 3))), number < Int.max {
                next = value.substring(with: match.range(at: 1)) + "\(number + 1)" + value.substring(with: match.range(at: 4)) + " "
            }
            return MarkdownEdit(range: selection, replacement: "\n" + next, selection: NSRange(location: selection.location + next.utf16.count + 1, length: 0))
        }
        let indent = String(before.prefix(while: { $0 == " " || $0 == "\t" }))
        return MarkdownEdit(range: selection, replacement: "\n" + indent, selection: NSRange(location: selection.location + indent.utf16.count + 1, length: 0))
    }

    static func insideFence(text: String, offset: Int) -> Bool {
        let prefix = (text as NSString).substring(to: offset)
        var fence: (character: Character, count: Int)?
        for line in prefix.components(separatedBy: "\n").dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, first == "`" || first == "~" else { continue }
            let count = trimmed.prefix(while: { $0 == first }).count
            guard count >= 3 else { continue }
            if let open = fence {
                if first == open.character, count >= open.count, trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else { fence = (first, count) }
        }
        return fence != nil
    }

    private static func codeBlock(text: String, selection: NSRange) -> MarkdownEdit {
        let source = text as NSString
        let content = source.substring(with: selection)
        let runs = content.split(whereSeparator: { $0 != "`" }).map(\.count)
        let fence = String(repeating: "`", count: max(3, (runs.max() ?? 0) + 1))
        let leading = selection.location > 0 && source.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" ? "\n" : ""
        let trailing = NSMaxRange(selection) < source.length && source.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) != "\n" ? "\n" : ""
        let opening = leading + fence + "\n"
        let replacement = opening + content + (content.hasSuffix("\n") ? "" : "\n") + fence + trailing
        return MarkdownEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + opening.utf16.count, length: selection.length))
    }
}
