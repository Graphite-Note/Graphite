/**
 * File: SectionLink.swift
 * -----------------------
 * Layer: Core
 * Description: A link to a section of a note (a heading's section, a block, or the whole note) as a PDF page keeps
 *              it: the section a drag from a note starts in, the obsidian:// address other PDF readers follow, and
 *              reading that address back.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import Foundation
import CryptoKit

/// A link to part of a note, as `[[Note#Heading]]` or `[[Note#^block]]` names it, kept on a
/// PDF page. The page shows a picture of the part and links to it with Obsidian's own
/// address, `obsidian://open?vault=…&file=Note%23Heading`, which Obsidian and Graphite open.
public struct SectionLink: Equatable, Hashable, Sendable {
    /// The note as a link names it: its vault path without `.md` (`Course/Lecture 1`).
    public let note: String
    /// The heading's text, or `^` and a block's identifier; nil for the whole note.
    public let subpath: String?

    public init(note: String, subpath: String?) {
        self.note = note
        self.subpath = subpath.flatMap { trimmed in trimmed.isEmpty ? nil : trimmed }
    }

    public init(notePath: VaultPath, subpath: String?) {
        self.init(note: (notePath.rawValue as NSString).deletingPathExtension, subpath: subpath)
    }

    /// The link's text, as written between `[[` and `]]`.
    public var linkText: String { subpath.map { subpath in note + "#" + subpath } ?? note }

    /// How the link is named to a person: the note's name and the heading (`Lecture 1 › Entropy`);
    /// a block is named by its note, as Obsidian names it.
    public var title: String {
        let noteName = (note as NSString).lastPathComponent
        guard let subpath, !subpath.hasPrefix("^") else { return noteName }
        return noteName + " › " + subpath
    }

    /// Obsidian's address of the section in the vault named `vaultName`.
    public func openingURL(inVaultNamed vaultName: String) -> URL? {
        URL(string: "obsidian://open?vault=\(Self.encoded(vaultName))&file=\(Self.encoded(linkText))")
    }

    /// The section an address names: an `obsidian://` or `graphite://` link that opens a
    /// file, with the vault it names (nil for none). Nil for any other address.
    public init?(openingURL url: URL) {
        guard let link = VaultURI(url: url), case .open(let file?, _) = link.action, !file.isEmpty else { return nil }
        let parts = file.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let note = String(parts[0])
        guard !note.isEmpty else { return nil }
        self.init(note: note.hasSuffix(".md") ? String(note.dropLast(3)) : note, subpath: parts.count > 1 ? String(parts[1]) : nil)
    }

    /// The vault an address names, for checking it is the vault that is open.
    public static func vaultName(ofOpeningURL url: URL) -> String? {
        VaultURI(url: url)?.vault
    }

    // MARK: Following a moved note

    /// A section address rewritten for notes that moved, from their old path to their new one;
    /// nil when it names none of them, or is no section address. The address keeps its vault,
    /// its scheme's form and its heading or block.
    public static func address(_ address: String, following moves: [VaultPath: VaultPath]) -> String? {
        guard let url = URL(string: address), let link = SectionLink(openingURL: url) else { return nil }
        let movedNote = moves.first { previousPath, _ in
            DocumentKind(path: previousPath) == .markdown && (previousPath.rawValue as NSString).deletingPathExtension == link.note
        }
        guard let newPath = movedNote?.value, let vaultName = vaultName(ofOpeningURL: url) else { return nil }
        return SectionLink(notePath: newPath, subpath: link.subpath).openingURL(inVaultNamed: vaultName)?.absoluteString
    }

    // MARK: The section's text

    /// The part of a note's whole text (frontmatter included) the link names, as an embed of it
    /// shows it; nil when the note has no such heading or block.
    public func sectionText(inNoteText noteText: String) -> String? {
        let body = (noteText as NSString).substring(from: FrontmatterLocator.length(in: noteText as NSString))
        return NoteBlocks.embeddedPart(of: body, subpath: subpath)
    }

    /// A digest of a section's text (SHA-256, hexadecimal), or of its absence, so a picture
    /// drawn from it can tell whether the note changed since.
    public static func textDigest(of sectionText: String?) -> String {
        guard let sectionText else { return "missing" }
        return SHA256.hash(data: Data(sectionText.utf8)).map { byte in String(format: "%02x", byte) }.joined()
    }

    // MARK: The section a drag starts in

    /// What a drag that starts at `location` (UTF-16) of a note's text links to: the heading's
    /// section when it starts on a heading's line; else the block it starts in, given an
    /// identifier when it has none (the edit adds it, as Obsidian's "Copy link to block" does);
    /// else the section of the heading above; else the whole note.
    public static func link(startingAt location: Int, in text: String, notePath: VaultPath) -> (link: SectionLink, identifierEdit: MarkdownTextEdit?) {
        let source = text as NSString
        let bodyStart = FrontmatterLocator.length(in: source)
        guard location >= bodyStart, location <= source.length else { return (SectionLink(notePath: notePath, subpath: nil), nil) }
        let body = source.substring(from: bodyStart)
        let headings = headingLines(in: body)
        let bodyLocation = location - bodyStart
        let lineRange = (body as NSString).lineRange(for: NSRange(location: min(bodyLocation, (body as NSString).length), length: 0))
        if let heading = headings.first(where: { heading in heading.lineStart == lineRange.location }) {
            return (SectionLink(notePath: notePath, subpath: heading.text), nil)
        }
        if let block = NoteBlocks.blocks(in: text).first(where: { block in NSLocationInRange(location, block.range) || NSMaxRange(block.range) == location }) {
            if let identifier = block.identifier { return (SectionLink(notePath: notePath, subpath: "^" + identifier), nil) }
            let existing = Set(NoteBlocks.blocks(in: text).compactMap(\.identifier))
            let identifier = NoteBlocks.newIdentifier(avoiding: existing)
            return (SectionLink(notePath: notePath, subpath: "^" + identifier), NoteBlocks.addingIdentifier(identifier, to: block, in: text))
        }
        let headingAbove = headings.last { heading in heading.lineStart <= bodyLocation }
        return (SectionLink(notePath: notePath, subpath: headingAbove?.text), nil)
    }

    /// The headings of a body with where their lines start (UTF-16), in order.
    private static func headingLines(in body: String) -> [(text: String, lineStart: Int)] {
        var occurrences: [String: Int] = [:]
        return NotePreviewDocument.outline(of: body).compactMap { heading in
            let occurrence = occurrences[heading.anchor, default: 0]
            occurrences[heading.anchor] = occurrence + 1
            return NotePreviewDocument.headingLineLocation(ofHeadingWithAnchor: heading.anchor, occurrence: occurrence, in: body)
                .map { lineStart in (heading.text, lineStart) }
        }
    }

    /// Percent-encodes a query value, `#`, `&`, `/` and `=` included, as Obsidian writes them.
    private static func encoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
