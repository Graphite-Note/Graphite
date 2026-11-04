/**
 * File: MermaidDirectives.swift
 * -----------------------------
 * Layer: Core
 * Description: Finds and skips directives written over several lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

/// Directives (`%%{ … }%%`) written over several lines, which a diagram's own statement readers do not skip: each skips
/// to the end of the line that starts with `%%`, so the second line of
///
///     %%{
///       init: { "theme": "dark" }
///     }%%
///
/// would be read as the diagram's type or as a statement. Mermaid removes a directive wherever it ends; here the ones
/// that span lines are found and skipped, or blanked, so that every reader sees what is left. A directive on one line
/// stays for each reader to skip, as before, and a `%%{` with no `}%%` after it stays a comment line.
enum MermaidDirectives {
    /// The position just after the `}%%` that ends the directive opened by the `%%{` at `position`, when that `}%%` is
    /// on a later line; nil when there is no directive there, it ends on its own line, or it is never closed.
    static func endOfMultiLineDirective(in bytes: [UInt8], at position: Int) -> Int? {
        guard case .closed(let end, let spansLines) = ending(of: bytes, at: position), spansLines else { return nil }
        return end
    }

    /// `bytes` with every multi-line directive that starts a line at or after `start` replaced by spaces, its line
    /// breaks kept so that line numbers stay what the text says; nil when there is none.
    static func blankingMultiLineDirectives(in bytes: [UInt8], from start: Int) -> [UInt8]? {
        var blanked: [UInt8]?
        var lineStart = start
        var hasNoClosingFurtherOn = false
        while lineStart < bytes.count {
            var contentStart = lineStart
            while contentStart < bytes.count, MermaidByte.isSpace(bytes[contentStart]) { contentStart += 1 }
            var scanFrom = contentStart
            if !hasNoClosingFurtherOn {
                switch ending(of: bytes, at: contentStart) {
                case .closed(let end, let spansLines):
                    if spansLines {
                        var copy = blanked ?? bytes
                        for index in contentStart..<end where copy[index] != MermaidByte.newline && copy[index] != MermaidByte.carriageReturn {
                            copy[index] = MermaidByte.space
                        }
                        blanked = copy
                        scanFrom = end
                    }
                case .unclosed: hasNoClosingFurtherOn = true // No `}%%` is left in the text, so none of the later ones closes either.
                case .notADirective: break
                }
            }
            guard let lineEnd = bytes[scanFrom...].firstIndex(of: MermaidByte.newline) else { break }
            lineStart = lineEnd + 1
        }
        return blanked
    }

    private enum Ending {
        case notADirective
        /// No `}%%` follows the `%%{`.
        case unclosed
        /// The position after the first `}%%`, and whether a line break lies between the `%%{` and it.
        case closed(end: Int, spansLines: Bool)
    }

    private static func ending(of bytes: [UInt8], at position: Int) -> Ending {
        guard hasDirectiveStart(in: bytes, at: position) else { return .notADirective }
        var index = position + directiveStart.count
        var spansLines = false
        while index + directiveEnd.count <= bytes.count {
            if bytes[index] == MermaidByte.newline { spansLines = true }
            if bytes[index] == MermaidByte.closingBrace, bytes[index + 1] == MermaidByte.percent, bytes[index + 2] == MermaidByte.percent {
                return .closed(end: index + directiveEnd.count, spansLines: spansLines)
            }
            index += 1
        }
        return .unclosed
    }

    private static func hasDirectiveStart(in bytes: [UInt8], at position: Int) -> Bool {
        guard position + directiveStart.count <= bytes.count else { return false }
        for (offset, byte) in directiveStart.enumerated() where bytes[position + offset] != byte { return false }
        return true
    }

    private static let directiveStart = Array("%%{".utf8)
    private static let directiveEnd = Array("}%%".utf8)
}
