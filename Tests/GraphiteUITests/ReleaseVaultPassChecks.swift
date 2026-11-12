/**
 * File: ReleaseVaultPassChecks.swift
 * ----------------------------------
 * Layer: Tests
 * Description: What the release pass finds wrong with a note in a view (an error, a block left as source, a picture
 *              not loaded, a freeze), and how it looks: Live Preview's views over its blocks, the reading view's blocks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import GraphiteCore
@testable import GraphiteUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One thing the release pass found wrong, where it found it.
struct ReleaseVaultFinding: Equatable, CustomStringConvertible {
    enum Shown: String {
        case livePreview = "Live Preview"
        case reading = "Reading view"
        case source = "Source mode"
        /// A PDF, canvas, base or picture in its own view.
        case ownView = "its own view"
        case wholeVault = "the vault"
    }

    enum Problem: Equatable {
        /// The workspace's error message, or why the tab could not open the file.
        case error(String)
        /// A block of `LivePreviewBlock.Kind` on screen with no view over its lines, so its source shows.
        case blockLeftAsSource(kind: String, line: Int)
        /// Source mode showing a rendered view, which hides source it should show.
        case renderedViewInSourceMode(count: Int)
        case pictureNotLoaded(target: String)
        case missingEmbed(target: String)
        case missingSection(target: String)
        case diagramNotDrawn(reason: String)
        case notShown(String)
        /// The main thread busy for one stretch longer than the budget, in milliseconds.
        case freeze(milliseconds: Int)
    }

    let path: String
    let shown: Shown
    let problem: Problem

    var description: String { "\(path) in \(shown.rawValue): \(problem)" }

    /// The vault's notes that show a failure on purpose: an embed of a note not written yet and of a heading that does not
    /// exist (`Links/Embeds.md`), which Graphite must show as such rather than as an error; an empty diagram; and what
    /// Graphite documents it does not do. Each must be seen, so a change in how Graphite shows it changes this list.
    static let intended: [ReleaseVaultFinding] = [
        ReleaseVaultFinding(path: "Links/Embeds.md", shown: .reading, problem: .missingEmbed(target: "A missing embed")),
        ReleaseVaultFinding(path: "Links/Embeds.md", shown: .reading, problem: .missingSection(target: "Link target#No such heading")),
        // Graphite shows only the SVG drawings it made; another app's SVG opens with the system preview (Docs/Coverage.md,
        // "Not done"), so `Pictures.md`'s SVG is not drawn in the note.
        ReleaseVaultFinding(path: "Pictures.md", shown: .livePreview, problem: .pictureNotLoaded(target: "Logo.svg")),
        ReleaseVaultFinding(path: "Pictures.md", shown: .reading, problem: .pictureNotLoaded(target: "Attachments/Logo.svg")),
        ReleaseVaultFinding(path: "Embeds/SVG in every form.md", shown: .livePreview, problem: .pictureNotLoaded(target: "Logo.svg")),
        ReleaseVaultFinding(path: "Embeds/SVG in every form.md", shown: .reading, problem: .pictureNotLoaded(target: "Attachments/Logo.svg")),
        // An empty Mermaid block is shown as its source with the reason (Docs/Native-diagrams-todo.md, the safety items).
        ReleaseVaultFinding(path: "Diagrams/Diagram options.md", shown: .reading,
                            problem: .diagramNotDrawn(reason: "reading(MermaidDiagrams.MermaidDiagramReadError.noDiagram)")),
    ]

    /// Defects the pass found and that are open in a todo file, reported on `GRAPHITE-RELEASE-KNOWN` lines rather than
    /// failing the pass; each goes when its item is fixed. Found on the iPad simulator on 2026-11-12
    /// (Docs/Editor-scrolling-todo.md): `Pictures.md` switched from the reading view to source mode still showing the
    /// reading view, with no text view, through its four pages. (The picture blocks left blank low on the screen are
    /// fixed and fail the pass again.)
    var isKnownOpenDefect: Bool {
        #if os(iOS)
        switch problem {
        case .notShown: path == "Pictures.md" && shown == .source
        case .error, .blockLeftAsSource, .renderedViewInSourceMode, .pictureNotLoaded, .missingEmbed, .missingSection, .diagramNotDrawn, .freeze: false
        }
        #else
        false
        #endif
    }
}

/// The views the pass looks into, on either platform.
@MainActor
enum ReleaseVaultViews {
    #if canImport(UIKit)
    typealias PlatformView = UIView
    typealias NoteTextView = MarkdownTextView
    #else
    typealias PlatformView = NSView
    typealias NoteTextView = MarkdownMacTextView
    #endif

    static func descendants<View: PlatformView>(of root: PlatformView, ofType type: View.Type) -> [View] {
        root.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, ofType: type) }
    }

    static func isShown(_ view: PlatformView) -> Bool {
        guard view.window != nil else { return false }
        var current: PlatformView? = view
        while let shownView = current {
            #if canImport(UIKit)
            if shownView.isHidden || shownView.alpha == 0 { return false }
            #else
            if shownView.isHidden { return false }
            #endif
            current = shownView.superview
        }
        return view.bounds.width > 0 && view.bounds.height > 0
    }

    /// The note's text view on screen: the widest shown, as an editor kept for a hidden tab is off screen.
    static func noteTextView(in root: PlatformView) -> NoteTextView? {
        descendants(of: root, ofType: NoteTextView.self).filter(isShown).max { first, second in first.bounds.width < second.bounds.width }
    }

    /// The hosted SwiftUI views Live Preview places in the text view over its blocks.
    static func renderedBlockViews(in textView: NoteTextView) -> [PlatformView] {
        textView.subviews.filter { subview in !subview.isHidden && String(describing: type(of: subview)).contains("HostingView") }
    }

    static func visibleRect(of textView: NoteTextView) -> CGRect {
        #if canImport(UIKit)
        textView.bounds
        #else
        textView.visibleRect
        #endif
    }

    /// Where the text container starts in the text view, which the editor adds to a fragment's frame to place a block.
    static func textContainerTop(of textView: NoteTextView) -> CGFloat {
        #if canImport(UIKit)
        textView.textContainerInset.top
        #else
        textView.textContainerOrigin.y
        #endif
    }
}

/// Live Preview's blocks as the release pass checks them: every block whose lines are on screen has a view over them,
/// found from the note's text by `LivePreviewBlockScanner` and from TextKit's layout of the viewport, independently of
/// the editor's own bookkeeping; and every picture among them was found and decoded.
@MainActor
enum LivePreviewBlockCheck {
    /// The blocks that start on screen with no rendered view at their first line, so their source shows instead.
    static func blocksLeftAsSource(in textView: ReleaseVaultViews.NoteTextView, blocks: [LivePreviewBlock]) -> [LivePreviewBlock] {
        guard let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return [] }
        let visibleRect = ReleaseVaultViews.visibleRect(of: textView)
        let containerTop = ReleaseVaultViews.textContainerTop(of: textView)
        let viewFrames = ReleaseVaultViews.renderedBlockViews(in: textView).map(\.frame)
        var checkedBlockIndexes = Set<Int>()
        var blocksWithoutViews: [LivePreviewBlock] = []
        layoutManager.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else { return false }
            let fragmentStart = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
            guard let blockIndex = blocks.firstIndex(where: { block in NSLocationInRange(fragmentStart, block.range) }),
                  !checkedBlockIndexes.contains(blockIndex) else { return true }
            let blockTop = fragment.layoutFragmentFrame.minY + containerTop
            guard blockTop >= visibleRect.minY, blockTop < visibleRect.maxY - 1 else { return true }
            checkedBlockIndexes.insert(blockIndex)
            if !viewFrames.contains(where: { frame in abs(frame.minY - blockTop) < 2 }) { blocksWithoutViews.append(blocks[blockIndex]) }
            return true
        }
        return blocksWithoutViews
    }

    /// The pictures of the blocks that have views on screen, which Live Preview looks up and decodes when it shows them.
    static func shownPictures(in textView: ReleaseVaultViews.NoteTextView, blocks: [LivePreviewBlock]) -> [EmbedReference] {
        guard let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
              let viewport = layoutManager.textViewportLayoutController.viewportRange else { return [] }
        let viewportStart = contentManager.offset(from: contentManager.documentRange.location, to: viewport.location)
        let viewportEnd = contentManager.offset(from: contentManager.documentRange.location, to: viewport.endLocation)
        let viewportCharacters = NSRange(location: viewportStart, length: max(0, viewportEnd - viewportStart))
        return blocks.filter { block in NSIntersectionRange(block.range, viewportCharacters).length > 0 }.flatMap(pictures(of:))
    }

    static func pictures(of block: LivePreviewBlock) -> [EmbedReference] {
        switch block.kind {
        case .embed(let embed): isPicture(embed) ? [embed] : []
        case .imageLine(let pieces):
            pieces.compactMap { piece in
                switch piece {
                case .image(let embed): isPicture(embed) ? embed : nil
                case .listMarker, .text: nil
                }
            }
        case .frontmatter, .table, .mathBlock, .baseDefinition, .horizontalRule, .callout, .pluginCodeBlock, .mermaidDiagram, .webFrame: []
        }
    }

    private static func isPicture(_ embed: EmbedReference) -> Bool {
        let fileName = embed.target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? embed.target
        return DocumentKind.imageFileExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    /// The name a finding gives a block's kind.
    static func kindName(of block: LivePreviewBlock) -> String {
        switch block.kind {
        case .frontmatter: "properties"
        case .table: "table"
        case .mathBlock: "formula"
        case .embed(let embed): "embed of \(embed.target)"
        case .imageLine: "line of pictures"
        case .baseDefinition: "base"
        case .horizontalRule: "rule"
        case .callout: "callout"
        case .pluginCodeBlock(let language): "\(language) block"
        case .mermaidDiagram: "diagram"
        case .webFrame: "web page"
        }
    }

    /// The block's first line, counted from 1, as a person finds it in the note.
    static func lineNumber(of block: LivePreviewBlock, in text: NSString) -> Int {
        text.substring(to: min(block.range.location, text.length)).components(separatedBy: "\n").count
    }
}

/// The reading view's blocks of a note, built as the reading view builds them (`ReadingVault.build`), and what in them
/// shows a failure: an embed or section not found, a diagram left as its source, a picture that does not decode.
enum ReadingBlockCheck {
    static func problems(in blocks: [RenderedBlock]) async -> [ReleaseVaultFinding.Problem] {
        var found: [ReleaseVaultFinding.Problem] = []
        for block in blocks {
            switch block {
            case .missingEmbed(_, let target): found.append(.missingEmbed(target: target))
            case .missingSection(_, let path, let subpath): found.append(.missingSection(target: "\(path.stem)#\(subpath)"))
            case .diagram(_, let diagram):
                if case .unreadable(_, let failure) = diagram { found.append(.diagramNotDrawn(reason: String(describing: failure))) }
            case .image(_, let path, let location, _, _):
                if (try? await ReadingImageCache.shared.thumbnail(for: location, kind: .block)) == nil { found.append(.pictureNotLoaded(target: path.rawValue)) }
            case .callout(_, _, _, _, let body), .transclusion(_, _, _, let body): found += await problems(in: body)
            case .properties, .markdown, .displayMath, .heading, .video, .audio, .pdf, .base, .baseFile, .footnotes, .pluginCodeBlock, .pluginSection,
                 .webFrame:
                break
            }
        }
        return found
    }
}
