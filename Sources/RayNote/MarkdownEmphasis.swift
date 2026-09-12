import Foundation

/// Source ranges for single-line emphasis. Delimiter runs are paired from the
/// inside out; the source is never rewritten, including unmatched delimiters.
enum MarkdownEmphasis {
    struct Span {
        let opening: NSRange
        let closing: NSRange
        let strong: Bool
        var content: NSRange { NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening)) }
        var range: NSRange { NSRange(location: opening.location, length: NSMaxRange(closing) - opening.location) }
    }
    private struct Delimiter {
        var start: Int
        var count: Int
        let character: UInt16
        let canOpen: Bool
        let canClose: Bool
    }
    static func parse(_ text: String, excluding literal: IndexSet = []) -> [Span] {
        let units = Array(text.utf16)
        var stack: [Delimiter] = [], spans: [Span] = []
        var index = 0
        func whitespace(_ index: Int) -> Bool {
            guard units.indices.contains(index) else { return true }
            return UnicodeScalar(units[index]).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        func punctuation(_ index: Int) -> Bool {
            guard units.indices.contains(index), let scalar = UnicodeScalar(units[index]) else { return false }
            return CharacterSet.punctuationCharacters.union(.symbols).contains(scalar)
        }
        while index < units.count {
            let character = units[index]
            if character == 10 || character == 13 { stack.removeAll(); index += 1; continue }
            if literal.contains(index) { index += 1; continue }
            if character == 92 { index += min(2, units.count - index); continue }
            guard character == 42 || character == 95 else { index += 1; continue }
            let start = index
            while index < units.count && units[index] == character && !literal.contains(index) { index += 1 }
            let left = !whitespace(index) && (!punctuation(index) || whitespace(start - 1) || punctuation(start - 1))
            let right = !whitespace(start - 1) && (!punctuation(start - 1) || whitespace(index) || punctuation(index))
            var closer = Delimiter(start: start, count: index - start, character: character,
                                   canOpen: left && (character != 95 || !right || punctuation(start - 1)),
                                   canClose: right && (character != 95 || !left || punctuation(index)))
            if closer.canClose {
                while closer.count > 0 {
                    guard let match = stack.lastIndex(where: { opener in
                        guard opener.character == character && opener.canOpen else { return false }
                        let ambiguous = opener.canClose || closer.canOpen
                        return !(ambiguous && (opener.count + closer.count) % 3 == 0 && (opener.count % 3 != 0 || closer.count % 3 != 0))
                    }) else { break }
                    let amount = min(stack[match].count, closer.count) >= 2 ? 2 : 1
                    let opening = NSRange(location: stack[match].start + stack[match].count - amount, length: amount)
                    let closing = NSRange(location: closer.start, length: amount)
                    spans.append(Span(opening: opening, closing: closing, strong: amount == 2))
                    stack.removeSubrange((match + 1)..<stack.count)
                    stack[match].count -= amount
                    if stack[match].count == 0 { stack.remove(at: match) }
                    closer.start += amount; closer.count -= amount
                }
            }
            if closer.canOpen && closer.count > 0 { stack.append(closer) }
        }
        return spans
    }
}
