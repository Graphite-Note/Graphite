/**
 * File: NativeMarkdownEditorMac.swift
 * -----------------------------------
 * Layer: UI
 * Description: The Mac's note editor: the NSViewRepresentable and its coordinator.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.4
 * Date: 26/11/2026
 */

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import AppKit

struct NativeMarkdownEditor: NSViewRepresentable {
    @Bindable var session: MarkdownSession
    let configuration: EditorConfiguration
    let headingScrollRequest: HeadingScrollRequest?
    let actions: EditorActions
    let follow: (String, Bool) -> Void
    /// Keeps this editor, with its undo history, after it leaves the screen; see
    /// `MarkdownEditorRetention`.
    var retention: MarkdownEditorRetention?
    var retentionOwner: TabDocument?
    var readAloudRange: NSRange?
    var followsReading = false
    var suspendReadingFollow: (() -> Void)?
    /// What Live Preview's rendered blocks read.
    let environment: LivePreviewEnvironment?
    /// The Color, Format, Paragraph and Insert submenus of the context menu; see `EditorContextMenuContent`.
    var contextMenu: EditorContextMenuActions?
    /// The vault's editing shortcuts.
    var keyCommandTable: EditorKeyCommandTable
    @Environment(\.linkPreviews) private var linkPreviews

    /// The Mac has no keyboard toolbar: of `actions`, it uses pasting, dropping, following
    /// links elsewhere, and focusing the note's side.
    init(session: MarkdownSession, configuration: EditorConfiguration, environment: LivePreviewEnvironment? = nil,
         headingScrollRequest: HeadingScrollRequest?, actions: EditorActions = EditorActions(),
         retention: MarkdownEditorRetention? = nil, retentionOwner: TabDocument? = nil, readAloudRange: NSRange? = nil,
         followsReading: Bool = false, suspendReadingFollow: (() -> Void)? = nil,
         readAloudHooks: ReadAloudEditorHooks? = nil, contextMenu: EditorContextMenuActions? = nil,
         keyCommandTable: EditorKeyCommandTable = .defaults, follow: @escaping (String, Bool) -> Void) {
        self.contextMenu = contextMenu
        self.keyCommandTable = keyCommandTable
        self.session = session
        self.configuration = configuration
        self.headingScrollRequest = headingScrollRequest
        self.actions = actions
        self.retention = retention
        self.retentionOwner = retentionOwner
        self.readAloudRange = readAloudRange
        self.followsReading = followsReading
        self.suspendReadingFollow = suspendReadingFollow
        self.environment = environment
        self.follow = follow
    }

    func makeCoordinator() -> Coordinator {
        if let retention, let retentionOwner, let keptEditor = retention.takeEditor(for: session, owner: retentionOwner) as? Coordinator {
            return keptEditor
        }
        return Coordinator(session: session, configuration: configuration)
    }

    func makeNSView(context: Context) -> MarkdownEditorContainerView {
        let container = MarkdownEditorContainerView()
        let coordinator = context.coordinator
        coordinator.retention = retention
        coordinator.retentionOwner = retentionOwner
        if coordinator.scrollView == nil {
            let scrollView = makeScrollView(coordinator: coordinator)
            coordinator.scrollView = scrollView
            container.host(scrollView)
        }
        coordinator.viewWasMade(with: container)
        retention?.editorDidAttach(coordinator)
        return container
    }

