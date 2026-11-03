/**
 * File: MarkdownSessionFolding.swift
 * ----------------------------------
 * Layer: UI
 * Description: Folding a note's headings and list items, which is kept on the device and not in the note.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

extension MarkdownSession {
    /// Folds or unfolds the heading or list item on the line at `location`; false when
    /// nothing there folds.
    @discardableResult
    func toggleFold(atLine location: Int) -> Bool {
        let regions = NoteFolding.regions(in: text)
        guard let region = NoteFolding.region(atLine: location, in: regions, text: text as NSString) else { return false }
        if foldedKeys.contains(region.key) { foldedKeys.remove(region.key) } else { foldedKeys.insert(region.key) }
        return true
    }

    /// Unfolds what hides a heading or text a jump is about to show.
    func unfold(toShow request: HeadingScrollRequest) {
        guard !foldedKeys.isEmpty else { return }
        let source = text as NSString
        var location = request.textRange?.location
        if location == nil, !request.anchor.isEmpty {
            // The heading's line: the first heading the outline lists with this anchor.
            location = HeadingLocator.lineLocation(ofHeadingWithAnchor: request.anchor, in: source)
        }
        guard let location else { return }
        let folded = NoteFolding.foldedRegions(in: NoteFolding.regions(in: text), foldedKeys: foldedKeys)
        let hiding = NoteFolding.regions(hiding: location, in: folded)
        if !hiding.isEmpty { foldedKeys.subtract(hiding.map(\.key)) }
    }

    func foldAll() {
        foldedKeys = Set(NoteFolding.regions(in: text).map(\.key))
    }

    func unfoldAll() {
        foldedKeys = []
    }
}
