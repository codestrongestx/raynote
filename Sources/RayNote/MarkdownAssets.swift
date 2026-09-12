import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Imports local image references into the library and exports portable copies beside a note.
/// Only the image destination is rewritten; all other Markdown bytes are preserved.
enum MarkdownAssets {
    struct Result { var text: String; var warnings: [String] }
    struct Reference { var destination: String; var range: NSRange }

    static func storePastedImage(_ data: Data, in library: URL) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let ext = UTType(identifier as String)?.preferredFilenameExtension else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let folder = library.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + ext
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return "![Image](Attachments/" + name + ")"
    }

    static func references(in text: String) -> [Reference] {
        let source = text as NSString
        var fences = MarkdownDocument.parse(text).compactMap { block -> NSRange? in
            if case .code = block.kind { return block.range }; return nil
        }
        var excluded = IndexSet()
        for range in fences { excluded.insert(integersIn: range.location..<NSMaxRange(range)) }
        fences += MarkdownCodeSpan.parse(text, excluding: excluded).map(\.range)
        let regex = try! NSRegularExpression(pattern: #"!\[[^\]\n]*\]\((<[^>\n]+>|[^\s)]+)(?:\s+\"[^\"\n]*\")?\)"#)
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard !fences.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return nil }
            var preceding = match.range.location, slashCount = 0
            while preceding > 0 && source.character(at: preceding - 1) == 92 { preceding -= 1; slashCount += 1 }
            guard slashCount % 2 == 0 else { return nil }
            let range = match.range(at: 1)
            return Reference(destination: source.substring(with: range), range: range)
        }
    }
    static func resolve(_ destination: String, relativeTo directory: URL) -> URL? {
        let raw = destination.hasPrefix("<") && destination.hasSuffix(">") ? String(destination.dropFirst().dropLast()) : destination
        return URL(string: raw, relativeTo: directory.appendingPathComponent("", isDirectory: true))?.absoluteURL
    }
    static func importDocument(at source: URL, into library: URL) throws -> Result {
        let text = try String(contentsOf: source, encoding: .utf8)
        return try copyImages(in: text, from: source.deletingLastPathComponent(), into: library, folderName: "Attachments")
    }
    static func exportDocument(_ text: String, from library: URL, to destination: URL) throws -> [String] {
        // A unique sibling folder avoids replacing assets belonging to an earlier export.
        let folder = destination.deletingPathExtension().lastPathComponent + "-assets-" + String(UUID().uuidString.prefix(8))
        let result = try copyImages(in: text, from: library, into: destination.deletingLastPathComponent(), folderName: folder)
        try result.text.write(to: destination, atomically: true, encoding: .utf8)
        return result.warnings
    }
    private static func copyImages(in text: String, from sourceDirectory: URL, into destinationDirectory: URL, folderName: String) throws -> Result {
        let folder = destinationDirectory.appendingPathComponent(folderName, isDirectory: true)
        var replacements: [(NSRange, String)] = [], warnings: [String] = [], copied: [URL: String] = [:]
        for reference in references(in: text) {
            guard let url = resolve(reference.destination, relativeTo: sourceDirectory) else { warnings.append(reference.destination); continue }
            guard url.isFileURL else { continue } // Remote images remain remote; imports do not download them.
            let canonical = url.standardizedFileURL
            if let existing = copied[canonical] { replacements.append((reference.range, existing)); continue }
            guard let imageSource = CGImageSourceCreateWithURL(canonical as CFURL, nil),
                  CGImageSourceGetType(imageSource) != nil, CGImageSourceGetCount(imageSource) > 0 else { warnings.append(reference.destination); continue }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = UUID().uuidString + (canonical.pathExtension.isEmpty ? "" : "." + canonical.pathExtension)
            let target = folder.appendingPathComponent(file)
            try FileManager.default.copyItem(at: canonical, to: target)
            let relative = (folderName + "/" + file).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            copied[canonical] = relative
            replacements.append((reference.range, relative))
        }
        let output = NSMutableString(string: text)
        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) { output.replaceCharacters(in: range, with: replacement) }
        return Result(text: output as String, warnings: warnings)
    }
}
