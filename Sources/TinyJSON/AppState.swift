import Foundation
import TinyKit

@Observable
final class AppState: FileState {
    init() {
        super.init(
            bookmarkKey: "lastFolderBookmarkJSON",
            defaultExtension: "json",
            supportedExtensions: ["json", "jsonl", "ndjson", "geojson", "txt", "text"]
        )
    }

    // MARK: - Spotlight

    private static let spotlightDomain = "com.tinyapps.tinyjson.files"

    override func didOpenFile(_ url: URL) {
        SpotlightIndexer.index(file: url, content: content, domainID: Self.spotlightDomain, displayName: url.lastPathComponent)
    }

    override func didSaveFile(_ url: URL) {
        didOpenFile(url)
    }

    // MARK: - Export

    var exportHTML: String {
        let escaped = ExportManager.escapeHTML(formattedJSON)
        let body = "<pre><code>\(escaped)</code></pre>"
        return ExportManager.wrapHTML(body: body, title: selectedFile?.lastPathComponent ?? "data")
    }

    /// Character offset of the first error (for click-to-jump).
    var errorOffset: Int?

    /// Line numbers with errors (for JSONL).
    var errorLines: [Int] = []

    var isJSONFile: Bool {
        guard let ext = selectedFile?.pathExtension.lowercased() else { return false }
        return ["json", "jsonl", "ndjson", "geojson"].contains(ext)
    }

    var isJSONL: Bool {
        guard let ext = selectedFile?.pathExtension.lowercased() else { return false }
        return ["jsonl", "ndjson"].contains(ext)
    }

    // MARK: - Parsing

