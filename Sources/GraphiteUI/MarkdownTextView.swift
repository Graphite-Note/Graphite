/**
 * File: MarkdownTextView.swift
 * ----------------------------
 * Layer: UI
 * Description: The iPad's and iPhone's note text view: paste and drop, focus, the readable column and Read Aloud's highlight.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.2
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import UIKit

/// A TextKit 2 text view that keeps a readable column centered on wide screens and
/// hosts Live Preview's rendered blocks.
final class MarkdownTextView: UITextView {
    /// Makes the toolbar above the keyboard. It is built the first time the keyboard asks for
    /// it: making its buttons took about 38 ms, at every note opened or switched to, also for
    /// notes only read.
    var makeKeyboardToolbar: (() -> UIView)? {
        didSet { builtKeyboardToolbar = nil }
    }
    private var builtKeyboardToolbar: UIView?

    override var inputAccessoryView: UIView? {
        get {
            if builtKeyboardToolbar == nil { builtKeyboardToolbar = makeKeyboardToolbar?() }
            return builtKeyboardToolbar ?? super.inputAccessoryView
        }
        set { super.inputAccessoryView = newValue }
    }

    var readAloudRange: NSRange? { didSet { if readAloudRange != oldValue { setNeedsLayout() } } }
    var followsReading = false {
        didSet {
            guard followsReading != oldValue else { return }
            // Following again (after Back to Reading) reveals the current word at once.
            lastHighlightLayout = nil
            setNeedsLayout()
        }
    }
    private(set) var readAloudHighlights: [UIView] = []
    /// Tells the floating player where the highlight is on screen, so it can move aside.
    var reportReadingHighlightFrame: ((CGRect?, CGRect?) -> Void)?
    static let readableColumnWidth: CGFloat = 740
    static let minimumHorizontalInset: CGFloat = 28
    var usesReadableLineLength = true { didSet { setNeedsLayout() } }
    /// The readable column's width: Graphite's, or the vault theme's line width.
    var readableColumnWidth: CGFloat = MarkdownTextView.readableColumnWidth { didSet { if readableColumnWidth != oldValue { setNeedsLayout() } } }
    /// The note's name above the text, drawn by a label the text is inset below.
    var inlineTitle: (text: String, font: UIFont, color: UIColor)? {
        didSet {
            guard inlineTitle?.text != oldValue?.text || inlineTitle?.font != oldValue?.font || inlineTitle?.color != oldValue?.color else { return }
            updateInlineTitleLabel()
        }
    }
    private var inlineTitleLabel: UILabel?
    private static let topInset: CGFloat = 32
    private static let inlineTitleSpacing: CGFloat = 20
    var didLayout: ((MarkdownTextView) -> Void)?
    /// Runs before the view takes a new width, while the old layout still says what is at its top.
    var willChangeWidth: (() -> Void)?
    override var frame: CGRect {
        willSet { if newValue.width != frame.width { willChangeWidth?() } }
    }
    override var bounds: CGRect {
        willSet { if newValue.width != bounds.width { willChangeWidth?() } }
    }
    var didMoveIntoWindow: ((MarkdownTextView) -> Void)?
    /// When a touch last reached the view. SwiftUI's focus system also hands focus to text
    /// views on its own (for example when a search field ends editing), which would raise
    /// the keyboard and scroll to the cursor; the note starts editing only when touched
    /// or when Graphite asks.
    private var lastTouchUptime: TimeInterval = -.infinity
    private var isEditingRequested = false
    /// True while the note's view goes away and the text view gives up the keyboard. Ending
    /// editing in an embedded PDF hands focus on to the text view around it, and a note
    /// touched a moment before took it: it began editing and made its own tab active again,
    /// right after an embed's "Open in PDF View" had shown the PDF's tab.
    var refusesFocus = false

    /// A text view on TextKit 2, the system's default for a text view made in code. Not
    /// `UITextView(usingTextLayoutManager:)`: that factory makes the view through an
    /// initializer Swift does not see, which left the properties above without their
    /// initial values, all zero, and crashed the first layout once one was an array.
    init() {
        super.init(frame: .zero, textContainer: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        // Only a touch on the text itself lets the note start editing. A touch on a rendered
        // block (the properties, a callout) belongs to the block; counting it let SwiftUI's
        // focus system hand the note the keyboard a moment later, its cursor in the YAML.
        if let hitView, event?.type == .touches, !isOverlay(hitView) { lastTouchUptime = ProcessInfo.processInfo.systemUptime }
        return hitView
    }

    /// Over a rendered block or a fold button, only scrolling and zooming are the text
    /// view's: its taps, loupe, selection and drag would take the touch from the block's
    /// own controls. A folded callout's title did not open, and a drag starting on the
    /// properties could end as a tap at the note's start.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let touchedView = super.hitTest(gestureRecognizer.location(in: self), with: nil) {
            // An image's corner handle resizes it; the note does not scroll under it.
            if touchedView is ImageResizeTouchView, gestureRecognizer === panGestureRecognizer { return false }
            if gestureRecognizer !== panGestureRecognizer, !(gestureRecognizer is UIPinchGestureRecognizer), isOverlay(touchedView) { return false }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// Whether `view` is in a rendered block's view or is a fold button, placed over the text,
    /// rather than one of the views UIKit draws the text with.
    private func isOverlay(_ view: UIView) -> Bool {
        var placedView = view
        while let superview = placedView.superview, superview !== self { placedView = superview }
        guard placedView.superview === self else { return false }
        if placedView is UIControl { return true }
        // A hosting controller's view: SwiftUI puts responders of its own between the view
        // and its controller, and the chain reaches a view again after the controller.
        var responder = placedView.next
        while let currentResponder = responder, !(currentResponder is UIView) {
            if currentResponder is UIViewController { return true }
            responder = currentResponder.next
        }
        return false
    }

    override var canBecomeFirstResponder: Bool {
        let wasRecentlyTouched = ProcessInfo.processInfo.systemUptime - lastTouchUptime < 1
        return super.canBecomeFirstResponder && (isFirstResponder || (!refusesFocus && (isEditingRequested || wasRecentlyTouched)))
    }

    /// Starts editing on Graphite's behalf, for example to show a rendered block's source.
    func beginEditing() {
        isEditingRequested = true
        becomeFirstResponder()
        isEditingRequested = false
    }

    private struct InlineTitleMeasure: Equatable {
        let text: NSAttributedString
        let width: CGFloat
    }
    private var measuredInlineTitle: (key: InlineTitleMeasure, height: CGFloat)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInset = usesReadableLineLength
            ? max(Self.minimumHorizontalInset, (bounds.width - readableColumnWidth) / 2)
            : Self.minimumHorizontalInset
        var topInset = Self.topInset
        if let inlineTitleLabel {
            let titleWidth = max(bounds.width - 2 * horizontalInset - 2 * textContainer.lineFragmentPadding, 1)
            // Measured again only when the title, its font or the width changes, not on every
            // frame of a scroll.
            let titleKey = InlineTitleMeasure(text: inlineTitleLabel.attributedText ?? NSAttributedString(string: inlineTitleLabel.text ?? ""), width: titleWidth)
            let titleHeight: CGFloat
            if let measuredInlineTitle, measuredInlineTitle.key == titleKey {
                titleHeight = measuredInlineTitle.height
            } else {
                titleHeight = ceil(inlineTitleLabel.sizeThatFits(CGSize(width: titleWidth, height: .greatestFiniteMagnitude)).height)
                measuredInlineTitle = (titleKey, titleHeight)
            }
            inlineTitleLabel.frame = CGRect(x: horizontalInset + textContainer.lineFragmentPadding, y: Self.topInset, width: titleWidth, height: titleHeight)
            topInset += titleHeight + Self.inlineTitleSpacing
        }
        // Room below the last line, so the end of a note scrolls up to the middle (EditorRoomBelowText).
        let bottomInset = EditorRoomBelowText.height(forVisibleHeight: bounds.height)
        let insets = UIEdgeInsets(top: topInset, left: horizontalInset, bottom: bottomInset, right: horizontalInset)
        // Setting equal insets would still invalidate the layout.
        if textContainerInset != insets { textContainerInset = insets }
        didLayout?(self)
        // UIKit lays a scroll view out on every frame of a scroll. The highlight is measured
        // again only when the word, the width or the text's height changed, so scrolling by
        // hand never pays for it, and never scrolls back to it.
        let highlightLayout = ReadAloudHighlightLayout(range: readAloudRange, width: bounds.width, contentHeight: contentSize.height)
        if highlightLayout != lastHighlightLayout {
            let wordChanged = highlightLayout.range != lastHighlightLayout?.range
            lastHighlightLayout = highlightLayout
            updateReadAloudHighlights(revealsWord: wordChanged)
        } else if let window, let first = readAloudHighlights.first {
            // Scrolling moves the highlight on screen; the player is told where it now is.
            let union = readAloudHighlights.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            reportReadingHighlightFrame?(convert(union, to: nil), window.bounds)
        }
    }

    private struct ReadAloudHighlightLayout: Equatable {
        let range: NSRange?
        let width: CGFloat
        let contentHeight: CGFloat
    }
    private var lastHighlightLayout: ReadAloudHighlightLayout?

    private func updateReadAloudHighlights(revealsWord: Bool) {
        guard let range = readAloudRange, range.location >= 0, range.length > 0,
              range.location <= textStorage.length, range.length <= textStorage.length - range.location,
              let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length), let textRange = textRange(from: start, to: end) else {
            readAloudHighlights.forEach { highlight in highlight.removeFromSuperview() }
            readAloudHighlights.removeAll(keepingCapacity: true)
            reportReadingHighlightFrame?(nil, nil)
            return
        }
        let frames = selectionRects(for: textRange).map(\.rect).filter { frame in frame.width > 0 && frame.height > 0 }
        defer {
            if let window, let first = frames.first {
                reportReadingHighlightFrame?(convert(frames.dropFirst().reduce(first) { $0.union($1) }, to: nil), window.bounds)
            }
        }
        let isScrolledByHand = isTracking || isDragging || isDecelerating
        let comfortableArea = bounds.inset(by: UIEdgeInsets(top: adjustedContentInset.top + 40, left: 0, bottom: adjustedContentInset.bottom + 120, right: 0))
        if revealsWord, followsReading, !isScrolledByHand, window != nil, let frame = frames.first, !comfortableArea.contains(frame) {
            // The word comes back a third of the way down, not at the very edge, so the
            // lines that follow are already in view.
            let visibleHeight = bounds.height - adjustedContentInset.top - adjustedContentInset.bottom
            let maximumOffset = max(-adjustedContentInset.top, contentSize.height + adjustedContentInset.bottom - bounds.height)
            let destination = frame.minY - adjustedContentInset.top - visibleHeight / 3
            setContentOffset(CGPoint(x: contentOffset.x, y: min(max(-adjustedContentInset.top, destination), maximumOffset)), animated: false)
        }
        guard readAloudHighlights.map(\.frame) != frames else { return }
        readAloudHighlights.forEach { highlight in highlight.removeFromSuperview() }
        readAloudHighlights.removeAll(keepingCapacity: true)
        for frame in frames {
            let highlight = UIView(frame: frame)
            highlight.backgroundColor = ReadAloudHighlightStyle.fill
            highlight.layer.cornerRadius = 3
            highlight.isUserInteractionEnabled = false
            highlight.isAccessibilityElement = false
            addSubview(highlight)
            readAloudHighlights.append(highlight)
        }
    }

    // MARK: Find

    /// Shows the text the find navigator moved to, which a fold or a rendered block can hide;
    /// set by the coordinator. A match in hidden text is counted and stepped to, but its
    /// highlight has no size.
    var revealFoundText: ((NSRange) -> Void)?
    /// The find navigator closed or started a new search.
    var didClearFoundText: (() -> Void)?

    /// `UITextSearching`'s `decorate(foundTextRange:document:usingStyle:)`, which Swift sees as
    /// closed to overriding, under its Objective-C selector, calling `UITextView`'s own.
    @objc(decorateFoundTextRange:inDocument:usingStyle:)
    func decorateFoundText(_ range: UITextRange, document: AnyObject?, style: UITextSearchFoundTextStyle) {
        let selector = #selector(decorateFoundText(_:document:style:))
        typealias Implementation = @convention(c) (AnyObject, Selector, UITextRange, AnyObject?, UITextSearchFoundTextStyle) -> Void
        guard let method = class_getInstanceMethod(UITextView.self, selector) else { return }
        unsafeBitCast(method_getImplementation(method), to: Implementation.self)(self, selector, range, document, style)
        guard style == .highlighted else { return }
        let location = offset(from: beginningOfDocument, to: range.start)
        revealFoundText?(NSRange(location: location, length: offset(from: range.start, to: range.end)))
    }

    override func clearAllDecoratedFoundText() {
        super.clearAllDecoratedFoundText()
        didClearFoundText?()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        // The find session's highlights ask this view for previews as they lay out; once it
        // is off screen (another tab, reading view, a closed tab), UIKit raises instead.
        // Dismissing the find bar leaves the session alive; only turning the interaction
        // off ends it.
        if newWindow == nil {
            if findInteraction?.isFindNavigatorVisible == true { findInteraction?.dismissFindNavigator() }
            isFindInteractionEnabled = false
        }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        isFindInteractionEnabled = true
        didMoveIntoWindow?(self)
        // A jump asked for while the view was off-window runs from the next layout pass.
        setNeedsLayout()
    }

    private func updateInlineTitleLabel() {
        guard let inlineTitle else {
            inlineTitleLabel?.removeFromSuperview()
            inlineTitleLabel = nil
            setNeedsLayout()
            return
        }
        let label = inlineTitleLabel ?? UILabel()
        label.text = inlineTitle.text
        label.font = inlineTitle.font
        label.textColor = inlineTitle.color
        label.numberOfLines = 0
        label.accessibilityTraits = .header
        if label.superview == nil { addSubview(label) }
        inlineTitleLabel = label
        setNeedsLayout()
    }

    /// The width available to a rendered block inside the text column.
    var contentColumnWidth: CGFloat {
        bounds.width - textContainerInset.left - textContainerInset.right - 2 * textContainer.lineFragmentPadding
    }

    // MARK: Keyboard

    /// Runs an editing command; set by the editor's coordinator.
    var runCommand: ((EditorCommand) -> Void)?
    /// The suggestions at the cursor, which take the arrow keys, Return, and Escape while open.
    weak var completion: CompletionModel?
    /// Closes the suggestions on Escape; set by the coordinator, which tracks what they were found for.
    var dismissCompletion: (() -> Void)?

    /// Whether the cursor is on a link, so Return with ⌥ or ⌘ follows it; set by the coordinator.
    var isCursorOnLink: (() -> Bool)?

    /// The vault's editing shortcuts (`VaultKeyboardShortcuts`); set by the editor.
    var keyCommandTable = EditorKeyCommandTable.defaults

    /// The system's own ⌘B and ⌘I: they arrive through `toggleBoldface` and `toggleItalics`,
    /// which also serve the edit menu's format items, so they get no key command of their own.
    private static let systemFormatShortcuts: [GraphiteCommand: KeyCombination] = [
        .toggleBold: KeyCombination(.command, .character("B")), .toggleItalics: KeyCombination(.command, .character("I")),
    ]

    /// The vault's editing shortcuts as key commands. The commands on a link exist only while
    /// the cursor is on one, so Return keeps its usual meaning elsewhere.
    private var editorKeyCommands: [UIKeyCommand] {
        let isOnLink = isCursorOnLink?() == true
        return keyCommandTable.entries.compactMap { entry in
            guard !entry.command.followsLink || isOnLink, Self.systemFormatShortcuts[entry.command] != entry.combination,
                  let input = entry.combination.keyCommandInput else { return nil }
            let keyCommand = UIKeyCommand(title: entry.command.title, action: #selector(runKeyCommand(_:)), input: input,
                                          modifierFlags: entry.combination.keyModifierFlags, propertyList: entry.command.identifier)
            keyCommand.wantsPriorityOverSystemBehavior = true
            return keyCommand
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        var keyCommands = (super.keyCommands ?? []) + editorKeyCommands
        if completion?.isVisible != true, markedTextRange == nil {
            // Shift-Return breaks the line without a new list item, as Obsidian's Shift-Enter does.
            let lineBreak = UIKeyCommand(title: "", action: #selector(breakLineWithinItem), input: "\r", modifierFlags: .shift)
            lineBreak.wantsPriorityOverSystemBehavior = true
            keyCommands.append(lineBreak)
        }
        if completion?.isVisible == true {
            for (input, name) in [(UIKeyCommand.inputUpArrow, "up"), (UIKeyCommand.inputDownArrow, "down"), (UIKeyCommand.inputEscape, "escape")] {
                let keyCommand = UIKeyCommand(title: "", action: #selector(runCompletionKey(_:)), input: input, modifierFlags: [], propertyList: name)
                keyCommand.wantsPriorityOverSystemBehavior = true
                keyCommands.append(keyCommand)
            }
        }
        return keyCommands
    }

    @objc private func runCompletionKey(_ keyCommand: UIKeyCommand) {
        switch keyCommand.propertyList as? String {
        case "up": completion?.moveSelection(by: -1)
        case "down": completion?.moveSelection(by: 1)
        default:
            if let dismissCompletion { dismissCompletion() } else { completion?.dismiss() }
        }
    }

    @objc private func breakLineWithinItem() {
        runCommand?(.lineBreakInItem)
    }

    @objc private func runKeyCommand(_ keyCommand: UIKeyCommand) {
        guard let identifier = keyCommand.propertyList as? String, let editorCommand = GraphiteCommand(rawValue: identifier)?.editorCommand else { return }
        runCommand?(editorCommand)
    }

    // MARK: Paste and drop

    /// Saves pasted or dropped files and images, and links dropped vault files; set by the
    /// coordinator. Each request carries the text revision it was made at, because the
    /// content loads and saves asynchronously while the note may change.
    var insertAttachment: ((_ data: Data, _ stem: String, _ fileExtension: String, _ request: InsertionRequest) -> Void)?
    var insertLinkToVaultFile: ((VaultPath, InsertionRequest) -> Void)?
    /// The vault of the note shown: a link to an item of another window's vault would name
    /// whatever has that path here.
    var currentVaultRoot: URL?
    /// The note's current text revision; set by the coordinator.
    var textRevision: (() -> Int)?
    /// Tells the person that a pasted or dropped item could not be read; set by the coordinator.
    var reportUnreadableItem: (() -> Void)?
    var convertsPastedHTML = true
    /// Community plugins that listen for pastes and drops (`editor-paste`, `editor-drop`); nil
    /// while none does. Each answers whether a plugin took the paste or drop over.
    var offerPasteToPlugins: ((_ text: String?, _ html: String?) async -> Bool)?
    var offerDropToPlugins: ((_ files: [(name: String, type: String)], _ text: String?) async -> Bool)?

    /// Image types saved as they are; others are converted to PNG. HEIC is converted to
    /// JPEG because Obsidian does not show HEIC images.
    private static let keptImageTypes: [(UTType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.gif, "gif"), (.webP, "webp")]

    private func insertionRequest(at range: NSRange) -> InsertionRequest {
        InsertionRequest(range: range, revision: textRevision?() ?? 0)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleUnderline(_:)) { return false }
        // ⌘B and ⌘I stay the system's while the vault gives them to bold and italics.
        for (command, selector) in [(GraphiteCommand.toggleBold, #selector(toggleBoldface(_:))), (.toggleItalics, #selector(toggleItalics(_:)))]
        where action == selector {
            guard let combination = Self.systemFormatShortcuts[command], keyCommandTable.isBound(command, to: combination) else { return false }
        }
        if action == #selector(paste(_:)) && UIPasteboard.general.hasImages && insertAttachment != nil { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        // An image copied on its own (a screenshot, an image from Safari or Photos). Safari
        // copies an image with its address, so a URL alongside does not make it text. The
        // item providers load it asynchronously: another app may only have promised the data.
        if pasteboard.hasImages, !pasteboard.hasStrings || pasteboard.hasURLs, let insertAttachment {
            // Read during the paste action itself: iOS allows reading the pasteboard only then.
            switch Self.pastedImage(from: pasteboard) {
            case .encoded(let data, let fileExtension):
                insertAttachment(data, WorkspaceModel.pastedImageStem(), fileExtension, insertionRequest(at: selectedRange))
            case .unencoded(let image):
                insertEncodedAttachment(of: image, stem: WorkspaceModel.pastedImageStem(), request: insertionRequest(at: selectedRange))
            case nil:
                paste(itemProviders: pasteboard.itemProviders)
            }
            return
        }
        // A web address pasted over selected text links the text to it, as in Obsidian.
        if selectedRange.length > 0, let pastedText = pasteboard.string,
           let edit = MarkdownEditing.linkingSelection(to: pastedText, in: (text ?? "") as NSString, selection: selectedRange),
           let start = position(from: beginningOfDocument, offset: edit.range.location), let end = position(from: start, offset: edit.range.length),
           let replacedRange = textRange(from: start, to: end) {
            replace(replacedRange, withText: edit.replacement)
            return
        }
        // Text plugins may take over (Link or Card makes a card of an address). The pasteboard is
        // read now, while iOS allows it; Graphite pastes what it read if no plugin takes it.
        if let offerPasteToPlugins, pasteboard.hasStrings {
            let text = pasteboard.string
            let htmlData = convertsPastedHTML ? pasteboard.data(forPasteboardType: UTType.html.identifier) : nil
            let html = htmlData.flatMap { data in String(data: data, encoding: .utf8) }
            let pastedRange = selectedRange
            let textWhenPasted = self.text ?? ""
            Task { [weak self] in
                let isTakenOver = await offerPasteToPlugins(text, html)
                guard let self, !isTakenOver else { return }
                if let htmlData, htmlData.count <= HTMLToMarkdown.maximumConvertedLength {
                    self.insertConvertedHTML(htmlData, plainText: text, at: pastedRange)
                } else if let text, !text.isEmpty {
                    // Where the paste was asked for, unless the note changed meanwhile; then
                    // at the cursor. It went in at the cursor, wherever it had moved.
                    if self.text == textWhenPasted, NSMaxRange(pastedRange) <= (textWhenPasted as NSString).length { self.selectedRange = pastedRange }
                    self.insertText(text)
                }
            }
            return
        }
        // A web page or rich text becomes Markdown, as with Obsidian's "Auto convert HTML".
        if convertsPastedHTML, let htmlData = pasteboard.data(forPasteboardType: UTType.html.identifier),
           htmlData.count <= HTMLToMarkdown.maximumConvertedLength {
            insertConvertedHTML(htmlData, plainText: pasteboard.string, at: selectedRange)
            return
        }
        super.paste(sender)
    }

    /// Converts pasted HTML off the main thread, since a large page takes long to convert.
    /// The pasteboard is read before, as iOS allows reading it only during the paste. The
    /// Markdown goes where the paste was asked for while the note is unchanged; after an
    /// edit that place may no longer exist, so the plain text goes at the cursor instead.
    private func insertConvertedHTML(_ htmlData: Data, plainText: String?, at pastedRange: NSRange) {
        let revisionAtPaste = textRevision?() ?? 0
        Task { [weak self] in
            let markdown = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .utf16) else { return nil }
                let markdown = HTMLToMarkdown.markdown(from: html)
                return markdown.isEmpty ? nil : markdown
            }.value
            guard let self else { return }
            let isTextUnchanged = (self.textRevision?() ?? 0) == revisionAtPaste
            guard let pastedText = isTextUnchanged ? (markdown ?? plainText) : plainText, !pastedText.isEmpty else { return }
            if isTextUnchanged, NSMaxRange(pastedRange) <= self.textStorage.length { self.selectedRange = pastedRange }
            self.insertText(pastedText)
        }
    }

    /// Encodes an image as PNG off the main thread, then saves it as an attachment.
    private func insertEncodedAttachment(of image: UIImage, stem: String, request: InsertionRequest) {
        Task { [weak self] in
            let pngData = await Task.detached(priority: .userInitiated) { image.pngData() }.value
            guard let self else { return }
            guard let pngData else {
                self.reportUnreadableItem?()
                return
            }
            self.insertAttachment?(pngData, stem, "png", request)
        }
    }

    /// A pasted image as bytes in a format kept as it is, or as an image still to be encoded.
    private enum PastedImage {
        case encoded(Data, fileExtension: String)
        case unencoded(UIImage)
    }

    private static func pastedImage(from pasteboard: UIPasteboard) -> PastedImage? {
        for (type, fileExtension) in keptImageTypes {
            if let data = pasteboard.data(forPasteboardType: type.identifier) { return .encoded(data, fileExtension: fileExtension) }
        }
        return pasteboard.image.map(PastedImage.unencoded)
    }

    /// Drops of files, images, and sidebar items arrive here (see `pasteConfiguration`).
    /// Every item asks for the place the drop landed; the coordinator moves each one past
    /// the note's changes, including the items inserted before it.
    override func paste(itemProviders: [NSItemProvider]) {
        // Plugins that listen for drops hear of the files first, by name and type.
        if let offerDropToPlugins {
            let files = itemProviders.map { provider in
                (name: provider.suggestedName ?? "", type: provider.registeredTypeIdentifiers.first.flatMap { identifier in UTType(identifier)?.preferredMIMEType } ?? "")
            }
            let request = insertionRequest(at: selectedRange)
            Task { [weak self] in
                guard !(await offerDropToPlugins(files, nil)), let self else { return }
                self.insertDroppedItems(itemProviders, dropRequest: request)
            }
            return
        }
        insertDroppedItems(itemProviders, dropRequest: insertionRequest(at: selectedRange))
    }

    private func insertDroppedItems(_ itemProviders: [NSItemProvider], dropRequest: InsertionRequest) {
        // What no file can be made of, such as a selection of text or a web link dragged from
        // Safari, is text: the text view inserts it itself. A text file from Files has a name
        // and becomes an attachment.
        let textProviders = itemProviders.filter(Self.isTextOnly)
        if !textProviders.isEmpty { super.paste(itemProviders: textProviders) }
        for provider in itemProviders where !Self.isTextOnly(provider) {
            if provider.hasItemConformingToTypeIdentifier(UTType.graphiteVaultItem.identifier) {
                // Read here, on the main actor: the item arrives on another thread.
                let vaultRoot = currentVaultRoot
                _ = provider.loadTransferable(type: VaultItemTransfer.self) { [weak self] result in
                    guard case .success(let item) = result, let path = item.path(inVaultAt: vaultRoot) else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    Task { @MainActor in self?.insertLinkToVaultFile?(path, dropRequest) }
                }
                continue
            }
            guard insertAttachment != nil else { continue }
            let suggestedStem = provider.suggestedName.map { name in (name as NSString).deletingPathExtension }
            if let (type, fileExtension) = Self.keptImageTypes.first(where: { type, _ in provider.hasItemConformingToTypeIdentifier(type.identifier) }) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, _ in
                    guard let data else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    Task { @MainActor in self?.insertAttachment?(data, suggestedStem ?? WorkspaceModel.pastedImageStem(), fileExtension, dropRequest) }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let image = object as? UIImage, let data = image.jpegData(compressionQuality: 0.9) else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    Task { @MainActor in self?.insertAttachment?(data, suggestedStem ?? WorkspaceModel.pastedImageStem(), "jpg", dropRequest) }
                }
            } else if let typeIdentifier = LibraryDropReader.importableType(of: provider)?.identifier {
                // Any other file, such as a PDF, a recording or a Word document, keeps its own format.
                // The name is read here: the provider is not sendable, and the file arrives on another thread.
                let suggestedName = provider.suggestedName
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] location, _ in
                    guard let location, let data = try? Data(contentsOf: location, options: .mappedIfSafe) else {
                        Task { @MainActor in self?.reportUnreadableItem?() }
                        return
                    }
                    let suggestedExtension = suggestedName.map { name in (name as NSString).pathExtension } ?? ""
                    let fileExtension = !location.pathExtension.isEmpty ? location.pathExtension
                        : !suggestedExtension.isEmpty ? suggestedExtension : (UTType(typeIdentifier)?.preferredFilenameExtension ?? "bin")
                    let stem = suggestedStem ?? location.deletingPathExtension().lastPathComponent
                    Task { @MainActor in self?.insertAttachment?(data, stem, fileExtension, dropRequest) }
                }
            }
        }
    }

    /// Whether a dropped item is only text or a link: no vault item, no image, nothing a file
    /// can be made of.
    private static func isTextOnly(_ provider: NSItemProvider) -> Bool {
        !provider.hasItemConformingToTypeIdentifier(UTType.graphiteVaultItem.identifier) && !provider.canLoadObject(ofClass: UIImage.self)
            && LibraryDropReader.importableType(of: provider) == nil
    }

    override func toggleBoldface(_ sender: Any?) { runCommand?(.bold) }
    override func toggleItalics(_ sender: Any?) { runCommand?(.italic) }
}

/// Hosts a note's text view for one SwiftUI view. The text view can outlive it: a hidden
/// note's text view is kept by `MarkdownEditorRetention` and shown again in a new container.
extension MarkdownTextView: EditorLinkPreviewSurface {
    var linkPreviewSource: NSString { textStorage.string as NSString }

    func characterIndex(atWindowPoint windowPoint: CGPoint) -> Int? {
        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point), let position = closestPosition(to: point) else { return nil }
        return offset(from: beginningOfDocument, to: position)
    }

    func windowFrames(ofCharacters range: NSRange) -> [CGRect] {
        guard let start = position(from: beginningOfDocument, offset: range.location), let end = position(from: start, offset: range.length),
              let characters = textRange(from: start, to: end) else { return [] }
        return selectionRects(for: characters).map(\.rect).filter { rect in rect.width > 0 && rect.height > 0 }.map { rect in convert(rect, to: nil) }
    }
}
#endif
