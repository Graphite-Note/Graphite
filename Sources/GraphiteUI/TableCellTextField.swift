/**
 * File: TableCellTextField.swift
 * ------------------------------
 * Layer: UI
 * Description: The native text field of a Live Preview table's cell editor and the keys it gives the table.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 18/11/2026
 */

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

#if canImport(UIKit)
typealias PlatformCellField = TableCellTextView
#else
typealias PlatformCellField = TableCellMacTextField
#endif

/// The text field of a Live Preview table's cell editor: a native text view, so the table
/// decides what Return, Tab, Shift-Tab, Escape and the arrow keys do. SwiftUI's text field
/// treated a hardware Return as submitting and gave up the keyboard on the iPad, so text typed
/// right after Return was lost. Shift-Return (Option-Return on the Mac too) puts a line break
/// in the cell. Smart dashes and quotes are off, as in the note's editor: a cell's `--` and
/// quotes are Markdown.
struct TableCellTextField {
    /// The cell editor that has the keyboard, in any table.
    @MainActor private static weak var focusedField: PlatformCellField?

    /// Takes the keyboard from another table's cell editor at once, as a tap opens this one:
    /// keys typed before this table's field takes the keyboard went into that cell's text.
    @MainActor static func endEditingInOtherTables() {
        guard let focusedField else { return }
        #if canImport(UIKit)
        focusedField.resignFirstResponder()
        #else
        if let window = focusedField.window, focusedField.currentEditor() != nil { window.makeFirstResponder(nil) }
        #endif
    }

    @Binding var text: String
    let font: PlatformFont
    /// Takes the keyboard, and places the caret, each time this changes.
    let focusRequest: Int
    /// Where the caret goes for the latest focus request or move to another cell.
    let caret: () -> TableCellCaret
    /// Whether the table took the key; one it did not take is typed as usual.
    let handleKey: (TableCellKey) -> Bool
    var actions = TableCellFieldActions()
    /// While cells are selected the caret is hidden, as Obsidian's (`.has-selection`).
    var hidesCaret = false
    let focusDidChange: (_ isFocused: Bool) -> Void
}

#if canImport(UIKit)
extension TableCellTextField: UIViewRepresentable {
    final class Coordinator: NSObject, UITextViewDelegate {
        var field: TableCellTextField
        var appliedFocusRequest = 0

        init(field: TableCellTextField) {
            self.field = field
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            // Selected cells are not typed into, as in Obsidian.
            if field.actions.hasCellSelection() {
                if replacement.isEmpty { _ = field.handleKey(.deleteSelection) }
                return false
            }
            guard replacement == "\n", let cellTextView = textView as? TableCellTextView, !cellTextView.isInsertingLineBreak else { return true }
            return !cellTextView.perform(.returnKey)
        }

        func textViewDidChange(_ textView: UITextView) {
            // Text an input method is still composing is not the cell's yet.
            guard textView.markedTextRange == nil, field.text != textView.text else { return }
            field.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            TableCellTextField.focusedField = textView as? TableCellTextView
            field.focusDidChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if TableCellTextField.focusedField === textView { TableCellTextField.focusedField = nil }
            field.focusDidChange(false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeUIView(context: Context) -> TableCellTextView {
        let textView = TableCellTextView()
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: TableCellTextView, context: Context) {
        context.coordinator.field = self
        textView.handleKey = handleKey
        textView.actions = actions
        textView.caret = caret
        textView.currentText = { [text = _text] in text.wrappedValue }
        if textView.font != font { textView.font = font }
        textView.tintColor = hidesCaret ? .clear : nil
        if textView.text != text, textView.markedTextRange == nil {
            textView.showCellText(text)
        }
        guard context.coordinator.appliedFocusRequest != focusRequest else { return }
        context.coordinator.appliedFocusRequest = focusRequest
        // Not during the view update, which a change of first responder would re-enter.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            if !textView.isFirstResponder { textView.becomeFirstResponder() }
            textView.placeCaret()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: TableCellTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? textView.bounds.width
        let fittingSize = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fittingSize.height))
    }
}

/// The cell editor's text view, with the keys the table moves by.
final class TableCellTextView: UITextView {
    var handleKey: ((TableCellKey) -> Bool)?
    var actions = TableCellFieldActions()
    var caret: (() -> TableCellCaret)?
    /// The draft as the table has it now, read at once after a key moved the editor.
    var currentText: (() -> String)?
    /// Typing in the cell being edited is undone by the note's history. UIKit's keyboard answers
    /// ⌘Z itself, before the key commands, once the cell has been typed in, with this undo
    /// manager; it records nothing and gives its undo and redo to the table, as the key command
    /// does, and keeps UIKit's own undo of the field from reaching another cell's text.
    private lazy var cellUndoManager = TableCellUndoManager { [weak self] isRedo in _ = self?.perform(isRedo ? .redo : .undo) }
    override var undoManager: UndoManager? { cellUndoManager }

