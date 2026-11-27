/**
 * File: DetachedWidgetPool.swift
 * ------------------------------
 * Layer: UI
 * Description: Live Preview's rendered-block views kept off screen, bounded by their estimated memory, oldest out first.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore

/// Rendered-block views taken off screen, kept so a block that scrolls back into view, or
/// that the cursor leaves, shows again without being built again: building a table's view
/// takes tens of milliseconds. Memory bounds the pool, estimated per view from its block's
/// kind; the views taken off longest ago go first once the estimate passes the budget.
struct DetachedWidgetPool<Host> {
    private var hostsByKey: [LivePreviewBlockKey: (host: Host, estimatedMegabytes: Double, sequence: Int)] = [:]
    /// The views kept, in the order they were taken off screen, oldest first. Taking a
    /// view back leaves its entry here, matched by sequence number, so keeping and taking
    /// cost the same however many views are kept: removing from the list each time grew
    /// with the pool, which now holds many more views.
    private var detachmentOrder: [(key: LivePreviewBlockKey, sequence: Int)] = []
    private var detachmentOrderStart = 0
    private var nextSequence = 0
    private var estimatedMegabytesInPool: Double = 0
    let budgetMegabytes: Int

    init(budgetMegabytes: Int) {
        self.budgetMegabytes = budgetMegabytes
    }

    var isEmpty: Bool { hostsByKey.isEmpty }
    var keys: [LivePreviewBlockKey] {
        detachmentOrder[detachmentOrderStart...].filter { kept in hostsByKey[kept.key]?.sequence == kept.sequence }.map(\.key)
    }

    /// A view's estimated memory, from measured views: a 12-by-4 table about 6 MB,
    /// properties about 4 MB, a callout or math block under 1 MB; an embed can hold a
    /// decoded image. Nil for audio and video, which are never kept: a player kept off
    /// screen could go on playing.
    ///
    /// Tables, callouts and formulas are estimated from their size: every table counted as
    /// large as that 12-by-4 one, so a note of small tables kept a few sections' views and
    /// built every other one again as it scrolled back (measured 2026-10-16: views of
    /// three-row tables, two-line callouts and short formulas take about 0.2 MB each).
    static func estimatedMegabytes(of block: LivePreviewBlock) -> Double? {
        switch block.kind {
        case .table:
            let rows = block.markdown.split(separator: "\n").filter { line in line.contains("|") }
            let columns = rows.first.map { header in header.split(separator: "|", omittingEmptySubsequences: true).count } ?? 1
            return 0.15 + 0.12 * Double(max(1, rows.count - 1) * max(1, columns))
        case .baseDefinition: return 6
        case .frontmatter: return 4
        // A frame's view holds a live page, which is never kept off screen; nor is a callout's that holds one.
        case .webFrame: return nil
        case .callout where WebFrameSyntax.mayHoldFrame(block.markdown): return nil
        case .mathBlock, .callout:
            return 0.15 + 0.05 * Double(block.markdown.split(separator: "\n", omittingEmptySubsequences: false).count)
        case .horizontalRule: return 0.1
        // A copy of what a plugin drew is a web view of its own.
        case .pluginCodeBlock: return 8
        // Shapes and lines of text, as a formula's glyphs are; estimated as a formula of as many lines, not measured.
        case .mermaidDiagram: return 0.15 + 0.05 * Double(block.markdown.split(separator: "\n", omittingEmptySubsequences: false).count)
        case .embed(let embed):
            // A video card's thumbnail, 640 by 360 pixels.
            if WebVideo(embed: embed) != nil { return 1 }
            let fileExtension = (WikiLinkResolver.pathPart(embed.target) as NSString).pathExtension.lowercased()
            if DocumentKind.videoFileExtensions.contains(fileExtension) || DocumentKind.audioFileExtensions.contains(fileExtension) { return nil }
            return 12
        // Each picture is decoded for the width it is shown at: a 200-point photo at three
        // pixels a point, four by three, takes about 1.1 MB; one without a width, a line's.
        case .imageLine(let pieces):
            return pieces.reduce(0.15) { estimate, piece in
                guard case .image(let embed) = piece else { return estimate + 0.05 }
                guard let width = embed.displayWidth else { return estimate + 12 }
                return estimate + min(12, max(0.1, 4 * (3 * width) * (3 * width * 3 / 4) / 1_000_000))
            }
        }
    }

    /// Keeps a view taken off screen, dropping the oldest kept views past the budget.
    mutating func keep(_ host: Host, for key: LivePreviewBlockKey, estimatedMegabytes: Double) {
        _ = take(key)
        guard estimatedMegabytes <= Double(budgetMegabytes) else { return }
        hostsByKey[key] = (host, estimatedMegabytes, nextSequence)
        detachmentOrder.append((key, nextSequence))
        nextSequence += 1
        estimatedMegabytesInPool += estimatedMegabytes
        while estimatedMegabytesInPool > Double(budgetMegabytes), detachmentOrderStart < detachmentOrder.count {
            let oldest = detachmentOrder[detachmentOrderStart]
            detachmentOrderStart += 1
            if hostsByKey[oldest.key]?.sequence == oldest.sequence { _ = take(oldest.key) }
        }
        // The entries passed over are dropped once they are most of the list.
        if detachmentOrderStart > 64, detachmentOrderStart * 2 > detachmentOrder.count {
            detachmentOrder.removeFirst(detachmentOrderStart)
            detachmentOrderStart = 0
        }
    }

    /// Takes a kept view out of the pool to show it again.
    mutating func take(_ key: LivePreviewBlockKey) -> Host? {
        guard let kept = hostsByKey.removeValue(forKey: key) else { return nil }
        estimatedMegabytesInPool -= kept.estimatedMegabytes
        return kept.host
    }

    /// A kept view, left in the pool, such as to give it a new appearance.
    func host(for key: LivePreviewBlockKey) -> Host? {
        hostsByKey[key]?.host
    }

    /// Drops the kept views of blocks no longer in the note.
    mutating func removeHosts(notIn keysInNote: Set<LivePreviewBlockKey>) {
        for key in Array(hostsByKey.keys) where !keysInNote.contains(key) { _ = take(key) }
    }

    mutating func removeAll() {
        hostsByKey.removeAll()
        detachmentOrder.removeAll()
        detachmentOrderStart = 0
        estimatedMegabytesInPool = 0
    }
}
