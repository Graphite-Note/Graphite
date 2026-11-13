/**
 * File: LivePreviewBlocks.swift
 * -----------------------------
 * Layer: Core
 * Description: Finds the regions of note source that Live Preview draws as rendered blocks.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.18
 * Date: 13/11/2026
 */

import Foundation

/// A region of note source that Live Preview replaces with a rendered view while the
/// cursor is elsewhere, as Obsidian does for properties, tables, math, and embeds.
public struct LivePreviewBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case frontmatter
        case table
        case mathBlock
        case embed(EmbedReference)
        /// A paragraph line that shows images among its text, or several images side by side,
        /// as `![[a.jpg|200]] ![[b.jpg|200]]`: its pieces in order.
        case imageLine([ImageLinePiece])
        case baseDefinition(String)
        case horizontalRule
        /// A `> [!type]` callout with its quoted body.
        case callout
        /// A fenced block in a language a community plugin draws (`registerMarkdownCodeBlockProcessor`),
        /// with the code between its fences in `markdown`.
        case pluginCodeBlock(language: String)
        /// A fenced block whose whole info text is `mermaid`, in any case, that no community plugin draws: a diagram,
        /// as reading view finds it (`NotePreviewBlock.mermaidDiagram`), with the code between its fences in `markdown`.
        case mermaidDiagram
        /// An `<iframe>` on lines of its own, or alone in a list item, as reading view finds it (`NotePreviewBlock.webFrame`):
        /// the page shown over its lines, its tag in `markdown`.
        case webFrame(WebFrameEmbed)

        /// Whether the block's view edits table cells in place, a table's own or those of a
        /// callout's body, and so is kept across the new keys its edits give the block.
        public var editsTablesInItsView: Bool {
            switch self {
            case .table, .callout: true
            case .frontmatter, .mathBlock, .embed, .imageLine, .baseDefinition, .horizontalRule, .pluginCodeBlock, .mermaidDiagram, .webFrame: false
            }
        }
    }
    public let kind: Kind
    /// Whole lines, including the final line break when there is one.
    public let range: NSRange
    /// The Markdown to render for tables, math blocks, and callouts: the lines joined by line
    /// feeds, with `%%` comments written over by spaces, so nothing that reads it meets a comment.
    public let markdown: String
    /// The lines as the note has them, for a block whose `markdown` differs from them.
    private let writtenLines: String?
    /// Whether a `%%` comment runs past the first or last line of a table or callout, or over a
    /// line break inside it. The lines alone then do not say what is hidden, and a command on a
    /// row would take part of the comment with it, so a table's cells are not edited in its view.
    public let isCutByComment: Bool

    /// A table's or callout's lines as the note has them, comments and line endings included,
    /// without the last line's break: what an edit of the block's own text starts from.
    public var sourceLines: String { writtenLines ?? markdown }

    init(kind: Kind, range: NSRange, markdown: String, writtenLines: String? = nil, isCutByComment: Bool = false) {
        self.kind = kind
        self.range = range
        self.markdown = markdown
        self.writtenLines = writtenLines
        self.isCutByComment = isCutByComment
    }

    /// The same block, found in text that starts `distance` characters later, as when
    /// some lines are scanned on their own.
    public func offset(by distance: Int) -> LivePreviewBlock {
        LivePreviewBlock(kind: kind, range: NSRange(location: range.location + distance, length: range.length), markdown: markdown,
                         writtenLines: writtenLines, isCutByComment: isCutByComment)
    }
}