    /// Shows another cell's text with the caret where the table asks, and forgets the typing
    /// undo of the cell before.
    func showCellText(_ cellText: String) {
        text = cellText
        placeCaret()
    }

    func placeCaret() {
        selectedRange = TableCellCaretRange.range(for: caret?() ?? .end, in: text) { [weak self] point in
            guard let self, let position = closestPosition(to: point) else { return nil }
            return offset(from: beginningOfDocument, to: position)
        }
    }

    /// While Shift-Return inserts its line break, which Return's check lets through.
    private(set) var isInsertingLineBreak = false

    override var keyCommands: [UIKeyCommand]? {
        let arrows: [(String, TableCellDirection)] = [
            (UIKeyCommand.inputUpArrow, .up), (UIKeyCommand.inputDownArrow, .down),
            (UIKeyCommand.inputLeftArrow, .backward), (UIKeyCommand.inputRightArrow, .forward),
        ]
        var commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tabKey)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(backtabKey)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapeKey)),
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(lineBreakKey)),
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(undoKey)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(redoKey)),
        ]
        // Only at the cell's edge, or while cells are selected: elsewhere the arrows move the
        // caret as usual. UIKit asks for the commands at each key.
        let takesArrows = actions.hasCellSelection()
        for (input, direction) in arrows where takesArrows || isAtEdge(logical(direction)) {
            commands.append(UIKeyCommand(input: input, modifierFlags: [], action: #selector(arrowKey(_:))))
            commands.append(UIKeyCommand(input: input, modifierFlags: .shift, action: #selector(shiftArrowKey(_:))))
        }
        for command in commands { command.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    /// Gives the key to the table and, when it moved the editor, shows the new cell's text
    /// at once: keys typed before SwiftUI's next update would otherwise go into the old cell's
    /// text and be written into the new cell.
    func perform(_ key: TableCellKey) -> Bool {
        guard handleKey?(key) == true else { return false }
        if let newText = currentText?(), newText != text { showCellText(newText) } else { placeCaretAfterMove() }
        return true
    }

    /// A move to a cell of the same text (two empty cells) still places the caret.
    private func placeCaretAfterMove() {
        if case .point = caret?() { return }
        placeCaret()
    }

    @objc private func tabKey() { _ = perform(.tab) }
    @objc private func backtabKey() { _ = perform(.backtab) }
    @objc private func escapeKey() { _ = perform(.escape) }
    @objc private func undoKey() { _ = perform(.undo) }
    @objc private func redoKey() { _ = perform(.redo) }

    private var isRightToLeft: Bool {
        baseWritingDirection(for: selectedTextRange?.start ?? beginningOfDocument, in: .forward) == .rightToLeft
    }

    /// The physical arrow's direction in the text's reading order.
    private func logical(_ physical: TableCellDirection) -> TableCellDirection {
        guard isRightToLeft else { return physical }
        switch physical {
        case .backward: return .forward
        case .forward: return .backward
        case .up, .down: return physical
        }
    }

    private func direction(of command: UIKeyCommand) -> TableCellDirection? {
        switch command.input {
        case UIKeyCommand.inputUpArrow: return .up
        case UIKeyCommand.inputDownArrow: return .down
        case UIKeyCommand.inputLeftArrow: return logical(.backward)
        case UIKeyCommand.inputRightArrow: return logical(.forward)
        default: return nil
        }
    }

    /// Whether the caret, with nothing selected, is at the cell's edge in that direction.
    private func isAtEdge(_ direction: TableCellDirection) -> Bool {
        guard let selected = selectedTextRange, selected.isEmpty else { return false }
        switch direction {
        case .backward: return compare(selected.start, to: beginningOfDocument) == .orderedSame
        case .forward: return compare(selected.end, to: endOfDocument) == .orderedSame
        case .up: return caretRect(for: selected.start).minY <= caretRect(for: beginningOfDocument).minY + 1
        case .down: return caretRect(for: selected.end).minY >= caretRect(for: endOfDocument).minY - 1
        }
    }

    @objc private func arrowKey(_ command: UIKeyCommand) {
        guard let direction = direction(of: command) else { return }
        _ = perform(.leave(direction))
    }

    @objc private func shiftArrowKey(_ command: UIKeyCommand) {
        guard let direction = direction(of: command) else { return }
        _ = perform(.extendSelection(direction))
    }

    @objc private func lineBreakKey() {
        guard !actions.hasCellSelection() else { return }
        isInsertingLineBreak = true
        insertText("\n")
        isInsertingLineBreak = false
    }

    override func copy(_ sender: Any?) {
        if !actions.copyCells(false) { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        if !actions.copyCells(true) { super.cut(sender) }
    }

    override func paste(_ sender: Any?) {
        if !actions.pasteCells() { super.paste(sender) }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if actions.hasCellSelection(), action == #selector(copy(_:)) || action == #selector(cut(_:)) || action == #selector(paste(_:)) { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func deleteBackward() {
        if actions.hasCellSelection() { _ = perform(.deleteSelection) } else { super.deleteBackward() }
    }
}
#else
extension TableCellTextField: NSViewRepresentable {
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var field: TableCellTextField
        var appliedFocusRequest = 0

        init(field: TableCellTextField) {
            self.field = field
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let isRightToLeft = textView.baseWritingDirection == .rightToLeft
            let key: TableCellKey
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)): key = .returnKey
            case #selector(NSResponder.insertTab(_:)): key = .tab
            case #selector(NSResponder.insertBacktab(_:)): key = .backtab
            case #selector(NSResponder.cancelOperation(_:)): key = .escape
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
                guard field.actions.hasCellSelection() else { return false }
                key = .deleteSelection
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if !field.actions.hasCellSelection() { textView.insertNewlineIgnoringFieldEditor(nil) }
                return true
            default:
                guard let (direction, extends) = Self.arrow(commandSelector, isRightToLeft: isRightToLeft) else { return false }
                guard field.actions.hasCellSelection() || Self.isAtEdge(direction, of: textView) else { return false }
                key = extends ? .extendSelection(direction) : .leave(direction)
            }
            guard field.handleKey(key) else { return false }
            // The new cell's text at once, so keys typed before SwiftUI's next update go into it.
            if textView.string != field.text {
                (control as? TableCellMacTextField)?.cellUndoManager.removeAllActions()
                textView.string = field.text
            }
            Self.placeCaret(field.caret(), in: textView)
            return true
        }

        private static func arrow(_ selector: Selector, isRightToLeft: Bool) -> (TableCellDirection, Bool)? {
            let backward: TableCellDirection = isRightToLeft ? .forward : .backward
            let forward: TableCellDirection = isRightToLeft ? .backward : .forward
            switch selector {
            case #selector(NSResponder.moveUp(_:)): return (.up, false)
            case #selector(NSResponder.moveDown(_:)): return (.down, false)
            case #selector(NSResponder.moveLeft(_:)): return (backward, false)
            case #selector(NSResponder.moveRight(_:)): return (forward, false)
            case #selector(NSResponder.moveUpAndModifySelection(_:)): return (.up, true)
            case #selector(NSResponder.moveDownAndModifySelection(_:)): return (.down, true)
            case #selector(NSResponder.moveLeftAndModifySelection(_:)): return (backward, true)
            case #selector(NSResponder.moveRightAndModifySelection(_:)): return (forward, true)
            default: return nil
            }
        }

        /// Whether the caret, with nothing selected, is at the cell's edge in that direction:
        /// its start or end, or its first or last line as laid out.
        static func isAtEdge(_ direction: TableCellDirection, of textView: NSTextView) -> Bool {
            let selected = textView.selectedRange()
            guard selected.length == 0 else { return false }
            let length = (textView.string as NSString).length
            switch direction {
            case .backward: return selected.location == 0
            case .forward: return selected.location == length
            case .up, .down:
                let caretRect = textView.firstRect(forCharacterRange: selected, actualRange: nil)
                let edgeRect = textView.firstRect(forCharacterRange: NSRange(location: direction == .up ? 0 : length, length: 0), actualRange: nil)
                // Screen rectangles: y grows upward.
                return direction == .up ? caretRect.maxY >= edgeRect.maxY - 1 : caretRect.minY <= edgeRect.minY + 1
            }
        }

        static func placeCaret(_ caret: TableCellCaret, in textView: NSTextView) {
            textView.selectedRange = TableCellCaretRange.range(for: caret, in: textView.string) { point in
                textView.characterIndexForInsertion(at: point)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            // Selected cells are not typed into, as in Obsidian: the typing is taken back.
            if field.actions.hasCellSelection() {
                textField.stringValue = field.text
                return
            }
            // Text an input method is still composing is not the cell's yet.
            if (textField.currentEditor() as? NSTextView)?.hasMarkedText() == true { return }
            guard field.text != textField.stringValue else { return }
            field.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.turnOffSubstitutionsForMarkdown()
            TableCellTextField.focusedField = notification.object as? TableCellMacTextField
            field.focusDidChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if TableCellTextField.focusedField === notification.object as AnyObject { TableCellTextField.focusedField = nil }
            field.focusDidChange(false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeNSView(context: Context) -> TableCellMacTextField {
        let textField = TableCellMacTextField(string: text)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = false
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 0
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.delegate = context.coordinator
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: TableCellMacTextField, context: Context) {
        context.coordinator.field = self
        textField.handleKey = handleKey
        textField.actions = actions
        if textField.font != font { textField.font = font }
        (textField.currentEditor() as? NSTextView)?.insertionPointColor = hidesCaret ? .clear : .textInsertionPointColor
        if textField.stringValue != text, (textField.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            textField.cellUndoManager.removeAllActions()
            textField.stringValue = text
            if let fieldEditor = textField.currentEditor() as? NSTextView { Coordinator.placeCaret(caret(), in: fieldEditor) }
        }
        guard context.coordinator.appliedFocusRequest != focusRequest else { return }
        context.coordinator.appliedFocusRequest = focusRequest
        let caret = caret
        DispatchQueue.main.async { [weak textField] in
            guard let textField, let window = textField.window else { return }
            if textField.currentEditor() == nil { window.makeFirstResponder(textField) }
            // AppKit reports the beginning of editing only at the first change.
            if textField.currentEditor() != nil { TableCellTextField.focusedField = textField }
            guard let fieldEditor = textField.currentEditor() as? NSTextView else { return }
            // The field editor is shared by the window's fields; a cell's `--` stays as typed.
            fieldEditor.turnOffSubstitutionsForMarkdown()
            fieldEditor.layoutManager?.ensureLayout(for: fieldEditor.textContainer!)
            Coordinator.placeCaret(caret(), in: fieldEditor)
        }
    }

    /// How far in from each side AppKit's text field cell measures and draws its text.
    private static let cellTextInset: CGFloat = 2

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: TableCellMacTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? textField.bounds.width
        textField.preferredMaxLayoutWidth = width
        // The cell measures its text 2 points in from each side, while the field editor that shows
        // it while editing lays it out from the field's edges: measured at the field's width, a
        // cell such as "M1 (cascode, bottom)" counted a second line and covered the row below.
        let measuringWidth = width + 2 * Self.cellTextInset
        let height = textField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: measuringWidth, height: .greatestFiniteMagnitude)).height
            ?? textField.intrinsicContentSize.height
        return CGSize(width: width, height: ceil(height))
    }
}

/// The cell editor's field on the Mac, with an undo history of its own for Edit › Undo while
/// typing: the window's field editor would apply typing undone after a move to another cell
/// to that cell's text. ⌘Z and ⇧⌘Z go to the table, which undoes the note's own history.
final class TableCellMacTextField: NSTextField {
    /// As on iOS, Edit › Undo and ⌘Z in the cell undo the note's history: the field editor asks
    /// this manager, which records no typing (with the typing in it, Edit › Undo undid only the
    /// cell's typing and then dimmed, short of the note's earlier steps).
    lazy var cellUndoManager = TableCellUndoManager { [weak self] isRedo in _ = self?.handleKey?(isRedo ? .redo : .undo) }
    var handleKey: ((TableCellKey) -> Bool)?
    var actions = TableCellFieldActions()

    /// Asked by the field editor, whose delegate the field is while it edits.
    @objc(undoManagerForTextView:)
    func undoManager(for textView: NSTextView) -> UndoManager? { cellUndoManager }

    /// The field's cell gives it a field editor of its own (`TableCellFieldEditor`), so Edit ›
    /// Copy, Cut and Paste reach the table's selected cells as ⌘C, ⌘X and ⌘V do.
    override class var cellClass: AnyClass? {
        get { TableCellMacTextFieldCell.self }
        set {}
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard currentEditor() != nil, let characters = event.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (characters, modifiers) {
        case ("z", [.command]): if handleKey?(.undo) == true { return true }
        case ("z", [.command, .shift]): if handleKey?(.redo) == true { return true }
        case ("c", [.command]): if actions.copyCells(false) { return true }
        case ("x", [.command]): if actions.copyCells(true) { return true }
        case ("v", [.command]): if actions.pasteCells() { return true }
        default: break
        }
        return super.performKeyEquivalent(with: event)
    }
}

private extension NSTextView {
    func turnOffSubstitutionsForMarkdown() {
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
    }
}
#endif