    private func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        guard let textView = scrollView.documentView as? MarkdownMacTextView else { return scrollView }
        coordinator.actions = actions
        coordinator.follow = follow
        coordinator.environment = environment
        textView.isRichText = false
        textView.quickFontSize = actions.quickFontSize
        textView.readableColumnWidth = configuration.usesReadableLineLength
            ? (configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownMacTextView.graphiteReadableColumnWidth) : nil
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = configuration.usesSpellChecking
        textView.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 32, height: 32)
        textView.inlineTitle = inlineTitle
        textView.setAccessibilityLabel("Markdown note")
        // The text and the saved cursor go in before the delegate, which would otherwise
        // record the cursor that setting the text leaves at its end.
        textView.string = session.text
        coordinator.lastSynchronizedText = session.text
        let textLength = (session.text as NSString).length
        let cursorLocation = min(session.selection.location, textLength)
        textView.setSelectedRange(NSRange(location: cursorLocation, length: min(session.selection.length, textLength - cursorLocation)))
        textView.delegate = coordinator
        textView.sectionLinkForDrag = { [weak coordinator] location in
            guard let session = coordinator?.session else { return nil }
            let text = session.text
            let (transfer, identifierEdit) = MarkdownEditorSectionDrag.transfer(startingAt: location, in: session)
            return (transfer, { MarkdownEditorSectionDrag.addIdentifier(identifierEdit, to: session, expectingText: text) })
        }
        coordinator.connect(textView)
        textView.updateDragTypeRegistration()
        if let savedScrollLocation = session.savedScrollLocation { coordinator.pendingJump = .topOfCharacter(savedScrollLocation) }
        session.isEditorAttached = true
        coordinator.reportPlace(of: textView)
        session.undoAvailability.follow(coordinator.noteUndoManager)
        coordinator.restyleEverything(in: textView)
        coordinator.keepSelectionOutOfConcealedProperties(in: textView)
        return scrollView
    }

    /// The theme's inline title, else the text font at 1.75 times, semibold, as on the iPad.
    private var inlineTitle: (text: String, font: NSFont, color: NSColor)? {
        configuration.inlineTitle.map { title in
            (title, InlineTitleStyle.font(textSize: configuration.textSize, typography: configuration.typography, theme: configuration.theme),
             configuration.theme?.inlineTitleColor ?? .labelColor)
        }
    }

    func updateNSView(_ container: MarkdownEditorContainerView, context: Context) {
        let coordinator = context.coordinator
        guard let scrollView = container.scrollViewShownHere else {
            // An earlier view of this note still shows the editor; this view's state
            // reaches it when the editor moves here.
            container.updateWhenScrollViewArrives = { [self] arrivedScrollView in update(arrivedScrollView, coordinator: coordinator) }
            return
        }
        update(scrollView, coordinator: coordinator)
    }

    private func update(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.session = session
        coordinator.actions = actions
        coordinator.follow = follow
        guard let textView = scrollView.documentView as? NSTextView else { return }
        (textView as? MarkdownMacTextView)?.readAloudRange = readAloudRange
        (textView as? MarkdownMacTextView)?.keyCommandTable = keyCommandTable
        (textView as? MarkdownMacTextView)?.keyCommandOwner = coordinator
        if coordinator.linkPreviews.use(linkPreviews, sourceNote: session.path) { textView.updateTrackingAreas() }
        (textView as? MarkdownMacTextView)?.quickFontSize = actions.quickFontSize
        (textView as? MarkdownMacTextView)?.readableColumnWidth = configuration.usesReadableLineLength
            ? (configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownMacTextView.graphiteReadableColumnWidth) : nil
        (textView as? MarkdownMacTextView)?.suspendReadingFollow = suspendReadingFollow
        // Plugins that start, or start listening, after the editor was made reach it here.
        (textView as? MarkdownMacTextView)?.pluginContextMenuItems = coordinator.actions.pluginContextMenuItems == nil ? nil : { [weak coordinator] in
            await coordinator?.actions.pluginContextMenuItems?() ?? []
        }
        (textView as? MarkdownMacTextView)?.offerPasteToPlugins = coordinator.actions.pluginPaste
        (textView as? MarkdownMacTextView)?.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        (textView as? MarkdownMacTextView)?.inlineTitle = inlineTitle
        if textView.isContinuousSpellCheckingEnabled != configuration.usesSpellChecking {
            textView.isContinuousSpellCheckingEnabled = configuration.usesSpellChecking
        }
        let editorActions = actions
        (textView as? MarkdownMacTextView)?.contextMenuEntries = contextMenu.map { menuActions in
            { EditorContextMenuContent.entries(actions: menuActions, editorActions: editorActions) }
        }
        let previousBlockPolicy = coordinator.renderedBlockPolicy
        let hasNewConfiguration = coordinator.configuration != configuration
        let hasNewBlockPolicy = coordinator.renderedBlockPolicy != previousBlockPolicy
        let topLineBeforeRestyle = hasNewConfiguration || hasNewBlockPolicy ? coordinator.topCharacter(of: textView) : nil
        coordinator.configuration = configuration
        coordinator.environment = environment
        // Turning the Properties view on or off, or a plugin starting to draw code blocks,
        // changes which blocks are rendered, as the configuration can.
        if hasNewConfiguration || coordinator.renderedBlockPolicy != previousBlockPolicy {
            coordinator.restyleEverything(in: textView, forcesBlockScan: coordinator.renderedBlockPolicy != previousBlockPolicy)
            coordinator.keepSelectionOutOfConcealedProperties(in: textView)
            // Source of another height takes the place of the blocks, or the text resizes;
            // the view stays on the line it showed, not at the same distance from the top.
            if let topLineBeforeRestyle, coordinator.pendingJump == nil { coordinator.pendingJump = .topOfCharacter(topLineBeforeRestyle) }
        }
        coordinator.refreshBlockViews(in: textView)
        let hasAppliedInsertion = coordinator.applyPendingInsertions(to: textView)
        if !hasAppliedInsertion, !textView.hasMarkedText(), session.text != coordinator.lastSynchronizedText {
            // The file changed on disk, or properties were edited from a panel.
            coordinator.replaceText(with: session.text, in: textView)
        }
        if session.foldedKeys != coordinator.foldTracking.appliedFoldedKeys { coordinator.applyFolds(in: textView) }
        if let headingScrollRequest, headingScrollRequest.token != session.handledHeadingScrollToken {
            session.handledHeadingScrollToken = headingScrollRequest.token
            // A jump replaces the return to where the note was left.
            if let textRange = headingScrollRequest.textRange {
                coordinator.pendingJump = .textRange(textRange)
            } else {
                coordinator.pendingJump = .heading(anchor: headingScrollRequest.anchor, occurrence: headingScrollRequest.occurrence)
            }
        }
        coordinator.serveSessionRequests(in: textView)
        coordinator.performPendingJumpIfReady(in: textView)
        if followsReading { (textView as? MarkdownMacTextView)?.followReadingRange() }
    }

    static func dismantleNSView(_ container: MarkdownEditorContainerView, coordinator: Coordinator) {
        coordinator.viewWasDismantled(with: container)
    }

    /// On the Mac, Live Preview conceals markup away from the selection and draws its blocks
    /// as views over their concealed source, as on the iPad.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextLayoutManagerDelegate, RetainableMarkdownEditor {
        var session: MarkdownSession
        /// The text's styling, markup revealed at the selection, and rendered blocks, shared
        /// with the iPad's editor; the Mac has the memory to keep more views off screen.
        let styling: MarkdownEditorStyling
        /// The cards of the links the pointer rests on, as the iPad's editor shows them.
        let linkPreviews = EditorLinkPreviews()
        var configuration: EditorConfiguration {
            get { styling.configuration }
            set { styling.configuration = newValue }
        }
        /// What Live Preview's rendered blocks read; nil in Source mode.
        var environment: LivePreviewEnvironment? {
            get { styling.environment }
            set { styling.environment = newValue }
        }
        /// The editor's views, which live as long as it: a hidden note's retention can keep
        /// them beyond their SwiftUI view.
        var scrollView: NSScrollView?
        weak var retention: MarkdownEditorRetention?
        weak var retentionOwner: TabDocument?
        /// The containers of the SwiftUI views that show this note.
        private var containersInUse = EditorContainersInUse<MarkdownEditorContainerView>()
        /// The note's own history. AppKit text views otherwise record in the window's,
        /// which every note in the window shares.
        let noteUndoManager = UndoManager()
        var actions = EditorActions() {
            // The editor owns the pane's slash commands; the note's suggestions only point at them.
            didSet { session.completion.slashCommands = actions.slashCommands }
        }
        var follow: (String, Bool) -> Void = { _, _ in }
        var appliedInsertionIdentifier: UUID?
        let topLineHold = MarkdownMacEditorTopLineHold(clock: LiveApplicationClock())
        /// Where the view goes once it is in a window and has a width, where the note can
        /// be measured.
        enum Jump: Equatable {
            /// `occurrence` picks one of several headings that read the same, from zero.
            case heading(anchor: String, occurrence: Int = 0)
            case textRange(NSRange)
            /// Back where the note was left.
            case topOfCharacter(Int)
        }
        var pendingJump: Jump?
        var textState: LivePreviewTextState { styling.textState }
        /// The markup the styling shows as written in Live Preview; see `RevealedMarkup`.
        var revealedMarkup: RevealedMarkup? { styling.revealedMarkup }
        private var renderedBlocks: LivePreviewRenderedBlocks { styling.renderedBlocks }
        /// The text last given to or taken from the session; see the iPad coordinator.
        var lastSynchronizedText = ""
        /// Pastes and drops whose content is still loading or saving.
        private var pendingInsertionRequests = PendingInsertionRequests()
        private var isPlacementScheduled = false
        /// The placement passes that follow one that could not place a rendered block, or moved one.
        private var placementRetries = RenderedBlockPlacementRetries()
        /// Set while blocks are placed again on a viewport laid out for them in the same pass.
        private var isPlacingOnViewportLaidOutNow = false
        /// Set by "Edit Source": the YAML shows, and the cursor can be in it, until the
        /// cursor leaves it.
        private(set) var showsPropertiesSource: Bool {
            get { styling.propertiesSource == .afterEditSource(isShown: true) }
            set { styling.propertiesSource = .afterEditSource(isShown: newValue) }
        }
        /// Set while Graphite changes the text itself, which may change the YAML.
        private var isApplyingOwnEdit = false
        /// Set while a command or a typing helper makes its edit, which is not typing.
        var isMakingCommandEdit = false
        /// Set while lines move: the folds' keys go with their headers.
        var isMovingLines = false
        /// What folds in the note, as on the iPad, and its chevrons.
        let foldTracking = EditorFoldTracking()
        let foldButtons = MacEditorFoldButtons()
        /// The handle beside the block under the pointer (`MacBlockHandles`).
        let blockHandles = MacBlockHandles()
        var postponedFoldScan: Task<Void, Never>?
        var foldScanClock: any ApplicationClock = LiveApplicationClock()
        /// Where the cursor was, to tell which way it moved into a folded section.
        var lastSelectionLocation = 0
        /// The suggestions at the cursor: what they were found for and what plugins heard.
        private var completionTracking = EditorCompletionTracking()

        init(session: MarkdownSession, configuration: EditorConfiguration) {
            self.session = session
            lastSynchronizedText = session.text
            // The properties show their YAML after "Edit Source", as Obsidian keeps them above the note.
            styling = MarkdownEditorStyling(configuration: configuration, propertiesSource: .afterEditSource(isShown: false), detachedViewsBudgetMegabytes: 64)
            super.init()
            // Until the note has keyboard focus; see `followKeyboardFocus`.
            styling.revealsMarkupAtSelection = false
            styling.didRestyle = { [weak self] restyledTextView in
                guard let self, let textView = restyledTextView as? NSTextView else { return }
                self.schedulePlacement(in: textView)
            }
            styling.foldedRegions = { [weak self] in
                guard let self else { return [] }
                return self.foldTracking.folded(foldedKeys: self.session.foldedKeys)
            }
        }

        /// Whether Live Preview draws its blocks as views.
        var rendersBlocks: Bool { styling.rendersBlocks }
        /// Whether the frontmatter is rendered as properties, as Obsidian's Live Preview shows
        /// them; without the Properties view it stays styled source.
        var rendersProperties: Bool { styling.rendersProperties }
        /// What decides which blocks are rendered; a change finds the blocks again.
        var renderedBlockPolicy: [String] { styling.renderedBlockPolicy }

        func undoManager(for view: NSTextView) -> UndoManager? { noteUndoManager }

        // MARK: Lifetime

        var editedSession: MarkdownSession { session }
        var retainedTextLength: Int { (scrollView?.documentView as? NSTextView)?.textStorage?.length ?? 0 }

        /// Takes in the container of a new SwiftUI view of the note; see the iPad editor's
        /// `viewWasMade`. An editor an earlier view still shows stays there until that
        /// view is dismantled.
        func viewWasMade(with container: MarkdownEditorContainerView) {
            let isShownInEarlierView = containersInUse.contains { earlierContainer in earlierContainer.scrollViewShownHere != nil }
            containersInUse.add(container)
            guard let scrollView, !isShownInEarlierView, container.scrollViewShownHere == nil else { return }
            container.host(scrollView)
            resume(scrollView)
        }

        /// Lets go of the container of a dismantled SwiftUI view. The editor it showed
        /// moves to the newest view of the note that is left; with none left, it leaves
        /// the screen.
        func viewWasDismantled(with container: MarkdownEditorContainerView) {
            containersInUse.remove(container)
            guard let scrollView = container.scrollViewShownHere else { return }
            if let remainingContainer = containersInUse.newest {
                remainingContainer.host(scrollView)
                return
            }
            suspend(scrollView)
            if retention?.keepHiddenEditor(self, owner: retentionOwner) != true { discardRetainedEditor() }
        }

        /// Takes the editor off screen without ending it; see the iPad editor's `suspend`.
        func suspend(_ scrollView: NSScrollView) {
            session.applyPendingInsertionsBeforeSaving = nil
            session.isEditorAttached = false
            stopObservingCharacterEdits()
            if let textView = scrollView.documentView as? NSTextView {
                if textView.window?.firstResponder === textView { textView.window?.makeFirstResponder(nil) }
                recordScrollLocation(of: textView)
            }
            session.recordEditorPlace = nil
            scrollView.removeFromSuperview()
            session.undoAvailability.follow(nil)
        }

        func resume(_ scrollView: NSScrollView) {
            if let textView = scrollView.documentView as? NSTextView {
                observeCharacterEdits(in: textView)
                reportPlace(of: textView)
                session.completion.performEdits = { [weak self, weak textView] edits in
                    guard let self, let textView else { return false }
                    return self.performCompletionEdits(edits, in: textView)
                }
            }
            session.isEditorAttached = true
            session.undoAvailability.follow(noteUndoManager)
        }

        /// The Mac keeps the views of every hidden note's blocks, within each editor's
        /// 64 MB pool, as before the iPad began keeping one note's.
        func releaseRenderedViews() {}

        func discardRetainedEditor() {
            // Blocks' views are taken out of the text view first: one still in it when the
            // text view goes stays registered with AppKit's notification center, and keeps
            // its environment, the note's session and the workspace's closures with it.
            styling.renderedBlocks.removeAllViews()
            scrollView?.removeFromSuperview()
            scrollView = nil
        }

        /// Connects the view's paste, drop, click, and focus handling, and follows its edits.
        func connect(_ textView: MarkdownMacTextView) {
            // Each request remembers the text revision it was made at: the content saves
            // asynchronously while the note may change, and the items of one paste or drop
            // all ask for the same place.
            textView.insertAttachment = { [weak self] data, stem, fileExtension, range in
                guard let self, let insertAttachment = self.actions.insertAttachment else { return }
                self.pendingInsertionRequests.remember(InsertionRequest(range: range, revision: self.textState.history.revision))
                insertAttachment(data, stem, fileExtension, range)
            }
            textView.insertLinkToVaultFile = { [weak self] path, range in
                guard let self, let insertLinkToVaultFile = self.actions.insertLinkToVaultFile else { return }
                self.pendingInsertionRequests.remember(InsertionRequest(range: range, revision: self.textState.history.revision))
                insertLinkToVaultFile(path, range)
            }
            textView.reportUnreadableItem = { [weak self] in self?.session.errorMessage = NativeMarkdownEditor.unreadableItemMessage }
            textView.currentVaultRoot = session.vaultRoot
            textView.linkPreviews = linkPreviews
            // Markup and a block's source show at the cursor only while the note has keyboard
            // focus, as on the iPad: a note opened from the file list, its cursor at the start,
            // showed the callout or table there as source until a click in the note.
            textView.didBecomeFirstResponder = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.session.blockViews.releaseTableCellCommands()
                self.actions.beginEditing?()
                self.followKeyboardFocus(true, in: textView)
            }
            textView.didResignFirstResponder = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.followKeyboardFocus(false, in: textView)
                self.closeCompletion()
            }
            connectClicksFindAndFolds(of: textView)
            // Bullets, task boxes, quote bars and inline math are drawn over their hidden
            // markup, as on the iPad.
            textView.textLayoutManager?.delegate = self
            textView.didMoveTextColumn = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.schedulePlacement(in: textView)
            }
            textView.didLayOutViewport = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.placeBlockViews(in: textView)
                self.positionFoldButtons(in: textView)
                // The suggestions follow the cursor as the note scrolls.
                if self.session.completion.context != nil { self.updateCompletion(in: textView) }
            }
            session.completion.performEdits = { [weak self, weak textView] edits in
                guard let self, let textView else { return false }
                return self.performCompletionEdits(edits, in: textView)
            }
            textView.didBecomeMeasurable = { [weak self] measurableView in
                // Not from inside the window change or layout itself.
                DispatchQueue.main.async { [weak self, weak measurableView] in
                    guard let self, let measurableView else { return }
                    // A kept editor is updated before its container is in the window, so the
                    // update leaves the reading place in the session; it is taken here, as the
                    // iPad editor takes it when it enters its window. Left there, it was taken
                    // at the next update, as the note switched back to reading.
                    self.goToReadingPlaceIfSwitched(in: measurableView)
                    self.performPendingJumpIfReady(in: measurableView)
                    self.returnToTopLineOnceSettled(in: measurableView)
                    self.startEditingIfRequested(in: measurableView)
                }
            }
            holdTopLineThroughWidthChanges(of: textView)
            observeCharacterEdits(in: textView)
        }

        // MARK: Character edits

        /// Follows every change to the characters, whichever path made it; AppKit reports
        /// `textDidChange` after its own edits, and a change it does not report is settled
        /// once it is done.
        func observeCharacterEdits(in textView: NSTextView) {
            session.applyPendingInsertionsBeforeSaving = { [weak self, weak textView] in
                guard let self, let textView else { return }
                _ = self.applyPendingInsertions(to: textView)
            }
            styling.observeCharacterEdits(in: textView) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.settleTextChange(in: textView)
                self.publish(textView)
            }
        }

        func stopObservingCharacterEdits() {
            styling.stopObservingCharacterEdits()
        }

        func currentSource(of textView: NSTextView) -> NSString {
            styling.currentSource(of: textView)
        }

        // MARK: Styling

        /// Finds the blocks again and styles the whole note.
        /// - Parameter forcesBlockScan: Finds the blocks again, after a change in which are rendered.
        func restyleEverything(in textView: NSTextView, forcesBlockScan: Bool = false) {
            takeInText(of: textView, forcesBlockScan: forcesBlockScan)
            foldTracking.appliedFoldedKeys = session.foldedKeys
            styling.restyleEverything(in: textView)
        }

        func restyle(_ range: NSRange, in textView: NSTextView) {
            styling.restyle(range, in: textView)
        }

        /// Restyles what the edits since the last styling changed, once no text is marked:
        /// styling would disturb an input method's composition.
        private func settleTextChange(in textView: NSTextView) {
            guard !textView.hasMarkedText(), textState.cachesDescribeOldText || textState.hasUnstyledEdit else { return }
            takeInText(of: textView)
            // A fold that moved to an edited line, or whose hidden text changed, restyles the
            // whole note rather than leaving the old section's lines hidden.
            let carried = foldTracking.carryFoldsAcrossEdit(textLength: textView.textStorage?.length ?? 0, foldedKeys: session.foldedKeys)
            if carried.foldedKeys != session.foldedKeys { session.foldedKeys = carried.foldedKeys }
            if carried.changed {
                restyleEverything(in: textView)
                styling.restyleBlocksAwaitingRestyle(in: textView)
                return
            }
            styling.restyleUnstyledEdit(in: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            lookahead.stop()
            linkPreviews.closeCard()
            // An edit moves the text again, so the blocks get a fresh set of placement passes.
            placementRetries.reset()
            blockHandles.hide()
            settleTextChange(in: textView)
            publish(textView)
            updateCompletion(in: textView, followsTyping: true)
        }

        /// Shows the markup at the cursor once the note has keyboard focus, and hides it, the
        /// blocks drawn again, once it has not.
        private func followKeyboardFocus(_ hasKeyboardFocus: Bool, in textView: NSTextView) {
            guard styling.revealsMarkupAtSelection != hasKeyboardFocus else { return }
            styling.revealsMarkupAtSelection = hasKeyboardFocus
            styling.restyleRevealedMarkup(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            session.selection = textView.selectedRange()
            lastSelectionLocation = textView.selectedRange().location
            concealPropertiesSourceIfLeft(in: textView)
            styling.restyleRevealedMarkup(in: textView)
            formatCodeBlockLeftBehind(in: textView, editingEnded: false)
            // During an edit the selection can be reported before the text; `textDidChange`
            // updates the suggestions for the same selection once the edit is settled.
            guard !textState.cachesDescribeOldText else { return }
            updateCompletion(in: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            formatCodeBlockLeftBehind(in: textView, editingEnded: true)
        }

        /// Formats the code block the user edited once the selection leaves it or editing
        /// ends, on the next turn of the run loop, through the text view so Undo puts the
        /// code back.
        private func formatCodeBlockLeftBehind(in textView: NSTextView, editingEnded: Bool) {
            guard configuration.formatsCodeBlocks else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, !textView.hasMarkedText(), let textStorage = textView.textStorage,
                      let edit = self.styling.codeFormattingEdit(afterSelectionChangeIn: textView, editingEnded: editingEnded),
                      NSMaxRange(edit.range) <= textStorage.length else { return }
                textView.breakUndoCoalescing()
                self.isApplyingOwnEdit = true
                defer { self.isApplyingOwnEdit = false }
                guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
                textView.didChangeText()
                if NSMaxRange(edit.selectionAfter) <= textStorage.length { textView.setSelectedRange(edit.selectionAfter) }
            }
        }

        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
                      toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
            // Folds describe the text before an edit until it settles.
            if !textState.cachesDescribeOldText,
               let target = foldTracking.locationOutsideFolds(for: newSelectedCharRange, movedFrom: lastSelectionLocation,
                                                              textLength: textView.textStorage?.length ?? 0, foldedKeys: session.foldedKeys) {
                return NSRange(location: target, length: 0)
            }
            guard let entry = concealedPropertiesEntry(in: textView) else { return newSelectedCharRange }
            return Self.selection(newSelectedCharRange, keptBelowConcealedPropertiesEndingAt: NSMaxRange(entry.range))
        }

        /// The spelling checker marks nothing in a block's concealed source: its marks were
        /// drawn at the hidden lines' height, a red speck above the block's view.
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
            guard value != 0, concealedEntries(in: textView).contains(where: { entry in NSIntersectionRange(entry.range, affectedCharRange).length > 0 }) else { return value }
            return 0
        }

        /// An edit that starts in the concealed YAML and reaches its end, as a backspace at
        /// the start of the note's text does, would join the properties' closing line to the
        /// text and turn the properties into text; it is refused. Replacing the whole YAML,
        /// as after Select All, and edits inside it, as find and replace makes, are allowed.
        /// What is typed goes through the same helpers as on the iPad; AppKit brings Return,
        /// Tab, Backspace and typed characters here.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isApplyingOwnEdit, !noteUndoManager.isUndoing, !noteUndoManager.isRedoing else {
                recordEditAboutToBeMade(replacing: affectedCharRange, in: textView)
                return true
            }
            let propertiesEntry = concealedPropertiesEntry(in: textView)
            if let propertiesEntry,
               NativeMarkdownEditor.cutsIntoRenderedProperties(affectedCharRange, propertiesEnd: NSMaxRange(propertiesEntry.range)) { return false }
            // Characters only, not an attribute change; and the note's own typing, not the find
            // bar's replace, which keeps the keyboard.
            if !isMakingCommandEdit, let replacementString, !textView.hasMarkedText(), textView.window?.firstResponder === textView,
               let edit = typingEdit(replacing: affectedCharRange, with: replacementString,
                                     belowProperties: propertiesEntry != nil, in: textView) {
                perform(edit, in: textView)
                return false
            }
            // An edit that reaches into a folded section unfolds it first, so nothing is
            // typed into, or deleted from, text that cannot be seen.
            if !isMakingCommandEdit, replacementString != nil {
                let touched = foldTracking.foldsTouched(byEditReplacing: affectedCharRange, foldedKeys: session.foldedKeys)
                if !touched.isEmpty {
                    session.foldedKeys.subtract(touched.map(\.key))
                    applyFolds(in: textView)
                }
            }
            recordEditAboutToBeMade(replacing: affectedCharRange, in: textView)
            return true
        }

        /// Applies every insertion waiting in the session, in order, and tells whether there
        /// was any. Several can be queued between updates, such as images dropped together;
        /// each apply removes its insertion from the queue.
        func applyPendingInsertions(to textView: NSTextView) -> Bool {
            var hasAppliedInsertion = false
            while let insertion = session.pendingInsertion, insertion.id != appliedInsertionIdentifier {
                apply(insertion, to: textView)
                hasAppliedInsertion = true
            }
            return hasAppliedInsertion
        }

        /// Makes an insertion through the text view, so it can be undone. A pasted or dropped
        /// block goes where its request points now, past the note's changes since.
        func apply(_ insertion: EditorInsertion, to textView: NSTextView) {
            appliedInsertionIdentifier = insertion.id
            isApplyingOwnEdit = true
            defer { isApplyingOwnEdit = false }
            let source = currentSource(of: textView)
            var insertionText = insertion.text
            var insertionRange = insertion.range
            var selectionAfter = insertion.selectionAfter
            let pendingRequest = insertion.selectionAfter == nil ? pendingInsertionRequests.take(preparedFor: insertion.range, in: textState.history) : nil
            if let movedRange = pendingRequest?.currentTarget(in: textState.history), movedRange != insertion.range {
                (insertionText, insertionRange) = MovedBlockInsertion.insertion(of: insertion.text, movedTo: movedRange, in: source)
                selectionAfter = nil
            }
            let safeLocation = min(insertionRange.location, source.length)
            let replacedRange = NSRange(location: safeLocation, length: min(insertionRange.length, source.length - safeLocation))
            // The edit happens where the person is: AppKit scrolls to the cursor, which in a
            // note scrolled without a click is still at its start, and restyling the whole note
            // re-estimates TextKit's layout. The line at the top stays there, as on the iPad.
            let topLineBeforeInsertion = topLine(of: textView)
            // insertText leaves the cursor after the inserted text, where the iPad leaves it.
            textView.setSelectedRange(replacedRange)
            textView.insertText(insertionText, replacementRange: replacedRange)
            let insertedRange = NSRange(location: safeLocation, length: (insertionText as NSString).length)
            if let pendingRequest {
                pendingInsertionRequests.placeRemainingItems(of: pendingRequest, after: NSMaxRange(insertedRange), at: textState.history.revision)
            }
            if let selectionAfter, NSMaxRange(selectionAfter) <= (textView.textStorage?.length ?? 0) {
                textView.setSelectedRange(selectionAfter)
            }
            restyleEverything(in: textView)
            publish(textView)
            session.markInsertionApplied(insertion)
            if let topLineBeforeInsertion {
                // A line below the insertion moved by the inserted length; one inside the
                // replaced text is gone, and the inserted text takes its place at the top.
                let location = topLineBeforeInsertion.location
                let movedLocation = location <= safeLocation ? location
                    : location >= NSMaxRange(replacedRange) ? location + insertedRange.length - replacedRange.length : safeLocation
                scrollToTop(of: movedLocation, distanceBelowTop: topLineBeforeInsertion.distanceBelowTop, in: textView)
            }
            // A paste at a cursor out of sight still shows what it inserted.
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        private func publish(_ textView: NSTextView) {
            let text = currentSource(of: textView) as String
            // The session's text changed elsewhere, and the update that brings it here has not
            // run or is waiting out a composition; see `TextDifference.carryingEdit`.
            if session.text != lastSynchronizedText, session.text != text {
                guard !textView.hasMarkedText() else { return }
                let merged = TextDifference.carryingEdit(from: lastSynchronizedText, to: text, onto: session.text)
                session.text = merged
                lastSynchronizedText = merged
                replaceText(with: merged, in: textView)
                return
            }
            session.text = text
            lastSynchronizedText = text
            session.selection = textView.selectedRange()
        }

        /// Puts a new text in place by replacing only what differs, as an undoable edit:
        /// setting the whole text would leave the undo history pointing at older text.
        func replaceText(with newText: String, in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let oldSource = NSString(string: textStorage.string)
            let newSource = newText as NSString
            guard let (replacedRange, replacementRange) = TextDifference.changedRanges(from: oldSource, to: newSource) else {
                lastSynchronizedText = newText
                return
            }
            let replacement = newSource.substring(with: replacementRange)
            let edit = CharacterEdit(editedRange: replacementRange, changeInLength: newSource.length - oldSource.length)
            let selection = TextRangeMapping.insertionTarget(textView.selectedRange(), through: edit)
            isApplyingOwnEdit = true
            defer { isApplyingOwnEdit = false }
            guard textView.shouldChangeText(in: replacedRange, replacementString: replacement) else {
                textView.string = newText
                restyleEverything(in: textView)
                return
            }
            textStorage.replaceCharacters(in: replacedRange, with: replacement)
            textView.didChangeText()
            if NSMaxRange(selection) <= textStorage.length { textView.setSelectedRange(selection) }
        }

        // MARK: Rendered blocks

        /// The frontmatter, while the properties are rendered and it describes the text on screen.
        private var propertiesEntry: LivePreviewBlockEntry? {
            guard rendersProperties, !textState.cachesDescribeOldText else { return nil }
            return textState.blockEntries.first { entry in entry.block.kind == .frontmatter && entry.range.location == 0 }
        }

        /// The frontmatter while its YAML is concealed under the properties view.
        private func concealedPropertiesEntry(in textView: NSTextView) -> LivePreviewBlockEntry? {
            guard !showsPropertiesSource, let entry = propertiesEntry, NSMaxRange(entry.range) <= (textView.textStorage?.length ?? 0) else { return nil }
            return entry
        }

        /// The blocks whose source is concealed under their views, in note order: the
        /// properties unless "Edit Source" shows their YAML, as Obsidian keeps them above the
        /// note, and every other block while the selection is outside it, as on the iPad.
        func concealedEntries(in textView: NSTextView) -> [LivePreviewBlockEntry] {
            styling.concealedEntries(in: textView)
        }

        /// A selection that starts in the concealed YAML starts after it instead, so the
        /// cursor never lands in text that is not drawn. A selection of the whole YAML, as
        /// Select All makes, is kept.
        static func selection(_ selection: NSRange, keptBelowConcealedPropertiesEndingAt propertiesEnd: Int) -> NSRange {
            guard selection.location < propertiesEnd else { return selection }
            if selection.location == 0, selection.length > 0, NSMaxRange(selection) >= propertiesEnd { return selection }
            return NSRange(location: propertiesEnd, length: max(NSMaxRange(selection), propertiesEnd) - propertiesEnd)
        }

        /// Moves the selection out of the concealed YAML, as when a note opens with the cursor
        /// at its start; AppKit asks the delegate only about selections made after it is set.
        func keepSelectionOutOfConcealedProperties(in textView: NSTextView) {
            guard let entry = concealedPropertiesEntry(in: textView) else { return }
            let selection = textView.selectedRange()
            let keptSelection = Self.selection(selection, keptBelowConcealedPropertiesEndingAt: NSMaxRange(entry.range))
            if keptSelection != selection { textView.setSelectedRange(keptSelection) }
        }

        /// Conceals the YAML "Edit Source" showed once the cursor leaves it. While it is
        /// being edited into something that is not frontmatter, it stays shown.
        private func concealPropertiesSourceIfLeft(in textView: NSTextView) {
            guard showsPropertiesSource, !textView.hasMarkedText(), !textState.hasUnstyledEdit, let entry = propertiesEntry,
                  !LivePreviewBlockActivity.isActive(blockRange: entry.range, selection: textView.selectedRange(), in: currentSource(of: textView)) else { return }
            showsPropertiesSource = false
            restyle(entry.range, in: textView)
        }

        /// Shows the YAML in place of the properties view, with the cursor on its first
        /// property: the view's "Edit Source".
        func showPropertiesSource(in textView: NSTextView) {
            guard !textView.hasMarkedText(), !textState.hasUnstyledEdit, let entry = concealedPropertiesEntry(in: textView) else { return }
            showsPropertiesSource = true
            restyle(entry.range, in: textView)
            let source = currentSource(of: textView)
            let firstPropertyLocation = min(NSMaxRange(source.lineRange(for: NSRange(location: 0, length: 0))), NSMaxRange(entry.range))
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: firstPropertyLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }

        /// Shows a block's source with the cursor at its start, after a click on its view;
        /// the cursor in the block keeps its source shown until it leaves.
        func revealSource(ofBlockWithKey key: LivePreviewBlockKey, in textView: NSTextView) {
            guard !textView.hasMarkedText(), !textState.cachesDescribeOldText,
                  let entry = textState.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
            if entry.block.kind == .frontmatter { return showPropertiesSource(in: textView) }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: entry.range.location, length: 0))
        }

        /// Gives the blocks' views the current environment and appearance in place, keeping
        /// their own state; only those that read the index when nothing else changed.
        func refreshBlockViews(in textView: NSTextView) {
            guard let environment else { return }
            let signature = LivePreviewWidgetSignature(environment: environment, accentHex: configuration.accentHex, notePath: session.path.rawValue)
            let didRefresh = renderedBlocks.refreshViews(for: signature, entries: textState.blockEntries) { entry in
                blockRootView(for: entry, environment: environment, textView: textView)
            }
            if didRefresh { placeBlockViews(in: textView) }
        }

        /// Places the views of the concealed blocks TextKit has laid out and takes off screen
        /// those of blocks that are not: TextKit lays out the viewport, so a long note's
        /// blocks below it cost nothing until they scroll into view, and says when it has.
        func placeBlockViews(in textView: NSTextView) {
            guard let environment, rendersBlocks, let textContainer = textView.textContainer, let textLayoutManager = textView.textLayoutManager,
                  textView.renderedBlockColumnWidth > 0 else {
                renderedBlocks.removeAllViews()
                return
            }
            // Mid-edit, the blocks describe the text before it; the views stay until it settles.
            guard !textState.cachesDescribeOldText, !textView.hasMarkedText() else { return }
            let columnMinX = textView.textContainerOrigin.x + textContainer.lineFragmentPadding
            let column = RenderedBlockColumn(minX: columnMinX, textContainerTop: textView.textContainerOrigin.y, width: textView.renderedBlockColumnWidth)
            guard let placement = renderedBlocks.placeViews(of: concealedEntries(in: textView), in: textView, textLayoutManager: textLayoutManager,
                                                            column: column, configuration: configuration, makeRootView: { entry in
                blockRootView(for: entry, environment: environment, textView: textView)
            }) else { return }
            // A paragraph a restyle changed has a new fragment, not laid out yet; waiting for
            // TextKit's next layout left the block blank until the next scroll (HUNT-364).
            if !placement.keysAwaitingLayout.isEmpty, !isPlacingOnViewportLaidOutNow {
                isPlacingOnViewportLaidOutNow = true
                defer { isPlacingOnViewportLaidOutNow = false }
                RenderedBlockPlacementRetries.layOutViewport(of: textLayoutManager) { textView.visibleRect.origin }
                placeBlockViews(in: textView)
                return
            }
            renderedBlocks.detachViews(except: placement.keysInUse, entries: textState.blockEntries)
            // A height measured at a new width, or by another editor, is reserved in the text first.
            styling.restyleLater(placement.entriesToRestyle, in: textView)
            // A block still without its view, or a view that moved, is placed again, as on the iPad.
            let isSettled = placementRetries.follow(placement) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.placeBlockViews(in: textView)
            }
            if isSettled && placement.entriesToRestyle.isEmpty {
                lookahead.makeViewsOnceStill(viewportStart: RenderedBlockLookahead.viewportCharacters(of: textLayoutManager)?.location) {
                    [weak self, weak textView] in self?.makeNextViewAhead(in: textView) ?? false
                }
            }
        }

        func removeAllBlockViews() {
            lookahead.stop()
            renderedBlocks.removeAllViews()
        }

        /// Makes the views of the blocks just below the screen once the note is still.
        private lazy var lookahead = RenderedBlockLookahead(renderedBlocks: renderedBlocks)

        /// Makes the next view below the screen (`RenderedBlockLookahead`); false when there is
        /// none to make, or the note is being edited or hidden.
        private func makeNextViewAhead(in textView: NSTextView?) -> Bool {
            guard let textView, let environment, rendersBlocks, textView.window != nil, !textView.hasMarkedText(), !textState.cachesDescribeOldText,
                  !textState.hasUnstyledEdit, let textContainer = textView.textContainer, textView.renderedBlockColumnWidth > 0,
                  let viewport = textView.textLayoutManager.flatMap(RenderedBlockLookahead.viewportCharacters(of:)) else { return false }
            let column = RenderedBlockColumn(minX: textView.textContainerOrigin.x + textContainer.lineFragmentPadding,
                                             textContainerTop: textView.textContainerOrigin.y, width: textView.renderedBlockColumnWidth)
            return renderedBlocks.makeNextViewAhead(below: viewport, in: concealedEntries(in: textView), textView: textView, column: column,
                                                    configuration: configuration) { entry in
                blockRootView(for: entry, environment: environment, textView: textView)
            }
        }

        /// Places the blocks after a change, on the next turn of the run loop; TextKit's
        /// own layout of the viewport places them too (`MarkdownMacTextView.didLayOutViewport`).
        func schedulePlacement(in textView: NSTextView) {
            // A block whose source now shows loses its view at once, before its text is drawn.
            if !textState.cachesDescribeOldText {
                renderedBlocks.detachViews(except: Set(concealedEntries(in: textView).map(\.key)), entries: textState.blockEntries)
            }
            guard !isPlacementScheduled else { return }
            isPlacementScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.isPlacementScheduled = false
                guard let textView else { return }
                self.placeBlockViews(in: textView)
            }
        }

        /// The hosted view takes the appearance from the text view it is in. A click on a
        /// block's view shows its source; on the properties, "Edit Source" does.
        private func blockRootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: NSTextView) -> RenderedBlockRoot {
            let key = entry.key
            let isFrontmatter = entry.block.kind == .frontmatter
            return LivePreviewRenderedBlocks.rootView(for: entry, environment: environment, accentHex: configuration.accentHex, colorScheme: nil, revealSource: { [weak self, weak textView] in
                // Not from inside the view's own action, which the view's removal would end.
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    if isFrontmatter { self.showPropertiesSource(in: textView) } else { self.revealSource(ofBlockWithKey: key, in: textView) }
                }
            }, reportHeight: { [weak self, weak textView] height in
                guard let self, let textView else { return }
                self.styling.reserveMeasuredHeight(height, forBlockWithKey: key, isFrontmatter: isFrontmatter, in: textView)
            }, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [weak self, weak textView] editor, transform in
                guard let self, let textView else { return }
                self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
            }, setIsEditingInView: { [weak self] isEditing, editor in
                guard let self else { return }
                if !isEditing { return self.renderedBlocks.endEditingInView(owner: editor) }
                guard let entry = self.textState.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                self.renderedBlocks.beginEditingInView(blockWithKey: key, at: entry.range.location, owner: editor)
            }, setDraftCommit: { [weak self] editor, commit in
                self?.session.blockViews.draftCommits[editor] = commit
            }, offerCellCommands: { [weak self] target in
                self?.session.blockViews.takeTableCellCommands(target)
            }, placeCaretBesideBlock: { [weak self, weak textView] editor, side in
                guard let self, let textView else { return }
                self.placeCaret(besideBlockWithKey: key, editedBy: editor, side: side, in: textView)
            }, undoInNote: { [weak self] isRedo in
                if isRedo { self?.noteUndoManager.redo() } else { self?.noteUndoManager.undo() }
            }), currentLocation: { [weak self] in
                self?.textState.blockEntries.first { candidate in candidate.key == key }?.range.location
            })
        }

        /// Replaces a rendered block's source with what its view made of it, as a table's cell
        /// editor does, through the text view so it can be undone. Mid-edit or during an input
        /// method's composition, the change waits a turn.
        func replaceSource(ofBlockWithKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, using transform: @escaping (String) -> String?,
                           in textView: NSTextView, attemptsLeft: Int = 3) {
            guard !textView.hasMarkedText(), !textState.cachesDescribeOldText else {
                guard attemptsLeft > 0 else { return }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            let source = currentSource(of: textView)
            guard let blockRange = renderedBlocks.rangeOfBlock(withKey: key, editedBy: editor, in: textState.blockEntries, source: source),
                  let replacement = transform(source.substring(with: blockRange)) else { return }
            replaceText(with: source.replacingCharacters(in: blockRange, with: replacement), in: textView)
        }

        /// Gives the note's text the keyboard with the caret on the line before or after a
        /// rendered block, as an arrow out of a table's edge does; an empty line is added first
        /// where the block starts or ends the note.
        func placeCaret(besideBlockWithKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, side: RenderedBlockSide, in textView: NSTextView) {
            let source = currentSource(of: textView)
            guard let blockRange = renderedBlocks.rangeOfBlock(withKey: key, editedBy: editor, in: textState.blockEntries, source: source) else { return }
            let placement = RenderedBlockCaretPlacement(beside: blockRange, side: side, in: source)
            if let lineBreakLocation = placement.lineBreakLocation {
                replaceText(with: source.replacingCharacters(in: NSRange(location: lineBreakLocation, length: 0), with: "\n"), in: textView)
            }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: placement.caretLocation, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        // MARK: Drawn replacements and tasks

        nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                                           in textElement: NSTextElement) -> NSTextLayoutFragment {
            ConcealedReplacementLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        /// Checks or unchecks the drawn task box at a clicked character, through the text view
        /// so it can be undone. On the selection's lines the box shows as `[ ]`, and a click
        /// there places the cursor.
        func toggleTask(atCharacter characterIndex: Int, in textView: NSTextView) -> Bool {
            guard let checkboxRange = taskCheckbox(atCharacter: characterIndex, in: textView), let textStorage = textView.textStorage else { return false }
            let source = currentSource(of: textView)
            let stateRange = NSRange(location: checkboxRange.location + 1, length: 1)
            guard NSMaxRange(stateRange) <= source.length else { return false }
            let newState = source.substring(with: stateRange) == " " ? "x" : " "
            let selection = textView.selectedRange()
            isMakingCommandEdit = true
            defer { isMakingCommandEdit = false }
            guard textView.shouldChangeText(in: stateRange, replacementString: newState) else { return true }
            textStorage.replaceCharacters(in: stateRange, with: newState)
            textView.didChangeText()
            if NSMaxRange(selection) <= textStorage.length { textView.setSelectedRange(selection) }
            return true
        }

        /// The drawn task box at a character. On the selection's lines the box shows as `[ ]`,
        /// and a click there places the cursor.
        func taskCheckbox(atCharacter characterIndex: Int, in textView: NSTextView) -> NSRange? {
            guard configuration.mode == .livePreview, !textState.cachesDescribeOldText, !textView.hasMarkedText() else { return nil }
            let source = currentSource(of: textView)
            guard characterIndex <= source.length else { return nil }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            if let revealedMarkup, revealedMarkup.showsLineMarker(at: lineRange.location) { return nil }
            return LivePreviewTapTargets.taskCheckboxRange(at: characterIndex, in: source)
        }

        // MARK: Suggestions

        /// Shows or hides suggestions for what is typed at the cursor, as the iPad's editor
        /// does: links after `[[`, tags after `#`, else what community plugins suggest.
        /// Plugins hear each change and cursor move from here (`editor-change`).
        func updateCompletion(in textView: NSTextView, followsTyping: Bool = false) {
            completionTracking.recordAcceptedSuggestion(isListOpen: session.completion.context != nil)
            defer { completionTracking.listDidUpdate(isOpen: session.completion.context != nil, at: textState.history.revision) }
            let selection = textView.selectedRange()
            guard textView.window?.firstResponder === textView, !textView.hasMarkedText(), selection.length == 0 else {
                session.completion.update(context: nil, caretRect: .zero)
                return
            }
            let source = currentSource(of: textView)
            let context = completionTracking.context(in: source, cursor: selection.location,
                                                     textRevision: textState.history.revision,
                                                     offersSlashCommands: session.completion.offersSlashCommands, followsTyping: followsTyping,
                                                     blockContext: { [styling] lineStart in
                                                         styling.blockContext(atLineStart: lineStart, in: textView, source: source)
                                                     },
                                                     pluginEditorDidChange: actions.pluginEditorDidChange)
            session.completion.update(context: context, caretRect: context == nil ? .zero : caretRect(in: textView))
        }

        /// The cursor in the coordinates of the view that shows the note, from its top left,
        /// where the pane draws the suggestions.
        private func caretRect(in textView: NSTextView) -> CGRect {
            guard let window = textView.window, let noteView = textView.enclosingScrollView?.superview ?? textView.enclosingScrollView else { return .zero }
            let screenRect = textView.firstRect(forCharacterRange: textView.selectedRange(), actualRange: nil)
            let rect = noteView.convert(window.convertFromScreen(screenRect), from: nil)
            return noteView.isFlipped ? rect : CGRect(x: rect.minX, y: noteView.bounds.height - rect.maxY, width: rect.width, height: rect.height)
        }

        /// While suggestions show, the arrow keys move through them, Return and Tab choose
        /// one, and Escape closes them, as on the iPad.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard session.completion.isVisible else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)): session.completion.moveSelection(by: -1)
            case #selector(NSResponder.moveDown(_:)): session.completion.moveSelection(by: 1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): session.completion.accept()
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                completionTracking.forgetOpenSuggestions()
                session.completion.dismiss()
            default: return false
            }
            return true
        }

        /// Closes the suggestions as the note loses keyboard focus; one chosen just before
        /// still gets its edits.
        private func closeCompletion() {
            completionTracking.recordAcceptedSuggestion(isListOpen: session.completion.context != nil)
            completionTracking.forgetOpenSuggestions()
            session.completion.update(context: nil, caretRect: .zero)
        }

        /// An accepted suggestion's edits, moved past what was typed since its suggestions
        /// were found (`EditorCompletionTracking`), made through the text view so Undo takes
        /// them back. Each is written against the original text; the last one's selection is kept.
        @discardableResult
        func performCompletionEdits(_ edits: [MarkdownTextEdit], in textView: NSTextView) -> Bool {
            completionTracking.recordAcceptedSuggestion(isListOpen: session.completion.context != nil)
            guard let movedEdits = completionTracking.editsMovedPastTyping(edits, history: textState.history) else {
                session.errorMessage = EditorCompletionTracking.noteChangedMessage
                return false
            }
            guard let primary = movedEdits.last, let textStorage = textView.textStorage else { return false }
            textView.breakUndoCoalescing()
            isMakingCommandEdit = true
            defer { isMakingCommandEdit = false }
            var selectionShift = 0
            for edit in movedEdits.sorted(by: { leftEdit, rightEdit in leftEdit.range.location > rightEdit.range.location }) {
                guard NSMaxRange(edit.range) <= textStorage.length,
                      textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { continue }
                textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
                textView.didChangeText()
                if edit != primary, edit.range.location < primary.range.location { selectionShift += edit.replacement.utf16.count - edit.range.length }
            }
            let selection = NSRange(location: primary.selectionAfter.location + selectionShift, length: primary.selectionAfter.length)
            if NSMaxRange(selection) <= textStorage.length { textView.setSelectedRange(selection) }
            return true
        }

        // MARK: Links

        /// Follows the link at a clicked character, as a tap does on the iPad: ⌘ opens it
        /// in a new tab and ⌥⌘ beside the note.
        /// Runs an editing shortcut as an edit Undo takes back; false for a command the Mac's
        /// editor does not run from the keyboard.
        func runKeyCommand(_ command: EditorCommand, in textView: NSTextView) -> Bool {
            switch command {
            case .find, .findAndReplace:
                let finderAction: NSTextFinder.Action = if case .find = command { .showFindInterface } else { .showReplaceInterface }
                let sender = NSMenuItem()
                sender.tag = finderAction.rawValue
                textView.performTextFinderAction(sender)
                return true
            case .undo, .redo, .attach, .draw, .dismissKeyboard, .followLink:
                return false
            case .moveLinesUp: return moveLines(up: true, in: textView)
            case .moveLinesDown: return moveLines(up: false, in: textView)
            case .heading, .wrap, .bulletList, .numberedList, .task, .indent, .outdent,
                 .insertWikilink, .insertTag, .insertMarkdownLink, .lineBreakInItem:
                guard let edit = MarkdownEditing.edit(for: command, in: currentSource(of: textView), selection: textView.selectedRange(),
                                                      indentUnit: configuration.editingBehavior.indentUnit, tabSize: configuration.editingBehavior.tabSize) else { return false }
                perform(edit, in: textView)
                return true
            }
        }

        func followLink(atCharacter characterIndex: Int, modifierFlags: NSEvent.ModifierFlags, in textView: NSTextView) -> Bool {
            guard let link = link(atCharacter: characterIndex, in: textView) else { return false }
            switch link {
            case .note(let target, let isWiki):
                if modifierFlags.contains(.command), let followLinkElsewhere = actions.followLinkElsewhere {
                    followLinkElsewhere(target, isWiki, TabPlacement.forLink(command: true, option: modifierFlags.contains(.option),
                                                                             shift: modifierFlags.contains(.shift)))
                } else {
                    follow(target, isWiki)
                }
            case .web(let location):
                NSWorkspace.shared.open(location)
            }
            return true
        }

        /// The link at a character in Live Preview, while its markup is concealed. A link
        /// that shows its markup is being edited, so a click there places the cursor; a
        /// link written in code or math is text.
        func link(atCharacter characterIndex: Int, in textView: NSTextView) -> LinkInText? {
            guard configuration.mode == .livePreview, !textState.cachesDescribeOldText else { return nil }
            let source = currentSource(of: textView)
            guard characterIndex < source.length else { return nil }
            if let revealedMarkup, LivePreviewTapTargets.isInsideLinkShowingItsMarkup(characterIndex, in: source, revealedMarkup: revealedMarkup) { return nil }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            guard let link = LinkLocator.link(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: false),
                  !LivePreviewTapTargets.isInsideCode(characterIndex, in: source) else { return nil }
            return link
        }

        // MARK: Session requests

        /// Answers what the session asks of the editor on screen, as the iPad editor does.
        func serveSessionRequests(in textView: NSTextView) {
            goToReadingPlaceIfSwitched(in: textView)
            presentFindIfRequested(in: textView)
            startEditingIfRequested(in: textView)
            selectIfRequested(in: textView)
        }

        /// Moves the cursor where a plugin put it without changing the text; after the update,
        /// as selecting reports back to the session.
        private func selectIfRequested(in textView: NSTextView) {
            guard session.selectionRequest != nil else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, let range = self.session.selectionRequest else { return }
                self.session.selectionRequest = nil
                let length = (textView.string as NSString).length
                let selection = CommunityPluginEditorChange.selection(anchor: range.location, head: NSMaxRange(range), inTextOfLength: length)
                textView.setSelectedRange(selection)
                textView.scrollRangeToVisible(selection)
            }
        }

        /// Puts the cursor in a note just created, as Obsidian does, once the editor is in a window.
        private func startEditingIfRequested(in textView: NSTextView) {
            guard session.startsEditingWhenShown, textView.window != nil else { return }
            // After the update: becoming first responder during one would re-enter SwiftUI.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, let window = textView.window, self.session.startsEditingWhenShown else { return }
                self.session.startsEditingWhenShown = false
                window.makeFirstResponder(textView)
            }
        }

        /// After the note switched from reading, shows the line that was at the top of the
        /// reading view: a kept editor would otherwise stay where it was itself.
        private func goToReadingPlaceIfSwitched(in textView: NSTextView) {
            guard textView.window != nil, let location = session.takeEditingStartLocation() else { return }
            // The note's start is the top of the view.
            guard location > 0 else {
                pendingJump = nil
                topLineHold.release()
                textView.scroll(NSPoint(x: 0, y: 0))
                return
            }
            pendingJump = .topOfCharacter(location)
            performPendingJumpIfReady(in: textView)
        }

        /// Opens the find bar the command palette asked for, once the editor is on screen.
        private func presentFindIfRequested(in textView: NSTextView) {
            guard session.findRequest != nil, textView.window != nil else { return }
            // After the update: showing the bar during one would re-enter SwiftUI.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, let window = textView.window, let request = self.session.findRequest else { return }
                self.session.findRequest = nil
                window.makeFirstResponder(textView)
                let action: NSTextFinder.Action = request == .findAndReplace ? .showReplaceInterface : .showFindInterface
                let sender = NSMenuItem()
                sender.tag = action.rawValue
                textView.performTextFinderAction(sender)
            }
        }

        // MARK: Jumps

        /// Makes the pending jump once the view is in a window and has a width.
        func performPendingJumpIfReady(in textView: NSTextView) {
            guard let jump = pendingJump, textView.window != nil, textView.bounds.width > 0 else { return }
            pendingJump = nil
            topLineHold.release()
            let textLength = textView.textStorage?.length ?? 0
            switch jump {
            case .heading(let anchor, let occurrence):
                guard let lineLocation = HeadingLocator.lineLocation(ofHeadingWithAnchor: anchor, occurrence: occurrence, in: currentSource(of: textView)) else { return }
                unfoldSections(hiding: lineLocation, in: textView)
                textView.setSelectedRange(NSRange(location: lineLocation, length: 0))
                scrollToTop(of: lineLocation, in: textView)
            case .textRange(let range):
                guard NSMaxRange(range) <= textLength else { return }
                unfoldSections(hiding: range.location, in: textView)
                // Selecting the match marks it, as a search does on the Mac.
                textView.setSelectedRange(range)
                scrollToTop(of: (currentSource(of: textView)).lineRange(for: NSRange(location: range.location, length: 0)).location, in: textView)
            case .topOfCharacter(let characterLocation):
                scrollToTop(of: min(characterLocation, textLength), in: textView)
            }
        }

        /// Brings a character's line to the top of the view, or as near as the note's end allows.
        /// - Parameter distanceBelowTop: How far below the view's top the line's top goes.
        func scrollToTop(of characterLocation: Int, distanceBelowTop: CGFloat = 12, in textView: NSTextView) {
            guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
                  let location = contentManager.location(contentManager.documentRange.location, offsetBy: characterLocation),
                  let precedingRange = NSTextRange(location: contentManager.documentRange.location, end: location) else { return }
            // Positions before the line must be real, not estimated, for the jump to land. The
            // view's height follows the layout only when the viewport is laid out, and a
            // scroll past its current height would stop short.
            textLayoutManager.ensureLayout(for: precedingRange)
            textLayoutManager.textViewportLayoutController.layoutViewport()
            guard let fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            textView.scroll(NSPoint(x: 0, y: max(0, fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y - distanceBelowTop)))
        }

        /// Lets the session ask where the editor is, as a tab closes or Graphite leaves the
        /// screen, while the editor shows the note. A pending jump has not landed yet, and is
        /// the place.
        func reportPlace(of textView: NSTextView) {
            session.recordEditorPlace = { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, self.pendingJump == nil else { return }
                self.recordScrollLocation(of: textView)
            }
        }

        /// How far, in points, the clip view's alignment to device pixels can move a scroll position.
        private static let scrollAlignmentAllowance: CGFloat = 1

        /// Remembers the character at the top of the view in the session. While the editor
        /// waits for a new width to settle, that is the line it will return to.
        func recordScrollLocation(of textView: NSTextView) {
            if let heldLocation = topLineHold.heldLocation {
                session.savedScrollLocation = heldLocation
                return
            }
            guard textView.visibleRect.minY > 1 else {
                session.savedScrollLocation = nil
                return
            }
            guard let location = topCharacter(of: textView) else { return }
            session.savedScrollLocation = location
        }

        /// The first character of the line at the top of the view; nil at the note's top,
        /// which needs no return to.
        func topCharacter(of textView: NSTextView) -> Int? {
            topLine(of: textView)?.location
        }

        /// The line at the top of the view, and how far below the view's top its own top is
        /// (negative when it starts above): `scrollToTop` with that distance puts the view back
        /// exactly where it was.
        func topLine(of textView: NSTextView) -> (location: Int, distanceBelowTop: CGFloat)? {
            let visibleTop = textView.visibleRect.minY
            guard visibleTop > 1 else { return nil }
            // `scrollToTop` puts a line 12 points below the top, but the clip view then aligns its
            // origin to whole device pixels: up to a point earlier on a display of one pixel to the
            // point, which would put the probe in the line above. The allowance keeps it in the line.
            let probeY = visibleTop + 12 + Self.scrollAlignmentAllowance - textView.textContainerOrigin.y
            guard let textLayoutManager = textView.textLayoutManager, let contentManager = textLayoutManager.textContentManager,
                  let fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: probeY)) else { return nil }
            let location = contentManager.offset(from: contentManager.documentRange.location, to: fragment.rangeInElement.location)
            return (location, fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y - visibleTop)
        }
    }
}
#endif