public enum LivePreviewBlockScanner {
    /// - Parameter pluginCodeBlockLanguages: Languages community plugins draw. As in Obsidian,
    ///   a fenced block in one of them is drawn by its plugin in Live Preview too, `mermaid` included.
    public static func blocks(in text: NSString, pluginCodeBlockLanguages: Set<String> = []) -> [LivePreviewBlock] {
        var blocks: [LivePreviewBlock] = []
        let frontmatter = frontmatterBlock(in: text)
        if let frontmatter { blocks.append(frontmatter) }
        let frontmatterLength = frontmatter?.range.length ?? 0
        // Reading view leaves a `%%` comment out before it looks for blocks, so a table, callout,
        // embed or formula in one is not drawn here either.
        let commentRanges = ObsidianComments.commentRanges(in: text as String)
        let lines = lines(in: commentsBlankedOut(of: text, commentRanges: commentRanges), from: frontmatterLength)
        // Most notes have no comment and no "\r\n": their blocks' Markdown is their lines.
        let linesMayDifferFromMarkdown = !commentRanges.isEmpty || text.range(of: "\r\n", options: .literal).location != NSNotFound
        let mathLines = DisplayMathLines(lines.map(\.content))
        var listItems = ListItemContainers()
        var lineIndex = 0
        // The line after a table, fence, math block or callout, which cannot be a
        // paragraph line that a following `---` underlines.
        var lineIndexAfterBlock = -1
        func span(_ firstIndex: Int, _ lastIndex: Int) -> NSRange {
            NSRange(location: lines[firstIndex].range.location, length: NSMaxRange(lines[lastIndex].range) - lines[firstIndex].range.location)
        }
        func markdown(_ firstIndex: Int, _ lastIndex: Int) -> String {
            lines[firstIndex...lastIndex].map(\.content).joined(separator: "\n")
        }
        /// A table or callout, which also keeps its lines as the note has them.
        func editableBlock(_ kind: LivePreviewBlock.Kind, _ firstIndex: Int, _ lastIndex: Int) -> LivePreviewBlock {
            let range = span(firstIndex, lastIndex)
            let rendered = markdown(firstIndex, lastIndex)
            guard linesMayDifferFromMarkdown else { return LivePreviewBlock(kind: kind, range: range, markdown: rendered) }
            let linesEnd = lines[lastIndex].range.location + lines[lastIndex].content.utf16.count
            let writtenRange = NSRange(location: range.location, length: linesEnd - range.location)
            let written = text.substring(with: writtenRange)
            let isCutByComment = commentRanges.contains { commentRange in
                NSIntersectionRange(commentRange, writtenRange).length > 0
                    && (commentRange.location < writtenRange.location || NSMaxRange(commentRange) > NSMaxRange(writtenRange)
                        || text.rangeOfCharacter(from: lineBreakCharacters, options: .literal, range: commentRange).location != NSNotFound)
            }
            return LivePreviewBlock(kind: kind, range: range, markdown: rendered, writtenLines: written == rendered ? nil : written,
                                    isCutByComment: isCutByComment)
        }
        while lineIndex < lines.count {
            let content = lines[lineIndex].content
            let trimmedContent = content.trimmingCharacters(in: .whitespaces)
            // Whether the line comes after a list item's text, where an item indented four
            // columns or more is a nested item and not indented code.
            let followsListItem = listItems.innermostContentColumn > 0
            if let (fence, info, _) = listItems.fenceOpening(of: content) {
                let language = info.lowercased()
                var closingIndex = lineIndex + 1
                while closingIndex < lines.count && !MarkdownFenceSyntax.closes(fence, lines[closingIndex].content.trimmingCharacters(in: .whitespaces)) { closingIndex += 1 }
                let lastIndex = min(closingIndex, lines.count - 1)
                // An unclosed fence runs to the end of the note, as in CommonMark and reading view.
                let lastContentIndex = closingIndex < lines.count ? closingIndex - 1 : lastIndex
                // Joined only for a block: most fences are code that stays text.
                func code() -> String { lineIndex + 1 <= lastContentIndex ? markdown(lineIndex + 1, lastContentIndex) : "" }
                // The language a plugin draws is read only while plugins draw some.
                let pluginLanguage = pluginCodeBlockLanguages.isEmpty ? "" : MarkdownFenceSyntax.language(ofInfo: info)
                if language == "base" {
                    let yaml = code()
                    blocks.append(LivePreviewBlock(kind: .baseDefinition(yaml), range: span(lineIndex, lastIndex), markdown: yaml))
                } else if !pluginLanguage.isEmpty, pluginCodeBlockLanguages.contains(pluginLanguage) {
                    blocks.append(LivePreviewBlock(kind: .pluginCodeBlock(language: pluginLanguage), range: span(lineIndex, lastIndex), markdown: code()))
                } else if language == "mermaid" {
                    blocks.append(LivePreviewBlock(kind: .mermaidDiagram, range: span(lineIndex, lastIndex), markdown: code()))
                }
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            if let (kind, lastIndex) = wholeLinesBlock(startingAt: lineIndex, of: lines, mathLines: mathLines) {
                blocks.append(LivePreviewBlock(kind: kind, range: span(lineIndex, lastIndex), markdown: markdown(lineIndex, lastIndex)))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            // A callout may sit in a list item, indented with the item's text.
            let containerColumn = listItems.innermostContentColumn
            if MarkdownQuoteSyntax.isCalloutHeader(content, containerColumn: containerColumn) {
                let bodyLineCount = MarkdownQuoteSyntax.calloutBodyLineCount(afterHeaderAt: lineIndex, lineCount: lines.count,
                    containerColumn: containerColumn) { index in lines[index].content }
                let lastIndex = lineIndex + bodyLineCount
                blocks.append(editableBlock(.callout, lineIndex, lastIndex))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            // A table needs a header row and a delimiter row, like GFM; its outer pipes may
            // be left out (`a | b` over `--|--`), as Obsidian and GFM allow.
            if lineIndex + 1 < lines.count, MarkdownTableSyntax.startsTable(header: trimmedContent, delimiter: lines[lineIndex + 1].content) {
                let hasOuterPipes = trimmedContent.hasPrefix("|")
                var lastIndex = lineIndex + 1
                while lastIndex + 1 < lines.count {
                    let row = lines[lastIndex + 1].content.trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") || (!hasOuterPipes && !row.isEmpty && row.contains("|")) else { break }
                    lastIndex += 1
                }
                blocks.append(editableBlock(.table, lineIndex, lastIndex))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            if let embed = EmbedLocator.standaloneEmbed(onLine: content) {
                // A web image is not a vault file, so it gets no embed widget and stays
                // Markdown, as reading view leaves it.
                if !embed.isRemoteImage {
                    blocks.append(LivePreviewBlock(kind: .embed(embed), range: lines[lineIndex].range, markdown: content))
                }
            } else if let pieces = imageLinePieces(ofParagraphLine: content) ?? imageLinePieces(ofListItem: content, followsListItem: followsListItem) {
                blocks.append(LivePreviewBlock(kind: .imageLine(pieces), range: lines[lineIndex].range, markdown: content))
            } else if MarkdownHeadingSyntax.level(of: content) == nil,
                      let opening = mathLines.opening(at: lineIndex), let closingLineIndex = opening.closingLineIndex {
                // A formula opened after other text (`- $$` in a list item, `Energy is $$`)
                // stays in its paragraph, closing line included, so that line does not
                // start a formula of its own.
                lineIndex = closingLineIndex + 1
                continue
            } else if MarkdownListSyntax.isThematicBreak(content), lineIndex == 0 || lineIndex == lineIndexAfterBlock
                        || MarkdownHeadingSyntax.setextHeadingLevel(ofLine: lines[lineIndex - 1].content, nextLine: content) == nil {
                // Directly after paragraph text, `---` underlines a heading instead of
                // drawing a rule; after a heading, a list item or a blank line it is a rule.
                blocks.append(LivePreviewBlock(kind: .horizontalRule, range: lines[lineIndex].range, markdown: content))
            }
            lineIndex += 1
        }
        return blocks
    }

    /// A display math block or a web frame that starts at `lineIndex`, and the last line it takes: blocks of whole lines,
    /// found as reading view finds them.
    private static func wholeLinesBlock(startingAt lineIndex: Int, of lines: [(range: NSRange, content: String)],
                                        mathLines: DisplayMathLines) -> (kind: LivePreviewBlock.Kind, lastIndex: Int)? {
        let trimmedContent = lines[lineIndex].content.trimmingCharacters(in: .whitespaces)
        // Display math is a block of its own, found as reading view finds it, so a
        // closing `$$` is never taken for a new opener.
        if trimmedContent.hasPrefix("$$") {
            let opening = mathLines.opening(at: lineIndex)
            if let opening, opening.isAtLineStart { return (.mathBlock, opening.closingLineIndex ?? lines.count - 1) }
            // A closed `$$…$$` alone on its line is display math too. With text after
            // it (`$$E=mc^2$$ where…`) it is inline math in a paragraph.
            if opening == nil, trimmedContent.hasSuffix("$$") { return (.mathBlock, lineIndex) }
        }
        // An `<iframe>` on lines of its own is HTML, never a callout's or a table's text.
        return WebFrameSyntax.frame(startingAt: lineIndex, lineCount: lines.count, line: { index in lines[index].content })
            .map { found in (.webFrame(found.frame), found.lastLineIndex) }
    }

    /// The pieces of a paragraph line that embeds images among its text. A heading, a list
    /// item (`imageLinePieces(ofListItem:followsListItem:)`), a quote, a table row or indented
    /// code keeps its own drawing, its images inline.
    private static func imageLinePieces(ofParagraphLine line: String) -> [ImageLinePiece]? {
        guard line.contains("!["), MarkdownHeadingSyntax.level(of: line) == nil, !MarkdownListSyntax.isListItem(line) else { return nil }
        var indentationColumns = 0
        for character in line {
            guard character == " " || character == "\t" else { break }
            indentationColumns += character == "\t" ? 4 - indentationColumns % 4 : 1
        }
        guard indentationColumns < 4, let first = line.first(where: { character in character != " " && character != "\t" }),
              first != ">", first != "|" else { return nil }
        return EmbedLocator.imageLinePieces(onLine: line)
    }

    /// The pieces of a list item whose text embeds images, as `- ![[a.jpg|200]] ![[b.jpg|200]]`:
    /// its marker, then its text and images as a paragraph line's. Obsidian draws the bullet or
    /// number with the pictures beside it. A task keeps its text, so its checkbox can still be
    /// ticked there, and so does an item in a quote, which a callout draws.
    private static func imageLinePieces(ofListItem line: String, followsListItem: Bool) -> [ImageLinePiece]? {
        guard line.contains("!["), let listLine = MarkdownListSyntax.listLine(line), listLine.isListItem,
              listLine.quotePrefix.isEmpty, listLine.taskStatus == nil else { return nil }
        let indentationColumns = listLine.indentation.reduce(0) { columns, character in character == "\t" ? columns + 4 - columns % 4 : columns + 1 }
        guard indentationColumns < 4 || followsListItem else { return nil }
        // The marker written over by spaces, so the embeds keep their places in the line.
        let markerLength = listLine.prefixLength
        let itemText = String(repeating: " ", count: markerLength) + (line as NSString).substring(from: markerLength)
        guard let pieces = EmbedLocator.imageLinePieces(onLine: itemText) else { return nil }
        return [.listMarker(ImageLineListMarker(indentation: listLine.indentation, marker: listLine.marker, spacing: listLine.spacing))] + pieces
    }

    /// `text` with its `%%` comments written over by spaces, line breaks kept, so every offset
    /// is where it was and nothing in a comment is read as a block. Most notes have none.
    private static func commentsBlankedOut(of text: NSString, commentRanges: [NSRange]) -> NSString {
        guard !commentRanges.isEmpty else { return text }
        let blanked = NSMutableString(string: text)
        for commentRange in commentRanges {
            let blankedUnits = (0..<commentRange.length).map { offset -> unichar in
                let unit = text.character(at: commentRange.location + offset)
                return unit == lineFeed || unit == carriageReturn ? unit : 0x20
            }
            blanked.replaceCharacters(in: commentRange, with: String(utf16CodeUnits: blankedUnits, count: blankedUnits.count))
        }
        return blanked
    }

    /// The leading frontmatter alone, for an editor that renders only the properties. It
    /// reads the start of the note, not every line.
    public static func frontmatterBlock(in text: NSString) -> LivePreviewBlock? {
        let frontmatterLength = FrontmatterLocator.length(in: text)
        guard frontmatterLength > 0 else { return nil }
        return LivePreviewBlock(kind: .frontmatter, range: NSRange(location: 0, length: frontmatterLength), markdown: text.substring(to: frontmatterLength))
    }

    /// Lines where CommonMark and reading view end them: at "\n", "\r\n" or a lone "\r".
    /// Each range includes its line break; the content excludes it, so a Windows note's
    /// "\r" never reaches fence, math or table detection. U+2028 and U+2029 stay inside a
    /// line, as reading view keeps them.
    private static func lines(in text: NSString, from start: Int) -> [(range: NSRange, content: String)] {
        var lines: [(range: NSRange, content: String)] = []
        var lineStart = start
        while lineStart < text.length {
            let breakLocation = text.rangeOfCharacter(from: lineBreakCharacters, options: .literal, range: NSRange(location: lineStart, length: text.length - lineStart)).location
            let contentEnd = breakLocation == NSNotFound ? text.length : breakLocation
            var nextLineStart = contentEnd
            if breakLocation != NSNotFound {
                nextLineStart = contentEnd + 1
                let isCRLF = text.character(at: contentEnd) == carriageReturn && nextLineStart < text.length && text.character(at: nextLineStart) == lineFeed
                if isCRLF { nextLineStart += 1 }
            }
            lines.append((NSRange(location: lineStart, length: nextLineStart - lineStart), text.substring(with: NSRange(location: lineStart, length: contentEnd - lineStart))))
            lineStart = nextLineStart
        }
        return lines
    }

    private static let lineBreakCharacters = CharacterSet(charactersIn: "\r\n")
    private static let lineFeed = UInt16(UInt8(ascii: "\n"))
    private static let carriageReturn = UInt16(UInt8(ascii: "\r"))

    /// Where the one fenced block in `language` holding `code` is in `text`: its zero-based
    /// first line (the opening fence) and the lines it spans. Nil when no block or more than
    /// one matches, since a plugin editing "its" lines must not reach another block.
    public static func onlyPluginCodeBlock(language: String, code: String, in text: String) -> (firstLine: Int, lineCount: Int)? {
        let source = text as NSString
        let matches = blocks(in: source, pluginCodeBlockLanguages: [language]).filter { block in
            block.kind == .pluginCodeBlock(language: language) && block.markdown == code
        }
        guard matches.count == 1, let block = matches.first else { return nil }
        // Lines end as `lines(in:)` ends them: at `\n`, `\r\n`, or a lone `\r`, which a
        // note saved by an old Mac app has.
        func lineNumber(at location: Int) -> Int {
            var lines = 0
            var index = 0
            while index < location {
                let unit = source.character(at: index)
                if unit == 0x0D {
                    lines += 1
                    if index + 1 < location, source.character(at: index + 1) == 0x0A { index += 1 }
                } else if unit == 0x0A {
                    lines += 1
                }
                index += 1
            }
            return lines
        }
        let firstLine = lineNumber(at: block.range.location)
        let lastLine = lineNumber(at: max(block.range.location, NSMaxRange(block.range) - 1))
        return (firstLine, lastLine - firstLine + 1)
    }
}
