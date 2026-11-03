/**
 * File: NativeMarkdownEditorMacFolding.swift
 * ------------------------------------------
 * Layer: UI
 * Description: The Mac's note editor doing what the iPad's does: typing helpers, folds, find opening what hides a match, and clicks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

#if os(macOS)
import AppKit
import GraphiteCore

extension NativeMarkdownEditor.Coordinator {
    /// What a click, the find bar and a fold button do; part of `connect`.
    func connectClicksFindAndFolds(of textView: MarkdownMacTextView) {
        textView.followLinkOnClick = { [weak self, weak textView] characterIndex, modifierFlags in
            guard let self, let textView else { return false }
            return self.followLink(atCharacter: characterIndex, modifierFlags: modifierFlags, in: textView)
        }
        textView.toggleTaskOnClick = { [weak self, weak textView] characterIndex in
            guard let self, let textView else { return false }
            return self.toggleTask(atCharacter: characterIndex, in: textView)
        }
        textView.isClickTarget = { [weak self, weak textView] characterIndex in
            guard let self, let textView else { return false }
            return self.taskCheckbox(atCharacter: characterIndex, in: textView) != nil || self.link(atCharacter: characterIndex, in: textView) != nil
        }
        textView.revealFoundText = { [weak self, weak textView] range in
            guard let self, let textView else { return }
            self.revealFoundText(range, in: textView)
        }
        foldButtons.toggle = { [weak self, weak textView] key in
            guard let self, let textView else { return }
            if self.session.foldedKeys.contains(key) { self.session.foldedKeys.remove(key) } else { self.session.foldedKeys.insert(key) }
            self.applyFolds(in: textView)
        }
    }

    /// Takes in the text: its rendered blocks, and what folds in it. An edit that makes the
    /// fold regions be found again (a line break) reads every line; with nothing folded,
    /// only the chevrons depend on them, so that waits for typing to pause, and a burst of
    /// typing costs one pass instead of one for each Return.
    func takeInText(of textView: NSTextView, forcesBlockScan: Bool = false) {
        let edit = textState.editSinceBlockScan
        styling.updateTextState(of: textView, forcesBlockScan: forcesBlockScan)
        foldTracking.update(source: textState.source, editSinceLastUpdate: edit, mayPostponeScan: session.foldedKeys.isEmpty)
        guard foldTracking.isWaitingForScan else { return }
        postponedFoldScan?.cancel()
        let clock = foldScanClock
        postponedFoldScan = Task { [weak self, weak textView] in
            do { try await clock.sleep(for: .milliseconds(250)) } catch { return } // Typing went on.
            guard let self, let textView else { return }
            self.foldTracking.scanIfWaiting()
            self.positionFoldButtons(in: textView)
        }
    }

    /// Moves the selected lines. A folded section moves and is moved past as one unit, its
    /// fold with it. A line that lands at the end of a folded heading's section is part of it
    /// now, and must not vanish into the fold.
    func moveLines(up: Bool, in textView: NSTextView) -> Bool {
        foldTracking.scanIfWaiting()
        let foldedSections = NoteFolding.foldedSections(foldTracking.folded(foldedKeys: session.foldedKeys))
        guard let edit = MarkdownEditing.movingLines(up: up, in: currentSource(of: textView), selection: textView.selectedRange(),
                                                     foldedSections: foldedSections) else { return false }
        isMovingLines = true
        perform(edit, in: textView)
        isMovingLines = false
        let hiding = NoteFolding.regions(hiding: edit.selectionAfter.location, in: foldTracking.folded(foldedKeys: session.foldedKeys))
        if !hiding.isEmpty {
            session.foldedKeys.subtract(hiding.map(\.key))
            applyFolds(in: textView)
            textView.setSelectedRange(edit.selectionAfter)
        }
        return true
    }

    /// The folds are carried from before a composition started: while one runs the text
    /// is not styled, and the regions wait for it to end.
    func recordEditAboutToBeMade(replacing range: NSRange, in textView: NSTextView) {
        guard !textView.hasMarkedText(), !session.foldedKeys.isEmpty else { return }
        foldTracking.recordEditAboutToBeMade(at: range.location, textLength: textView.textStorage?.length ?? 0,
                                             foldedKeys: session.foldedKeys, followsFolds: !isMovingLines)
    }

    /// What a key does beyond inserting itself, as on the iPad; nil for a plain insertion.
    func typingEdit(replacing range: NSRange, with replacement: String, belowProperties: Bool, in textView: NSTextView) -> MarkdownTextEdit? {
        let source = currentSource(of: textView)
        if !textState.cachesDescribeOldText,
           let edit = foldTracking.newLineAfterFoldedSection(replacing: range, with: replacement, in: source as String, foldedKeys: session.foldedKeys) {
            return edit
        }
        if belowProperties, let edit = MarkdownEditing.typingBelowClosingProperties(typed: replacement, in: source, selection: range) { return edit }
        guard range == textView.selectedRange() || replacement.isEmpty else { return nil }
        return configuration.editingBehavior.typingEdit(replacing: range, with: replacement, in: source, selection: textView.selectedRange())
    }

    /// Makes an edit of a command or a typing helper as one change Undo takes back.
    func perform(_ edit: MarkdownTextEdit, in textView: NSTextView) {
        guard let textStorage = textView.textStorage, NSMaxRange(edit.range) <= textStorage.length else { return }
        isMakingCommandEdit = true
        defer { isMakingCommandEdit = false }
        if edit.range.length > 0 || !edit.replacement.isEmpty {
            textView.breakUndoCoalescing()
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        }
        if NSMaxRange(edit.selectionAfter) <= textStorage.length {
            textView.setSelectedRange(edit.selectionAfter)
            textView.scrollRangeToVisible(edit.selectionAfter)
        }
    }

    // MARK: Folding

    /// Applies the session's folds: restyles the sections whose fold changed, and moves the
    /// cursor out of what is hidden. Restyling the whole note, for many folds at once,
    /// re-estimates TextKit's layout, so the view goes back to the line it showed.
    func applyFolds(in textView: NSTextView) {
        foldTracking.scanIfWaiting()
        if !textState.cachesDescribeOldText, let changedSections = foldTracking.sectionsChangingFold(to: session.foldedKeys) {
            foldTracking.appliedFoldedKeys = session.foldedKeys
            for section in changedSections { restyle(section, in: textView) }
        } else {
            let topLine = topCharacter(of: textView)
            restyleEverything(in: textView)
            if let topLine, pendingJump == nil {
                pendingJump = .topOfCharacter(topLine)
                performPendingJumpIfReady(in: textView)
            }
        }
        if let target = foldTracking.locationOutsideFolds(for: textView.selectedRange(), movedFrom: lastSelectionLocation,
                                                          textLength: textView.textStorage?.length ?? 0, foldedKeys: session.foldedKeys) {
            textView.setSelectedRange(NSRange(location: target, length: 0))
        }
        schedulePlacement(in: textView)
        positionFoldButtons(in: textView)
    }

    /// Places a chevron beside each heading and list item that folds, for the lines TextKit
    /// has laid out on screen. Mid-edit, the regions describe the text before it, and the
    /// buttons stay until it settles.
    func positionFoldButtons(in textView: NSTextView) {
        guard !textState.cachesDescribeOldText, !foldTracking.isWaitingForScan else { return }
        foldButtons.place(regionsByStart: foldTracking.regionsByStart(foldedKeys: session.foldedKeys), foldedKeys: session.foldedKeys,
                          source: currentSource(of: textView), in: textView)
    }

    /// Unfolds the sections that hide `location`, before a jump or a find shows it.
    func unfoldSections(hiding location: Int, in textView: NSTextView) {
        foldTracking.scanIfWaiting()
        let hiding = NoteFolding.regions(hiding: location, in: foldTracking.folded(foldedKeys: session.foldedKeys))
        guard !hiding.isEmpty else { return }
        session.foldedKeys.subtract(hiding.map(\.key))
        applyFolds(in: textView)
    }

    /// Shows the match the find bar moved to: its folded sections open, and a rendered block
    /// over it shows its source, though the bar holds the keyboard. Markup follows the
    /// keyboard again when it comes back to the note (`followKeyboardFocus`).
    func revealFoundText(_ range: NSRange, in textView: NSTextView) {
        guard !textState.cachesDescribeOldText, !textView.hasMarkedText(), NSMaxRange(range) <= (textView.textStorage?.length ?? 0) else { return }
        unfoldSections(hiding: range.location, in: textView)
        guard concealedEntries(in: textView).contains(where: { entry in
            entry.block.kind != .frontmatter && NSLocationInRange(range.location, entry.range)
        }) else { return }
        styling.revealsMarkupAtSelection = true
        if textView.selectedRange() != range { textView.setSelectedRange(range) }
        styling.restyleRevealedMarkup(in: textView)
    }
}
#endif
