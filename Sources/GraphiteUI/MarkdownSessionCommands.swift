/**
 * File: MarkdownSessionCommands.swift
 * -----------------------------------
 * Layer: UI
 * Description: What commands ask of an open note: insertions, ticking a task, its properties, and the find bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */

import Foundation
import GraphiteCore

extension MarkdownSession {
    /// Moves the cursor or selection of the editor on screen, or the one a new editor of the
    /// note starts with.
    func requestSelection(_ range: NSRange) {
        selection = range
        selectionRequest = range
    }

    /// Rewrites only the frontmatter, in Obsidian's property format, and saves through
    /// the normal autosave path. The properties were parsed with `declaredPropertyTypes`,
    /// so unchanged values keep their exact YAML.
    func replaceProperties(_ properties: [NoteProperty]) {
        text = NoteProperties.replacingFrontmatter(in: text, with: properties, declaredTypes: declaredPropertyTypes)
    }

    /// Inserts `content` at `range` of the current text, or at the cursor.
    func insert(_ content: String, at range: NSRange? = nil) {
        let target = insertionTarget(for: range)
        request(EditorInsertion(text: content, range: target.range))
    }

    /// Inserts a block such as an embed on its own line. Blank lines around the cursor
    /// are kept, so paragraphs never merge and a following `---` never turns the
    /// block into a heading.
    /// - Parameter separatedByBlankLines: Keeps an empty line around the block (quotes).
    func insertBlock(_ block: String, at range: NSRange? = nil, separatedByBlankLines: Bool = false) {
        let target = insertionTarget(for: range)
        let insertionRange = target.range
        let source = target.text
        // Never split the frontmatter: Obsidian would stop reading the note's properties.
        let frontmatterLength = FrontmatterLocator.length(in: source)
        let location = max(min(insertionRange.location, source.length), frontmatterLength)
        let endLocation = max(min(insertionRange.location + insertionRange.length, source.length), location)
        let insertion = MarkdownBlockInsertion.text(inserting: block, into: source, replacing: NSRange(location: location, length: endLocation - location),
                                                    separatedByBlankLines: separatedByBlankLines)
        request(EditorInsertion(text: insertion, range: NSRange(location: location, length: endLocation - location)))
    }

    /// Ticks or unticks the task at `location`, as a tap on its checkbox in reading view
    /// does, leaving the cursor where it is. False when the text no longer has the task
    /// there.
    @discardableResult
    func toggleTask(at location: ReadingTasks.Location) -> Bool {
        guard let edit = ReadingTasks.togglingEdit(at: location, in: text, selection: selection) else { return false }
        apply(edit)
        return true
    }

    /// Opens the find bar in the editor, leaving reading view first: it searches the text.
    func requestFind(_ request: FindRequest, editingMode: EditingMode) {
        if viewMode == .reading { viewMode = editingMode == .source ? .source : .livePreview }
        findRequest = request
    }

    /// Obsidian's "Toggle reading view": reading, or back to the editing mode.
    func toggleReadingView(editingMode: EditingMode) {
        viewMode = viewMode != .reading ? .reading : (editingMode == .source ? .source : .livePreview)
    }
}
