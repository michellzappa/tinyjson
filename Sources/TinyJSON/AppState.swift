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

    /// Warnings from lenient parsing (e.g. "Stripped 3 comments", "Removed trailing commas").
    var jsonWarnings: [String] = []

    /// Attempt lenient parsing: fix common issues and return whatever we can.
    /// Sets `jsonWarnings` with descriptions of what was repaired.
    var lenientParsedJSON: Any? {
        guard !content.isEmpty else {
            jsonWarnings = []
            return nil
        }
        if isJSONL { return parsedJSONLines }

        // If strict parsing works, no warnings needed
        if let data = content.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            jsonWarnings = []
            return obj
        }

        // Try to repair
        var warnings: [String] = []
        var text = content

        // 1. Strip BOM
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
            warnings.append("Stripped BOM")
        }

        // 2. Strip comments (// and /* */) outside of strings
        let (stripped, commentCount) = Self.stripComments(from: text)
        if commentCount > 0 {
            text = stripped
            warnings.append("Stripped \(commentCount) comment\(commentCount == 1 ? "" : "s")")
        }

        // 4. Remove trailing commas before } or ]
        let trailingCommaPattern = #",\s*([}\]])"#
        if let regex = try? NSRegularExpression(pattern: trailingCommaPattern),
           regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) > 0 {
            let count = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
            warnings.append("Removed \(count) trailing comma\(count == 1 ? "" : "s")")
        }

        // 5. Replace single-quoted strings with double-quoted
        // Simple heuristic: only outside of double-quoted strings
        let singleQuoteCount = text.filter { $0 == "'" }.count
        if singleQuoteCount >= 2 {
            var result = ""
            var inDouble = false
            var prev: Character = "\0"
            for ch in text {
                if ch == "\"" && prev != "\\" {
                    inDouble.toggle()
                    result.append(ch)
                } else if ch == "'" && !inDouble && prev != "\\" {
                    result.append("\"")
                } else {
                    result.append(ch)
                }
                prev = ch
            }
            if result != text {
                text = result
                warnings.append("Replaced single quotes with double quotes")
            }
        }

        // Try parsing the repaired text
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            jsonWarnings = warnings
            return obj
        }

        // 6. Last resort: try wrapping bare values, or try as JSONL
        // Try parsing line-by-line as if it were JSONL
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1 {
            var results: [Any] = []
            var badCount = 0
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    results.append(obj)
                } else {
                    badCount += 1
                }
            }
            if !results.isEmpty {
                warnings.append("Parsed as line-delimited JSON (\(results.count) valid, \(badCount) invalid line\(badCount == 1 ? "" : "s"))")
                jsonWarnings = warnings
                return results
            }
        }

        jsonWarnings = warnings.isEmpty ? [] : warnings
        return nil
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

    // MARK: - Comment stripping (string-aware)

    /// Strip // and /* */ comments that are outside of JSON strings.
    /// Returns the cleaned text and the number of comments removed.
    static func stripComments(from text: String) -> (String, Int) {
        var result = ""
        result.reserveCapacity(text.count)
        var count = 0
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]

            // Skip over strings (preserve their content)
            if ch == "\"" {
                result.append(ch)
                i = text.index(after: i)
                while i < text.endIndex {
                    let sc = text[i]
                    result.append(sc)
                    if sc == "\\" {
                        i = text.index(after: i)
                        if i < text.endIndex {
                            result.append(text[i])
                            i = text.index(after: i)
                        }
                    } else if sc == "\"" {
                        i = text.index(after: i)
                        break
                    } else {
                        i = text.index(after: i)
                    }
                }
                continue
            }

            // Check for single-line comment
            let next = text.index(after: i)
            if ch == "/" && next < text.endIndex && text[next] == "/" {
                count += 1
                // Skip to end of line
                var j = next
                while j < text.endIndex && text[j] != "\n" {
                    j = text.index(after: j)
                }
                i = j // leave the \n
                continue
            }

            // Check for block comment
            if ch == "/" && next < text.endIndex && text[next] == "*" {
                count += 1
                var j = text.index(next, offsetBy: 1, limitedBy: text.endIndex) ?? text.endIndex
                while j < text.endIndex {
                    if text[j] == "*" {
                        let afterStar = text.index(after: j)
                        if afterStar < text.endIndex && text[afterStar] == "/" {
                            i = text.index(after: afterStar)
                            break
                        }
                    }
                    j = text.index(after: j)
                }
                if j >= text.endIndex { i = text.endIndex }
                continue
            }

            result.append(ch)
            i = text.index(after: i)
        }

        return (result, count)
    }
}
