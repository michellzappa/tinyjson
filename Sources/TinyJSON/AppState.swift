import Foundation
import TinyKit

@Observable
final class AppState: FileState {
    init() {
        super.init(
            bookmarkKey: "lastFolderBookmarkJSON",
            defaultExtension: "json",
            supportedExtensions: ["json", "jsonl", "geojson", "txt", "text"]
        )
    }

    var isJSONFile: Bool {
        guard let ext = selectedFile?.pathExtension.lowercased() else { return false }
        return ["json", "jsonl", "geojson"].contains(ext)
    }

    /// Parse the current content as JSON. Returns nil if invalid.
    var parsedJSON: Any? {
        guard let data = content.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Friendly validation error message, or nil if valid JSON.
    var jsonError: String? {
        guard !content.isEmpty else { return nil }
        guard let data = content.data(using: .utf8) else { return "Invalid UTF-8 encoding" }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return nil
        } catch {
            return friendlyJSONError(error, in: content)
        }
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

        // Fallback: try to give a useful message without offset info
        if desc.contains("No value") {
            return "Empty or incomplete JSON"
        }
        if desc.contains("Garbage at end") || desc.contains("garbage at end") {
            return "Extra content after the JSON value"
        }

        // Clean up Apple's verbose error format
        return desc
            .replacingOccurrences(of: "The data couldn\u{2019}t be read because it isn\u{2019}t in the correct format.", with: "Invalid JSON")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    /// Pretty-print the current JSON content.
    var formattedJSON: String {
        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return content
        }
        return str
    }

    /// Format the current content in-place.
    func formatJSON() {
        let formatted = formattedJSON
        if formatted != content {
            content = formatted
        }
    }
}
