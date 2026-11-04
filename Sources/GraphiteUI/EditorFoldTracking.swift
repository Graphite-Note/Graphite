/**
 * File: EditorFoldTracking.swift
 * ------------------------------
 * Layer: UI
 * Description: What folds in the note on screen and how folds follow its edits, the same in the iPad's and the Mac's editors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// The headings and list items that fold in the text an editor shows, kept up to date as it
/// is edited. What is folded lives in the session (`MarkdownSession.foldedKeys`); this works
/// out what that hides, and carries folds across edits.
@MainActor
final class EditorFoldTracking {
    /// Notes longer than this do not fold, to keep typing fast.
    private static let maximumFoldingLength = 2_000_000

    private(set) var regions: [FoldableRegion] = [] {
        didSet { revision += 1 }
    }
    /// Changes with `regions`, for what is worked out from them on every frame.
    private var revision = 0
    /// The text `regions` were found in or moved to.
    private var source: NSString?
    /// Whether the text moved on from `regions` and a scan is owed; see `update`.
    private(set) var isWaitingForScan = false
    /// The folds last applied to the text's styling.
    var appliedFoldedKeys: Set<String> = []
    /// The text's length, the edit's location, and the folds before the edit under way.
    private var lengthBeforeEdit = 0
    private var editLocationBeforeEdit = 0
    private var foldedBeforeEdit: [FoldableRegion] = []
    /// Keeps the folded regions and the headers that show a fold button, worked out again only
    /// when the regions or the folds change: they were worked out several times on every
    /// frame of a scroll, each a pass over every foldable region.
    private var layoutCache: (revision: Int, foldedKeys: Set<String>, folded: [FoldableRegion], regionsByStart: [Int: FoldableRegion])?

    /// Takes in the text. Typing only moves the regions, which keeps a keystroke in a long note
    /// within a frame. An edit that needs them found again reads every line, once; with
    /// `mayPostponeScan` that waits for `scanIfWaiting()` so a burst of typing pays once.
    func update(source newSource: NSString, editSinceLastUpdate edit: (edit: CharacterEdit, sourceBeforeEdit: NSString)?, mayPostponeScan: Bool = false) {
        if edit == nil, newSource === source { return }
        defer { source = newSource }
        if newSource.length > Self.maximumFoldingLength {
            regions = []
            isWaitingForScan = false
            return
        }
        if !isWaitingForScan, let edit, edit.sourceBeforeEdit === source,
           let moved = NoteFolding.regions(regions, across: edit.edit.replacedRange, replacementLength: edit.edit.editedRange.length,
                                           before: edit.sourceBeforeEdit, after: newSource) {
            regions = moved
            return
        }
        if mayPostponeScan {
            isWaitingForScan = true
            return
        }
        regions = NoteFolding.regions(in: newSource as String)
        isWaitingForScan = false
    }

    /// Finds the regions owed by an `update` that postponed it.
    func scanIfWaiting() {
        guard isWaitingForScan, let source else { return }
        regions = NoteFolding.regions(in: source as String)
        isWaitingForScan = false
    }

    private func layout(foldedKeys: Set<String>) -> (folded: [FoldableRegion], regionsByStart: [Int: FoldableRegion]) {
        if let layoutCache, layoutCache.revision == revision, layoutCache.foldedKeys == foldedKeys {
            return (layoutCache.folded, layoutCache.regionsByStart)
        }
        let folded = NoteFolding.foldedRegions(in: regions, foldedKeys: foldedKeys)
        var regionsByStart: [Int: FoldableRegion] = [:]
        for region in regions where NoteFolding.regions(hiding: region.headerRange.location, in: folded).isEmpty {
            if regionsByStart[region.headerRange.location] == nil { regionsByStart[region.headerRange.location] = region }
        }
        layoutCache = (revision, foldedKeys, folded, regionsByStart)
        return (folded, regionsByStart)
    }

    /// The regions folded away, without those inside another folded one.
    func folded(foldedKeys: Set<String>) -> [FoldableRegion] { layout(foldedKeys: foldedKeys).folded }

    /// The visible headers that show a fold button, by where their lines start.
    func regionsByStart(foldedKeys: Set<String>) -> [Int: FoldableRegion] { layout(foldedKeys: foldedKeys).regionsByStart }

    /// Where the sections whose fold changed since `appliedFoldedKeys` lie, so only they are
    /// restyled; nil when so many changed, as with Fold All, that the whole note is.
    func sectionsChangingFold(to foldedKeys: Set<String>) -> [NSRange]? {
        let changedKeys = foldedKeys.symmetricDifference(appliedFoldedKeys)
        guard changedKeys.count <= 8 else { return nil }
        let changed = regions.filter { region in changedKeys.contains(region.key) }
        guard changed.count == changedKeys.count else { return nil }
        return changed.map { region in NSRange(location: region.headerRange.location, length: region.endLocation - region.headerRange.location) }
    }

    /// Takes note of an edit about to be made, whose folds `carryFoldsAcrossEdit` follows.
    func recordEditAboutToBeMade(at location: Int, textLength: Int, foldedKeys: Set<String>, followsFolds: Bool = true) {
        lengthBeforeEdit = textLength
        editLocationBeforeEdit = location
        foldedBeforeEdit = followsFolds ? folded(foldedKeys: foldedKeys) : []
    }

    /// A folded heading or list item whose line was edited has a new key; the fold moves to
    /// it, as the fold belongs to the line. Returns whether the folds changed, so the note is
    /// restyled rather than left with the old section's hidden lines.
    func carryFoldsAcrossEdit(textLength: Int, foldedKeys: Set<String>) -> (changed: Bool, foldedKeys: Set<String>) {
        let previouslyFolded = foldedBeforeEdit
        foldedBeforeEdit = []
        guard !previouslyFolded.isEmpty else { return (false, foldedKeys) }
        let lengthChange = textLength - lengthBeforeEdit
        let editLocation = editLocationBeforeEdit
        // Every fold follows its header to where the edit moved it, whatever key the header
        // has now: keys count headings of the same text, so a new "## Notes" typed above a
        // folded one took its key, and the fold jumped to the other heading.
        var keys = foldedKeys.subtracting(previouslyFolded.map(\.key))
        for region in previouslyFolded {
            let headerStart = region.headerRange.location + (editLocation < region.headerRange.location ? lengthChange : 0)
            if let moved = regions.first(where: { candidate in candidate.headerRange.location == headerStart }) {
                keys.insert(moved.key)
            } else if regions.contains(where: { candidate in candidate.key == region.key }) {
                keys.insert(region.key)
            }
        }
        var changed = keys != foldedKeys
        // A section that still folds but whose hidden text moved or changed needs restyling too.
        let stillFolded = NoteFolding.foldedRegions(in: regions, foldedKeys: keys)
        if stillFolded.map(\.hiddenRange) != previouslyFolded.map({ region in
            NSRange(location: region.hiddenRange.location + (editLocation < region.hiddenRange.location ? lengthChange : 0), length: region.hiddenRange.length)
        }) { changed = true }
        return (changed, keys)
    }

    /// Where a cursor that landed in a folded section goes instead: past the section when
    /// it moved down into it, else to the end of the section's header line.
    func locationOutsideFolds(for selection: NSRange, movedFrom previousLocation: Int, textLength: Int, foldedKeys: Set<String>) -> Int? {
        guard selection.length == 0 else { return nil }
        let location = selection.location
        for region in folded(foldedKeys: foldedKeys) {
            let hasVisibleEnd = region.endLocation > NSMaxRange(region.hiddenRange)
            let isHidden = location > region.hiddenRange.location && (location < region.endLocation || (!hasVisibleEnd && location == region.endLocation))
            guard isHidden else { continue }
            // A tap lands in the hidden text's collapsed lines, which sit at the end of the
            // header line; the arrow keys move from the header past the section.
            let movedDownByOneLine = previousLocation == region.hiddenRange.location
            return movedDownByOneLine && hasVisibleEnd && region.endLocation <= textLength ? region.endLocation : region.hiddenRange.location
        }
        return nil
    }

    /// The edit that replaces `range` with `replacement`, when it is made on a folded section
    /// rather than typed: Return at the end of a folded line starts a line after the section.
    func newLineAfterFoldedSection(replacing range: NSRange, with replacement: String, in text: String, foldedKeys: Set<String>) -> MarkdownTextEdit? {
        guard replacement == "\n", range.length == 0,
              let region = folded(foldedKeys: foldedKeys).first(where: { region in region.hiddenRange.location == range.location }) else { return nil }
        return NoteFolding.newLineAfterFoldedSection(region, in: text)
    }

    /// The folds to take off before an edit of `range` is made, which reaches into what they
    /// hide; nothing is typed into, or deleted from, text that cannot be seen.
    func foldsTouched(byEditReplacing range: NSRange, foldedKeys: Set<String>) -> [FoldableRegion] {
        let folded = folded(foldedKeys: foldedKeys)
        guard folded.contains(where: { region in NoteFolding.edit(replacing: range, touchesHiddenTextOf: region) }) else { return [] }
        return folded.filter { region in
            NSIntersectionRange(NSRange(location: region.hiddenRange.location, length: region.endLocation - region.hiddenRange.location), range).length > 0
                || NSLocationInRange(range.location, region.hiddenRange)
        }
    }
}
