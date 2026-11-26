/**
 * File: NativeMarkdownEditor.swift
 * --------------------------------
 * Layer: UI
 * Description: The iPad's and iPhone's note editor (UITextView) with its coordinator; the Mac's is NativeMarkdownEditorMac.swift.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.82
 * Date: 26/11/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

#if canImport(UIKit)
import UIKit

/// The target of an undo action the iPad's editor registers itself; see `replaceCharacters`.
final class UndoActionToken {}

struct NativeMarkdownEditor: UIViewRepresentable {
    @Bindable var session: MarkdownSession
    let configuration: EditorConfiguration
    var environment: LivePreviewEnvironment?
    let headingScrollRequest: HeadingScrollRequest?
    var actions = EditorActions()
    let follow: (String, Bool) -> Void
    /// Keeps this editor, with its undo history, after it leaves the screen; see
    /// `MarkdownEditorRetention`. Without it the editor is torn down when hidden.
    var retention: MarkdownEditorRetention?
    /// The tab the note is open in, which decides whether a kept editor is still wanted.
    var retentionOwner: TabDocument?
    var readAloudRange: NSRange?
    var followsReading = false
    var suspendReadingFollow: (() -> Void)?
    var readAloudHooks: ReadAloudEditorHooks?
    /// The Color, Format, Paragraph and Insert submenus of the edit menu; see `EditorContextMenuContent`.
    var contextMenu: EditorContextMenuActions?
    /// The vault's editing shortcuts.
    var keyCommandTable: EditorKeyCommandTable
    @Environment(\.linkPreviews) private var linkPreviews

    init(session: MarkdownSession, configuration: EditorConfiguration, environment: LivePreviewEnvironment? = nil,
         headingScrollRequest: HeadingScrollRequest?, actions: EditorActions = EditorActions(),
         retention: MarkdownEditorRetention? = nil, retentionOwner: TabDocument? = nil, readAloudRange: NSRange? = nil,
         followsReading: Bool = false, suspendReadingFollow: (() -> Void)? = nil, readAloudHooks: ReadAloudEditorHooks? = nil,
         contextMenu: EditorContextMenuActions? = nil, keyCommandTable: EditorKeyCommandTable = .defaults, follow: @escaping (String, Bool) -> Void) {
        self.contextMenu = contextMenu
        self.keyCommandTable = keyCommandTable
        self.session = session
        self.configuration = configuration
        self.environment = environment
        self.headingScrollRequest = headingScrollRequest
        self.actions = actions
        self.retention = retention
        self.retentionOwner = retentionOwner
        self.readAloudRange = readAloudRange
        self.followsReading = followsReading
        self.suspendReadingFollow = suspendReadingFollow
        self.readAloudHooks = readAloudHooks
        self.follow = follow
    }

    func makeCoordinator() -> Coordinator {
        if let retention, let retentionOwner, let keptEditor = retention.takeEditor(for: session, owner: retentionOwner) as? Coordinator {
            return keptEditor
        }
        return Coordinator(session: session, configuration: configuration)
    }

    func makeUIView(context: Context) -> MarkdownEditorContainerView {
        let container = MarkdownEditorContainerView()
        let coordinator = context.coordinator
        coordinator.retention = retention
        coordinator.retentionOwner = retentionOwner
        if coordinator.textView == nil {
            let textView = makeTextView(coordinator: coordinator)
            coordinator.textView = textView
            container.host(textView)
        }
        coordinator.viewWasMade(with: container)
        retention?.editorDidAttach(coordinator)
        return container
    }

    private func makeTextView(coordinator: Coordinator) -> MarkdownTextView {
        let textView = MarkdownTextView()
        coordinator.environment = environment
        coordinator.follow = follow
        textView.textLayoutManager?.delegate = coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.spellCheckingType = configuration.usesSpellChecking ? .yes : .no
        textView.accessibilityLabel = "Markdown note"
        // The system's find and replace bar, opened with ⌘F or the toolbar.
        textView.isFindInteractionEnabled = true
        textView.addInteraction(UIPencilInteraction(delegate: coordinator))
        coordinator.actions = actions
        textView.runCommand = { [weak coordinator, weak textView] command in
            guard let coordinator, let textView else { return }
            coordinator.run(command, in: textView)
        }
        coordinator.updateKeyboardToolbar(of: textView)
        textView.completion = session.completion
        textView.dismissCompletion = { [weak coordinator] in coordinator?.dismissCompletion() }
        textView.isCursorOnLink = { [weak coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            return coordinator.link(atCharacter: textView.selectedRange.location, in: textView, skipsShownMarkup: false) != nil
        }
        textView.textRevision = { [weak coordinator] in coordinator?.textRevision ?? 0 }
        textView.reportUnreadableItem = { [weak coordinator] in coordinator?.session.errorMessage = NativeMarkdownEditor.unreadableItemMessage }
        textView.currentVaultRoot = session.vaultRoot
        coordinator.updateInsertionHandlers(of: textView)
        textView.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        // Anything another app drags (Photos, Files, Messages, Mail, a school's app) can be
        // dropped into the note: files of any kind, pictures, items from the sidebar, and text
        // and links, which `insertDroppedItems` hands back to the text view.
        textView.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
            UTType.item.identifier, UTType.content.identifier, UTType.data.identifier,
        ])
        session.completion.performEdits = { [weak coordinator, weak textView] edits in
            guard let coordinator, let textView else { return false }
            return coordinator.performCompletionEdits(edits, in: textView)
        }
        textView.usesReadableLineLength = configuration.usesReadableLineLength
        // The theme's line width, plus the text container's padding on each side.
        textView.readableColumnWidth = configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownTextView.readableColumnWidth
        // The theme's inline title (Phase 3), else the text font at 1.75 times, semibold.
        textView.inlineTitle = configuration.inlineTitle.map { title in
            (title, InlineTitleStyle.font(textSize: configuration.textSize, typography: configuration.typography, theme: configuration.theme),
             configuration.theme?.inlineTitleColor ?? .label)
        }
        // The text and the saved cursor go in before the delegate: setting the text places
        // the cursor at its end, which the delegate would otherwise record as the note's.
        textView.text = session.text
        coordinator.lastSynchronizedText = session.text
        let textLength = (session.text as NSString).length
        let cursorLocation = min(session.selection.location, textLength)
        textView.selectedRange = NSRange(location: cursorLocation, length: min(session.selection.length, textLength - cursorLocation))
        textView.delegate = coordinator
        // Drags of the text carry their section (`MarkdownEditorSectionDrag`); dropped back in the note they move it (`MarkdownEditorTextMove`).
        coordinator.takeDragsAndDrops(of: textView)
        coordinator.observeCharacterEdits(in: textView)
        coordinator.observeMemoryWarnings()
        session.undoAvailability.follow(textView.undoManager)
        textView.willChangeWidth = { [weak coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.rememberTopLineBeforeWidthChange(of: textView)
        }
        textView.revealFoundText = { [weak coordinator, weak textView] range in
            guard let coordinator, let textView else { return }
            coordinator.revealFoundText(range, in: textView)
        }
        textView.didClearFoundText = { [weak coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            coordinator.endRevealingFoundText(in: textView)
        }
        textView.didLayout = { [weak coordinator] layoutView in
            coordinator?.returnToScrollLocationIfWidthChangedWhileHidden(in: layoutView)
            coordinator?.schedulePendingJumpIfReady(in: layoutView)
            coordinator?.positionWidgets(in: layoutView)
            coordinator?.positionFoldButtons(in: layoutView)
            coordinator?.layOutViewportAgainIfShort(in: layoutView)
            coordinator?.placeWidgetsAfterWidthChange(in: layoutView)
        }
        textView.didMoveIntoWindow = { [weak coordinator] windowedView in
            coordinator?.startEditingIfRequested(in: windowedView)
            coordinator?.presentFindIfRequested(in: windowedView)
            coordinator?.selectIfRequested(in: windowedView)
            coordinator?.goToReadingPlaceIfSwitched(in: windowedView)
        }
        if let savedScrollLocation = session.savedScrollLocation { coordinator.pendingJump = .topOfCharacter(savedScrollLocation) }
        session.isEditorAttached = true
        coordinator.reportPlace(of: textView)
        coordinator.installTouchRecognizers(on: textView)
        coordinator.installQuickFontSizePinch(on: textView)
        coordinator.rebuildBlocks(in: textView)
        coordinator.restyleEverything(in: textView)
        coordinator.styledInterfaceStyle = textView.traitCollection.userInterfaceStyle
        // Rendered blocks and drawn replacements take their colors from the appearance.
        textView.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak coordinator] (changedView: MarkdownTextView, _: UITraitCollection) in
            coordinator?.appearanceDidChange(in: changedView)
        }
        return textView
    }

    func updateUIView(_ container: MarkdownEditorContainerView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = container.textViewShownHere else {
            // An earlier view of this note still shows the text view; this view's state
            // reaches the editor when the text view moves here.
            container.updateWhenTextViewArrives = { [self] arrivedTextView in update(arrivedTextView, coordinator: coordinator) }
            return
        }
        update(textView, coordinator: coordinator)
    }

    private func update(_ textView: MarkdownTextView, coordinator: Coordinator) {
        coordinator.session = session
        textView.readAloudRange = readAloudRange
        textView.keyCommandTable = keyCommandTable
        textView.followsReading = followsReading
        coordinator.suspendReadingFollow = suspendReadingFollow
        coordinator.installReadAloudHooks(readAloudHooks, in: textView)
        if coordinator.linkPreviews.use(linkPreviews, sourceNote: session.path) { coordinator.watchPointerForLinks(in: textView) }
        coordinator.contextMenu = contextMenu
        let previousBlockPolicy = coordinator.renderedBlockPolicy
        coordinator.environment = environment
        coordinator.follow = follow
        coordinator.actions = actions
        coordinator.updateInsertionHandlers(of: textView)
        coordinator.updateKeyboardToolbar(of: textView)
        coordinator.quickFontSizePinch?.adjustment = actions.quickFontSize
        textView.convertsPastedHTML = configuration.editingBehavior.convertsPastedHTML
        textView.usesReadableLineLength = configuration.usesReadableLineLength
        // The theme's line width, plus the text container's padding on each side.
        textView.readableColumnWidth = configuration.theme?.readableColumnWidth(forTextSize: configuration.textSize).map { width in width + 10 } ?? MarkdownTextView.readableColumnWidth
        // The theme's inline title (Phase 3), else the text font at 1.75 times, semibold.
        textView.inlineTitle = configuration.inlineTitle.map { title in
            (title, InlineTitleStyle.font(textSize: configuration.textSize, typography: configuration.typography, theme: configuration.theme),
             configuration.theme?.inlineTitleColor ?? .label)
        }
        textView.spellCheckingType = configuration.usesSpellChecking ? .yes : .no
        // Turning the Properties view on or off changes which blocks are rendered, as the
        // configuration can.
        if coordinator.configuration != configuration || coordinator.renderedBlockPolicy != previousBlockPolicy {
            let topCharacter = coordinator.topCharacter(of: textView)
            coordinator.configuration = configuration
            coordinator.rebuildBlocks(in: textView, forcesBlockScan: true)
            coordinator.restyleEverything(in: textView)
            // Source of another height takes the place of the blocks, or the text resizes;
            // the view stays on the line it showed, not at the same distance from the top.
            if let topCharacter, coordinator.pendingJump == nil { coordinator.pendingJump = .topOfCharacter(topCharacter) }
        }
        // Rendered blocks already on screen show the new settings, index state, files and
        // accent in place, keeping their own state (such as a base's chosen view). A changed
        // file reaches them too: each looks its files up again and keeps showing what it
        // shows until then. Rebuilding them blanked every drawing in the note for a few
        // frames after each save, since the system reports the note's own save as a change.
        coordinator.refreshWidgets(for: LivePreviewWidgetSignature(environment: environment, accentHex: configuration.accentHex, notePath: session.path.rawValue),
                                   in: textView)
        let hasAppliedInsertion = coordinator.applyPendingInsertions(to: textView)
        if !hasAppliedInsertion, session.text != coordinator.lastSynchronizedText, textView.markedTextRange == nil {
            // The file changed on disk, or properties were edited from a rendered view.
            coordinator.replaceText(with: session.text, in: textView)
        }
        if session.foldedKeys != coordinator.appliedFoldedKeys { coordinator.applyFolds(in: textView) }
        coordinator.startEditingIfRequested(in: textView)
        coordinator.presentFindIfRequested(in: textView)
        coordinator.selectIfRequested(in: textView)
        if let headingScrollRequest, headingScrollRequest.token != session.handledHeadingScrollToken {
            session.handledHeadingScrollToken = headingScrollRequest.token
            // A jump replaces the return to where the note was left.
            if let textRange = headingScrollRequest.textRange {
                coordinator.pendingJump = .textRange(textRange)
            } else {
                coordinator.pendingJump = .heading(anchor: headingScrollRequest.anchor, occurrence: headingScrollRequest.occurrence)
            }
        }
        coordinator.performPendingJumpIfReady(in: textView)
    }

    static func dismantleUIView(_ container: MarkdownEditorContainerView, coordinator: Coordinator) {
        coordinator.viewWasDismantled(with: container)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate, NSTextLayoutManagerDelegate, RetainableMarkdownEditor,
                             UIPencilInteractionDelegate {
        var session: MarkdownSession
        /// The text view this coordinator styles and edits through. It lives as long as the
        /// coordinator, which a hidden note's retention can keep beyond its SwiftUI view.
        var textView: MarkdownTextView?
        weak var retention: MarkdownEditorRetention?
        weak var retentionOwner: TabDocument?
        /// The containers of the SwiftUI views that show this note.
        private var containersInUse = EditorContainersInUse<MarkdownEditorContainerView>()
        /// Set while a dismantled view lets go of the text view; see `viewWasDismantled`.
        private var isLettingGoOfTextView = false
        /// The text view's width when it left the screen; a new width reflows the note,
        /// so it returns to its top line rather than to the old pixel offset.
        private var widthWhenHidden: CGFloat?
        /// The text's styling, markup revealed at the selection, and rendered blocks, shared
        /// with the Mac's editor. Views kept off screen are dropped on a memory warning.
        let styling: MarkdownEditorStyling
        /// The cards of the links the pointer, Apple Pencil hovering or a long press rests on,
        /// as the Mac's editor shows them.
        let linkPreviews = EditorLinkPreviews()
        private var linkHoverRecognizer: UIHoverGestureRecognizer?
        private var linkPressRecognizer: UILongPressGestureRecognizer?
        /// The handle a finger's long press in the margin lifts (`TouchBlockHandles`).
        let blockHandles = TouchBlockHandles()
        var configuration: EditorConfiguration {
            get { styling.configuration }
            set { styling.configuration = newValue }
        }
        var environment: LivePreviewEnvironment? {
            get { styling.environment }
            set { styling.environment = newValue }
        }
        var follow: (String, Bool) -> Void = { _, _ in }
        var appliedInsertionIdentifier: UUID?
        /// Where the view should go once it is in a window and has a width: laying out a
        /// view that has neither measures the note at the wrong width, and the system's find
        /// highlight asserts off-window.
        enum Jump: Equatable {
            /// `occurrence` picks one of several headings that read the same, from zero.
            case heading(anchor: String, occurrence: Int = 0)
            case textRange(NSRange)
            /// Back where the note was left, as when switching tabs. A line can be taller than the
            /// view, with a block's reserved space in it: `distanceIntoLine` is how far into it the top was.
            case topOfCharacter(Int, distanceIntoLine: CGFloat = 0)
        }
        var pendingJump: Jump?
        private var isPendingJumpScheduled = false
        /// Headings and list items that fold, found with the blocks, and the folds last applied.
        let foldTracking = EditorFoldTracking()
        var appliedFoldedKeys: Set<String> {
            get { foldTracking.appliedFoldedKeys }
            set { foldTracking.appliedFoldedKeys = newValue }
        }
        private var foldButtons: [String: (chevron: UIButton, ellipsis: UIButton)] = [:]
        /// Where the cursor was, to tell which way it moved into a folded section.
        private var lastSelectionLocation = 0
        private var foldedRegions: [FoldableRegion] { foldTracking.folded(foldedKeys: session.foldedKeys) }
        /// Set while a second viewport layout is waiting, so layout passes do not ask for more.
        private var isViewportRelayoutPending = false
        /// Set when a layout pass found the viewport short while the relayout above waited, so it looks again after.
        private var hasShortfallWhileRelayoutPending = false
        var actions = EditorActions() {
            // The editor owns the pane's slash commands; the note's suggestions only point at them.
            didSet { session.completion.slashCommands = actions.slashCommands }
        }
        /// The quick font size pinch on the text view, which follows `actions.quickFontSize`.
        var quickFontSizePinch: QuickFontSizePinchRecognizer?
        var suspendReadingFollow: (() -> Void)?
        /// Which optional keyboard toolbar buttons exist; the toolbar is rebuilt when this changes.
        private var keyboardToolbarButtons: KeyboardToolbarButtons?
        /// Set while Graphite changes the text itself, so its own change is not rewritten again.
        private var isPerformingEdit = false
        /// Set while lines move: the folds' keys go with their headers, so folds are not
        /// carried from where the headers were.
        private var isMovingLines = false
        /// Set while an insertion moves the cursor, changes the text, and moves the cursor
        /// again: the insertion restyles the whole note and updates the suggestions once, for
        /// the final cursor, instead of for each step.
        private var isApplyingInsertion = false
        /// The text a drag from this note took, while that drag lasts: dropped back into the
        /// note, it is moved by the editor as one step of the history (`MarkdownEditorTextMove`).
        var textDraggedWithinNote: DraggedNoteText?
        /// The text last given to or taken from the session. Comparing the session's text with
        /// it is instant while nothing else changed the session's text, because both share
        /// one storage; comparing with the text view's text reads the whole note each update.
        var lastSynchronizedText = ""
        /// The text when the composition under way began. UIKit reports each change of marked text,
        /// so a composition reaches the session as it goes while nothing else changed the note. A
        /// change from elsewhere then replaces those first characters too, and what is carried over
        /// when the composition ends is all of it, measured from here (HUNT-063).
        private var textBeforeComposition: String?
        /// The text, its rendered blocks, and the edits styling has not caught up with. Every
        /// character edit reaches it from the text storage before UIKit reports the new
        /// selection, so nothing styles the new text with ranges found in the old one.
        private var textState: LivePreviewTextState { styling.textState }
        /// The markup the styling shows as written; see `RevealedMarkup`.
        private var revealedMarkup: RevealedMarkup? { styling.revealedMarkup }
        /// Whether the text view has keyboard focus; markup is revealed only then.
        private var isEditing = false {
            didSet { styling.revealsMarkupAtSelection = isEditing }
        }
        private var blockEntries: [LivePreviewBlockEntry] { textState.blockEntries }
        private var renderedBlocks: LivePreviewRenderedBlocks { styling.renderedBlocks }
        private var memoryWarningObserver: NSObjectProtocol?
        /// The layout passes that follow one that could not place a rendered block, or moved one.
        private var placementRetries = RenderedBlockPlacementRetries()
        /// Set while blocks are placed again on a viewport laid out for them in the same pass.
        private var isPlacingOnViewportLaidOutNow = false
        /// Makes the views of the blocks just below the screen once the note is still.
        private lazy var lookahead = RenderedBlockLookahead(renderedBlocks: renderedBlocks)
        /// The text column's width when rendered blocks were last placed, and the placement
        /// waiting for a new width to settle.
        private var placedColumnWidth: CGFloat = 0
        private var placementAfterWidthChange: DispatchWorkItem?
        /// The line at the top of the view, and the column's width, before the width began to change.
        private var topLineBeforeWidthChange: (location: Int, columnWidth: CGFloat)?
        /// The appearance the text was last styled for, and the wait for the app to come back.
        var styledInterfaceStyle: UIUserInterfaceStyle = .unspecified
        private var sceneActivationObserver: NSObjectProtocol?
        /// Set while a rendered block shows its source because the find navigator moved into it.
        private var isShowingFoundTextInBlock = false
        /// A heading the view keeps at its top while rendered blocks above it settle their
        /// heights, until they have or until the person scrolls or starts editing.
        private var pinnedHeading: HeadingJumpPin?
        /// Pastes and drops whose content is still loading or saving.
        private var pendingInsertionRequests = PendingInsertionRequests()
        /// The suggestions at the cursor: what they were found for and what plugins heard.
        private var completionTracking = EditorCompletionTracking()
        /// Block views kept off screen, by their estimated memory. At 24 MB the iPad kept about a
        /// third of a 40-section note's 120 block views and built 84 again scrolling back up
        /// (23 to 24 frames of 97 over 16 ms); at 64 MB it builds about 28 (9 to 10 over 16 ms)
        /// for about 40 MB more at the peak (simulator, 2026-10-22). The iPhone has less memory.
        /// A memory warning empties the pool either way.
        private static var detachedViewsBudgetMegabytes: Int { UIDevice.current.userInterfaceIdiom == .pad ? 64 : 32 }

        init(session: MarkdownSession, configuration: EditorConfiguration) {
            self.session = session
            lastSynchronizedText = session.text
            // The properties show their YAML while the cursor is in it, as any block's source.
            styling = MarkdownEditorStyling(configuration: configuration, propertiesSource: .whileTheCursorIsInIt,
                                            detachedViewsBudgetMegabytes: Self.detachedViewsBudgetMegabytes)
            super.init()
            styling.revealsMarkupAtSelection = false
            styling.foldedRegions = { [weak self] in self?.foldedRegions ?? [] }
            // The text view's next layout pass places the rendered blocks and fold buttons.
            styling.didRestyle = { restyledTextView in (restyledTextView as? UIView)?.setNeedsLayout() }
        }

        // MARK: Lifetime

        var editedSession: MarkdownSession { session }
        var retainedTextLength: Int { textView?.textStorage.length ?? 0 }

        /// Takes in the container of a new SwiftUI view of the note. A hidden note's text
        /// view is shown in it at once. A text view that an earlier view still shows stays
        /// there until that view is dismantled: SwiftUI makes the new view in the middle
        /// of its update, where taking the keyboard from the text view made SwiftUI update
        /// again from inside that update, and it can dismantle the new view before the
        /// earlier one. So does a view made while a dismantled one lets go of the text view.
        func viewWasMade(with container: MarkdownEditorContainerView) {
            let isShownInEarlierView = containersInUse.contains { earlierContainer in earlierContainer.textViewShownHere != nil }
            containersInUse.add(container)
            guard let textView, !isShownInEarlierView, !isLettingGoOfTextView, container.textViewShownHere == nil else { return }
            // The same text view, cursor, layout, and undo history as when it was hidden.
            container.host(textView)
            resume(textView)
        }

        /// Lets go of the container of a dismantled SwiftUI view. The text view it showed
        /// moves to the newest view of the note that is left (the split opening or
        /// closing, a tab moved to the other side); with none left, the editor leaves
        /// the screen.
        ///
        /// The keyboard goes first, from the text view or from a view inside it, such as an
        /// embedded PDF or a rendered block's field. Giving it up can lay the window out at
        /// once, and SwiftUI then makes the note's next view in the middle of this
        /// dismantling; that view gets the text view once this one has let it go. Moving it
        /// there while UIKit was still removing it left SwiftUI updating without end (an
        /// iPad, 2026-10-10).
        func viewWasDismantled(with container: MarkdownEditorContainerView) {
            containersInUse.remove(container)
            guard let textView = container.textViewShownHere else { return }
            // The keyboard given up here, by the text view or a view inside it, does not
            // come back to the note.
            textView.refusesFocus = true
            defer { textView.refusesFocus = false }
            isLettingGoOfTextView = true
            textView.endEditing(true)
            if let remainingContainer = containersInUse.newest {
                remainingContainer.host(textView)
                placeWidgetsAgain(in: textView)
                isLettingGoOfTextView = false
                return
            }
            suspend(textView)
            isLettingGoOfTextView = false
            if let containerMadeMeanwhile = containersInUse.newest {
                containerMadeMeanwhile.host(textView)
                resume(textView)
                return
            }
            if retention?.keepHiddenEditor(self, owner: retentionOwner) != true { discardRetainedEditor() }
        }

        /// Takes the editor off screen without ending it: the text view keeps its text,
        /// selection, undo history and the views of its rendered blocks, so going back to
        /// the note shows them without SwiftUI making them again (about 100 to 150 ms for a
        /// note with a table and properties). The retention keeps those views for the most
        /// recently hidden note only (`releaseRenderedViews`). Insertions requested
        /// meanwhile go into the session's text, which the editor adopts as an undoable
        /// edit when it is shown again.
        func suspend(_ textView: MarkdownTextView) {
            // Ends editing first, so leaving editing does not place rendered blocks again.
            textView.endEditing(true)
            session.applyPendingInsertionsBeforeSaving = nil
            session.isEditorAttached = false
            stopObservingCharacterEdits()
            stopObservingMemoryWarnings()
            textView.findInteraction?.dismissFindNavigator()
            recordScrollLocation(of: textView)
            session.recordEditorPlace = nil
            widthWhenHidden = textView.bounds.width
            textView.removeFromSuperview()
            session.undoAvailability.follow(nil)
        }

        /// Shows a suspended editor again, in a new container.
        func resume(_ textView: MarkdownTextView) {
            observeCharacterEdits(in: textView)
            observeMemoryWarnings()
            session.completion.performEdits = { [weak self, weak textView] edits in
                guard let self, let textView else { return false }
                return self.performCompletionEdits(edits, in: textView)
            }
            session.isEditorAttached = true
            session.undoAvailability.follow(textView.undoManager)
            reportPlace(of: textView)
            placeWidgetsAgain(in: textView)
        }

        /// Lets the session ask where the editor is, as Graphite leaves the screen, while the
        /// editor shows the note. A pending jump has not landed yet, and is the place.
        func reportPlace(of textView: MarkdownTextView) {
            session.recordEditorPlace = { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, self.pendingJump == nil else { return }
                self.recordScrollLocation(of: textView)
            }
        }

        /// Ends the editor for good; its undo history goes with the text view. The blocks'
        /// views go first, so none keeps the note's session and the workspace's closures.
        func discardRetainedEditor() {
            removeAllWidgets()
            guard let textView else { return }
            textView.didLayout = nil
            textView.removeFromSuperview()
            self.textView = nil
        }

        /// A kept text view shown at another width (the other side of a split, a rotation
        /// while hidden) returns to the line that was at its top.
        func returnToScrollLocationIfWidthChangedWhileHidden(in textView: MarkdownTextView) {
            guard let widthWhenHidden, textView.window != nil, textView.bounds.width > 0 else { return }
            self.widthWhenHidden = nil
            guard abs(textView.bounds.width - widthWhenHidden) > 0.5, pendingJump == nil,
                  let savedScrollLocation = session.savedScrollLocation else { return }
            pendingJump = .topOfCharacter(savedScrollLocation)
        }

        // MARK: Apple Pencil

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            guard let textView else { return }
            handlePencilDoubleTap(hoverLocation: tap.hoverPose?.location, in: textView)
        }

        /// Starts a drawing, at the hovering Pencil's place in the text when it hovers, else
        /// at the cursor. The iPadOS setting to ignore double-tap is honored.
        func handlePencilDoubleTap(hoverLocation: CGPoint?, in textView: MarkdownTextView,
                                   preferredTapAction: UIPencilPreferredAction = UIPencilInteraction.preferredTapAction) {
            guard preferredTapAction != .ignore else { return }
            startDrawingAtPencil(hoverLocation: hoverLocation, in: textView)
        }

        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended, let textView else { return }
            handlePencilSqueeze(hoverLocation: squeeze.hoverPose?.location, in: textView)
        }

        /// A squeeze of Apple Pencil Pro starts a drawing as a double-tap does, when iPadOS
        /// leaves the squeeze to the app to show its tools; a note's tools are its drawing.
        func handlePencilSqueeze(hoverLocation: CGPoint?, in textView: MarkdownTextView,
                                 preferredSqueezeAction: UIPencilPreferredAction = UIPencilInteraction.preferredSqueezeAction) {
            guard preferredSqueezeAction == .showContextualPalette else { return }
            startDrawingAtPencil(hoverLocation: hoverLocation, in: textView)
        }

        private func startDrawingAtPencil(hoverLocation: CGPoint?, in textView: MarkdownTextView) {
            // Apple Pencil's double-tap and squeeze reach every Pencil interaction in the
            // window, so one made in the drawing editor reaches the note under it too;
            // answering it would replace the open drawing, unsaved strokes and all.
            guard let drawOnPencilDoubleTap = actions.drawOnPencilDoubleTap, textView.window != nil,
                  !textView.isCoveredByPresentedScreen else { return }
            if let hoverLocation, let position = textView.closestPosition(to: hoverLocation) {
                let offset = textView.offset(from: textView.beginningOfDocument, to: position)
                textView.selectedRange = NSRange(location: offset, length: 0)
                session.selection = textView.selectedRange
            }
            drawOnPencilDoubleTap()
        }

        private var isLivePreview: Bool { styling.rendersBlocks }
        /// What decides which blocks are rendered besides the configuration: plugins that
        /// register a code block language later have their blocks found again.
        var renderedBlockPolicy: [String] { styling.renderedBlockPolicy }
        var textRevision: Int { textState.history.revision }
        /// Whether the text state describes the text on screen, not the text before an edit in progress.
        var hasSettledText: Bool { !textState.cachesDescribeOldText }

        // MARK: Character edits

        /// Follows every change to the text view's characters. The text storage reports a
        /// change before UIKit's selection callback runs against the new text, and on paths
        /// that never call `shouldChangeTextIn`: `insertText`, `replace(_:withText:)`,
        /// Backspace, undo and redo, find and replace, and setting the text.
        func observeCharacterEdits(in textView: UITextView) {
            session.applyPendingInsertionsBeforeSaving = { [weak self, weak textView] in
                guard let self, let textView else { return }
                _ = self.applyPendingInsertions(to: textView)
            }
            // UIKit reports `textViewDidChange` after its own edits and Graphite settles its
            // own; this catches a path that does neither, once UIKit's edit is done.
            styling.observeCharacterEdits(in: textView) { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.textViewDidChange(textView)
            }
        }

        func stopObservingCharacterEdits() {
            styling.stopObservingCharacterEdits()
        }

        func observeMemoryWarnings() {
            memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                           object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.renderedBlocks.dropDetachedViews() }
            }
        }

        func stopObservingMemoryWarnings() {
            if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
            memoryWarningObserver = nil
        }

        /// The text as an immutable snapshot: reading `UITextView.text` copies the whole note.
        func currentSource(of textView: UITextView) -> NSString {
            styling.currentSource(of: textView)
        }

        /// Whether blocks, folds, and the revealed markup describe the text on screen, so
        /// they can be styled or acted on.
        private func canStyle(_ textView: UITextView) -> Bool {
            styling.canStyle(textView)
        }

        // MARK: Styling

        func rebuildBlocks(in textView: UITextView, forcesBlockScan: Bool = false) {
            let edit = textState.editSinceBlockScan
            styling.updateTextState(of: textView, forcesBlockScan: forcesBlockScan)
            // The snapshot the blocks were found in, which the next edit names as the text
            // before it: the folds move with that edit only if they were found in the same one.
            let source = textState.source
            foldTracking.update(source: source, editSinceLastUpdate: edit)
            styling.revealMarkupAtSelection(of: textView)
        }

        func restyleEverything(in textView: UITextView) {
            appliedFoldedKeys = session.foldedKeys
            // The pending edit is styled with the rest, so its blocks and folds must describe the text.
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            styling.restyleEverything(in: textView)
        }

        private func restyle(_ range: NSRange, in textView: UITextView) {
            styling.restyle(range, in: textView)
        }

        /// Brings blocks and styling up to date after character edits. The blocks follow the
        /// text even while an IME composes, so they never describe older text; styling waits
        /// for the composition to end, because it would disturb the marked text.
        private func settleTextChange(in textView: UITextView) {
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            guard textView.markedTextRange == nil else { return }
            // A fold that moved to an edited line, or whose hidden text changed, restyles the
            // whole note rather than leaving the old section's lines hidden.
            if carryFoldsAcrossEdit(in: textView) {
                restyleEverything(in: textView)
                styling.restyleBlocksAwaitingRestyle(in: textView)
                return
            }
            styling.restyleUnstyledEdit(in: textView)
        }

        /// The blocks whose source is concealed under their views, in note order: every block
        /// the cursor is not in, all of them while the note is only read, and none that a
        /// folded section hides.
        private func concealedEntries(in textView: UITextView) -> [LivePreviewBlockEntry] {
            styling.concealedEntries(in: textView)
        }

        // MARK: Editing

        /// Puts the cursor in a note just created, as Obsidian does, once the editor is on screen.
        func startEditingIfRequested(in textView: MarkdownTextView) {
            guard session.startsEditingWhenShown, textView.window != nil else { return }
            // After the update: becoming first responder during one would re-enter SwiftUI.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, self.session.startsEditingWhenShown else { return }
                self.session.startsEditingWhenShown = false
                textView.beginEditing()
            }
        }

        /// After the note switched from reading, shows the line that was at the top of the
        /// reading view: a kept editor would otherwise return to where it was itself.
        func goToReadingPlaceIfSwitched(in textView: MarkdownTextView) {
            guard textView.window != nil, let location = session.takeEditingStartLocation() else { return }
            // The note's start is the top of the view, with the inline title above the text.
            guard location > 0 else {
                pendingJump = nil
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: -textView.adjustedContentInset.top), animated: false)
                return
            }
            pendingJump = .topOfCharacter(location)
            performPendingJumpIfReady(in: textView)
        }

        /// Opens the find bar the command palette asked for, once the editor is on screen.
        func presentFindIfRequested(in textView: MarkdownTextView) {
            guard session.findRequest != nil, textView.window != nil else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, let request = self.session.findRequest else { return }
                self.session.findRequest = nil
                textView.findInteraction?.presentFindNavigator(showingReplace: request == .findAndReplace)
            }
        }

        /// Moves the cursor where a plugin put it without changing the text, once the editor
        /// is on screen; after the update, as selecting reports back to the session.
        func selectIfRequested(in textView: MarkdownTextView) {
            guard session.selectionRequest != nil, textView.window != nil else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.window != nil, let range = self.session.selectionRequest else { return }
                self.session.selectionRequest = nil
                let length = textView.textStorage.length
                let selection = CommunityPluginEditorChange.selection(anchor: range.location, head: NSMaxRange(range), inTextOfLength: length)
                textView.selectedRange = selection
                textView.scrollRangeToVisible(selection)
            }
        }

        /// Applies every insertion waiting in the session, in order, and tells whether there
        /// was any. Several can be queued between updates, such as images dropped together;
        /// each apply removes its insertion from the queue.
        func applyPendingInsertions(to textView: UITextView) -> Bool {
            var hasAppliedInsertion = false
            while let insertion = session.pendingInsertion, insertion.id != appliedInsertionIdentifier {
                apply(insertion, to: textView)
                hasAppliedInsertion = true
            }
            return hasAppliedInsertion
        }

        func apply(_ insertion: EditorInsertion, to textView: UITextView) {
            appliedInsertionIdentifier = insertion.id
            // Restyling the whole note re-estimates TextKit's layout, which would otherwise
            // leave the view somewhere else in the note; the edit happens where the person is.
            let contentOffset = textView.contentOffset
            defer {
                textView.layoutIfNeeded()
                textView.setContentOffset(contentOffset, animated: false)
                keepSelectionVisible(in: textView)
            }
            let source = currentSource(of: textView)
            var insertionText = insertion.text
            var insertionRange = insertion.range
            var selectionAfter = insertion.selectionAfter
            // A paste or drop prepared its block for the place it asked for.
            let pendingRequest = insertion.selectionAfter == nil ? pendingInsertionRequests.take(preparedFor: insertion.range, in: textState.history) : nil
            if let movedRange = pendingRequest?.currentTarget(in: textState.history), movedRange != insertion.range {
                // The note changed while a paste or drop was loading and saving: the block
                // goes where the person put it, with the line breaks that place needs.
                (insertionText, insertionRange) = MovedBlockInsertion.insertion(of: insertion.text, movedTo: movedRange, in: source)
                selectionAfter = nil
            }
            let safeLocation = min(insertionRange.location, source.length)
            isApplyingInsertion = true
            textView.selectedRange = NSRange(location: safeLocation, length: min(insertionRange.length, source.length - safeLocation))
            // insertText keeps the insertion on the native undo stack.
            isPerformingEdit = true
            textView.insertText(insertionText)
            isPerformingEdit = false
            // insertText leaves the cursor after the inserted text.
            if let pendingRequest {
                pendingInsertionRequests.placeRemainingItems(of: pendingRequest, after: textView.selectedRange.location, at: textRevision)
            }
            if let selectionAfter, NSMaxRange(selectionAfter) <= textView.textStorage.length {
                textView.selectedRange = selectionAfter
            }
            isApplyingInsertion = false
            if textState.cachesDescribeOldText { rebuildBlocks(in: textView) }
            restyleEverything(in: textView)
            publish(textView)
            updateCompletion(in: textView)
            // Consumed synchronously: a recreated editor must never apply it a second time.
            session.markInsertionApplied(insertion)
        }

        /// Hands pastes and drops to the pane's actions, remembering where each asked to go.
        func updateInsertionHandlers(of textView: MarkdownTextView) {
            textView.insertAttachment = actions.insertAttachment == nil ? nil : { [weak self] data, stem, fileExtension, request in
                guard let self, let insertAttachment = self.actions.insertAttachment else { return }
                self.pendingInsertionRequests.remember(request)
                insertAttachment(data, stem, fileExtension, request.range)
            }
            textView.offerPasteToPlugins = actions.pluginPaste
            textView.offerDropToPlugins = actions.pluginDrop
            textView.insertLinkToVaultFile = actions.insertLinkToVaultFile == nil ? nil : { [weak self] path, request in
                guard let self, let insertLinkToVaultFile = self.actions.insertLinkToVaultFile else { return }
                self.pendingInsertionRequests.remember(request)
                insertLinkToVaultFile(path, request.range)
            }
        }

        /// The keyboard toolbar's optional buttons.
        struct KeyboardToolbarButtons: Equatable {
            let attach, choosePhoto, takePhoto, scanDocument, newNotebook, draw: Bool
        }

        /// Builds the keyboard toolbar again when its optional buttons change, such as when
        /// Drawings is turned on or off while the note is open. Its buttons call the pane's
        /// current actions, not the ones from when the toolbar was built.
        func updateKeyboardToolbar(of textView: MarkdownTextView) {
            let buttons = KeyboardToolbarButtons(attach: actions.attach != nil, choosePhoto: actions.choosePhoto != nil,
                                                 takePhoto: actions.takePhoto != nil, scanDocument: actions.scanDocument != nil,
                                                 newNotebook: actions.newNotebook != nil, draw: actions.draw != nil)
            guard buttons != keyboardToolbarButtons else { return }
            keyboardToolbarButtons = buttons
            var toolbarActions = EditorActions()
            if buttons.attach { toolbarActions.attach = { [weak self] in self?.actions.attach?() } }
            if buttons.choosePhoto { toolbarActions.choosePhoto = { [weak self] in self?.actions.choosePhoto?() } }
            if buttons.takePhoto { toolbarActions.takePhoto = { [weak self] in self?.actions.takePhoto?() } }
            if buttons.scanDocument { toolbarActions.scanDocument = { [weak self] in self?.actions.scanDocument?() } }
            if buttons.newNotebook { toolbarActions.newNotebook = { [weak self] in self?.actions.newNotebook?() } }
            if buttons.draw { toolbarActions.draw = { [weak self] in self?.actions.draw?() } }
            textView.makeKeyboardToolbar = { [weak self, weak textView] in
                EditorKeyboardToolbar(actions: toolbarActions) { command in
                    guard let self, let textView else { return }
                    self.run(command, in: textView)
                }
            }
            if textView.isFirstResponder { textView.reloadInputViews() }
        }

        /// Replaces characters as one change that can be undone. Through the text view while
        /// it has the keyboard; otherwise in its text storage, with the undo registered here:
        /// `replace(_:withText:)` on a text view without the keyboard ran the system's smart
        /// dashes over the whole note though they are off for it (iOS 27), so writing one cell
        /// of a table turned every `---` of its delimiter row, and of the frontmatter, into `—`.
        func replaceCharacters(in range: NSRange, with replacement: String, in textView: UITextView) {
            guard NSMaxRange(range) <= textView.textStorage.length else { return }
            if textView.isFirstResponder,
               let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
               let end = textView.position(from: start, offset: range.length),
               let textRange = textView.textRange(from: start, to: end) {
                textView.replace(textRange, withText: replacement)
                return
            }
            let replacedText = (textView.textStorage.string as NSString).substring(with: range)
            let restoredRange = NSRange(location: range.location, length: (replacement as NSString).length)
            // The undo manager does not keep its target alive, and can outlive this editor; the
            // handler keeps its own token, and does nothing once the editor is gone.
            let undoToken = UndoActionToken()
            textView.undoManager?.registerUndo(withTarget: undoToken) { [weak self, weak textView, undoToken] _ in
                withExtendedLifetime(undoToken) {}
                guard let self, let textView else { return }
                // Undoing registers the redo in turn.
                self.isPerformingEdit = true
                self.replaceCharacters(in: restoredRange, with: replacedText, in: textView)
                self.isPerformingEdit = false
                self.textViewDidChange(textView)
            }
            let attributes = textView.textStorage.length > 0
                ? textView.textStorage.attributes(at: min(range.location, textView.textStorage.length - 1), effectiveRange: nil)
                : textView.typingAttributes
            textView.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }

        /// Puts a new text in place by replacing only what differs, through the text view,
        /// so the change joins the undo history instead of clearing it, and the cursor
        /// stays on the same character.
        func replaceText(with newText: String, in textView: UITextView) {
            textBeforeComposition = nil
            let oldSource = NSString(string: textView.textStorage.string)
            let newSource = newText as NSString
            guard let (replacedRange, replacementRange) = TextDifference.changedRanges(from: oldSource, to: newSource) else {
                lastSynchronizedText = newText
                return
            }
            let edit = CharacterEdit(editedRange: replacementRange, changeInLength: newSource.length - oldSource.length)
            let selection = TextRangeMapping.insertionTarget(textView.selectedRange, through: edit)
            // Text another app changed, adopted as Graphite comes back to the screen, must not
            // move the note under the reader, as an insertion does not (`apply(_:to:)`).
            let contentOffset = textView.contentOffset
            isPerformingEdit = true
            replaceCharacters(in: replacedRange, with: newSource.substring(with: replacementRange), in: textView)
            isPerformingEdit = false
            if NSMaxRange(selection) <= textView.textStorage.length { textView.selectedRange = selection }
            if let textLayoutManager = textView.textLayoutManager {
                textView.layoutIfNeeded()
                let maximumOffset = maximumContentOffset(of: textView, layoutManager: textLayoutManager)
                textView.setContentOffset(CGPoint(x: contentOffset.x, y: min(max(contentOffset.y, -textView.adjustedContentInset.top), maximumOffset)), animated: false)
            }
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
        }

        /// Obsidian's typing helpers, the same on the Mac.
        private func smartEdit(replacing range: NSRange, with replacement: String, in textView: UITextView) -> MarkdownTextEdit? {
            configuration.editingBehavior.typingEdit(replacing: range, with: replacement, in: currentSource(of: textView), selection: textView.selectedRange)
        }

        /// Where the frontmatter ends while it is rendered as properties.
        private var renderedPropertiesEnd: Int? {
            guard styling.rendersProperties, !textState.cachesDescribeOldText else { return nil }
            let frontmatter = textState.blockEntries.first { entry in entry.block.kind == .frontmatter && entry.range.location == 0 }
            return frontmatter.map { entry in NSMaxRange(entry.range) }
        }

        /// Makes an edit through the text view, so it joins the undo history.
        func perform(_ edit: MarkdownTextEdit, in textView: UITextView) {
            let length = textView.textStorage.length
            guard NSMaxRange(edit.range) <= length else { return }
            if edit.range.length > 0 || !edit.replacement.isEmpty {
                isPerformingEdit = true
                replaceCharacters(in: edit.range, with: edit.replacement, in: textView)
                isPerformingEdit = false
            }
            if NSMaxRange(edit.selectionAfter) <= textView.textStorage.length { textView.selectedRange = edit.selectionAfter }
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
            keepSelectionVisible(in: textView)
            textView.setNeedsLayout()
        }

        /// Several edits made at once, such as a link and the `^id` it points to. Each is
        /// written against the original text; the last one's selection is kept.
        func perform(_ edits: [MarkdownTextEdit], in textView: UITextView) {
            guard let primary = edits.last else { return }
            var selectionShift = 0
            for edit in edits.sorted(by: { leftEdit, rightEdit in leftEdit.range.location > rightEdit.range.location }) {
                perform(MarkdownTextEdit(range: edit.range, replacement: edit.replacement, selectionAfter: edit.selectionAfter), in: textView)
                if edit != primary, edit.range.location < primary.range.location { selectionShift += edit.replacement.utf16.count - edit.range.length }
            }
            let selection = NSRange(location: primary.selectionAfter.location + selectionShift, length: primary.selectionAfter.length)
            if NSMaxRange(selection) <= textView.textStorage.length { textView.selectedRange = selection }
        }

        /// An accepted suggestion's edits, which arrive after finding what to insert (and,
        /// for a block link, writing its `^id`). They were made for the text the suggestions
        /// were found in, so they move past what was typed meanwhile. When that typing
        /// changed the text they replace, none are made: a link without its `^id`, or a
        /// query replaced in the middle of new text, would corrupt the note.
        @discardableResult
        func performCompletionEdits(_ edits: [MarkdownTextEdit], in textView: UITextView) -> Bool {
            completionTracking.recordAcceptedSuggestion(isListOpen: session.completion.context != nil)
            guard let movedEdits = completionTracking.editsMovedPastTyping(edits, history: textState.history) else {
                session.errorMessage = EditorCompletionTracking.noteChangedMessage
                return false
            }
            perform(movedEdits, in: textView)
            return true
        }

        /// Closes the suggestions on Escape. They were not accepted, so no edits follow.
        func dismissCompletion() {
            completionTracking.forgetOpenSuggestions()
            session.completion.dismiss()
        }

        /// Shows or hides suggestions for what is typed at the cursor.
        func updateCompletion(in textView: UITextView, followsTyping: Bool = false) {
            completionTracking.recordAcceptedSuggestion(isListOpen: session.completion.context != nil)
            defer { completionTracking.listDidUpdate(isOpen: session.completion.context != nil, at: textRevision) }
            guard textView.isFirstResponder, textView.markedTextRange == nil, textView.selectedRange.length == 0 else {
                session.completion.update(context: nil, caretRect: .zero)
                return
            }
            let source = currentSource(of: textView)
            let context = completionTracking.context(in: source, cursor: textView.selectedRange.location,
                                                     textRevision: textRevision,
                                                     offersSlashCommands: session.completion.offersSlashCommands, followsTyping: followsTyping,
                                                     blockContext: { [styling] lineStart in
                                                         styling.blockContext(atLineStart: lineStart, in: textView, source: source)
                                                     },
                                                     pluginEditorDidChange: actions.pluginEditorDidChange)
            var caretRect = CGRect.zero
            if context != nil, let end = textView.selectedTextRange?.end {
                caretRect = textView.caretRect(for: end).offsetBy(dx: -textView.contentOffset.x, dy: -textView.contentOffset.y)
            }
            session.completion.update(context: context, caretRect: caretRect)
        }

        /// Runs a toolbar, menu, or shortcut command.
        func run(_ command: EditorCommand, in textView: UITextView) {
            switch command {
            case .undo: textView.undoManager?.undo()
            case .redo: textView.undoManager?.redo()
            case .attach: actions.attach?()
            case .draw: actions.draw?()
            case .find: textView.findInteraction?.presentFindNavigator(showingReplace: false)
            case .findAndReplace: textView.findInteraction?.presentFindNavigator(showingReplace: true)
            case .followLink(let placement):
                switch link(atCharacter: textView.selectedRange.location, in: textView, skipsShownMarkup: false) {
                case .note(let target, let isWiki)?:
                    if placement == .currentTab { follow(target, isWiki) } else { actions.followLinkElsewhere?(target, isWiki, placement) }
                case .web(let location)?: UIApplication.shared.open(location)
                case nil: break
                }
            case .dismissKeyboard: textView.resignFirstResponder()
            case .moveLinesUp, .moveLinesDown:
                // A folded section moves and is moved past as one unit, its fold with it.
                let foldedSections = NoteFolding.foldedSections(foldedRegions)
                var movesUp = false
                if case .moveLinesUp = command { movesUp = true }
                guard let edit = MarkdownEditing.movingLines(up: movesUp, in: currentSource(of: textView), selection: textView.selectedRange,
                                                             foldedSections: foldedSections) else { return }
                if let propertiesEnd = renderedPropertiesEnd,
                   NativeMarkdownEditor.cutsIntoRenderedProperties(edit.range, propertiesEnd: propertiesEnd) { return }
                isMovingLines = true
                perform(edit, in: textView)
                isMovingLines = false
                // A line that lands at the end of a folded heading's section is part of it now,
                // and must not vanish into the fold.
                let hiding = NoteFolding.regions(hiding: edit.selectionAfter.location, in: foldedRegions)
                guard !hiding.isEmpty else { return }
                session.foldedKeys.subtract(hiding.map(\.key))
                applyFolds(in: textView)
                textView.selectedRange = edit.selectionAfter
            default:
                guard let edit = MarkdownEditing.edit(for: command, in: currentSource(of: textView), selection: textView.selectedRange,
                                                      indentUnit: configuration.editingBehavior.indentUnit, tabSize: configuration.editingBehavior.tabSize) else { return }
                perform(edit, in: textView)
            }
        }

        /// Scrolls only when the cursor is outside the visible part of the note.
        private func keepSelectionVisible(in textView: UITextView) {
            guard let end = textView.selectedTextRange?.end else { return }
            let caret = textView.caretRect(for: end)
            guard !caret.isNull, !caret.isInfinite else { return }
            let visible = textView.bounds.inset(by: textView.adjustedContentInset)
            if !visible.contains(caret) { textView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -40), animated: false) }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            // Return at the end of a folded line starts a line after the folded section.
            if !isPerformingEdit, textView.markedTextRange == nil,
               let edit = foldTracking.newLineAfterFoldedSection(replacing: range, with: replacement, in: textView.text, foldedKeys: session.foldedKeys) {
                perform(edit, in: textView)
                return false
            }
            // An edit that reaches into a folded section unfolds it first, so nothing is
            // typed into, or deleted from, text that cannot be seen.
            if !isPerformingEdit {
                let touched = foldTracking.foldsTouched(byEditReplacing: range, foldedKeys: session.foldedKeys)
                if !touched.isEmpty {
                    session.foldedKeys.subtract(touched.map(\.key))
                    applyFolds(in: textView)
                }
            }
            // Undo and redo also arrive here, restoring earlier text; they must apply exactly
            // as recorded, not as typing that continues a list or pairs a bracket.
            let isHistoryChange = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            if !isPerformingEdit, !isHistoryChange, session.completion.isVisible, replacement == "\n" || replacement == "\t" {
                session.completion.accept()
                return false
            }
            if !isPerformingEdit, !isHistoryChange, isLivePreview, textView.markedTextRange == nil, let propertiesEnd = renderedPropertiesEnd {
                // Backspace below the properties would join their closing line to the text and
                // turn them into text; the YAML itself, once its source shows, stays editable.
                if textView.selectedRange.location >= propertiesEnd,
                   NativeMarkdownEditor.cutsIntoRenderedProperties(range, propertiesEnd: propertiesEnd) { return false }
                if let edit = MarkdownEditing.typingBelowClosingProperties(typed: replacement, in: currentSource(of: textView), selection: range) {
                    perform(edit, in: textView)
                    return false
                }
            }
            if !isPerformingEdit, !isHistoryChange, textView.markedTextRange == nil, let smartEdit = smartEdit(replacing: range, with: replacement, in: textView) {
                perform(smartEdit, in: textView)
                return false
            }
            // The folds are carried from before a composition started: during one, the
            // foldable regions already follow the marked text.
            if textView.markedTextRange == nil {
                foldTracking.recordEditAboutToBeMade(at: range.location, textLength: textView.textStorage.length,
                                                     foldedKeys: session.foldedKeys, followsFolds: !isMovingLines)
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            linkPreviews.closeCard()
            blockHandles.hide()
            // The insertion settles its own change once it is complete.
            guard !isApplyingInsertion else { return }
            settleTextChange(in: textView)
            publish(textView)
            // Typing can carry the cursor into code, as a fence's closing line does.
            updateKeyboardForCode(in: textView)
            updateCompletion(in: textView, followsTyping: true)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // The cursor is kept in sight from now on, not a heading jumped to.
            pinnedHeading = nil
            session.blockViews.releaseTableCellCommands()
            actions.beginEditing?()
            isEditing = true
            session.isTyping = true
            // A tap that starts editing is turned into a cursor position after this call.
            // Revealing the markup at the old cursor now would invalidate the layout below
            // it, and the tap would land at the end of the note; the markup is revealed
            // once the cursor is in place.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.isEditing else { return }
                self.updateRevealedMarkup(in: textView)
                self.placeWidgetsAgain(in: textView)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            session.isTyping = false
            formatCodeBlockLeftBehind(in: textView, editingEnded: true)
            // A suggestion chosen as the keyboard closes still gets its edits.
            completionTracking.recordAcceptedSuggestion(isListOpen: session.completion.context != nil)
            completionTracking.forgetOpenSuggestions()
            session.completion.update(context: nil, caretRect: .zero)
            updateRevealedMarkup(in: textView)
            // In a split, the other note can take the keyboard without this view being laid
            // out again, so its rendered blocks are placed here.
            placeWidgetsAgain(in: textView)
        }

        /// Places rendered blocks again with a fresh set of passes.
        private func placeWidgetsAgain(in textView: UITextView) {
            placementRetries.reset()
            textView.setNeedsLayout()
        }

        /// A new width (the sidebar opening, a split, a rotation) reflows the text after TextKit
        /// laid out the viewport for the old one, so placing blocks on those fragments left a
        /// rendered block blank and fold chevrons out of place until the next scroll. Once the
        /// width stops changing, the viewport is laid out again and everything placed on it.
        func placeWidgetsAfterWidthChange(in textView: MarkdownTextView) {
            let width = textView.contentColumnWidth
            guard abs(width - placedColumnWidth) > 0.5 else {
                if placementAfterWidthChange == nil { topLineBeforeWidthChange = nil }
                return
            }
            placedColumnWidth = width
            placementAfterWidthChange?.cancel()
            let placement = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.placementAfterWidthChange = nil
                guard textView.window != nil else { return }
                textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
                self.placeWidgetsAgain(in: textView)
                self.returnToTopLineAfterWidthChange(in: textView)
            }
            placementAfterWidthChange = placement
            // After the sidebar's animation, which changes the width many times.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: placement)
        }

        /// Every line rewraps at a new width while the offset stays the same number, so a view
        /// on screen would show another passage; it goes back to the line it showed, once the
        /// width settles. Only the first of a run of changes says what that line was.
        func rememberTopLineBeforeWidthChange(of textView: MarkdownTextView) {
            guard topLineBeforeWidthChange == nil, pendingJump == nil, textView.bounds.width > 0 else { return }
            topLineBeforeWidthChange = topCharacter(of: textView).map { location in (location, textView.contentColumnWidth) }
        }

        private func returnToTopLineAfterWidthChange(in textView: MarkdownTextView) {
            guard let topLine = topLineBeforeWidthChange else { return }
            topLineBeforeWidthChange = nil
            guard abs(textView.contentColumnWidth - topLine.columnWidth) > 0.5, pendingJump == nil,
                  !textView.isDragging, !textView.isDecelerating else { return }
            pendingJump = .topOfCharacter(topLine.location)
            performPendingJumpIfReady(in: textView)
        }

        /// The appearance changed. iPadOS flips it and back to take its dark and light snapshots
        /// as the app leaves the screen, and restyling for those laid the note out again and
        /// moved it. While the app is not active it waits for the app to come back, and only
        /// an appearance that really changed restyles then, holding the line at the top.
        func appearanceDidChange(in textView: MarkdownTextView) {
            if let scene = textView.window?.windowScene, scene.activationState != .foregroundActive {
                observeSceneActivation(of: scene, textView: textView)
                return
            }
            styledInterfaceStyle = textView.traitCollection.userInterfaceStyle
            restyleEverythingHoldingTopLine(in: textView)
            refreshWidgets(in: textView)
        }

        private func observeSceneActivation(of scene: UIScene, textView: MarkdownTextView) {
            guard sceneActivationObserver == nil else { return }
            sceneActivationObserver = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: scene,
                                                                             queue: .main) { [weak self, weak textView] _ in
                Task { @MainActor [weak self, weak textView] in
                    guard let self else { return }
                    if let observer = self.sceneActivationObserver { NotificationCenter.default.removeObserver(observer) }
                    self.sceneActivationObserver = nil
                    guard let textView, textView.traitCollection.userInterfaceStyle != self.styledInterfaceStyle else { return }
                    self.appearanceDidChange(in: textView)
                }
            }
        }

        // MARK: Find

        /// Shows the match the find navigator moved to: its folded sections open, and a rendered
        /// block over it shows its source until the search ends, as `reveal(_:in:)` does for a
        /// search result. On the next turn: the navigator is in the middle of its own move.
        func revealFoundText(_ range: NSRange, in textView: MarkdownTextView) {
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, self.canStyle(textView), NSMaxRange(range) <= textView.textStorage.length else { return }
                self.unfoldSections(hiding: range.location, in: textView)
                if self.styling.concealedEntries(in: textView).contains(where: { entry in NSLocationInRange(range.location, entry.range) }) {
                    self.isShowingFoundTextInBlock = true
                    self.styling.revealsMarkupAtSelection = true
                    textView.selectedRange = NSRange(location: range.location, length: 0)
                    self.updateRevealedMarkup(in: textView)
                    textView.layoutIfNeeded()
                }
                textView.scrollRangeToVisible(range)
            }
        }

        func endRevealingFoundText(in textView: MarkdownTextView) {
            guard isShowingFoundTextInBlock else { return }
            isShowingFoundTextInBlock = false
            styling.revealsMarkupAtSelection = isEditing
            updateRevealedMarkup(in: textView)
        }

        /// The Color, Format, Paragraph and Insert submenus; set by the editor.
        var contextMenu: EditorContextMenuActions?

        /// The system's edit menu, with Graphite's submenus and community plugins' items for
        /// the cursor after it.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            var extraItems: [UIMenuElement] = []
            if let contextMenu { extraItems += EditorContextMenuContent.menuElements(actions: contextMenu, editorActions: actions) }
            if let readAloudHooks {
                extraItems.append(UIAction(title: "Read from Here", image: UIImage(systemName: "speaker.wave.2")) { _ in
                    readAloudHooks.readFromHere(range.location)
                })
            }
            if let pluginItems = actions.pluginEditMenuElement?() { extraItems.append(pluginItems) }
            guard !extraItems.isEmpty else { return nil }
            return UIMenu(children: suggestedActions + extraItems)
        }

        // MARK: Read Aloud

        var readAloudHooks: ReadAloudEditorHooks?
        private var readAloudTapRecognizer: UITapGestureRecognizer?
        private let readAloudTapDelegate = SimultaneousTapDelegate()

        /// While the note is read, a tap moves reading to the tapped paragraph (or marks a
        /// range end); the view also reports its first visible line and the highlight's place.
        func installReadAloudHooks(_ hooks: ReadAloudEditorHooks?, in textView: MarkdownTextView) {
            readAloudHooks = hooks
            textView.reportReadingHighlightFrame = hooks?.reportHighlightFrame
            if hooks != nil, readAloudTapRecognizer == nil {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(readAloudTap(_:)))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = readAloudTapDelegate
                textView.addGestureRecognizer(recognizer)
                readAloudTapRecognizer = recognizer
            }
            readAloudTapRecognizer?.isEnabled = hooks?.isReadingThisNote ?? false
            hooks?.registerVisibleLocation { [weak textView] in
                guard let textView else { return nil }
                let point = CGPoint(x: textView.textContainerInset.left + 8, y: textView.contentOffset.y + textView.adjustedContentInset.top + 12)
                guard let position = textView.closestPosition(to: point) else { return nil }
                return textView.offset(from: textView.beginningOfDocument, to: position)
            }
        }

        @objc private func readAloudTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView, let hooks = readAloudHooks, hooks.isReadingThisNote,
                  let position = textView.closestPosition(to: recognizer.location(in: textView)) else { return }
            hooks.tapped(textView.offset(from: textView.beginningOfDocument, to: position))
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Folds describe the text before an edit until it settles.
            if !textState.cachesDescribeOldText, let target = locationOutsideFolds(for: textView.selectedRange, in: textView) {
                textView.selectedRange = NSRange(location: target, length: 0)
                return
            }
            lastSelectionLocation = textView.selectedRange.location
            if textView.isFirstResponder { session.hasPlacedCursor = true }
            session.selection = textView.selectedRange
            guard !isApplyingInsertion else { return }
            updateRevealedMarkup(in: textView)
            formatCodeBlockLeftBehind(in: textView, editingEnded: false)
            // During an edit the selection is reported before the text; `textViewDidChange`
            // updates the suggestions right after, for the same selection.
            guard !textState.cachesDescribeOldText else { return }
            updateKeyboardForCode(in: textView)
            updateCompletion(in: textView)
        }

        /// Formats the code block the user edited once the selection leaves it or editing
        /// ends, on the next turn of the run loop rather than inside the text view's callback,
        /// through the text view so Undo puts the code back.
        private func formatCodeBlockLeftBehind(in textView: UITextView, editingEnded: Bool) {
            guard configuration.formatsCodeBlocks else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.markedTextRange == nil,
                      let edit = self.styling.codeFormattingEdit(afterSelectionChangeIn: textView, editingEnded: editingEnded) else { return }
                self.perform(edit, in: textView)
            }
        }

        /// Restyles the markup that starts or stops showing as the selection moves: the
        /// markers of the inline elements it reaches and leaves, the markers of the lines
        /// it moves between, and the rendered blocks the cursor enters or leaves.
        private func updateRevealedMarkup(in textView: UITextView) {
            guard isLivePreview, canStyle(textView) else { return }
            // An edit whose styling waited for an IME composition that ended without
            // `textViewDidChange` is styled now, revealed markup included.
            if textState.hasUnstyledEdit {
                settleTextChange(in: textView)
                return
            }
            styling.restyleRevealedMarkup(in: textView)
        }

        private func publish(_ textView: UITextView) {
            let text = currentSource(of: textView) as String
            // The session's text changed elsewhere, and the update that brings it here has not
            // run or is waiting out a composition; see `TextDifference.carryingEdit`.
            if session.text != lastSynchronizedText, session.text != text {
                guard textView.markedTextRange == nil else { return }
                let merged = TextDifference.carryingEdit(from: textBeforeComposition ?? lastSynchronizedText, published: lastSynchronizedText,
                                                         to: text, onto: session.text)
                session.text = merged
                lastSynchronizedText = merged
                replaceText(with: merged, in: textView)
                return
            }
            if textView.markedTextRange == nil {
                textBeforeComposition = nil
            } else if textBeforeComposition == nil {
                textBeforeComposition = lastSynchronizedText
            }
            session.text = text
            lastSynchronizedText = text
            session.selection = textView.selectedRange
            session.undoAvailability.refresh()
            // An edit moves the text again, so rendered blocks get a fresh set of placement
            // passes; a budget spent earlier would otherwise leave a block unplaced.
            placementRetries.reset()
            lookahead.stop()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            placeWidgetsAgain(in: textView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView else { return }
            placeWidgetsAgain(in: textView)
        }

        // MARK: Rendered blocks

        /// Places rendered blocks over the space reserved for them. Only fragments TextKit
        /// has laid out for the viewport are used, because only their frames say where the
        /// text on screen is drawn. Forcing layout elsewhere would move the estimated
        /// positions of the visible text, and the views would drift from it. A fragment
        /// outside the viewport keeps an estimated frame, or one from before the blocks
        /// around it took their measured heights, so a view placed from it covers the text
        /// next to it, such as the heading a jump has just brought to the top.
        func positionWidgets(in textView: MarkdownTextView) {
            guard isLivePreview, let environment, let textLayoutManager = textView.textLayoutManager else {
                removeAllWidgets()
                return
            }
            // Mid-edit, the blocks describe the text before it; the views stay until it settles.
            guard !textState.cachesDescribeOldText else { return }
            let column = RenderedBlockColumn(minX: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding,
                                             textContainerTop: textView.textContainerInset.top, width: textView.contentColumnWidth)
            // TextKit can have no viewport range until it lays out the viewport again, as after
            // a restyle; that layout places the views. Removing them meanwhile rebuilt them all,
            // each reported its height again and restyled, and the rebuilding could go on
            // without end.
            guard let placement = renderedBlocks.placeViews(of: concealedEntries(in: textView), in: textView, textLayoutManager: textLayoutManager,
                                                            column: column, configuration: configuration, makeRootView: { entry in
                widgetRootView(for: entry, environment: environment, textView: textView)
            }) else { return }
            // The cursor leaving a block restyles it, which replaces its fragment, and TextKit
            // lays the viewport out only after this pass; it is laid out now instead.
            if !placement.keysAwaitingLayout.isEmpty, !isPlacingOnViewportLaidOutNow {
                isPlacingOnViewportLaidOutNow = true
                defer { isPlacingOnViewportLaidOutNow = false }
                RenderedBlockPlacementRetries.layOutViewport(of: textLayoutManager) { textView.contentOffset }
                positionWidgets(in: textView)
                return
            }
            renderedBlocks.detachViews(except: placement.keysInUse, entries: blockEntries)
            // A height measured at a new width, or by another editor, is reserved in the text first.
            styling.restyleLater(placement.entriesToRestyle, in: textView)
            // After a jump (the keyboard closing, a scroll to a heading) or a restyle, TextKit
            // can finish laying out the viewport after this pass, and a placed view can change
            // the height it reserves; the passes `RenderedBlockPlacementRetries` gives follow.
            if placementRetries.follow(placement, placeAgain: { [weak textView] in textView?.setNeedsLayout() }) {
                makeViewsAheadOnceStill(in: textView)
            }
            keepPinnedHeadingAtTop(in: textView)
        }

        private func makeViewsAheadOnceStill(in textView: MarkdownTextView) {
            let viewportStart = textView.textLayoutManager.flatMap(RenderedBlockLookahead.viewportCharacters(of:))?.location
            lookahead.makeViewsOnceStill(viewportStart: viewportStart) { [weak self, weak textView] in self?.makeNextViewAhead(in: textView) ?? false }
        }

        /// Makes the next view below the screen (`RenderedBlockLookahead`); false when there is
        /// none to make, or the note is scrolled, edited or hidden.
        private func makeNextViewAhead(in textView: MarkdownTextView?) -> Bool {
            guard let textView, isLivePreview, let environment, textView.window != nil, !textView.isTracking, !textView.isDecelerating,
                  textView.markedTextRange == nil, !textState.cachesDescribeOldText, !textState.hasUnstyledEdit,
                  let viewport = textView.textLayoutManager.flatMap(RenderedBlockLookahead.viewportCharacters(of:)) else { return false }
            let column = RenderedBlockColumn(minX: textView.textContainerInset.left + textView.textContainer.lineFragmentPadding,
                                             textContainerTop: textView.textContainerInset.top, width: textView.contentColumnWidth)
            return renderedBlocks.makeNextViewAhead(below: viewport, in: concealedEntries(in: textView), textView: textView, column: column,
                                                    configuration: configuration) { entry in
                widgetRootView(for: entry, environment: environment, textView: textView)
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? MarkdownTextView else { return }
            // The blocks and fold buttons are placed by the layout pass UIKit runs on every
            // frame of a scroll (`didLayout`); placing them here as well did it twice a frame.
            if session.completion.context != nil { updateCompletion(in: textView) }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            lookahead.stop()
            pinnedHeading = nil
            topLineBeforeWidthChange = nil
            suspendReadingFollow?()
            linkPreviews.closeCard()
        }

        /// Gives the rendered blocks on screen, and those kept off screen, the environment and
        /// appearance `signature` describes, in place; only the blocks that read the index
        /// when nothing else changed.
        func refreshWidgets(for signature: LivePreviewWidgetSignature, in textView: MarkdownTextView) {
            guard let environment else { return }
            _ = renderedBlocks.refreshViews(for: signature, entries: blockEntries) { entry in
                widgetRootView(for: entry, environment: environment, textView: textView)
            }
        }

        /// Gives every rendered block a new root view, as after a change of appearance.
        func refreshWidgets(in textView: MarkdownTextView) {
            guard let environment else { return }
            renderedBlocks.refreshViews(entries: blockEntries) { entry in widgetRootView(for: entry, environment: environment, textView: textView) }
        }

        /// The appearance is passed in: a hosted view does not inherit it from the text view.
        /// A tap on a block's view puts the cursor at the block's start, showing its source.
        private func widgetRootView(for entry: LivePreviewBlockEntry, environment: LivePreviewEnvironment, textView: MarkdownTextView) -> RenderedBlockRoot {
            let key = entry.key
            let isFrontmatter = entry.block.kind == .frontmatter
            return LivePreviewRenderedBlocks.rootView(for: entry, environment: environment, accentHex: configuration.accentHex,
                                                      colorScheme: textView.traitCollection.userInterfaceStyle == .dark ? .dark : .light, revealSource: { [weak self, weak textView] in
                guard let self, let textView, self.canStyle(textView),
                      let currentEntry = self.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                textView.beginEditing()
                textView.selectedRange = NSRange(location: currentEntry.range.location, length: 0)
                self.textViewDidChangeSelection(textView)
            }, reportHeight: { [weak self, weak textView] height in
                guard let self, let textView else { return }
                self.styling.reserveMeasuredHeight(height, forBlockWithKey: key, isFrontmatter: isFrontmatter, in: textView)
            }, sourceEditing: RenderedBlockSourceEditing(replaceSource: { [weak self, weak textView] editor, transform in
                guard let self, let textView else { return }
                self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView)
            }, setIsEditingInView: { [weak self] isEditing, editor in
                guard let self else { return }
                if !isEditing { return self.renderedBlocks.endEditingInView(owner: editor) }
                guard let entry = self.blockEntries.first(where: { candidate in candidate.key == key }) else { return }
                self.renderedBlocks.beginEditingInView(blockWithKey: key, at: entry.range.location, owner: editor)
            }, setDraftCommit: { [weak self] editor, commit in
                self?.session.blockViews.draftCommits[editor] = commit
            }, offerCellCommands: { [weak self] target in
                self?.session.blockViews.takeTableCellCommands(target)
            }, placeCaretBesideBlock: { [weak self, weak textView] editor, side in
                guard let self, let textView else { return }
                self.placeCaret(besideBlockWithKey: key, editedBy: editor, side: side, in: textView)
            }, undoInNote: { [weak textView] isRedo in
                if isRedo { textView?.undoManager?.redo() } else { textView?.undoManager?.undo() }
            }), currentLocation: { [weak self] in
                self?.blockEntries.first { candidate in candidate.key == key }?.range.location
            })
        }

        /// Replaces a rendered block's source with what its view made of it, as a table's cell
        /// editor does, through the text view so it can be undone. Mid-edit or during an input
        /// method's composition, the change waits a turn.
        func replaceSource(ofBlockWithKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, using transform: @escaping (String) -> String?,
                           in textView: UITextView, attemptsLeft: Int = 3) {
            guard canStyle(textView), textView.markedTextRange == nil else {
                guard attemptsLeft > 0 else { return }
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.replaceSource(ofBlockWithKey: key, editedBy: editor, using: transform, in: textView, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            let source = currentSource(of: textView)
            guard let blockRange = renderedBlocks.rangeOfBlock(withKey: key, editedBy: editor, in: blockEntries, source: source),
                  let replacement = transform(source.substring(with: blockRange)) else { return }
            replaceText(with: source.replacingCharacters(in: blockRange, with: replacement), in: textView)
        }

        /// Gives the note's text the keyboard with the caret on the line before or after a
        /// rendered block, as an arrow out of a table's edge does; an empty line is added first
        /// where the block starts or ends the note.
        func placeCaret(besideBlockWithKey key: LivePreviewBlockKey, editedBy editor: ObjectIdentifier, side: RenderedBlockSide, in textView: UITextView) {
            let source = currentSource(of: textView)
            guard let blockRange = renderedBlocks.rangeOfBlock(withKey: key, editedBy: editor, in: blockEntries, source: source) else { return }
            let placement = RenderedBlockCaretPlacement(beside: blockRange, side: side, in: source)
            if let lineBreakLocation = placement.lineBreakLocation {
                replaceText(with: source.replacingCharacters(in: NSRange(location: lineBreakLocation, length: 0), with: "\n"), in: textView)
            }
            // The note's view takes the keyboard only after a touch or when asked: an arrow key is neither.
            if let markdownTextView = textView as? MarkdownTextView { markdownTextView.beginEditing() } else { textView.becomeFirstResponder() }
            textView.selectedRange = NSRange(location: placement.caretLocation, length: 0)
            textViewDidChangeSelection(textView)
        }

        /// When rendered blocks settle their heights after TextKit laid out the viewport, the
        /// text below them moves down and the laid-out part can end above the bottom of the
        /// view. After a jump, UIKit lays the viewport out for the new offset only after this
        /// pass, which found the lines laid out for the old one: they start below the top of
        /// the view, and the blocks above them (a base just under the heading jumped to) were
        /// never placed. Lines in such a gap have no rendered blocks or fold chevrons until
        /// the next scroll, so the viewport is laid out once more then.
        func layOutViewportAgainIfShort(in textView: MarkdownTextView) {
            guard let textLayoutManager = textView.textLayoutManager,
                  let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else { return }
            var laidOutTop = CGFloat.greatestFiniteMagnitude
            var laidOutBottom: CGFloat = 0
            textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
                laidOutTop = min(laidOutTop, fragment.layoutFragmentFrame.minY)
                laidOutBottom = max(laidOutBottom, fragment.layoutFragmentFrame.maxY)
                return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
            }
            let visibleTop = textView.contentOffset.y - textView.textContainerInset.top
            let documentRange = textLayoutManager.documentRange
            guard laidOutBottom > 0,
                  ViewportLayoutCoverage.leavesVisibleTextUncovered(
                      laidOutTop: laidOutTop, laidOutBottom: laidOutBottom, visibleTop: visibleTop, visibleBottom: visibleTop + textView.bounds.height,
                      startsAtDocumentStart: viewportRange.location.compare(documentRange.location) != .orderedDescending,
                      endsAtDocumentEnd: viewportRange.endLocation.compare(documentRange.endLocation) != .orderedAscending) else { return }
            // A shortfall within the moment after the last one is looked at again when that moment
            // ends: a page scrolled to in the meantime, as by a jump or a scroll set in code, kept the
            // viewport of the page before, and its blocks below that viewport stayed blank until the
            // next scroll (Docs/Editor-scrolling-todo.md, the release pass's blank pictures).
            guard !isViewportRelayoutPending else {
                hasShortfallWhileRelayoutPending = true
                return
            }
            isViewportRelayoutPending = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
                self.placeWidgetsAgain(in: textView)
                // Another shortfall is allowed only after a moment, so a note whose end is
                // above the bottom of the view cannot loop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak textView] in
                    self.isViewportRelayoutPending = false
                    guard self.hasShortfallWhileRelayoutPending else { return }
                    self.hasShortfallWhileRelayoutPending = false
                    textView?.setNeedsLayout()
                }
            }
        }

        // MARK: Folding

        /// Applies the session's folds: restyles the sections whose fold changed, and moves the
        /// cursor out of what is hidden. Restyling the whole note, for many folds at once,
        /// re-estimates TextKit's layout, so the view goes back to the line it showed.
        func applyFolds(in textView: UITextView) {
            if !textState.cachesDescribeOldText, let changedSections = foldTracking.sectionsChangingFold(to: session.foldedKeys) {
                appliedFoldedKeys = session.foldedKeys
                for section in changedSections { restyle(section, in: textView) }
            } else {
                restyleEverythingHoldingTopLine(in: textView)
            }
            if let target = locationOutsideFolds(for: textView.selectedRange, in: textView) {
                textView.selectedRange = NSRange(location: target, length: 0)
            }
            placeWidgetsAgain(in: textView)
            if let markdownTextView = textView as? MarkdownTextView { positionFoldButtons(in: markdownTextView) }
        }

        /// Restyles the whole note and returns to the line at the top of the view.
        private func restyleEverythingHoldingTopLine(in textView: UITextView) {
            let heldLine = lineKeptAtTop() ?? topLine(of: textView)
            restyleEverything(in: textView)
            guard let heldLine, pendingJump == nil else { return }
            pendingJump = .topOfCharacter(heldLine.location, distanceIntoLine: heldLine.distanceIntoLine)
            performPendingJumpIfReady(in: textView)
        }

        /// The time a jump's pin is measured in.
        private var currentUptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

        /// The line a jump is keeping at the top, while it does. The blocks above can have moved
        /// the text since a layout pass last put the line back, so the line the offset falls on
        /// is not the person's place then, and holding it would keep the wrong line for good.
        private func lineKeptAtTop() -> (location: Int, distanceIntoLine: CGFloat)? {
            guard var pinnedHeading else { return nil }
            let isBlockAboveAwaitingHeight = renderedBlocks.hasPlacedBlockAwaitingHeight(before: pinnedHeading.location, in: blockEntries)
            guard pinnedHeading.holds(atUptime: currentUptime, isBlockAboveAwaitingHeight: isBlockAboveAwaitingHeight) else { return nil }
            return (pinnedHeading.location, pinnedHeading.distanceIntoLine)
        }

        func toggleFold(_ key: String, in textView: UITextView) {
            if session.foldedKeys.contains(key) { session.foldedKeys.remove(key) } else { session.foldedKeys.insert(key) }
            applyFolds(in: textView)
        }

        /// A folded heading or list item whose line was edited has a new key; see `EditorFoldTracking`.
        private func carryFoldsAcrossEdit(in textView: UITextView) -> Bool {
            let carried = foldTracking.carryFoldsAcrossEdit(textLength: textView.textStorage.length, foldedKeys: session.foldedKeys)
            if carried.foldedKeys != session.foldedKeys { session.foldedKeys = carried.foldedKeys }
            return carried.changed
        }

        /// Unfolds the sections that hide `location`, before a jump shows it.
        private func unfoldSections(hiding location: Int, in textView: UITextView) {
            let hiding = NoteFolding.regions(hiding: location, in: foldedRegions)
            guard !hiding.isEmpty else { return }
            session.foldedKeys.subtract(hiding.map(\.key))
            applyFolds(in: textView)
        }

        /// Where a cursor that landed in a folded section goes instead.
        private func locationOutsideFolds(for selection: NSRange, in textView: UITextView) -> Int? {
            foldTracking.locationOutsideFolds(for: selection, movedFrom: lastSelectionLocation, textLength: textView.textStorage.length,
                                              foldedKeys: session.foldedKeys)
        }

        /// Places a chevron beside each heading and list item that folds, and "…" after a
        /// folded one, for the lines TextKit has laid out on screen.
        func positionFoldButtons(in textView: MarkdownTextView) {
            // Mid-edit, the regions describe the text before it; the buttons stay until it settles.
            guard !textState.cachesDescribeOldText else { return }
            guard !foldTracking.regions.isEmpty, let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let viewportRange = textLayoutManager.textViewportLayoutController.viewportRange else {
                removeFoldButtons()
                return
            }
            let regionsByStart = foldTracking.regionsByStart(foldedKeys: session.foldedKeys)
            let source = currentSource(of: textView)
            let documentStart = contentStorage.documentRange.location
            var keysInUse = Set<String>()
            textLayoutManager.enumerateTextLayoutFragments(from: viewportRange.location, options: []) { fragment in
                let fragmentStart = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
                if let region = regionsByStart[fragmentStart], NSMaxRange(region.headerRange) <= source.length,
                   let firstLine = fragment.textLineFragments.first, let lastLine = fragment.textLineFragments.last {
                    keysInUse.insert(region.key)
                    let isFolded = session.foldedKeys.contains(region.key)
                    let buttons = foldButtons[region.key] ?? makeFoldButtons(for: region.key, in: textView)
                    foldButtons[region.key] = buttons
                    let header = source.substring(with: region.headerRange)
                    let indentLength = (header.prefix { character in character == " " || character == "\t" } as Substring).utf16.count
                    let fragmentOrigin = CGPoint(x: textView.textContainerInset.left + fragment.layoutFragmentFrame.minX,
                                                 y: textView.textContainerInset.top + fragment.layoutFragmentFrame.minY)
                    let textStartX = firstLine.locationForCharacter(at: min(indentLength, max(0, firstLine.characterRange.length - 1))).x
                    // Apple's smallest comfortable touch target; the chevron is drawn at 11 points inside it.
                    let size: CGFloat = 28
                    let firstLineBounds = firstLine.typographicBounds
                    buttons.chevron.frame = CGRect(x: max(2, fragmentOrigin.x + textStartX - size - 4),
                                                   y: fragmentOrigin.y + firstLineBounds.minY + (firstLineBounds.height - size) / 2, width: size, height: size)
                    // Set when the fold or the header changes, not on every frame of a scroll.
                    let chevronImage = isFolded ? Self.foldedChevron : Self.unfoldedChevron
                    if buttons.chevron.image(for: .normal) !== chevronImage {
                        buttons.chevron.setImage(chevronImage, for: .normal)
                        buttons.chevron.alpha = isFolded ? 1 : 0.4
                    }
                    let headerText = header.trimmingCharacters(in: .whitespaces).drop { character in character == "#" }
                        .trimmingCharacters(in: .whitespaces)
                    let label = isFolded ? "Unfold \(headerText)" : "Fold \(headerText)"
                    if buttons.chevron.accessibilityLabel != label { buttons.chevron.accessibilityLabel = label }
                    buttons.ellipsis.isHidden = !isFolded
                    if isFolded {
                        let lastLineBounds = lastLine.typographicBounds
                        buttons.ellipsis.frame = CGRect(x: fragmentOrigin.x + lastLineBounds.maxX + 6,
                                                        y: fragmentOrigin.y + lastLineBounds.minY + (lastLineBounds.height - size) / 2, width: 34, height: size)
                    }
                }
                return fragment.rangeInElement.location.compare(viewportRange.endLocation) == .orderedAscending
            }
            for (key, buttons) in foldButtons where !keysInUse.contains(key) {
                buttons.chevron.removeFromSuperview()
                buttons.ellipsis.removeFromSuperview()
                foldButtons[key] = nil
            }
        }

        private static let foldedChevron = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        private static let unfoldedChevron = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))

        private func makeFoldButtons(for key: String, in textView: UITextView) -> (chevron: UIButton, ellipsis: UIButton) {
            let toggle = UIAction { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.toggleFold(key, in: textView)
            }
            let chevron = UIButton(type: .system, primaryAction: toggle)
            chevron.tintColor = .secondaryLabel
            let ellipsis = UIButton(type: .system, primaryAction: toggle)
            ellipsis.setTitle("…", for: .normal)
            ellipsis.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            ellipsis.tintColor = .secondaryLabel
            ellipsis.backgroundColor = UIColor.tertiarySystemFill
            ellipsis.layer.cornerRadius = 6
            ellipsis.accessibilityLabel = "Unfold"
            textView.addSubview(chevron)
            textView.addSubview(ellipsis)
            // A heading's margin is mostly its chevron: a long press there lifts the heading.
            blockHandles.watchPresses(on: chevron)
            return (chevron, ellipsis)
        }

        private func removeFoldButtons() {
            for buttons in foldButtons.values {
                buttons.chevron.removeFromSuperview()
                buttons.ellipsis.removeFromSuperview()
            }
            foldButtons.removeAll()
        }

        func removeAllWidgets() {
            lookahead.stop()
            renderedBlocks.removeAllViews()
        }

        func releaseRenderedViews() {
            // Only while hidden: a shown editor's blocks are on screen.
            guard textView?.window == nil else { return }
            removeAllWidgets()
        }

        // MARK: Drawn replacements

        nonisolated func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                                           in textElement: NSTextElement) -> NSTextLayoutFragment {
            ConcealedReplacementLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // MARK: Links, tasks, and headings

        /// Pinching the note changes the vault's font size while quick adjustment is on.
        func installQuickFontSizePinch(on textView: UITextView) {
            let recognizer = QuickFontSizePinchRecognizer()
            recognizer.adjustment = actions.quickFontSize
            textView.addGestureRecognizer(recognizer)
            quickFontSizePinch = recognizer
        }

        /// The note's own touches: a tap on a link or a checkbox, and the block handles' long
        /// press in the margin (`TouchBlockHandles`).
        func installTouchRecognizers(on textView: UITextView) {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.delegate = self
            textView.addGestureRecognizer(recognizer)
            connectBlockHandles(of: textView)
        }

        /// While Page Preview is on, the pointer of a trackpad or mouse, or Apple Pencil
        /// hovering, resting on a link shows its card, and a long press on a link whose
        /// markup is hidden (one a tap follows) shows it at once. Nothing is installed before.
        func watchPointerForLinks(in textView: MarkdownTextView) {
            if linkPreviews.isWatchingPointer, linkHoverRecognizer == nil {
                let hoverRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(handleLinkHover(_:)))
                textView.addGestureRecognizer(hoverRecognizer)
                linkHoverRecognizer = hoverRecognizer
                let pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLinkPress(_:)))
                pressRecognizer.delegate = self
                textView.addGestureRecognizer(pressRecognizer)
                linkPressRecognizer = pressRecognizer
            }
            linkHoverRecognizer?.isEnabled = linkPreviews.isWatchingPointer
            linkPressRecognizer?.isEnabled = linkPreviews.isWatchingPointer
        }

        @objc private func handleLinkHover(_ recognizer: UIHoverGestureRecognizer) {
            guard let textView = recognizer.view as? MarkdownTextView else { return }
            switch recognizer.state {
            case .began, .changed: linkPreviews.pointerMoved(to: recognizer.location(in: nil), over: textView)
            case .ended, .cancelled, .failed: linkPreviews.pointerLeft()
            case .possible, .recognized: break
            @unknown default: break
            }
        }

        @objc private func handleLinkPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let textView = recognizer.view as? MarkdownTextView else { return }
            _ = linkPreviews.press(at: recognizer.location(in: nil), in: textView)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return false }
            let point = gestureRecognizer.location(in: textView)
            if gestureRecognizer === linkPressRecognizer { return link(at: point, in: textView) != nil }
            return taskCheckboxRange(at: point, in: textView) != nil || link(at: point, in: textView) != nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = recognizer.view as? UITextView else { return }
            let point = recognizer.location(in: textView)
            if let checkboxRange = taskCheckboxRange(at: point, in: textView) {
                toggleTask(checkboxRange, in: textView)
            } else if let link = link(at: point, in: textView) {
                switch link {
                case .note(let target, let isWiki):
                    // ⌘ opens the link in a new tab, ⌥⌘ beside the note and ⇧⌥⌘ in a new window, as in Obsidian.
                    let modifierFlags = recognizer.modifierFlags
                    if modifierFlags.contains(.command), let followLinkElsewhere = actions.followLinkElsewhere {
                        followLinkElsewhere(target, isWiki, TabPlacement.forLink(command: true, option: modifierFlags.contains(.alternate),
                                                                                 shift: modifierFlags.contains(.shift)))
                    } else {
                        follow(target, isWiki)
                    }
                case .web(let location):
                    UIApplication.shared.open(location)
                }
            }
        }

        /// The `[ ]` or `[x]` under the finger on a line whose checkbox is drawn.
        private func taskCheckboxRange(at point: CGPoint, in textView: UITextView) -> NSRange? {
            guard isLivePreview, canStyle(textView), let position = textView.closestPosition(to: point) else { return nil }
            let characterIndex = textView.offset(from: textView.beginningOfDocument, to: position)
            let source = currentSource(of: textView)
            guard characterIndex <= source.length else { return nil }
            // The selection's lines show `[ ]` as written, and a tap there places the cursor.
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            if let revealedMarkup, revealedMarkup.showsLineMarker(at: lineRange.location) { return nil }
            return LivePreviewTapTargets.taskCheckboxRange(at: characterIndex, in: source)
        }

        /// Checks or unchecks a task through the text view, so the change can be undone.
        private func toggleTask(_ checkboxRange: NSRange, in textView: UITextView) {
            let source = currentSource(of: textView)
            let stateRange = NSRange(location: checkboxRange.location + 1, length: 1)
            guard NSMaxRange(stateRange) <= source.length else { return }
            let isChecked = source.substring(with: stateRange) != " "
            let selectedRange = textView.selectedRange
            isPerformingEdit = true
            replaceCharacters(in: stateRange, with: isChecked ? " " : "x", in: textView)
            isPerformingEdit = false
            textView.selectedRange = selectedRange
            if textState.cachesDescribeOldText || session.text != textView.text { textViewDidChange(textView) }
        }

        /// A link under the finger whose markup is concealed, as in Obsidian's Live
        /// Preview, where a tap on a link follows it instead of placing the cursor.
        private func link(at point: CGPoint, in textView: UITextView) -> LinkInText? {
            guard isLivePreview, let position = textView.closestPosition(to: point) else { return nil }
            return link(atCharacter: textView.offset(from: textView.beginningOfDocument, to: position), in: textView, skipsShownMarkup: true)
        }

        /// The link around a character. Taps skip a link whose markup is showing, which is
        /// being edited; the keyboard's link commands do not. A link written in code or
        /// math is text.
        func link(atCharacter characterIndex: Int, in textView: UITextView, skipsShownMarkup: Bool) -> LinkInText? {
            let source = currentSource(of: textView)
            guard characterIndex <= source.length, source.length > 0 else { return nil }
            if skipsShownMarkup {
                guard characterIndex < source.length else { return nil }
                if let revealedMarkup, canStyle(textView),
                   LivePreviewTapTargets.isInsideLinkShowingItsMarkup(characterIndex, in: source, revealedMarkup: revealedMarkup) { return nil }
            }
            let lineRange = source.lineRange(for: NSRange(location: characterIndex, length: 0))
            guard let link = LinkLocator.link(in: source.substring(with: lineRange), at: characterIndex - lineRange.location, includesEnd: !skipsShownMarkup),
                  !LivePreviewTapTargets.isInsideCode(characterIndex, in: source) else { return nil }
            return link
        }

        // MARK: Jumps

        /// Runs the pending jump from the next turn of the run loop once a layout pass finds
        /// the view in a window with a width. Layout passes do not scroll from inside themselves.
        func schedulePendingJumpIfReady(in textView: MarkdownTextView) {
            guard pendingJump != nil, !isPendingJumpScheduled, textView.window != nil, textView.bounds.width > 0 else { return }
            isPendingJumpScheduled = true
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self else { return }
                self.isPendingJumpScheduled = false
                guard let textView else { return }
                self.performPendingJumpIfReady(in: textView)
            }
        }

        /// Makes the pending jump when the view is in a window and has a width; otherwise it
        /// waits for a layout pass that finds both.
        func performPendingJumpIfReady(in textView: UITextView) {
            guard let jump = pendingJump, textView.window != nil, textView.bounds.width > 0 else { return }
            pendingJump = nil
            switch jump {
            case .heading(let anchor, let occurrence): scroll(to: anchor, occurrence: occurrence, in: textView)
            case .textRange(let range): reveal(range, in: textView)
            case .topOfCharacter(let characterLocation, let distanceIntoLine):
                scrollToTop(of: min(characterLocation, textView.textStorage.length), distanceIntoLine: distanceIntoLine, in: textView)
            }
        }

        /// Brings a heading to the top of the view, as Obsidian's outline does. The cursor
        /// moves there only while editing, so a jump never raises the keyboard.
        /// - Parameter occurrence: Which of the headings with this anchor, from zero, for
        ///   notes where several headings read the same.
        func scroll(to anchor: String, occurrence: Int = 0, in textView: UITextView) {
            guard let lineLocation = HeadingLocator.lineLocation(ofHeadingWithAnchor: anchor, occurrence: occurrence, in: currentSource(of: textView)) else { return }
            unfoldSections(hiding: lineLocation, in: textView)
            if textView.isFirstResponder { textView.selectedRange = NSRange(location: lineLocation, length: 0) }
            scrollToTop(of: lineLocation, in: textView)
        }

        /// Shows a range, such as a search match or a linked block, near the top and marks it
        /// briefly. The mark is drawn by Graphite: the system's find highlight asserts when
        /// the text view is not yet in a window, as happens right after a note opens.
        func reveal(_ range: NSRange, in textView: UITextView) {
            let source = currentSource(of: textView)
            guard NSMaxRange(range) <= source.length else { return }
            unfoldSections(hiding: range.location, in: textView)
            scrollToTop(of: source.lineRange(for: NSRange(location: range.location, length: 0)).location, in: textView)
            if textView.isFirstResponder { textView.selectedRange = NSRange(location: range.location, length: 0) }
            Task { @MainActor [weak self, weak textView] in
                // After the jump settles, so the mark lands on the text's final position.
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let textView, textView.window != nil, NSMaxRange(range) <= textView.textStorage.length else { return }
                self.flashHighlight(range, in: textView)
            }
        }

        private func flashHighlight(_ range: NSRange, in textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            let accent = UIColor.graphiteAccent(hex: configuration.accentHex) ?? .tintColor
            let rects = textView.selectionRects(for: textRange).map(\.rect).filter { rect in rect.width > 1 && rect.height > 1 }
            let marks = rects.map { rect -> UIView in
                let mark = UIView(frame: rect.insetBy(dx: -2, dy: -1))
                mark.backgroundColor = accent.withAlphaComponent(0.28)
                mark.layer.cornerRadius = 4
                mark.isUserInteractionEnabled = false
                textView.addSubview(mark)
                return mark
            }
            UIView.animate(withDuration: 0.6, delay: 1.8, options: [.allowUserInteraction]) {
                marks.forEach { mark in mark.alpha = 0 }
            } completion: { _ in
                marks.forEach { mark in mark.removeFromSuperview() }
            }
        }

        /// Corrects the offset while the blocks above a heading that was jumped to take their
        /// measured heights, as long as `HeadingJumpPin` holds: while a block above has not
        /// reported its height (a base loading its rows), and for a moment after the heading
        /// last moved or such a block reported. A heading near the end of the note stops where the note ends, as the
        /// jump itself does.
        private func keepPinnedHeadingAtTop(in textView: UITextView) {
            guard var pinnedHeading else { return }
            let uptime = currentUptime
            let isBlockAboveAwaitingHeight = renderedBlocks.hasPlacedBlockAwaitingHeight(before: pinnedHeading.location, in: blockEntries)
            let holds = pinnedHeading.holds(atUptime: uptime, isBlockAboveAwaitingHeight: isBlockAboveAwaitingHeight)
            self.pinnedHeading = holds ? pinnedHeading : nil
            guard holds else { return }
            guard let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: pinnedHeading.location),
                  var fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            // A heading's fragment that a restyle replaced has no frame until TextKit lays it
            // out again, which it does only within the viewport. A block above that grew can
            // leave the heading above the viewport, where no later pass would, so the text up
            // to and including the heading is laid out here, as the jump does.
            if fragment.state != .layoutAvailable {
                guard let throughHeading = NSTextRange(location: contentStorage.documentRange.location, end: fragment.rangeInElement.endLocation) else { return }
                textLayoutManager.ensureLayout(for: throughHeading)
                guard let laidOutFragment = textLayoutManager.textLayoutFragment(for: location), laidOutFragment.state == .layoutAvailable else { return }
                fragment = laidOutFragment
            }
            let targetOffset = fragment.layoutFragmentFrame.minY + textView.textContainerInset.top - 12 + pinnedHeading.distanceIntoLine
            let clampedOffset = min(max(-textView.adjustedContentInset.top, targetOffset), maximumContentOffset(of: textView, layoutManager: textLayoutManager))
            if abs(textView.contentOffset.y - clampedOffset) > 1 {
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: clampedOffset), animated: false)
                self.pinnedHeading?.recordMove(atUptime: uptime)
            }
        }

        /// The largest vertical offset that still ends at the note's end. The content size
        /// can lag behind a layout just forced, so the layout's own height bounds it too.
        private func maximumContentOffset(of textView: UITextView, layoutManager textLayoutManager: NSTextLayoutManager) -> CGFloat {
            let contentHeight = max(textView.contentSize.height,
                                    textLayoutManager.usageBoundsForTextContainer.maxY + textView.textContainerInset.top + textView.textContainerInset.bottom)
            return max(-textView.adjustedContentInset.top, contentHeight - textView.bounds.height + textView.adjustedContentInset.bottom)
        }

        /// Remembers the character at the top of the view in the session.
        func recordScrollLocation(of textView: UITextView) {
            guard textView.contentOffset.y > -textView.adjustedContentInset.top + 1 else {
                session.savedScrollLocation = nil
                return
            }
            guard let location = topCharacter(of: textView) else { return }
            session.savedScrollLocation = location
        }

        /// The first character of the line at the top of the view; nil at the note's top,
        /// which needs no return to, and while the view is not on screen.
        func topCharacter(of textView: UITextView) -> Int? {
            topLine(of: textView)?.location
        }

        /// `scrollToTop` puts a line 12 points below the top, but the scroll view rounds its offset to
        /// whole pixels and a pin leaves a point or less uncorrected, which would put the probe in the
        /// line above: each return to the line would then land a line higher. As on the Mac.
        private static let scrollAlignmentAllowance: CGFloat = 1.5

        /// The line at the top of the view, and how far past where `scrollToTop` puts it the view is
        /// scrolled. Properties taller than the window are one line of the text with their space in
        /// it, so this is the place within them; going back to the line alone went to their start.
        private func topLine(of textView: UITextView) -> (location: Int, distanceIntoLine: CGFloat)? {
            let probeY = textView.contentOffset.y + 12 + Self.scrollAlignmentAllowance - textView.textContainerInset.top
            guard textView.window != nil, textView.contentOffset.y > -textView.adjustedContentInset.top + 1, let textLayoutManager = textView.textLayoutManager,
                  let fragment = textLayoutManager.textLayoutFragment(for: CGPoint(x: 0, y: probeY)),
                  let manager = textLayoutManager.textContentManager else { return nil }
            let location = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
            let distance = textView.contentOffset.y - (fragment.layoutFragmentFrame.minY + textView.textContainerInset.top - 12)
            return (location, distance > Self.scrollAlignmentAllowance ? distance : 0)
        }

        func scrollToTop(of characterLocation: Int, distanceIntoLine: CGFloat = 0, in textView: UITextView) {
            pinnedHeading = HeadingJumpPin(location: characterLocation, pinnedAtUptime: currentUptime, distanceIntoLine: distanceIntoLine)
            guard let textLayoutManager = textView.textLayoutManager,
                  let contentStorage = textLayoutManager.textContentManager as? NSTextContentStorage,
                  let location = contentStorage.location(contentStorage.documentRange.location, offsetBy: characterLocation),
                  let precedingRange = NSTextRange(location: contentStorage.documentRange.location, end: location) else { return }
            // Positions before the heading must be real, not estimated, for the jump to land.
            textLayoutManager.ensureLayout(for: precedingRange)
            guard let fragment = textLayoutManager.textLayoutFragment(for: location) else { return }
            let targetOffset = fragment.layoutFragmentFrame.minY + textView.textContainerInset.top - 12 + distanceIntoLine
            let maximumOffset = maximumContentOffset(of: textView, layoutManager: textLayoutManager)
            textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: min(max(-textView.adjustedContentInset.top, targetOffset), maximumOffset)), animated: false)
            textView.setNeedsLayout()
        }
    }
}
#endif

extension NativeMarkdownEditor {
    /// Shown when a pasted or dropped item's content cannot be read, so nothing is added.
    static let unreadableItemMessage = "An item could not be read, so it was not added to the note."

    /// An edit that starts in the rendered properties' YAML and reaches its end, as a backspace
    /// at the start of the note's text does, would join their closing line to the text and
    /// turn the properties into text.
    static func cutsIntoRenderedProperties(_ range: NSRange, propertiesEnd: Int) -> Bool {
        range.location > 0 && range.location < propertiesEnd && NSMaxRange(range) >= propertiesEnd
    }
}
