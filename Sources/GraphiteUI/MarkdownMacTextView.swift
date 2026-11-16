/**
 * File: MarkdownMacTextView.swift
 * -------------------------------
 * Layer: UI
 * Description: The Mac's note text view: paste and drop, focus, the readable column and link cards.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import AppKit

/// The Mac's Markdown text view. Pasted and dropped files and images become attachments,
/// items dragged from the sidebar become links, and a click on a link whose markup is
/// concealed follows it, as on the iPad.
final class MarkdownMacTextView: NSTextView {
    /// The inherited convenience factory currently creates TextKit 1. Source
    /// highlights and native geometry require an explicitly owned TextKit 2 view.
    static func makeScrollableTextView() -> NSScrollView {
        let textView = MarkdownMacTextView(usingTextLayoutManager: true)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        // The find bar of "Search current file" shows above the note, inside the scroll view.
        textView.usesFindBar = true
        textView.textContainer?.containerSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    var readAloudRange: NSRange? { didSet { if readAloudRange != oldValue { needsDisplay = true } } }
    var suspendReadingFollow: (() -> Void)?

    func followReadingRange() {
        guard window != nil, let range = readAloudRange, range.location >= 0, range.length > 0,
              let textStorage, range.location <= textStorage.length, range.length <= textStorage.length - range.location else { return }
        scrollRangeToVisible(range)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let range = readAloudRange, range.location >= 0, range.length > 0,
              let textStorage, range.location <= textStorage.length, range.length <= textStorage.length - range.location,
              let textLayoutManager, let contentManager = textLayoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length), let textRange = NSTextRange(location: start, end: end) else { return }
        ReadAloudHighlightStyle.fill.setFill()
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            let positionedFrame = frame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            if positionedFrame.intersects(dirtyRect) { NSBezierPath(roundedRect: positionedFrame, xRadius: 3, yRadius: 3).fill() }
            return true
        }
    }
    /// Saves pasted or dropped files and images, and links vault items; set by the coordinator.
    var insertAttachment: ((_ data: Data, _ stem: String, _ fileExtension: String, _ range: NSRange) -> Void)?
    /// The vault of the note shown: a link to an item of another window's vault would name
    /// whatever has that path here.
    var currentVaultRoot: URL?
    var insertLinkToVaultFile: ((VaultPath, NSRange) -> Void)?
    /// Tells the person that a pasted or dropped file could not be read; set by the coordinator.
    var reportUnreadableItem: (() -> Void)?
    /// Follows the link a click lands on and says whether there was one; set by the coordinator.
    var followLinkOnClick: ((_ characterIndex: Int, _ modifierFlags: NSEvent.ModifierFlags) -> Bool)?
    /// Whether a click at a character would tick a box or follow a link; set by the coordinator.
    var isClickTarget: ((_ characterIndex: Int) -> Bool)?
    /// The events after a press; the window's own unless a test gives its own.
    var nextEventAfterPress: (() -> (type: NSEvent.EventType, location: CGPoint)?)?
    /// Checks or unchecks the drawn task box a click lands on and says whether there was
    /// one; set by the coordinator.
    var toggleTaskOnClick: ((_ characterIndex: Int) -> Bool)?
    /// Called when the view takes keyboard focus; set by the coordinator.
    var didBecomeFirstResponder: (() -> Void)?
    /// Called when the view gives up keyboard focus, as when the file list takes it; set by
    /// the coordinator.
    var didResignFirstResponder: (() -> Void)?
    /// Control-scrolling or pinching the trackpad changes the vault's font size; nil when
    /// quick adjustment is off. Set by the coordinator.
    var quickFontSize: QuickFontSizeAdjustment?
    private var quickFontSizeInput = QuickFontSizeMacInput()

    /// The vault's editing shortcuts; set by the editor.
    var keyCommandTable = EditorKeyCommandTable.defaults
    /// The editor's coordinator, which runs the editing command a shortcut names.
    weak var keyCommandOwner: NativeMarkdownEditor.Coordinator?
    /// The preview cards of the links the pointer rests on, which the coordinator owns.
    weak var linkPreviews: EditorLinkPreviews?
    private var linkTrackingArea: NSTrackingArea?

    /// The pointer is watched for links only while Page Preview is on.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let linkTrackingArea {
            removeTrackingArea(linkTrackingArea)
            self.linkTrackingArea = nil
        }
        guard linkPreviews?.isWatchingPointer == true else { return }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        linkTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        linkPreviews?.pointerMoved(to: event.locationInWindow, over: self)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        linkPreviews?.pointerLeft()
    }

    /// Escape closes a link's card before anything else.
    override func cancelOperation(_ sender: Any?) {
        if let linkPreviews, linkPreviews.isShowingCard {
            linkPreviews.closeCard()
            return
        }
        super.cancelOperation(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, runKeyCommand(for: event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if runKeyCommand(for: event) { return }
        super.keyDown(with: event)
    }

    /// Runs the editing command the vault gives the key press; false when it gives none, or
    /// while text is being composed.
    private func runKeyCommand(for event: NSEvent) -> Bool {
        guard !hasMarkedText(), let keyCommandOwner, let combination = KeyCombination(event: event),
              let editorCommand = keyCommandTable.command(matching: combination)?.editorCommand else { return false }
        return keyCommandOwner.runKeyCommand(editorCommand, in: self)
    }

    override func scrollWheel(with event: NSEvent) {
        // Control-scrolling changes the font size and does not scroll, so reading keeps following.
        if quickFontSizeInput.handleScroll(event, adjustment: quickFontSize) { return }
        suspendReadingFollow?()
        didScrollByWheel?()
        // A link's card stays where the link was; the note moves away from it.
        linkPreviews?.closeCard()
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        if quickFontSizeInput.handleMagnify(event, adjustment: quickFontSize) { return }
        super.magnify(with: event)
    }
    /// Called when the view enters a window or first gets a width, the two things a jump
    /// needs to measure the note; set by the coordinator.
    var didBecomeMeasurable: ((MarkdownMacTextView) -> Void)?
    /// Called when the text column moves or changes width, which the views placed over the
    /// text follow; set by the coordinator.
    var didMoveTextColumn: (() -> Void)?
    /// Called before the view leaves its window or takes a new width, while its lines are still
    /// where they were, and after the new width; set by the coordinator.
    var willLeaveWindow: (() -> Void)?
    var willChangeWidth: (() -> Void)?
    var didChangeWidth: (() -> Void)?
    /// Called when the person scrolls with the wheel or trackpad; set by the coordinator.
    var didScrollByWheel: (() -> Void)?
    /// Called once TextKit has laid out the viewport, as the view scrolls or its text
    /// changes, where the rendered blocks are placed; set by the coordinator.
    var didLayOutViewport: (() -> Void)?

    override func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(textViewportLayoutController)
        didLayOutViewport?()
    }

    private var canInsertAttachments: Bool { insertAttachment != nil || insertLinkToVaultFile != nil }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { didBecomeFirstResponder?() }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { didResignFirstResponder?() }
        return didResign
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { willLeaveWindow?() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didBecomeMeasurable?(self) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let previousWidth = frame.width
        if newSize.width != previousWidth { willChangeWidth?() }
        super.setFrameSize(newSize)
        updateReadableInset()
        // The view grows taller with its text; only a new width moves the column.
        if newSize.width != previousWidth {
            didMoveTextColumn?()
            didChangeWidth?()
        }
        if previousWidth <= 0, newSize.width > 0 { didBecomeMeasurable?(self) }
    }

    /// The room below the last line that the view's height includes now.
    private(set) var appliedRoomBelowText: CGFloat = 0

    /// TextKit sizes the view to its text through here; the room below the last line is added
    /// to that height (MarkdownMacTextViewRoomBelowText.swift). AppKit also passes the view's
    /// present height through, which has its room already.
    override func setConstrainedFrameSize(_ desiredSize: NSSize) {
        guard desiredSize.height != frame.height else { return super.setConstrainedFrameSize(desiredSize) }
        appliedRoomBelowText = roomBelowText
        super.setConstrainedFrameSize(NSSize(width: desiredSize.width, height: desiredSize.height + appliedRoomBelowText))
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        updateRoomBelowTextForVisibleHeight()
    }

    /// The readable column's width (Graphite's, or the vault theme's line width), or nil to
    /// use the whole width; as the iPad editor, the text is centered in it.
    var readableColumnWidth: CGFloat? { didSet { if readableColumnWidth != oldValue { updateReadableInset() } } }
    static let minimumHorizontalInset: CGFloat = 32
    /// The iPad editor's column, so a note wraps alike on both.
    static let graphiteReadableColumnWidth: CGFloat = 740

    private func updateReadableInset() {
        let horizontalInset = readableColumnWidth.map { width in max(Self.minimumHorizontalInset, (frame.width - width) / 2) } ?? Self.minimumHorizontalInset
        defer { layOutInlineTitle() }
        guard abs(textContainerInset.width - horizontalInset) > 0.5 else { return }
        textContainerInset = CGSize(width: horizontalInset, height: textContainerInset.height)
        didMoveTextColumn?()
    }

    override func mouseDown(with event: NSEvent) {
        // Control-click opens the context menu, with the plugins' items.
        if event.modifierFlags.contains(.control), pluginContextMenuItems != nil {
            rightMouseDown(with: event)
            return
        }
        let characterIndex = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard event.clickCount == 1, isClickTarget?(characterIndex) == true else {
            super.mouseDown(with: event)
            return
        }
        // A press on a link or a box acts on release; one that moves away starts a selection.
        guard outcomeOfPress(event) == .released else {
            super.mouseDown(with: event)
            return
        }
        if toggleTaskOnClick?(characterIndex) == true { return }
        _ = followLinkOnClick?(characterIndex, event.modifierFlags)
    }

    /// Shows the text the find bar moved to, which a fold or a rendered block can hide; set by
    /// the coordinator.
    var revealFoundText: ((NSRange) -> Void)?

    override func scrollRangeToVisible(_ range: NSRange) {
        if enclosingScrollView?.isFindBarVisible == true, window?.firstResponder !== self { revealFoundText?(range) }
        super.scrollRangeToVisible(range)
    }

    /// The note's name above the text, as on the iPad, drawn by a label the text is inset below.
    var inlineTitle: (text: String, font: NSFont, color: NSColor)? {
        didSet {
            guard inlineTitle?.text != oldValue?.text || inlineTitle?.font != oldValue?.font || inlineTitle?.color != oldValue?.color else { return }
            updateInlineTitleLabel()
        }
    }
    var inlineTitleLabel: NSTextField?
    /// The label's measured height, by the width it was measured at: the view's frame changes
    /// with every line typed, and only a new width or title measures it again.
    var measuredInlineTitle: (width: CGFloat, height: CGFloat)?

    // MARK: Plugins' menu items and paste

    /// Asks community plugins for their items in the context menu at the cursor; set by the
    /// coordinator while plugins add some.
    var pluginContextMenuItems: (() async -> [NSMenuItem])?
    /// The plugins' items for the menu being opened; empty otherwise.
    var pendingPluginMenuItems: [NSMenuItem] = []
    /// Offers a paste to community plugins that listen; true when one took it over.
    var offerPasteToPlugins: ((_ text: String?, _ html: String?) async -> Bool)?
    /// Whether a pasted web page or rich text becomes Markdown (Obsidian's "Auto convert HTML").
    var convertsPastedHTML = true
    /// What a paste reads; a test gives its own so the person's clipboard is not touched.
    var pastingPasteboard = NSPasteboard.general

    /// The Color, Format, Paragraph and Insert submenus, built when the menu opens; set by the
    /// pane's update, nil outside Source and Live Preview editing.
    var contextMenuEntries: (() -> [EditorContextMenuEntry])?

    override func rightMouseDown(with event: NSEvent) {
        // As in Obsidian, the menu is for where it was opened: a click outside the selection
        // moves the cursor there first, so a menu item acts on the word clicked.
        if pluginContextMenuItems != nil || contextMenuEntries != nil {
            let characterIndex = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if !NSLocationInRange(characterIndex, selectedRange()) || selectedRange().length == 0 {
                setSelectedRange(NSRange(location: characterIndex, length: 0))
            }
        }
        guard let pluginContextMenuItems else {
            super.rightMouseDown(with: event)
            return
        }
        Task { @MainActor [weak self] in
            let items = await pluginContextMenuItems()
            guard let self, self.window != nil else { return }
            self.pendingPluginMenuItems = items
            self.openContextMenu(for: event)
            self.pendingPluginMenuItems = []
        }
    }

    private func openContextMenu(for event: NSEvent) {
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        var menu = super.menu(for: event)
        if let contextMenuEntries {
            let editorMenu = menu ?? NSMenu()
            editorMenu.insertEditorContextMenuEntries(contextMenuEntries())
            menu = editorMenu
        }
        guard !pendingPluginMenuItems.isEmpty else { return menu }
        let pluginsMenu = menu ?? NSMenu()
        pluginsMenu.addItem(.separator())
        for item in pendingPluginMenuItems { pluginsMenu.addItem(item) }
        return pluginsMenu
    }

    override func paste(_ sender: Any?) {
        let pasteboard = pastingPasteboard
        if canInsertAttachments, insertAttachments(from: pasteboard, at: selectedRange()) { return }
        // Text plugins may take over (Link or Card makes a card of an address); the text is
        // pasted as usual when none does.
        // A web address pasted over selected text links the text to it, as in Obsidian.
        if selectedRange().length > 0, let pastedText = pasteboard.string(forType: .string),
           let edit = MarkdownEditing.linkingSelection(to: pastedText, in: string as NSString, selection: selectedRange()) {
            if shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                replaceCharacters(in: edit.range, with: edit.replacement)
                didChangeText()
                setSelectedRange(edit.selectionAfter)
            }
            return
        }
        if let offerPasteToPlugins, let text = pasteboard.string(forType: .string) {
            let html = pasteboard.string(forType: .html)
            let htmlData = convertsPastedHTML ? pasteboard.data(forType: .html) : nil
            let pastedRange = selectedRange()
            let textWhenPasted = string
            Task { @MainActor [weak self] in
                let isTakenOver = await offerPasteToPlugins(text, html)
                guard let self, !isTakenOver else { return }
                if let htmlData, htmlData.count <= HTMLToMarkdown.maximumConvertedLength {
                    self.insertConvertedHTML(htmlData, plainText: text, at: pastedRange)
                    return
                }
                // The range was the selection's before the plugins answered: a note changed
                // meanwhile takes the text at its selection now. A note made shorter raised
                // an exception, and a longer one received the text at the wrong place.
                let pastedRange = self.string == textWhenPasted ? pastedRange : self.selectedRange()
                if self.shouldChangeText(in: pastedRange, replacementString: text) {
                    self.replaceCharacters(in: pastedRange, with: text)
                    self.didChangeText()
                    self.setSelectedRange(NSRange(location: pastedRange.location + (text as NSString).length, length: 0))
                }
            }
            return
        }
        if pasteConvertedHTML(from: pasteboard) { return }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + MacPastedAttachment.pasteboardTypes + MacDroppedFiles.promisedFileTypes
    }

    /// Whether a drag carries something saved as an attachment or linked, rather than text.
    private func offersAttachments(_ draggingInfo: NSDraggingInfo) -> Bool {
        canInsertAttachments && (MacPastedAttachment.isOffered(on: draggingInfo.draggingPasteboard)
            || (insertAttachment != nil && MacDroppedFiles.hasPromisedFiles(on: draggingInfo.draggingPasteboard)))
    }

    override func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(draggingInfo)
        return offersAttachments(draggingInfo) ? .copy : operation
    }

    override func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(draggingInfo)
        return offersAttachments(draggingInfo) ? .copy : operation
    }

    override func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
        let dropLocation = characterIndexForInsertion(at: convert(draggingInfo.draggingLocation, from: nil))
        let dropRange = NSRange(location: dropLocation, length: 0)
        let pasteboard = draggingInfo.draggingPasteboard
        // Photos and Mail promise their files rather than give their addresses; a picture
        // they also put on the pasteboard would lose its name and format.
        if insertAttachment != nil, MacDroppedFiles.hasPromisedFiles(on: pasteboard), !MacDroppedFiles.hasFileAddresses(on: pasteboard),
           pasteboard.availableType(from: [MacPastedAttachment.vaultItemType]) == nil {
            Task { [weak self] in
                let files = await MacDroppedFiles.read(from: pasteboard)
                for file in files {
                    // Read away from the main thread: a promised film can be large.
                    let location = file.location
                    let reading = Task.detached(priority: .userInitiated) { try? Data(contentsOf: location) } // Unreadable: reported below.
                    guard let data = await reading.value else {
                        self?.reportUnreadableItem?()
                        continue
                    }
                    let fileExtension = location.pathExtension.isEmpty ? "bin" : location.pathExtension
                    self?.insertAttachment?(data, location.deletingPathExtension().lastPathComponent, fileExtension, dropRange)
                }
                DroppedFileBatch(files: files).discard()
            }
            return true
        }
        if canInsertAttachments, insertAttachments(from: pasteboard, at: dropRange) { return true }
        return super.performDragOperation(draggingInfo)
    }

    /// Inserts what the pasteboard carries besides text; false when it carries only text.
    private func insertAttachments(from pasteboard: NSPasteboard, at range: NSRange) -> Bool {
        let attachments = MacPastedAttachment.attachments(on: pasteboard, vaultRoot: currentVaultRoot)
        guard !attachments.isEmpty else { return false }
        for attachment in attachments {
            switch attachment {
            case .vaultItem(let path): insertLinkToVaultFile?(path, range)
            case .file(let data, let stem, let fileExtension): insertAttachment?(data, stem, fileExtension, range)
            case .unreadableFile: reportUnreadableItem?()
            }
        }
        return true
    }
}

/// Hosts a note's scroll view and text view for one SwiftUI view; see the iPad container.
extension MarkdownMacTextView: EditorLinkPreviewSurface {
    var linkPreviewSource: NSString { (textStorage?.string ?? "") as NSString }

    func characterIndex(atWindowPoint windowPoint: CGPoint) -> Int? {
        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point) else { return nil }
        return characterIndexForInsertion(at: point)
    }

    func windowFrames(ofCharacters range: NSRange) -> [CGRect] {
        guard let textLayoutManager, let contentManager = textLayoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: range.length), let textRange = NSTextRange(location: start, end: end) else { return [] }
        var frames: [CGRect] = []
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            frames.append(self.convert(frame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y), to: nil))
            return true
        }
        return frames
    }
}
#endif
