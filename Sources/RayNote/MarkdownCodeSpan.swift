import Foundation

/// Source-preserving, single-line code spans shared by editing, rendering, and assets.
/// Only complete backtick runs of equal length pair; shorter embedded runs are literal.
enum MarkdownCodeSpan {
    struct Span {
        var opening: NSRange
        var content: NSRange
        var closing: NSRange
        var range: NSRange { NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location) }
    }

    static func parse(_ text: String, excluding excluded: IndexSet = []) -> [Span] {
        let units = Array(text.utf16)
        var result: [Span] = []
        var runs: [(range: NSRange, escaped: Bool)] = []
        func flush() {
            var nextByLength: [Int: Int] = [:]
            var closing: [Int: Int] = [:]
            for index in runs.indices.reversed() {
                let length = runs[index].range.length
                closing[index] = nextByLength[length]
                nextByLength[length] = index
            }
            var index = 0
            while index < runs.count {
                guard !runs[index].escaped, let end = closing[index] else { index += 1; continue }
                let opening = runs[index].range, closing = runs[end].range
                var content = NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening))
                // Markdown removes one padding space at each end, except for all-space code.
                if content.length >= 2, units[content.location] == 32, units[NSMaxRange(content) - 1] == 32,
                   units[content.location..<NSMaxRange(content)].contains(where: { $0 != 32 }) {
                    content.location += 1; content.length -= 2
                }
                result.append(Span(opening: opening, content: content, closing: closing))
                index = end + 1
            }
            runs.removeAll(keepingCapacity: true)
        }
        var index = 0
        while index < units.count {
            if units[index] == 10 || units[index] == 13 || excluded.contains(index) {
                if !runs.isEmpty { flush() }
                index += 1; continue
            }
            guard units[index] == 96 else { index += 1; continue }
            let start = index
            while index < units.count, units[index] == 96, !excluded.contains(index) { index += 1 }
            var before = start, slashes = 0
            while before > 0, units[before - 1] == 92 { before -= 1; slashes += 1 }
            runs.append((NSRange(location: start, length: index - start), slashes % 2 == 1))
        }
        flush()
        return result
    }
}