    /// Parse the current content as JSON. Returns nil if invalid.
    /// For JSONL files, parses each line independently and returns an array.
    var parsedJSON: Any? {
        guard !content.isEmpty else { return nil }
        if isJSONL {
            return parsedJSONLines
        }
        guard let data = content.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Parse JSONL: each non-empty line is an independent JSON value.
    /// Returns an array of all successfully parsed lines.
    private var parsedJSONLines: Any? {
        let lines = content.components(separatedBy: "\n")
        var results: [Any] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                continue // skip bad lines — errors tracked separately
            }
            results.append(obj)
        }
        return results.isEmpty ? nil : results
    }

    // MARK: - Error reporting

    /// Friendly validation error message, or nil if valid.
    var jsonError: String? {
        guard !content.isEmpty else { return nil }

        if isJSONL {
            return jsonlError
        }

        guard let data = content.data(using: .utf8) else {
            errorOffset = nil
            errorLines = []
            return "Invalid UTF-8 encoding"
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            errorOffset = nil
            errorLines = []
            return nil
        } catch {
            return friendlyJSONError(error, in: content)
        }
    }

    /// Error reporting for JSONL files: parse each line, collect errors.
    private var jsonlError: String? {
        let lines = content.components(separatedBy: "\n")
        var badLines: [(lineNum: Int, charOffset: Int)] = []
        var charOffset = 0

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if let data = trimmed.data(using: .utf8) {
                    do {
                        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                    } catch {
                        badLines.append((lineNum: i + 1, charOffset: charOffset))
                    }
                }
            }
            charOffset += line.utf8.count + 1 // +1 for \n
        }

        let totalNonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        errorLines = badLines.map(\.lineNum)
        errorOffset = badLines.first?.charOffset

        if badLines.isEmpty {
            return nil
        }

        let lineList = badLines.prefix(5).map { String($0.lineNum) }.joined(separator: ", ")
        let suffix = badLines.count > 5 ? ", ..." : ""
        let parsed = totalNonEmpty - badLines.count
        return "\(badLines.count) invalid \(badLines.count == 1 ? "line" : "lines") (of \(totalNonEmpty)): \(lineList)\(suffix) — \(parsed) parsed OK"
    }

    /// Produce a human-readable error with line number and context.
    private func friendlyJSONError(_ error: Error, in text: String) -> String {
        let nsError = error as NSError
        let desc = nsError.localizedDescription

        // NSJSONSerialization errors include character offset in the debug description
        // Try to extract it and convert to line:column
        if let range = desc.range(of: "character "),
           let endRange = desc[range.upperBound...].rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) {
            let numStr = String(desc[range.upperBound..<endRange.lowerBound])
            if let charOffset = Int(numStr) {
                self.errorOffset = charOffset
                self.errorLines = []
                let (line, col) = lineAndColumn(for: charOffset, in: text)
                let context = contextSnippet(around: charOffset, in: text)

                // Build a friendly message
                var msg = "Line \(line), column \(col): "

                if desc.contains("No value") || desc.contains("no value") {
                    msg += "unexpected end of input"
                } else if desc.contains("Invalid value") {
                    msg += "unexpected character"
                    if let ch = charAtOffset(charOffset, in: text) {
                        msg += " '\(ch)'"
                    }
                } else if desc.contains("Unterminated string") || desc.contains("unterminated string") {
                    msg += "unterminated string"
                } else if desc.contains("Garbage at end") || desc.contains("garbage at end") {
                    msg += "extra content after JSON value"
                } else {
                    // Fall back to the original description but keep our line info
                    msg += desc.replacingOccurrences(of: "The data couldn.*\\.", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if !context.isEmpty {
                    msg += "\n\(context)"
                }
                return msg
            }
        }

        errorOffset = nil
        errorLines = []

        // Fallback: try to give a useful message without offset info
        if desc.contains("No value") {
            return "Empty or incomplete JSON"
        }
        if desc.contains("Garbage at end") || desc.contains("garbage at end") {
            return "Extra content after the JSON value — is this a JSONL file? Rename to .jsonl"
        }

        // Clean up Apple's verbose error format
        return desc
            .replacingOccurrences(of: "The data couldn\u{2019}t be read because it isn\u{2019}t in the correct format.", with: "Invalid JSON")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private func lineAndColumn(for charOffset: Int, in text: String) -> (line: Int, column: Int) {
        var line = 1
        var col = 1
        for (i, ch) in text.utf8.enumerated() {
            if i >= charOffset { break }
            if ch == 0x0A { // \n
                line += 1
                col = 1
            } else {
                col += 1
            }
        }
        return (line, col)
    }

    private func charAtOffset(_ offset: Int, in text: String) -> Character? {
        let utf8 = text.utf8
        guard offset < utf8.count else { return nil }
        let idx = utf8.index(utf8.startIndex, offsetBy: offset)
        return text[idx]
    }

    private func contextSnippet(around charOffset: Int, in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var currentOffset = 0
        for (i, line) in lines.enumerated() {
            let lineEnd = currentOffset + line.utf8.count + 1 // +1 for \n
            if charOffset < lineEnd {
                let colInLine = charOffset - currentOffset
                let lineNum = i + 1
                let displayLine = String(line.prefix(80))
                let pointer = String(repeating: " ", count: min(colInLine, displayLine.count)) + "^"
                return "  \(lineNum) | \(displayLine)\n    | \(pointer)"
            }
            currentOffset = lineEnd
        }
        return ""
    }

    // MARK: - Formatting

    /// Pretty-print the current JSON content. For JSONL, compact each line.
    var formattedJSON: String {
        if isJSONL {
            return formattedJSONL
        }
        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return content
        }
        return str
    }

    /// Format JSONL: compact each line independently, preserving one-object-per-line.
    private var formattedJSONL: String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let compact = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                  let str = String(data: compact, encoding: .utf8) else {
                result.append(line) // keep bad lines as-is
                continue
            }
            result.append(str)
        }
        return result.joined(separator: "\n")
    }

    /// Format the current content in-place.
    func formatJSON() {
        let formatted = formattedJSON
        if formatted != content {
            content = formatted
        }
    }
}
