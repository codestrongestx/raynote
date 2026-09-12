import Foundation

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph(String)
        case heading(Int, String)
        case code(language: String, text: String)
        case quote(String)
        case list(marker: String, text: String, depth: Int)
        case task(checked: Bool, text: String, depth: Int, checkOffset: Int)
        case table(headers: [String], rows: [[String]], alignments: [ColumnAlignment])
        case image(alt: String, destination: String)
        case rule
    }
    enum ColumnAlignment: Equatable { case leading, center, trailing }
    var id: Int { range.location }
    var range: NSRange
    var kind: Kind
}

/// A block parser for the native reading view. Inline parsing is delegated to Foundation.
enum MarkdownDocument {
    static func parse(_ source: String) -> [MarkdownBlock] {
        struct Line { var text: String; var range: NSRange }
        var offset = 0
        let lines = source.components(separatedBy: "\n").map { text -> Line in
            defer { offset += text.utf16.count + 1 }
            return Line(text: text.hasSuffix("\r") ? String(text.dropLast()) : text, range: NSRange(location: offset, length: text.utf16.count))
        }
        var result: [MarkdownBlock] = []
        var i = 0
        // Each rule is reused across all lines. Compiling it per line made large
        // documents spend most of their parsing time rebuilding the same regexes.
        var expressions: [String: NSRegularExpression] = [:]
        func match(_ pattern: String, _ line: String) -> [String]? {
            let regex: NSRegularExpression
            if let cached = expressions[pattern] { regex = cached }
            else {
                guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
                expressions[pattern] = compiled; regex = compiled
            }
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else { return nil }
            return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : (line as NSString).substring(with: m.range(at: $0)) }
        }
        func range(_ start: Int, _ end: Int) -> NSRange { NSRange(location: lines[start].range.location, length: NSMaxRange(lines[end].range) - lines[start].range.location) }
        while i < lines.count {
            let start = i
            let line = lines[i].text
            if line.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            if let fence = match("^ {0,3}(`{3,}|~{3,})(.*)$", line) {
                i += 1
                var body: [String] = []
                while i < lines.count {
                    let value = lines[i].text.trimmingCharacters(in: .whitespaces)
                    let run = value.prefix(while: { $0 == fence[1].first! })
                    if run.count >= fence[1].count && value.dropFirst(run.count).trimmingCharacters(in: .whitespaces).isEmpty { break }
                    body.append(lines[i].text); i += 1
                }
                let end = min(i, lines.count - 1)
                result.append(MarkdownBlock(range: range(start, end), kind: .code(language: fence[2].trimmingCharacters(in: .whitespaces), text: body.joined(separator: "\n"))))
                if i < lines.count { i += 1 }; continue
            }
            if i + 1 < lines.count, line.contains("|"), let alignment = tableSeparator(lines[i + 1].text), cells(line).count == alignment.count {
                let headers = cells(line); i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].text.contains("|"), !lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let row = cells(lines[i].text)
                    rows.append(Array((row + Array(repeating: "", count: headers.count)).prefix(headers.count))); i += 1
                }
                result.append(MarkdownBlock(range: range(start, i - 1), kind: .table(headers: headers, rows: rows, alignments: alignment))); continue
            }
            if let heading = match("^ {0,3}(#{1,6})[ \\t]+(.+?)\\s*#*\\s*$", line) {
                result.append(MarkdownBlock(range: lines[i].range, kind: .heading(heading[1].count, heading[2])))
            } else if match("^ {0,3}(?:\\*\\s*){3,}$|^ {0,3}(?:-\\s*){3,}$|^ {0,3}(?:_\\s*){3,}$", line) != nil {
                result.append(MarkdownBlock(range: lines[i].range, kind: .rule))
            } else if let task = match("^([ \\t]*)[-*+] \\[([ xX])\\] (.*)$", line) {
                let marker = (line as NSString).range(of: "[")
                result.append(MarkdownBlock(range: lines[i].range, kind: .task(checked: task[2].lowercased() == "x", text: task[3], depth: task[1].replacingOccurrences(of: "\t", with: "  ").count / 2, checkOffset: lines[i].range.location + marker.location + 1)))
            } else if let list = match("^([ \\t]*)([-*+]|[0-9]+[.)]) (.*)$", line) {
                result.append(MarkdownBlock(range: lines[i].range, kind: .list(marker: ["-", "*", "+"].contains(list[2]) ? "•" : list[2], text: list[3], depth: list[1].replacingOccurrences(of: "\t", with: "  ").count / 2)))
            } else if let quote = match("^ {0,3}> ?(.*)$", line) {
                result.append(MarkdownBlock(range: lines[i].range, kind: .quote(quote[1])))
            } else if let image = match(#"^!\[([^\]]*)\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"]*")?\)$"#, line) {
                result.append(MarkdownBlock(range: lines[i].range, kind: .image(alt: image[1], destination: image[2])))
            } else {
                result.append(MarkdownBlock(range: lines[i].range, kind: .paragraph(line)))
            }
            i += 1
        }
        return result
    }

    static func cells(_ source: String) -> [String] {
        var line = source.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") && !line.hasSuffix("\\|") { line.removeLast() }
        var result: [String] = [], cell = "", escaped = false, codeFence = 0
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if escaped { cell.append(ch); escaped = false; i += 1; continue }
            if ch == "\\" { cell.append(ch); escaped = true; i += 1; continue }
            if ch == "`" {
                var count = 1
                while i + count < chars.count && chars[i + count] == "`" { count += 1 }
                if codeFence == 0 { codeFence = count } else if codeFence == count { codeFence = 0 }
                cell += String(repeating: "`", count: count); i += count; continue
            }
            if ch == "|" && codeFence == 0 { result.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else { cell.append(ch) }
            i += 1
        }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        return result
    }
    private static func tableSeparator(_ line: String) -> [MarkdownBlock.ColumnAlignment]? {
        let values = cells(line)
        guard values.count > 0, values.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) else { return nil }
        return values.map { $0.hasPrefix(":") && $0.hasSuffix(":") ? .center : $0.hasSuffix(":") ? .trailing : .leading }
    }
}
