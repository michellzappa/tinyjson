import AppKit
import TinyKit

/// Syntax highlighter for JSON files.
/// Colors keys, strings, numbers, booleans, null, and structural characters.
final class JSONHighlighter: SyntaxHighlighting {
    var baseFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var keyColor: NSColor {
        isDark ? NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0)
               : NSColor(red: 0.0, green: 0.3, blue: 0.7, alpha: 1.0)
    }

    private var stringColor: NSColor {
        isDark ? NSColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1.0)
               : NSColor(red: 0.1, green: 0.5, blue: 0.1, alpha: 1.0)
    }

    private var numberColor: NSColor {
        isDark ? NSColor(red: 0.95, green: 0.7, blue: 0.4, alpha: 1.0)
               : NSColor(red: 0.8, green: 0.4, blue: 0.0, alpha: 1.0)
    }

    private var boolNullColor: NSColor {
        isDark ? NSColor(red: 0.8, green: 0.6, blue: 1.0, alpha: 1.0)
               : NSColor(red: 0.5, green: 0.2, blue: 0.7, alpha: 1.0)
    }

    private var punctuationColor: NSColor {
        NSColor.secondaryLabelColor
    }

    func highlight(_ textStorage: NSTextStorage) {
        let source = textStorage.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        guard fullRange.length > 0 else { return }

        textStorage.beginEditing()

        // Reset to base
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.clear,
        ], range: fullRange)

        let ns = source as NSString
        let length = ns.length
        var i = 0

        // Track whether the last string we saw was a key (followed by ':')
        // We do a two-pass approach: first find all strings, then classify

        while i < length {
            let ch = ns.character(at: i)

            switch ch {
            // String
            case 0x22: // "
                let start = i
                i += 1
                while i < length {
                    let c = ns.character(at: i)
                    if c == 0x5C { // backslash
                        i += 2
                        continue
                    }
                    if c == 0x22 { // closing "
                        i += 1
                        break
                    }
                    i += 1
                }
                let strRange = NSRange(location: start, length: i - start)

                // Check if this string is a key (next non-whitespace is ':')
                var j = i
                while j < length {
                    let wc = ns.character(at: j)
                    if wc == 0x20 || wc == 0x09 || wc == 0x0A || wc == 0x0D { // whitespace
                        j += 1
                    } else {
                        break
                    }
                }
                let isKey = j < length && ns.character(at: j) == 0x3A // ':'

                textStorage.addAttribute(.foregroundColor, value: isKey ? keyColor : stringColor, range: strRange)
                if isKey {
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium), range: strRange)
                }

            // Numbers
            case 0x30...0x39, 0x2D: // 0-9, -
                let start = i
                if ch == 0x2D { i += 1 }
                while i < length {
                    let c = ns.character(at: i)
                    if (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x65 || c == 0x45 || c == 0x2B || c == 0x2D {
                        i += 1
                    } else {
                        break
                    }
                }
                // Only color if we consumed at least one digit
                if i > start && (i > start + 1 || ch != 0x2D) {
                    textStorage.addAttribute(.foregroundColor, value: numberColor, range: NSRange(location: start, length: i - start))
                }

            // true, false, null
            case 0x74: // t (true)
                if i + 3 < length && ns.substring(with: NSRange(location: i, length: 4)) == "true" {
                    textStorage.addAttribute(.foregroundColor, value: boolNullColor, range: NSRange(location: i, length: 4))
                    i += 4
                } else {
                    i += 1
                }

            case 0x66: // f (false)
                if i + 4 < length && ns.substring(with: NSRange(location: i, length: 5)) == "false" {
                    textStorage.addAttribute(.foregroundColor, value: boolNullColor, range: NSRange(location: i, length: 5))
                    i += 5
                } else {
                    i += 1
                }

            case 0x6E: // n (null)
                if i + 3 < length && ns.substring(with: NSRange(location: i, length: 4)) == "null" {
                    textStorage.addAttribute(.foregroundColor, value: boolNullColor, range: NSRange(location: i, length: 4))
                    i += 4
                } else {
                    i += 1
                }

            // Structural characters: { } [ ] : ,
            case 0x7B, 0x7D, 0x5B, 0x5D, 0x3A, 0x2C:
                textStorage.addAttribute(.foregroundColor, value: punctuationColor, range: NSRange(location: i, length: 1))
                i += 1

            default:
                i += 1
            }
        }

        textStorage.endEditing()
    }
}
