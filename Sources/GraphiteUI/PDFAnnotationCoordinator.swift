/**
 * File: PDFAnnotationCoordinator.swift
 * ------------------------------------
 * Layer: UI
 * Description: Puts a PencilKit canvas on each PDF page and connects it to the tools, the palette, touches and saving.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
import UIKit
import PencilKit

/// Owns the Pencil canvases of one PDF view and turns their drawings and text selections
/// into edits of the session.
///
/// PDFKit calls the overlay provider on the main thread; its Objective-C protocol has no
/// actor annotations, so the preconcurrency conformance checks isolation at run time.
@MainActor
final class PDFAnnotationCoordinator: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate,
                                      UIGestureRecognizerDelegate, @preconcurrency UIEditMenuInteractionDelegate, PDFInkCanvasProvider {
    /// Canvases of pages that scrolled away are kept for a while, so scrolling back does
    /// not decode their ink again. Undo does not depend on them: the PDF's history names
    /// pages, not canvases.
    private static let retainedHiddenCanvasCount = 6
    private static let textSelectionPressDuration: TimeInterval = 0.35
    private static let selectionMenuIdentifier = "GraphiteTextSelection" as NSString
    private static let markupMenuIdentifier = "GraphiteMarkup" as NSString

    let session: PDFSession
    /// An embed sits inside the note's own scroll view, which annotating restricts too.
    let isEmbedded: Bool
    var beginInteraction: (() -> Void)?
    var linkActions: PDFLinkActions?
    /// Where the lasso's pictures of a page can be added as an attachment.
    var noteDestination: LassoNoteDestination?
    /// See `GraphitePDFView.beginWritingWithPencil`.
    var beginWritingWithPencil: (() -> Void)?
    private var pencilWhileReadingRecognizer: PencilTouchDownRecognizer?
    private weak var pdfView: GraphitePDFDisplayView?
    /// Canvases whose drawing recognizer is left finished with no touch down (`CanvasLeftDrawingWatch`).
    private var leftDrawingWatch = CanvasLeftDrawingWatch()
    /// The pictures of the combined ink groups of the pages shown (`PDFCombinedInkPictures`), made with the first page shown.
    private(set) var combinedInkPictures: PDFCombinedInkPictures?
    /// Apple's floating palette, which this view's canvases follow.
    let toolPicker = PencilToolPalette.makeToolPicker()
    private lazy var paletteAccessoryItem = PencilToolPalette.makeAccessoryItem(
        for: toolPicker, offersReadAloudPen: { [weak self] in self?.readAloudPen != nil }, offersTextBoxes: true)
    private let toolPickerHost = PencilToolPickerHostView()
    /// The palette is drawn above every screen of the app; it gives way while a sheet, an
    /// alert or a file picker is presented over the PDF.
    private lazy var presentedScreenObserver = PresentedScreenObserver(view: toolPickerHost) { [weak self] in
        self?.updateToolPickerVisibility()
    }
    var canvasesByPage: [ObjectIdentifier: PDFPageCanvasView] = [:]
    private var displayedPages: Set<ObjectIdentifier> = []
    private var hiddenCanvasOrder: [ObjectIdentifier] = []
    private var input = PDFAnnotationInput(isEnabled: false, drawsWithFinger: false, showsToolPicker: false)
    private var markupTapRecognizer: UITapGestureRecognizer?
    private var textSelectionRecognizer: UILongPressGestureRecognizer?
    /// Takes a resting hand's touches on the pages, which the page's scrolling, zooming,
    /// tapping and selecting wait for (`PalmRejectionRecognizer`).
    private var palmRejection: PalmRejectionInstallation?
    private var editMenuInteraction: UIEditMenuInteraction?
    private var tappedMarkup: (annotation: PDFAnnotation, page: PDFPage)?
    /// Opens a note's text when its icon is tapped (`PDFNoteReading`).
    private(set) var noteReading: PDFNoteReading?
    /// Where the saved text-mark colours are kept (`PDFTextMarkColors`); a test gives its own.
    var markupPreferences: UserDefaults = .standard
    private lazy var markColorPicker = PDFMarkColorPicker(preferences: markupPreferences)
    /// The finger's text selection being dragged (`handleTextSelection`).
    private var selectionDrag: PDFTextSelectionDrag?
    /// The fixed bar's text highlighter: a drag on a page selects text and marks it on lift.
    private var textHighlighter: PDFTextHighlighterInteraction?
    /// Erases the text marks the eraser passes over (`PDFTextMarkEraser`).
    private var textMarkEraser: PDFTextMarkEraser?
    private var pageObserver: PDFViewPageObserver?
    private var pictureSelection: PDFPictureSelectionController?
    /// The page's text boxes: drawn over the ink, placed, selected and typed in.
    private var textBoxInteraction: PDFTextBoxInteraction?
    /// Takes pictures dropped onto the pages; a PDF embedded in a note leaves drops to the note.
    private(set) var pictureDrops: PDFPictureDropInteraction?
    private var toolboxObserver: NSObjectProtocol?
    private var zoomObserver: NSObjectProtocol?
    /// Draws the canvases at the zoom once it has settled, not at every step of a pinch.
    private var renderingScaleUpdate: DispatchWorkItem?
    /// The pixels a page's canvas may take after a memory warning: a quarter of the usual, so
    /// the canvas covers less of the page around what is on screen, still at the zoom.
    private static let canvasPixelBudgetAfterMemoryWarning = PDFCanvasShownRegion.maximumCanvasPixelCount / 4
    private var isHoldingCanvasMemory = false
    /// Follows the pages' scrolling, so a canvas covering part of its page moves with it.
    private var pagesScrollObservation: NSKeyValueObservation?
    private var scaleFactorAtMemoryWarning: CGFloat = 0
    private var memoryWarningObserver: NSObjectProtocol?
    /// For tests, which cannot send touches.
    var pictureSelectionController: PDFPictureSelectionController? { pictureSelection }
    /// For tests: how many times a canvas's strokes were all compared with those last recorded.
    var everyStrokeComparisonCount = 0
    /// For tests: how many decodes of a page's stored ink were begun, and how many of them ran on the main actor.
    var storedInkDecodeCount = 0
    var mainActorDecodeCount = 0
    /// Held weakly: a recognizer made later at a freed one's address is observed too.
    private let observedScrollRecognizers = NSHashTable<UIGestureRecognizer>.weakObjects()
    /// The scroll views around this embed that it restricts while annotating.
    private var restrictedEnclosingScrollViews: [ObjectIdentifier] = []
    private var hasAppliedInput = false
    private var hasPendingFirstResponderUpdate = false
    /// True once the view is dismantled; the coordinator is not used again.
    var isDetached = false
    /// The session's view generation this coordinator's view was made for (`PDFSession.rebuildView`).
    var viewGeneration = 0
    /// The window's kept PDF views, where this view goes while its tab is hidden.
    weak var hiddenViews: HiddenPDFViews?
    /// True while the view is kept for its hidden tab (`HiddenPDFViews`), off screen.
    private(set) var isParked = false

    /// Whether the kept view can come back: still its session's newest view, not built again since.
    var canShowAgain: Bool { isParked && !isDetached && pdfView != nil && session.viewGeneration == viewGeneration }

    /// The view leaves the screen with its tab and is kept: its ink recorded, the palette put
    /// away, nothing watching touches; the canvases, their ink and the history stay, and the
    /// session's saves and undo still reach them.
    func park() {
        for canvas in canvasesByPage.values { recordUnrecordedInk(of: canvas) }
        healthMonitor?.stop()
        healthMonitor = nil
        presentedScreenObserver.isObserving = false
        toolPicker.setVisible(false, forFirstResponder: toolPickerHost)
        toolPickerHost.takesFirstResponderBackFromSelections = false
        toolPickerHost.resignFirstResponderOnNextTurn()
        isParked = true
    }

    /// The kept view is shown again; its window change brings back the palette and first responder.
    func resume() {
        isParked = false
        hasAppliedInput = false
        // Undo and redo reach the canvases shown again, whichever view of the session was attached meanwhile.
        session.inkCanvasProvider = self
        if let pdfView { healthMonitor = PDFPaneHealthMonitor(coordinator: self, pdfView: pdfView) }
    }
    /// Watches that the PDF keeps taking touches (`PDFPaneHealthMonitor`).
    private var healthMonitor: PDFPaneHealthMonitor?

    /// A scroll view around annotating embeds, with the gesture settings it had before.
    private struct EnclosingScrollRestriction {
        weak var scrollView: UIScrollView?
        let panTouchTypes: [NSNumber]
        let minimumPanTouchCount: Int
        let pinchTouchTypes: [NSNumber]?
        var restrictingCoordinators: Set<ObjectIdentifier>
    }

    /// Shared by every coordinator: two annotating embeds in one note restrict the same
    /// scroll view, and its own settings come back only when the last of them stops.
    private static var enclosingScrollRestrictions: [ObjectIdentifier: EnclosingScrollRestriction] = [:]

    init(session: PDFSession, isEmbedded: Bool) {
        self.session = session
        self.isEmbedded = isEmbedded
        super.init()
    }

    func attach(to view: GraphitePDFDisplayView) {
        pdfView = view
        view.annotationCoordinator = self
        view.documentUndoManager = session.undoManager
        toolPickerHost.documentUndoManager = session.undoManager
        toolPickerHost.canvases = { [weak self] in self.map { coordinator in Array(coordinator.canvasesByPage.values) } ?? [] }
        session.inkCanvasProvider = self
        view.addSubview(toolPickerHost)
        toolPicker.accessoryItem = paletteAccessoryItem
        if !isEmbedded { toolPicker.addObserver(paletteInsetObserver) }
        let fingerAndPointer = [UITouch.TouchType.direct, .indirectPointer].map { touchType in NSNumber(value: touchType.rawValue) }

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapRecognizer.delegate = self
        tapRecognizer.allowedTouchTypes = fingerAndPointer
        view.addGestureRecognizer(tapRecognizer)
        markupTapRecognizer = tapRecognizer

        let selectionRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTextSelection(_:)))
        selectionRecognizer.minimumPressDuration = Self.textSelectionPressDuration
        selectionRecognizer.delegate = self
        selectionRecognizer.allowedTouchTypes = fingerAndPointer
        view.addGestureRecognizer(selectionRecognizer)
        textSelectionRecognizer = selectionRecognizer

        installPencilWhileReadingRecognizer(in: view)
        noteReading = PDFNoteReading(view: view, session: session)

        // A hand resting on a page while the Pencil writes does not tap, select, scroll or zoom.
        palmRejection = PencilActivity.installRecognizers(in: view, isWriting: { [weak self] in self?.input.isEnabled ?? false },
                                                          handTouchesDidChange: { [weak self] handTouches in self?.handTouchesDidChange(handTouches) })
        makeWaitForPalmRejection([tapRecognizer, selectionRecognizer])

        let menuInteraction = UIEditMenuInteraction(delegate: self)
        view.addInteraction(menuInteraction)
        editMenuInteraction = menuInteraction
        pageObserver = PDFViewPageObserver(session: session, view: view)
        healthMonitor = PDFPaneHealthMonitor(coordinator: self, pdfView: view)
        toolboxObserver = NotificationCenter.default.addObserver(forName: PencilToolbox.selectionDidChange, object: PencilToolbox.shared, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.takeFixedToolFromToolbox() }
        }
        let pictureSelection = PDFPictureSelectionController(session: session, pdfView: view)
        self.pictureSelection = pictureSelection
        session.visiblePageCenter = { [weak pictureSelection] in pictureSelection?.visiblePageCenter() }
        textBoxInteraction = PDFTextBoxInteraction(session: session, pdfView: view)
        if !isEmbedded { pictureDrops = PDFPictureDropInteraction(session: session, pdfView: view) }
        textHighlighter = PDFTextHighlighterInteraction(session: session, pdfView: view)
        textMarkEraser = PDFTextMarkEraser(session: session, pdfView: view)
        session.registerPendingInkRecordWriter(for: self, inBackground: { [weak self] in
            await self?.writeDeferredInkRecordsInBackground()
        }) { [weak self] in self?.writeDeferredInkRecords() }
        session.registerUnrecordedInkRecorder(for: self) { [weak self] in self?.recordUnrecordedInkBeforeHistoryStep() }
        zoomObserver = NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: view, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRenderingScaleUpdate() }
        }
        pagesScrollObservation = view.pagesScrollView?.observe(\.contentOffset) { [weak self] _, _ in
            // Reported on the main thread that scrolls; the canvases move on the main actor.
            Task { @MainActor [weak self] in self?.followVisibleAreaOfCanvases() }
        }
        observeMemoryWarnings()
    }

    /// A Pencil on a page while reading switches to writing, and draws (`handlePencilTouchWhileReading`).
    private func installPencilWhileReadingRecognizer(in view: GraphitePDFDisplayView) {
        let pencilRecognizer = PencilTouchDownRecognizer(target: self, action: #selector(handlePencilTouchWhileReading(_:)))
        pencilRecognizer.drawingRecognizerUnderTouch = { [weak self, weak view] touch in
            guard let self, let view, !self.input.isEnabled, self.beginWritingWithPencil != nil,
                  let canvas = self.shownCanvas(at: touch.location(in: view), in: view) else { return nil }
            // PencilKit draws only on a canvas that takes touches; going on writing leaves it so.
            canvas.isUserInteractionEnabled = true
            return canvas.drawingGestureRecognizer
        }
        pencilRecognizer.delegate = self
        pencilRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        view.addGestureRecognizer(pencilRecognizer)
        pencilWhileReadingRecognizer = pencilRecognizer
    }

    private func observeMemoryWarnings() {
        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
            queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.releaseMemoryOfCanvases() }
        }
    }

    /// Ink drawn while zooming is magnified, as PencilKit's own canvas does it; it is drawn
    /// again at the new scale once the zoom has stayed for a moment.
    private func scheduleRenderingScaleUpdate() {
        renderingScaleUpdate?.cancel()
        if let pdfView, abs(pdfView.scaleFactor - scaleFactorAtMemoryWarning) > 0.001 { isHoldingCanvasMemory = false }
        let update = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.updateRenderingScale() }
        }
        renderingScaleUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: update)
    }

    /// A stroke under way keeps its canvas as it is: the new scale waits for the lift, since
    /// laying the canvas out again changes its bounds and zoom under PencilKit's live stroke.
    private func updateRenderingScale() {
        guard !isDetached, let pdfView else { return }
        if isStrokeUnderWay {
            scheduleRenderingScaleUpdate()
            return
        }
        // Only what is on screen; a kept page stays at its own size (`willEndDisplayingOverlayView`).
        for identifier in displayedPages {
            guard let canvas = canvasesByPage[identifier] else { continue }
            canvas.overlayView?.setRenderingScale(renderingScale(in: pdfView))
            canvas.overlayView?.canvasPixelBudget = canvasPixelBudget
            // Laid out now, while no stroke is known to be under way: left to the next layout
            // pass, the canvas changed size under a stroke begun in between.
            canvas.overlayView?.layoutIfNeeded()
            // A canvas covering part of its page takes the part now on screen.
            canvas.overlayView?.followVisibleArea()
            // The eraser follows the zoom on screen, also past where the canvas's scale stops.
            if canvas.tool is PKEraserTool { canvas.retakeChosenTool() }
        }
    }

    /// PencilKit's recognizer stays `.possible` until a stroke has moved a little, so the touches
    /// it follows count as well.
    private var isStrokeUnderWay: Bool {
        PencilActivity.isPencilTouching(at: PencilActivity.now)
            || canvasesByPage.values.contains { canvas in
                canvas.drawingGestureRecognizer.state != .possible || canvas.drawingGestureRecognizer.numberOfTouches > 0
            }
    }

    /// The scale a page's canvas draws at for the view's zoom: the zoom, at any zoom.
    private func renderingScale(in view: PDFView) -> CGFloat {
        PDFPageOverlayView.renderingScale(forZoom: view.scaleFactor)
    }

    /// The pixels a page's canvas may take. After a memory warning, until the next change of
    /// zoom, a quarter of the usual: the canvas covers less of its page, still at the zoom.
    private var canvasPixelBudget: CGFloat {
        isHoldingCanvasMemory ? Self.canvasPixelBudgetAfterMemoryWarning : PDFCanvasShownRegion.maximumCanvasPixelCount
    }

    /// The pages scrolled: a canvas that covers part of its page moves with what is on screen,
    /// not during a stroke, which waits for the lift, nor during a pinch, after which the zoom's
    /// update lays the canvases out again.
    private func followVisibleAreaOfCanvases() {
        guard !isDetached, !isParked, let pdfView, !(pdfView.pagesScrollView?.isZooming ?? false) else { return }
        let overlays = displayedPages.compactMap { identifier in canvasesByPage[identifier]?.overlayView }
        guard overlays.contains(where: { overlay in overlay.shownRegion.size != overlay.bounds.size }) else { return }
        if isStrokeUnderWay {
            scheduleRenderingScaleUpdate()
            return
        }
        for overlay in overlays { overlay.followVisibleArea() }
    }

    /// The system is short of memory: pages kept for scrolling back go, after their ink is
    /// recorded, and the pages on screen take less of it. Being killed would lose what was
    /// written since the last save.
    private func releaseMemoryOfCanvases() {
        guard !isDetached, let pdfView else { return }
        for identifier in hiddenCanvasOrder {
            if let canvas = canvasesByPage.removeValue(forKey: identifier) { release(canvas) }
        }
        hiddenCanvasOrder.removeAll()
        isHoldingCanvasMemory = true
        scaleFactorAtMemoryWarning = pdfView.scaleFactor
        for identifier in displayedPages {
            canvasesByPage[identifier]?.overlayView?.canvasPixelBudget = canvasPixelBudget
        }
    }

    func detach() {
        isDetached = true
        paletteFrameFollowing?.cancel()
        paletteFrameFollowing = nil
        combinedInkPictures?.stop()
        combinedInkPictures = nil
        healthMonitor?.stop()
        healthMonitor = nil
        presentedScreenObserver.isObserving = false
        toolPicker.setVisible(false, forFirstResponder: toolPickerHost)
        toolPickerHost.takesFirstResponderBackFromSelections = false
        // Called as SwiftUI dismantles the view, in the middle of its update.
        toolPickerHost.resignFirstResponderOnNextTurn()
        for canvas in canvasesByPage.values { release(canvas) }
        canvasesByPage.removeAll()
        session.unregisterPendingInkRecordWriter(for: self)
        // The session's history outlives this view; a later view of the session applies it.
        if session.inkCanvasProvider === self { session.inkCanvasProvider = nil }
        restoreEnclosingScrollViews()
        pageObserver?.stop()
        pictureSelection?.stop()
        pictureSelection = nil
        textBoxInteraction?.stop()
        pictureDrops?.stop()
        pictureDrops = nil
        textBoxInteraction = nil
        textHighlighter = nil
        textMarkEraser = nil
        if let toolboxObserver { NotificationCenter.default.removeObserver(toolboxObserver) }
        toolboxObserver = nil
        if let zoomObserver { NotificationCenter.default.removeObserver(zoomObserver) }
        zoomObserver = nil
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        memoryWarningObserver = nil
        renderingScaleUpdate?.cancel()
        pagesScrollObservation = nil
    }

    func highlightReading(_ highlights: [PDFReadAloudHighlight], followsReading: Bool, suspendFollowing: (() -> Void)?,
                          reportFrame: ((CGRect?, CGRect?) -> Void)? = nil) {
        pageObserver?.highlightReading(highlights, followsReading: followsReading, suspendFollowing: suspendFollowing, reportFrame: reportFrame)
    }

    // MARK: The Read Aloud pen

    /// Set from the view: where the pen's taps go. Canvases take it as they are configured.
    var readAloudPen: ((PDFReadAloudPenTap) -> Void)? {
        didSet {
            guard (readAloudPen == nil) != (oldValue == nil) else { return }
            for canvas in canvasesByPage.values { configure(canvas) }
        }
    }
    private var readAloudMarkers: [PDFReadAloudMarker] = []

    /// Set from the view: told where the palette covers the window as it shows, hides or moves.
    var reportPaletteFrame: ((CGRect?) -> Void)? {
        didSet {
            guard reportPaletteFrame != nil, paletteFrameObserver == nil else { return }
            let observer = PaletteFrameObserver { [weak self] in self?.reportPaletteFrameNow() }
            toolPicker.addObserver(observer)
            paletteFrameObserver = observer
        }
    }
    private var paletteFrameObserver: PaletteFrameObserver?
    /// Keeps the last page clear of a palette docked along the bottom of a phone's screen.
    private lazy var paletteInsetObserver = PaletteFrameObserver { [weak self] in self?.clearPagesOfPalette() }

    /// A palette docked at the bottom of a phone covers the last 70 to 100 points of the pages, and the PDF reaches
    /// under the bottom safe area: the pages scroll that far past their end while it shows, and no further after.
    private func clearPagesOfPalette() {
        followPaletteFrameWhileItSettles(applyPaletteInset())
    }

    /// Insets the pages by the height the palette covers, and says whether the palette shows without a frame yet.
    private func applyPaletteInset() -> Bool {
        guard let pdfView, let scrollView = pdfView.pagesScrollView else { return false }
        var coveredHeight: CGFloat = 0
        var awaitsPaletteFrame = false
        if pdfView.window != nil, toolPicker.isVisible {
            let obscured = toolPicker.frameObscured(in: pdfView)
            if !obscured.isNull, !obscured.isEmpty { coveredHeight = pdfView.bounds.intersection(obscured).height } else { awaitsPaletteFrame = true }
        }
        if abs(scrollView.contentInset.bottom - coveredHeight) > 0.5 {
            scrollView.contentInset.bottom = coveredHeight
            scrollView.verticalScrollIndicatorInsets.bottom = coveredHeight
        }
        return awaitsPaletteFrame
    }

    /// The palette tells its observers it shows before it knows where it docks, and does not tell them again when it
    /// does (HUNT-273: on an iPhone 17 Pro simulator, iOS 27.2, the frame came a moment later and the pages kept no
    /// inset). While it shows without a frame, the frame is looked at again every 50 ms for up to two seconds.
    private func followPaletteFrameWhileItSettles(_ awaitsPaletteFrame: Bool) {
        guard awaitsPaletteFrame else {
            paletteFrameFollowing?.cancel()
            paletteFrameFollowing = nil
            return
        }
        guard paletteFrameFollowing == nil else { return }
        paletteFrameFollowing = Task { [weak self, paletteFrameClock] in
            for _ in 0..<40 {
                try? await paletteFrameClock.sleep(for: .milliseconds(50)) // Cancelled when the frame is known or the palette goes; checked next.
                guard !Task.isCancelled, let self else { return }
                guard self.applyPaletteInset() else { break }
            }
            self?.paletteFrameFollowing = nil
        }
    }

    private var paletteFrameFollowing: Task<Void, Never>?
    private let paletteFrameClock: any Clock<Duration> = ContinuousClock()

    /// The height along the bottom of the window that a floating palette takes, with its margin.
    private static let floatingPaletteBand: CGFloat = 150

    private func reportPaletteFrameNow() {
        guard let reportPaletteFrame else { return }
        guard let pdfView, pdfView.window != nil, toolPicker.isVisible else { reportPaletteFrame(nil); return }
        let obscured = toolPicker.frameObscured(in: pdfView)
        guard obscured.isNull || obscured.isEmpty, let window = pdfView.window else {
            reportPaletteFrame(pdfView.convert(obscured, to: nil))
            return
        }
        // A palette floating on iPad reports no frame; it starts along the bottom of the
        // window, where the player then does not go.
        reportPaletteFrame(CGRect(x: window.bounds.minX, y: window.bounds.maxY - Self.floatingPaletteBand,
                                  width: window.bounds.width, height: Self.floatingPaletteBand))
    }

    /// The word under a tap of the pen, or the whole page where the page has no text.
    func handleReadAloudPenTap(atWindowPoint windowPoint: CGPoint) {
        guard let pdfView, let readAloudPen else { return }
        let viewPoint = pdfView.convert(windowPoint, from: nil)
        guard let page = pdfView.page(for: viewPoint, nearest: false) else { return }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        if (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            readAloudPen(.page(pageIndex: pageIndex))
            return
        }
        let pagePoint = pdfView.convert(viewPoint, to: page)
        // A tap in the margin, between columns or on a figure reads nothing.
        guard let word = page.selectionForWord(at: pagePoint) else { return }
        let bounds = word.bounds(for: page)
        let range = word.range(at: 0, on: page)
        guard bounds.insetBy(dx: -8, dy: -6).contains(pagePoint), range.location != NSNotFound, range.length > 0 else { return }
        readAloudPen(.word(pageIndex: pageIndex, range: range, bounds: bounds))
    }

    func showReadAloudMarkers(_ markers: [PDFReadAloudMarker]) {
        guard markers != readAloudMarkers else { return }
        readAloudMarkers = markers
        for canvas in canvasesByPage.values { placeReadAloudMarkers(on: canvas) }
    }

    /// The markers of a page, over its overlay, so they scroll and zoom with the page and
    /// never enter its file.
    private func placeReadAloudMarkers(on canvas: PDFPageCanvasView) {
        guard let overlay = canvas.overlayView, let page = canvas.page else { return }
        for marker in overlay.subviews where marker is ReadAloudPenMarkerView { marker.removeFromSuperview() }
        let pageIndex = session.document.index(for: page)
        let box = page.bounds(for: pdfView?.displayBox ?? .cropBox)
        guard box.width > 0, box.height > 0, overlay.bounds.width > 0 else { return }
        let scaleX = overlay.bounds.width / box.width, scaleY = overlay.bounds.height / box.height
        for marker in readAloudMarkers where marker.pageIndex == pageIndex {
            let markerView = ReadAloudPenMarkerView(isStart: marker.isStart)
            overlay.addSubview(markerView)
            // Page space grows upward from the box's corner; the overlay's grows downward.
            markerView.place(overWord: CGRect(x: (marker.bounds.minX - box.minX) * scaleX, y: (box.maxY - marker.bounds.maxY) * scaleY,
                                              width: marker.bounds.width * scaleX, height: marker.bounds.height * scaleY))
        }
    }

    func update(input newInput: PDFAnnotationInput) {
        guard let pdfView else { return }
        defer {
            updateToolPickerVisibility(isInsideViewUpdate: true)
            // The session's selected picture or text box may have changed; SwiftUI updates the view then.
            pictureSelection?.update()
            textBoxInteraction?.syncWithActivity()
        }
        // SwiftUI calls this on every update of the pane; the view tree is walked only
        // when the input actually changes.
        guard newInput != input || !hasAppliedInput else { return }
        hasAppliedInput = true
        let wasEnabled = input.isEnabled
        input = newInput
        PencilToolPalette.updateShapesButton(paletteAccessoryItem, isOn: newInput.drawsShapes)
        if wasEnabled != newInput.isEnabled {
            // Reading is not typing in a box or arranging one.
            if !newInput.isEnabled { session.textBoxActivity = .idle }
            editMenuInteraction?.dismissMenu()
            tappedMarkup = nil
            selectionDrag = nil
            pdfView.clearSelection()
        }
        for canvas in canvasesByPage.values { configure(canvas) }
        // ⌘V pastes while the PDF is written on (`PDFAnnotationCoordinator.pasteFromPasteboard`).
        toolPickerHost.pasteFromPasteboard = newInput.isEnabled ? { [weak self] in self?.pasteFromPasteboard() } : nil
        configureScrollGestures(of: pdfView)
        configureEnclosingScrollViews(of: pdfView)
        // With finger drawing, a long press belongs to the pen, as in Goodnotes.
        textSelectionRecognizer?.isEnabled = newInput.isEnabled && !newInput.drawsWithFinger
    }

    /// With the fixed tool bar, a canvas draws with the bar's tool from the moment it is
    /// chosen; SwiftUI's update of this view would come a moment later.
    private func takeFixedToolFromToolbox() {
        guard input.fixedTool != nil else { return }
        input.fixedTool = PencilToolbox.shared.selection
        for canvas in canvasesByPage.values { canvas.takeTool(from: toolPicker, fixedTool: input.fixedTool) }
    }

    func windowDidChange() {
        healthMonitor?.windowDidChange(to: pdfView?.window)
        // SwiftUI settles focus after inserting the view; claim first responder after it.
        Task { @MainActor [weak self] in self?.updateToolPickerVisibility() }
    }

    // MARK: Undo history

    func editingCanvas(for page: PDFPage) -> PDFPageCanvasView? {
        guard let canvas = canvasesByPage[ObjectIdentifier(page)], canvas.page === page, canvas.hasRestoredStoredInk,
              !canvas.isRestoringStoredInk, canvas.delegate != nil else { return nil }
        return canvas
    }

    func isDisplaying(_ page: PDFPage) -> Bool {
        displayedPages.contains(ObjectIdentifier(page))
    }

    // MARK: Touch routing

    func canvas(at point: CGPoint, in view: PDFView) -> PDFPageCanvasView? {
        input.isEnabled ? shownCanvas(at: point, in: view) : nil
    }

    /// The canvas shown at a point, while writing or reading, also while its stored ink is
    /// decoded: what it draws then is recorded after that ink (`mergeStoredInk`).
    private func shownCanvas(at point: CGPoint, in view: PDFView) -> PDFPageCanvasView? {
        for identifier in displayedPages {
            guard let canvas = canvasesByPage[identifier], canvas.window != nil, !canvas.isHidden else { continue }
            if canvas.bounds.contains(canvas.convert(point, from: view)) { return canvas }
        }
        return nil
    }

    /// While annotating, the Pencil never scrolls or zooms; with finger drawing, one
    /// finger draws and scrolling takes two, as in Goodnotes.
    private func configureScrollGestures(of view: UIView) {
        let withoutPencil = [UITouch.TouchType.direct, .indirect, .indirectPointer].map { touchType in NSNumber(value: touchType.rawValue) }
        let allTouchTypes = withoutPencil + [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        for scrollView in scrollViews(in: view) {
            scrollView.panGestureRecognizer.allowedTouchTypes = input.isEnabled ? withoutPencil : allTouchTypes
            scrollView.panGestureRecognizer.minimumNumberOfTouches = input.isEnabled && input.drawsWithFinger ? 2 : 1
            scrollView.pinchGestureRecognizer?.allowedTouchTypes = input.isEnabled ? withoutPencil : allTouchTypes
            for recognizer in [scrollView.panGestureRecognizer, scrollView.pinchGestureRecognizer].compactMap({ recognizer in recognizer })
            where !observedScrollRecognizers.contains(recognizer) {
                recognizer.addTarget(self, action: #selector(scrollGestureChanged(_:)))
                observedScrollRecognizers.add(recognizer)
            }
            makeWaitForPalmRejection([scrollView.panGestureRecognizer, scrollView.pinchGestureRecognizer].compactMap { recognizer in recognizer })
        }
        // PDFKit's own taps and long presses on its pages, which it adds as pages are shown.
        makeWaitForPalmRejection(pageTapsAndPresses(in: view))
    }

    /// Makes recognizers wait for palm rejection to fail, each once. It fails at once for a
    /// finger while the Pencil is not active, so they do not wait for one.
    private func makeWaitForPalmRejection(_ recognizers: [UIGestureRecognizer]) {
        palmRejection?.makeWait(recognizers)
    }

    /// For tests, which cannot send a Pencil's touches.
    var pencilTouchWhileReadingRecognizer: PencilTouchDownRecognizer? { pencilWhileReadingRecognizer }

    /// For tests, which cannot send touches: whether a recognizer waits for palm rejection.
    func waitsForPalmRejection(_ recognizer: UIGestureRecognizer) -> Bool {
        palmRejection?.isWaiting(recognizer) ?? false
    }

    /// For tests: the recognizer that takes a resting hand's touches.
    var palmRejectionRecognizer: PalmRejectionRecognizer? { palmRejection?.recognizer }

    /// The taps and long presses of the pages, not of the Pencil canvases, whose drawing
    /// must never wait, nor of a picture's selection frame.
    private func pageTapsAndPresses(in view: UIView) -> [UIGestureRecognizer] {
        guard !(view is PKCanvasView), !(view is SelectionFrameView) else { return [] }
        let ownRecognizers = (view.gestureRecognizers ?? []).filter { recognizer in
            recognizer is UITapGestureRecognizer || recognizer is UILongPressGestureRecognizer
        }
        return ownRecognizers + view.subviews.flatMap { subview in pageTapsAndPresses(in: subview) }
    }

    /// With finger drawing, a stroke a resting hand began on any page is taken back.
    private func handTouchesDidChange(_ handTouches: [UITouch]) {
        guard input.drawsWithFinger else { return }
        for canvas in canvasesByPage.values { canvas.takeBackStroke(ofHand: handTouches) }
    }

    /// With finger drawing, the first finger of a two-finger scroll or pinch has already
    /// started a stroke (or erasing) on the canvas. Cancelling the canvas input when the
    /// scroll begins discards that partial stroke, as Goodnotes does.
    @objc private func scrollGestureChanged(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .began, input.isEnabled, input.drawsWithFinger else { return }
        for canvas in canvasesByPage.values where canvas.drawingGestureRecognizer.state != .possible {
            canvas.drawingGestureRecognizer.isEnabled = false
            canvas.drawingGestureRecognizer.isEnabled = true
        }
    }

    /// The note around an embed scrolls by the same rule while annotating: otherwise its pan
    /// takes Pencil and one-finger strokes on the pages, scrolling the note or cutting the
    /// stroke short. The note's own settings come back when annotating ends.
    private func configureEnclosingScrollViews(of view: UIView) {
        guard isEmbedded, input.isEnabled else {
            restoreEnclosingScrollViews()
            return
        }
        if restrictedEnclosingScrollViews.isEmpty {
            for scrollView in enclosingScrollViews(of: view) {
                let identifier = ObjectIdentifier(scrollView)
                var restriction = Self.enclosingScrollRestrictions[identifier].flatMap { restriction in restriction.scrollView === scrollView ? restriction : nil }
                    ?? EnclosingScrollRestriction(scrollView: scrollView,
                                                  panTouchTypes: scrollView.panGestureRecognizer.allowedTouchTypes,
                                                  minimumPanTouchCount: scrollView.panGestureRecognizer.minimumNumberOfTouches,
                                                  pinchTouchTypes: scrollView.pinchGestureRecognizer?.allowedTouchTypes,
                                                  restrictingCoordinators: [])
                restriction.restrictingCoordinators.insert(ObjectIdentifier(self))
                Self.enclosingScrollRestrictions[identifier] = restriction
                restrictedEnclosingScrollViews.append(identifier)
            }
        }
        let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        for identifier in restrictedEnclosingScrollViews {
            guard let restriction = Self.enclosingScrollRestrictions[identifier], let scrollView = restriction.scrollView else { continue }
            scrollView.panGestureRecognizer.allowedTouchTypes = restriction.panTouchTypes.filter { touchType in touchType != pencil }
            scrollView.panGestureRecognizer.minimumNumberOfTouches = input.drawsWithFinger ? max(2, restriction.minimumPanTouchCount) : restriction.minimumPanTouchCount
            if let pinchTouchTypes = restriction.pinchTouchTypes {
                scrollView.pinchGestureRecognizer?.allowedTouchTypes = pinchTouchTypes.filter { touchType in touchType != pencil }
            }
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollGestureChanged(_:)))
            // A hand resting on the page does not scroll the note under the Pencil. The wait
            // fails at once for a finger while the Pencil is away, and when nothing is written.
            makeWaitForPalmRejection([scrollView.panGestureRecognizer])
        }
    }

    private func restoreEnclosingScrollViews() {
        for identifier in restrictedEnclosingScrollViews {
            guard var restriction = Self.enclosingScrollRestrictions[identifier] else { continue }
            restriction.scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(scrollGestureChanged(_:)))
            restriction.restrictingCoordinators.remove(ObjectIdentifier(self))
            guard restriction.restrictingCoordinators.isEmpty else {
                Self.enclosingScrollRestrictions[identifier] = restriction
                continue
            }
            Self.enclosingScrollRestrictions[identifier] = nil
            guard let scrollView = restriction.scrollView else { continue }
            scrollView.panGestureRecognizer.allowedTouchTypes = restriction.panTouchTypes
            scrollView.panGestureRecognizer.minimumNumberOfTouches = restriction.minimumPanTouchCount
            if let pinchTouchTypes = restriction.pinchTouchTypes { scrollView.pinchGestureRecognizer?.allowedTouchTypes = pinchTouchTypes }
        }
        restrictedEnclosingScrollViews.removeAll()
    }

    private func enclosingScrollViews(of view: UIView) -> [UIScrollView] {
        var scrollViews: [UIScrollView] = []
        var ancestor = view.superview
        while let ancestorView = ancestor {
            if let scrollView = ancestorView as? UIScrollView { scrollViews.append(scrollView) }
            ancestor = ancestorView.superview
        }
        return scrollViews
    }

    /// PDFView's own scroll views, not the canvases (which are scroll views too).
    private func scrollViews(in view: UIView) -> [UIScrollView] {
        guard !(view is PKCanvasView) else { return [] }
        let nested = view.subviews.flatMap { subview in scrollViews(in: subview) }
        guard let scrollView = view as? UIScrollView else { return nested }
        return [scrollView] + nested
    }

    // MARK: Page overlays

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        let identifier = ObjectIdentifier(page)
        if let existing = canvasesByPage[identifier], existing.page === page {
            if let overlayView = existing.overlayView { return overlayView }
            // PDFKit let go of the page's view, and the overlay with it, while the canvas was
            // kept. The canvas goes into a new overlay with its drawing, history and pending
            // record. A new canvas restored the page's ink from its last saved record and lost
            // every stroke drawn since, on screen and, at the next stroke, in the file
            // (seen on the owner's iPad, 2026-10-13).
            let overlayView = PDFPageOverlayView(canvas: existing)
            overlayView.visibleAreaView = view
            overlayView.canvasPixelBudget = canvasPixelBudget
            overlayView.setRenderingScale(renderingScale(in: view))
            return overlayView
        }
        if let replaced = canvasesByPage.removeValue(forKey: identifier) { release(replaced) }
        let canvas = makeCanvas(for: page)
        canvasesByPage[identifier] = canvas
        let overlayView = PDFPageOverlayView(canvas: canvas)
        overlayView.visibleAreaView = view
        overlayView.canvasPixelBudget = canvasPixelBudget
        overlayView.setRenderingScale(renderingScale(in: view))
        return overlayView
    }

    func pdfView(_ pdfView: PDFView, willDisplayOverlayView overlayView: UIView, for page: PDFPage) {
        // PDFKit makes a page's view, with its taps and long presses, as the page is shown.
        makeWaitForPalmRejection(pageTapsAndPresses(in: overlayView.superview ?? overlayView))
        guard let canvas = (overlayView as? PDFPageOverlayView)?.canvas else { return }
        let identifier = ObjectIdentifier(page)
        if canvasesByPage[identifier] !== canvas, canvas.page === page { adoptCanvasShownAgain(canvas, on: page) }
        displayedPages.insert(identifier)
        hiddenCanvasOrder.removeAll { hiddenIdentifier in hiddenIdentifier == identifier }
        // PDFKit shows a page's view again as a zoom changes, which may be during a stroke.
        if isStrokeUnderWay {
            scheduleRenderingScaleUpdate()
        } else {
            (overlayView as? PDFPageOverlayView)?.canvasPixelBudget = canvasPixelBudget
            (overlayView as? PDFPageOverlayView)?.setRenderingScale(renderingScale(in: pdfView))
            (overlayView as? PDFPageOverlayView)?.followVisibleArea()
        }
        configure(canvas)
        showCombinedInk(of: page)
        placeReadAloudMarkers(on: canvas)
        if let overlay = overlayView as? PDFPageOverlayView { textBoxInteraction?.pageDidAppear(page, in: overlay) }
    }

    /// Draws the pictures of the page's combined ink groups (`PDFCombinedInkPictures`).
    private func showCombinedInk(of page: PDFPage) {
        guard !isDetached, let pdfView else { return }
        if combinedInkPictures == nil {
            combinedInkPictures = PDFCombinedInkPictures(view: pdfView, changeVersion: { [weak session] in session?.changeVersion ?? 0 })
        }
        combinedInkPictures?.pageAppeared(page)
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard overlayView is PDFPageOverlayView else { return }
        let identifier = ObjectIdentifier(page)
        displayedPages.remove(identifier)
        combinedInkPictures?.pageLeft(page)
        // The page's ink annotations stay hidden while its canvas is kept: PDFKit gives every annotation a layer of its
        // own, drawn on the main thread from its appearance whenever it is shown, so showing a page's ink each time its
        // view left the screen, and hiding it again as it came back, drew every stroke of the page twice. On a page of
        // 6,000 strokes that froze the iPad for one to two and a half seconds at each zoom (Docs/Bug-hunt-todo.md,
        // HUNT-344). Thumbnails draw hidden ink themselves (`PDFThumbnailRenderer`); the ink shows again when the canvas
        // is let go (`release`).
        textBoxInteraction?.pageDidDisappear(page)
        hiddenCanvasOrder.append(identifier)
        // A page kept for scrolling back takes no more than a page's memory. It leaves the
        // screen now, where nothing lays it out by itself.
        if let keptOverlay = overlayView as? PDFPageOverlayView {
            keptOverlay.setRenderingScale(1)
            keptOverlay.layoutIfNeeded()
        }
        while hiddenCanvasOrder.count > Self.retainedHiddenCanvasCount {
            let evictedIdentifier = hiddenCanvasOrder.removeFirst()
            if let evictedCanvas = canvasesByPage.removeValue(forKey: evictedIdentifier) { release(evictedCanvas) }
        }
    }

    private func makeCanvas(for page: PDFPage) -> PDFPageCanvasView {
        // The page's annotations are read once, for the group of new ink and for the ink to restore.
        let storedInk = PDFInkGroups.storedInk(on: page)
        let canvas = PDFPageCanvasView(page: page, inkTracker: PDFPageInkTracker(group: storedInk.newGroup()))
        canvas.annotationCoordinator = self
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Pages are white paper; dark-mode ink adaptation would make black ink invisible.
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        // Its overlay zooms it to the scale it draws at, which nothing else changes.
        canvas.pinchGestureRecognizer?.isEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.drawingGestureRecognizer.addTarget(self, action: #selector(drawingGestureChanged(_:)))
        restoreStoredInkIfNeeded(on: canvas, knownStoredInk: storedInk)
        configure(canvas)
        textMarkEraser?.follow(canvas)
        // PencilKit's own finger long press (its Select All and Insert Space menu) waits
        // until the press is known not to select PDF text.
        if let textSelectionRecognizer {
            for recognizer in longPressRecognizers(in: canvas) { recognizer.require(toFail: textSelectionRecognizer) }
        }
        // Nor does a resting hand open that menu. PencilKit's drawing itself never waits.
        makeWaitForPalmRejection(longPressRecognizers(in: canvas).filter { recognizer in recognizer !== canvas.drawingGestureRecognizer })
        // A finger tap on a highlight (with finger drawing) opens its menu instead of also
        // leaving a dot. The tap takes only touches on markup or with text selected, so
        // other strokes do not wait for it.
        if let markupTapRecognizer { canvas.drawingGestureRecognizer.require(toFail: markupTapRecognizer) }
        return canvas
    }

    private func longPressRecognizers(in view: UIView) -> [UILongPressGestureRecognizer] {
        (view.gestureRecognizers ?? []).compactMap { recognizer in recognizer as? UILongPressGestureRecognizer }
            + view.subviews.flatMap { subview in longPressRecognizers(in: subview) }
    }

    /// A canvas shows the page's ink while annotating; otherwise the ink annotations do.
    /// The page's canvas shows its ink while reading too, without taking touches: PDFKit
    /// draws the ink annotations as lines of one width in one flat color, so a highlighter
    /// became a thin opaque line, a pencil lost its grain and every stroke its pressure, and
    /// the page changed each time writing was turned on or off. The annotations, which other
    /// PDF readers show, stay hidden only while the page's canvas, shown or kept, has the same ink.
    func configure(_ canvas: PDFPageCanvasView) {
        restoreStoredInkIfNeeded(on: canvas)
        canvas.readAloudPenTapped = readAloudPen == nil ? nil : { [weak self] windowPoint in self?.handleReadAloudPenTap(atWindowPoint: windowPoint) }
        canvas.textToolTapped = { [weak self] windowPoint in self?.textBoxInteraction?.handleTextToolTap(atWindowPoint: windowPoint) }
        canvas.textHighlighterDragged = { [weak self] dragEvent in self?.handleTextHighlighterDrag(dragEvent) }
        canvas.takeTool(from: toolPicker, fixedTool: input.fixedTool)
        canvas.drawingPolicy = input.drawsWithFinger ? .anyInput : .pencilOnly
        canvas.showWritingGuides(input.writingGuides)
        canvas.overlayView?.showsWritingGuides = input.isEnabled
        // While its stored ink is decoded, the page's annotations show it under the canvas, which
        // takes touches: a stroke begun then is kept and recorded after the stored ink (HUNT-307).
        canvas.isUserInteractionEnabled = input.isEnabled
        if let page = canvas.page {
            // Hidden while the canvas has the page's ink, shown or kept for scrolling back (`willEndDisplayingOverlayView`).
            let isHidden = !canvas.isRestoringStoredInk
            let pageEditCount = session.editCount(of: page)
            if canvas.inkAnnotationsState?.isHidden != isHidden || canvas.inkAnnotationsState?.pageEditCount != pageEditCount {
                setInkAnnotationsHidden(isHidden, on: page, group: canvas.inkTracker.group)
                canvas.inkAnnotationsState = (isHidden, pageEditCount)
            }
        }
    }

    private func release(_ canvas: PDFPageCanvasView) {
        recordUnrecordedInk(of: canvas, isGoingAway: true)
        writeDeferredInkRecord(of: canvas)
        canvas.stopFollowing(toolPicker)
        canvas.delegate = nil
        if let page = canvas.page {
            setInkAnnotationsHidden(false, on: page, group: canvas.inkTracker.group)
            canvas.editCountWhenLetGo = session.editCount(of: page)
        }
    }

    /// PDFKit shows a page's view again with the overlay it kept, without asking for one, after
    /// the page's canvas was let go (more than `retainedHiddenCanvasCount` other pages shown, or
    /// a memory warning). The canvas becomes the page's own again: until 2026-11-04 it stayed let
    /// go, took strokes it never recorded, and the health check, finding a canvas on screen "not
    /// its own" within a second, built the whole view again, which decoded every page shown,
    /// fitted the zoom and showed blank pages meanwhile (HUNT-313). A page whose ink did not
    /// change since keeps its drawing; one that did reads it again.
    private func adoptCanvasShownAgain(_ canvas: PDFPageCanvasView, on page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        if let pagesCanvas = canvasesByPage[identifier], pagesCanvas !== canvas { release(pagesCanvas) }
        canvasesByPage[identifier] = canvas
        if let editCountWhenLetGo = canvas.editCountWhenLetGo, editCountWhenLetGo == session.editCount(of: page), canvas.hasRestoredStoredInk,
           !canvas.isRestoringStoredInk {
            canvas.delegate = self
        } else {
            // Its drawing is not the page's ink any more: emptied, as a new canvas is, and read again.
            canvas.storedInkRestoreCount += 1
            canvas.heldStoredInk = nil
            canvas.isRestoringStoredInk = false
            canvas.hasRestoredStoredInk = false
            canvas.inkTracker = PDFPageInkTracker(group: PDFInkGroups.storedInk(on: page).newGroup())
            canvas.recordedDrawing = PKDrawing()
            canvas.showWithoutRecording(PKDrawing())
        }
        canvas.editCountWhenLetGo = nil
        canvas.inkAnnotationsState = nil
        canvas.mayHoldUnrecordedInk = false
    }

    /// While a canvas covers a page, it shows the ink; the ink annotations are hidden so
    /// translucent strokes are not drawn twice.
    private func setInkAnnotationsHidden(_ isHidden: Bool, on page: PDFPage, group: String) {
        for annotation in page.annotations where annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String == group {
            if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
        }
    }

    /// Hides the annotations just added with these names, while the rest of the group is
    /// already hidden under the canvas. They were added last, so the page's annotations are
    /// read from the end and no further than the last of them.
    private func hideInkAnnotations(named names: Set<String>, on page: PDFPage) {
        var namesLeft = names
        for annotation in page.annotations.reversed() {
            if namesLeft.isEmpty { break }
            guard let name = annotation.persistentName, namesLeft.remove(name) != nil else { continue }
            if annotation.shouldDisplay { annotation.shouldDisplay = false }
        }
    }

    // MARK: Drawing

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        (canvasView as? HistoryCanvasView)?.drawingDidFinishRendering()
    }

    @objc private func drawingGestureChanged(_ recognizer: UIGestureRecognizer) {
        recognizer.view?.enclosingPageCanvas?.mayHoldUnrecordedInk = true
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        (canvasView as? PDFPageCanvasView)?.mayHoldUnrecordedInk = true
        // Drawn before the stored ink arrived: recorded after it once it has (`mergeStoredInk`).
        if let canvas = canvasView as? PDFPageCanvasView, canvas.isRestoringStoredInk {
            applyHeldStoredInkOnTheNextTurn(on: canvas)
            return
        }
        guard let canvas = canvasView as? PDFPageCanvasView, !canvas.isShowingWithoutRecording, let page = canvas.page,
              canvas.bounds.width > 0, canvas.bounds.height > 0 else { return }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        PencilWritingTrace.measure("Pen-up recording") { recordDrawingChange(of: canvas, on: page, pageIndex: pageIndex) }
    }

    private func recordDrawingChange(of canvas: PDFPageCanvasView, on page: PDFPage, pageIndex: Int) {
        do {
            let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: canvas.drawingSize)
            // Archiving the whole drawing at every pen-up grows with the page's strokes;
            // the session asks for the record before it is needed (see `writeDeferredInkRecords`).
            // The shape tool, or a hold at the stroke's end, replaces the stroke just drawn;
            // the history records the shape.
            let drawing = PencilWritingTrace.measure("Shape recognition") { canvas.drawingAfterShapeRecognition(shapeToolIsOn: input.drawsShapes) }
            // A drawing the history itself showed was recorded before it was shown.
            let change = PencilWritingTrace.measure("Drawing change") { canvas.changeSinceRecorded(to: drawing) }
            // A stroke just drawn after the others converts and hides that stroke alone; any
            // other change compares the page's strokes and annotations (FR-104).
            let appendingUpdate = change?.appendedStrokeIndex.flatMap { appendedStrokeIndex in
                PencilWritingTrace.measure("Ink tracker update") {
                    canvas.inkTracker.updateAppending(drawing.strokes[appendedStrokeIndex], at: appendedStrokeIndex,
                                                      pageIndex: pageIndex, coordinates: coordinates)
                }
            }
            let update = appendingUpdate ?? PencilWritingTrace.measure("Ink tracker update") {
                canvas.inkTracker.update(for: drawing, pageIndex: pageIndex, coordinates: coordinates, defersEditableRecord: true)
            }
            try PencilWritingTrace.measure("Apply ink update") { try session.apply(.updateInk(update)) }
            if let change {
                PencilWritingTrace.measure("Register undo step") { session.registerInkChange(change, on: page, overlaySize: canvas.drawingSize) }
                if let appendedStrokeIndex = change.appendedStrokeIndex {
                    PencilWritingTrace.strokeWasRecorded(drawing.strokes[appendedStrokeIndex], on: canvas)
                }
            }
            canvas.recordedDrawing = drawing
            canvas.mayHoldUnrecordedInk = false
            if displayedPages.contains(ObjectIdentifier(page)) {
                PencilWritingTrace.measure("Hide ink annotations") {
                    if appendingUpdate != nil {
                        hideInkAnnotations(named: Set(update.addedStrokes.compactMap(\.name)), on: page)
                    } else {
                        setInkAnnotationsHidden(true, on: page, group: canvas.inkTracker.group)
                    }
                }
            }
        } catch {
            session.errorMessage.report(error)
        }
    }

    // MARK: Health (`PDFPaneHealthMonitor`)

    var drawsWithFinger: Bool { input.drawsWithFinger }
    var isWriting: Bool { input.isEnabled }

    /// Puts right what must hold for every canvas on screen, and says what it changed: the
    /// canvas is the page's own, counted as shown, recording its changes, and taking touches
    /// while the PDF is written on. A canvas on screen that is not the page's own cannot be
    /// trusted with the page's ink; the view is built again instead.
    /// - Parameters:
    ///   - touchIsDown: Whether a touch is down anywhere in the PDF's window.
    ///   - now: The uptime clock's time.
    func repairCanvases(touchIsDown: Bool = false, now: TimeInterval = PencilActivity.now) -> [String] {
        guard !isDetached, let pdfView else { return [] }
        var repairs: [String] = []
        for overlay in Self.overlays(in: pdfView) where overlay.window != nil {
            let canvas = overlay.canvas
            guard let page = canvas.page else { continue }
            let pageIndex = session.document.index(for: page)
            guard pageIndex != NSNotFound else { continue }
            let identifier = ObjectIdentifier(page)
            var needsConfiguring = false
            if canvasesByPage[identifier] !== canvas {
                // Shown again by PDFKit after it was let go, without the display call that adopts it.
                adoptCanvasShownAgain(canvas, on: page)
                repairs.append("Page \(pageIndex + 1) showed a canvas let go of; it is the page's own again")
                needsConfiguring = true
            }
            if !displayedPages.contains(identifier) {
                displayedPages.insert(identifier)
                hiddenCanvasOrder.removeAll { hiddenIdentifier in hiddenIdentifier == identifier }
                repairs.append("Page \(pageIndex + 1) was shown but not counted as shown")
                needsConfiguring = true
            }
            if canvas.hasRestoredStoredInk, !canvas.isRestoringStoredInk, canvas.delegate == nil {
                canvas.delegate = self
                canvas.mayHoldUnrecordedInk = true
                repairs.append("Page \(pageIndex + 1)'s canvas did not record its changes")
            }
            if canvas.resumeDrawingLeftOff(forLongerThan: PDFPaneHealthMonitor.stuckGestureSeconds) {
                repairs.append("Page \(pageIndex + 1)'s canvas had drawing switched off for a held shape whose touch never ended")
            }
            if let repair = repairLeftDrawing(canvas, pageIndex: pageIndex, touchIsDown: touchIsDown, now: now) { repairs.append(repair) }
            if canvas.heldStoredInk != nil { applyHeldStoredInk(on: canvas) }
            if input.isEnabled, !canvas.isUserInteractionEnabled || canvas.isHidden {
                repairs.append("Page \(pageIndex + 1)'s canvas took no touches while writing")
                needsConfiguring = true
            }
            if needsConfiguring { configure(canvas) }
        }
        leftDrawingWatch.keepOnly(Self.overlays(in: pdfView).map(\.canvas))
        return repairs
    }

    /// Resets a canvas left drawing a stroke whose touch has lifted (`CanvasLeftDrawingWatch`), and says so.
    private func repairLeftDrawing(_ canvas: PDFPageCanvasView, pageIndex: Int, touchIsDown: Bool, now: TimeInterval) -> String? {
        let stuckSeconds = PDFPaneHealthMonitor.stuckGestureSeconds
        guard leftDrawingWatch.resetIfLeftDrawing(canvas, forLongerThan: stuckSeconds, touchIsDown: touchIsDown, now: now) else { return nil }
        return "Page \(pageIndex + 1)'s canvas was left drawing a stroke whose touch had lifted; its recognizers were reset"
    }

    /// Each canvas on screen or kept, for a diagnostic record.
    func canvasDiagnostics() -> [String] {
        guard let pdfView else { return [] }
        let shown = Self.overlays(in: pdfView).map(\.canvas)
        let kept = canvasesByPage.values.filter { canvas in !shown.contains { shownCanvas in shownCanvas === canvas } }
        return (shown + kept).map { canvas in
            let pageIndex = canvas.page.map { page in session.document.index(for: page) } ?? NSNotFound
            let isOwn = canvas.page.map { page in canvasesByPage[ObjectIdentifier(page)] === canvas } ?? false
            return "page \(pageIndex == NSNotFound ? "none" : String(pageIndex + 1)): own \(isOwn), on screen \(canvas.window != nil), "
                + "counted as shown \(canvas.page.map { page in displayedPages.contains(ObjectIdentifier(page)) } ?? false), "
                + "records changes \(canvas.delegate === self), touches \(canvas.isUserInteractionEnabled), hidden \(canvas.isHidden), "
                + "restoring \(canvas.isRestoringStoredInk), strokes \(canvas.drawing.strokes.count), "
                + "drawing gesture \(canvas.drawingGestureRecognizer.state.rawValue) with \(canvas.drawingGestureRecognizer.numberOfTouches) touches, "
                + "zoom \(String(format: "%.2f", canvas.zoomScale)), size \(NSCoder.string(for: canvas.bounds.size))"
        }
    }

    /// Records every canvas's ink, then has the PDF's view built again, as switching tabs
    /// does. An embedded PDF is not rebuilt: the note around it is.
    func rebuildViewAfterRecordingInk() {
        guard !isDetached, !isEmbedded else { return }
        for canvas in canvasesByPage.values { recordUnrecordedInk(of: canvas) }
        writeDeferredInkRecords()
        PencilActivity.forgetPencil()
        session.rebuildView()
    }

    private static func overlays(in view: UIView) -> [PDFPageOverlayView] {
        ((view as? PDFPageOverlayView).map { [$0] } ?? []) + view.subviews.flatMap { subview in overlays(in: subview) }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        (canvasView as? HistoryCanvasView)?.toolUseDidBegin()
        (canvasView as? PDFPageCanvasView)?.mayHoldUnrecordedInk = true
        if let canvas = canvasView as? PDFPageCanvasView {
            canvas.toolUseBeginTime = PencilActivity.now
            canvas.strokeCountWhenToolUseBegan = canvas.drawing.strokes.count
        }
        beginInteraction?()
        pdfView?.clearSelection()
        // Drawing ends arranging a picture or a text box, and typing in one.
        if session.selectedPicture != nil { session.selectedPicture = nil }
        if session.textBoxActivity != .idle {
            session.textBoxActivity = .idle
            textBoxInteraction?.syncWithActivity()
        }
        // A text field or the selection menu may have taken first responder.
        if input.holdsFirstResponder, !toolPickerHost.isFirstResponder { toolPickerHost.becomeFirstResponder() }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        guard let canvas = canvasView as? PDFPageCanvasView else { return }
        canvas.toolUseBeginTime = nil
        // An inking tool's stroke still to arrive looks at held stored ink when it does.
        let strokeMayStillArrive = canvas.tool is PKInkingTool && canvas.drawing.strokes.count == canvas.strokeCountWhenToolUseBegan
        if !strokeMayStillArrive { applyHeldStoredInkOnTheNextTurn(on: canvas) }
    }

    /// - Parameter isInsideViewUpdate: True when SwiftUI is updating its views, as in
    ///   `updateUIView`. When the first responder changes, SwiftUI asks its views about
    ///   focus, which it cannot do in the middle of updating them: with a note beside the
    ///   PDF, focusing the PDF's side left the app computing without end. The first
    ///   responder then changes on the next turn of the main queue.
    private func updateToolPickerVisibility(isInsideViewUpdate: Bool = false) {
        // A change that waited may arrive after the view is dismantled.
        guard !isDetached else { return }
        let isInWindow = pdfView?.window != nil
        // Covered by a presented screen, the palette hides and the PDF keeps first responder,
        // so the palette comes back with its tool and the PDF's history when the screen goes.
        presentedScreenObserver.isObserving = input.holdsFirstResponder && isInWindow
        let isCovered = presentedScreenObserver.isViewCovered
        toolPicker.setVisible(input.isEnabled && input.showsToolPicker && isInWindow && !isCovered, forFirstResponder: toolPickerHost)
        DispatchQueue.main.async { [weak self] in self?.reportPaletteFrameNow() }
        toolPickerHost.takesFirstResponderBackFromSelections = input.holdsFirstResponder && isInWindow
        guard isInsideViewUpdate else {
            updateFirstResponder()
            return
        }
        guard !hasPendingFirstResponderUpdate else { return }
        hasPendingFirstResponderUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingFirstResponderUpdate = false
            self.updateFirstResponder()
        }
    }

    private func updateFirstResponder() {
        // A change that waited for the view update may arrive after the view is dismantled.
        guard !isDetached, let pdfView else { return }
        // The text box typed in keeps first responder, which the keyboard and Scribble need.
        if textBoxInteraction?.isEditing == true { return }
        if input.holdsFirstResponder && pdfView.window != nil {
            // A screen presented over the PDF keeps the first responder it takes, as a text
            // field in a sheet does; the PDF takes it back when the screen goes.
            if !toolPickerHost.isFirstResponder && !presentedScreenObserver.isViewCovered { toolPickerHost.becomeFirstResponder() }
        } else if toolPickerHost.isFirstResponder {
            toolPickerHost.resignFirstResponder()
        }
    }

    // MARK: Text selection

    /// While annotating, touches on a page belong to its canvas, so PDFKit's own text
    /// selection never sees them. A finger press selects the word under it; dragging
    /// extends the selection, and lifting shows Copy and the markup actions, or, with the
    /// text highlighter chosen, marks the selection.
    @objc private func handleTextSelection(_ recognizer: UILongPressGestureRecognizer) {
        guard let pdfView else { return }
        let viewPoint = recognizer.location(in: pdfView)
        switch recognizer.state {
        case .began:
            beginInteraction?()
            editMenuInteraction?.dismissMenu()
            selectionDrag = PDFTextSelectionDrag(startingAt: viewPoint, in: pdfView)
            showTextSelection(selectionDrag?.anchorWord, in: pdfView)
        case .changed:
            if let selection = selectionDrag?.selection(extendedTo: viewPoint, in: pdfView) { showTextSelection(selection, in: pdfView) }
        case .ended:
            selectionDrag = nil
            let marked = textHighlighter?.markSelectionOnLift(style: input.markupStyle, marksOnLift: marksTextOnLift) ?? false
            if !marked { presentSelectionMenu() }
        default:
            selectionDrag = nil
            textHighlighter?.stopShowingWhileSelecting()
        }
    }

    /// With the text highlighter chosen, the selection shows as it will be marked while the finger moves; otherwise as
    /// PDFKit shows a selection, for its menu.
    private func showTextSelection(_ selection: PDFSelection?, in pdfView: PDFView) {
        if marksTextOnLift, let textHighlighter {
            textHighlighter.showWhileSelecting(selection, style: input.markupStyle)
        } else {
            pdfView.currentSelection = selection
        }
    }

    /// Whether a text selection is marked as the touch that made it lifts: the fixed bar's text highlighter is chosen.
    private var marksTextOnLift: Bool { input.fixedTool?.kind == .textHighlighter }

    /// A drag of the text highlighter on a page's canvas (`TextHighlighterToolController`).
    private func handleTextHighlighterDrag(_ dragEvent: TextHighlighterDrag) {
        // A tool changed during the drag ends it unmarked.
        guard input.isEnabled, marksTextOnLift else {
            textHighlighter?.handle(.cancelled, style: input.markupStyle)
            return
        }
        if case .tapped(let windowPoint) = dragEvent {
            // A tap on a mark offers to remove or recolour it, as a finger's tap does.
            if let pdfView { presentMarkupMenu(at: pdfView.convert(windowPoint, from: nil)) }
            return
        }
        if case .began = dragEvent {
            beginInteraction?()
            editMenuInteraction?.dismissMenu()
            tappedMarkup = nil
        }
        textHighlighter?.handle(dragEvent, style: input.markupStyle)
    }

    private func presentSelectionMenu() {
        guard let pdfView, let selection = pdfView.currentSelection, !(selection.string ?? "").isEmpty,
              let firstPage = selection.pages.first else { return }
        let selectionBounds = pdfView.convert(selection.bounds(for: firstPage), from: firstPage)
        let configuration = UIEditMenuConfiguration(identifier: Self.selectionMenuIdentifier, sourcePoint: CGPoint(x: selectionBounds.midX, y: selectionBounds.minY))
        editMenuInteraction?.presentEditMenu(with: configuration)
    }

    private func selectionMenu() -> UIMenu? {
        guard let selection = pdfView?.currentSelection, let selectedText = selection.string, !selectedText.isEmpty else { return nil }
        let copy = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.string = selectedText }
        let markingItems = PDFMarkMenus.markingItems(savedColors: savedTextMarkColors, mark: { [weak self] style in self?.markSelection(as: style) },
                                                     pickColor: { [weak self] color, choose in self?.pickMarkColor(color, choose: choose) },
                                                     removeSavedColor: { [weak self] color in self?.removeSavedTextMarkColor(color) })
        var children: [UIMenuElement] = [copy] + markingItems
        if let linkActions, let page = selection.pages.first, session.document.index(for: page) != NSNotFound {
            children.append(UIMenu(options: .displayInline, children: linkActions.menuElements(pageIndex: session.document.index(for: page), text: selectedText)))
        }
        return UIMenu(children: children)
    }

    private func markSelection(as style: PDFMarkupStyle) {
        guard let pdfView else { return }
        PDFSelectionMarking.markSelection(of: pdfView, in: session, as: style)
    }

    private var savedTextMarkColors: PDFTextMarkColors {
        PDFTextMarkColors(decoding: markupPreferences.data(forKey: PDFAnnotationPreferenceKey.textMarkColors))
    }

    private func removeSavedTextMarkColor(_ color: PDFMarkupColor) {
        markupPreferences.set(savedTextMarkColors.removing(color).encoded, forKey: PDFAnnotationPreferenceKey.textMarkColors)
    }

    /// Opens the colour picker over the selection or the tapped mark; the colour picked is saved and handed to `choose`.
    private func pickMarkColor(_ color: PDFMarkupColor, choose: @escaping (PDFMarkupColor) -> Void) {
        guard let pdfView else { return }
        let sourcePoint = pdfView.currentSelection.flatMap { selection in
            selection.pages.first.map { page in pdfView.convert(selection.bounds(for: page), from: page) }
        }.map { bounds in CGPoint(x: bounds.midX, y: bounds.minY) } ?? CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY)
        markColorPicker.present(with: color, from: pdfView, at: sourcePoint, choose: choose)
    }

    // MARK: Existing markup

    /// A tap on a highlight, underline or strikethrough offers to recolor or remove it;
    /// any other tap clears the text selection.
    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let pdfView else { return }
        let viewPoint = recognizer.location(in: pdfView)
        guard presentMarkupMenu(at: viewPoint) else {
            pdfView.clearSelection()
            // A tap on a text box selects it, or types in the one selected; a tap beside it
            // ends typing or arranging.
            // A picture over the box there takes the tap.
            let isPictureOnTop = isPictureTheTopmostObject(at: viewPoint)
            if input.isEnabled, !placesTextBoxes, !isPictureOnTop, textBoxInteraction?.handleTap(at: viewPoint) == true { return }
            // A tap on a picture selects it; a tap beside it ends arranging.
            let tappedPicture = input.isEnabled ? pictureSelection?.picture(at: viewPoint) : nil
            if tappedPicture != nil, session.textBoxActivity != .idle { session.textBoxActivity = .idle }
            // A tap on the picture already selected shows or hides its menu; a newly selected one opens it.
            if tappedPicture != nil, session.selectedPicture == tappedPicture { pictureSelection?.selectedPictureWasTapped() }
            if session.selectedPicture != tappedPicture { session.selectedPicture = tappedPicture }
            return
        }
    }

    /// Offers to recolour or remove the mark at the point, and says whether there is one.
    @discardableResult
    private func presentMarkupMenu(at viewPoint: CGPoint) -> Bool {
        guard let markup = markup(at: viewPoint) else { return false }
        tappedMarkup = markup
        editMenuInteraction?.presentEditMenu(with: UIEditMenuConfiguration(identifier: Self.markupMenuIdentifier, sourcePoint: viewPoint))
        return true
    }

    /// Whether a picture is the topmost object under the point, over any text box there, while no box is typed in.
    private func isPictureTheTopmostObject(at viewPoint: CGPoint) -> Bool {
        guard textBoxInteraction?.isEditing != true, let pdfView, let page = pdfView.page(for: viewPoint, nearest: false),
              let topmost = session.topmostObjectAnnotation(at: pdfView.convert(viewPoint, to: page), on: page, shapeTolerance: 0) else { return false }
        return PDFPageManager.isPicture(topmost)
    }

    private func markup(at viewPoint: CGPoint) -> (annotation: PDFAnnotation, page: PDFPage)? {
        guard input.isEnabled, let pdfView, let page = pdfView.page(for: viewPoint, nearest: false) else { return nil }
        return page.markupAnnotation(at: pdfView.convert(viewPoint, to: page)).map { annotation in (annotation, page) }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pdfView else { return false }
        if gestureRecognizer === pencilWhileReadingRecognizer {
            return !input.isEnabled && beginWritingWithPencil != nil
                && pdfView.page(for: gestureRecognizer.location(in: pdfView), nearest: false) != nil
        }
        if gestureRecognizer === markupTapRecognizer {
            return input.isEnabled && takesTap(at: gestureRecognizer.location(in: pdfView), in: pdfView)
        }
        if gestureRecognizer === textSelectionRecognizer {
            let viewPoint = gestureRecognizer.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: false) else { return false }
            return !(page.selectionForWord(at: pdfView.convert(viewPoint, to: page))?.string ?? "").isEmpty
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A touch on a selection's floating toolbar is the bar's alone: it neither taps nor selects the page under it.
        if FloatingSelectionToolbar.contains(touch.view) { return false }
        guard gestureRecognizer === markupTapRecognizer, let pdfView else { return true }
        // A touch on a picture's selection frame or one of its handles moves, resizes or turns
        // the picture. Taken as a tap too, a quick drag on a handle outside the picture ended
        // arranging instead; the drawing editor's `PictureTapGate` leaves such touches out too.
        if let touchedView = touch.view, touchedView is SelectionFrameView || touchedView.superview is SelectionFrameView { return false }
        return input.isEnabled && takesTap(at: touch.location(in: pdfView), in: pdfView)
    }

    /// The tap acts on markup or a picture under it, clears a text selection, and ends
    /// arranging a picture; any other tap is left to the pen.
    private func takesTap(at viewPoint: CGPoint, in pdfView: PDFView) -> Bool {
        markup(at: viewPoint) != nil || pdfView.currentSelection != nil || session.selectedPicture != nil
            || pictureSelection?.picture(at: viewPoint) != nil || (!placesTextBoxes && textBoxInteraction?.takesTap(at: viewPoint) == true)
    }

    /// Whether the text tool is in use, whose own taps place and type in text boxes.
    private var placesTextBoxes: Bool {
        input.fixedTool.map { tool in tool.kind == .text } ?? PaletteInkSelection.of(pdfView?.window?.windowScene).placesTextBoxes
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Taps never block scrolling; a selection drag must not scroll the page.
        gestureRecognizer === markupTapRecognizer || gestureRecognizer === pencilWhileReadingRecognizer
    }

    /// A Pencil on a page while reading switches to writing, and the page does not scroll with
    /// it. The touch that switched draws: the page's canvas takes no touches while reading, so
    /// the recognizer tells the canvas's own drawing recognizer of it (`PencilTouchDownRecognizer`).
    @objc private func handlePencilTouchWhileReading(_ recognizer: PencilTouchDownRecognizer) {
        guard recognizer.state == .began, !input.isEnabled, let beginWritingWithPencil, let pdfView else { return }
        for scrollView in scrollViews(in: pdfView) {
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.panGestureRecognizer.isEnabled = true
        }
        beginWritingWithPencil()
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
        if configuration.identifier as? NSString == Self.selectionMenuIdentifier { return selectionMenu() }
        guard let (annotation, page) = tappedMarkup, let kind = PDFMarkupKind(annotationType: annotation.type) else { return nil }
        let colorMenu = PDFMarkMenus.colorMenu(for: kind, currentColor: PDFMarkup(annotation: annotation)?.color, savedColors: savedTextMarkColors,
                                               recolor: { [weak self] color in
                                                   guard let self else { return }
                                                   PDFSelectionMarking.recolor(annotation, on: page, to: color, in: self.session)
                                               },
                                               pickColor: { [weak self] color, choose in self?.pickMarkColor(color, choose: choose) })
        let remove = UIAction(title: "Remove \(kind.title)", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            PDFSelectionMarking.remove(annotation, on: page, in: self.session)
        }
        return UIMenu(children: [colorMenu, remove])
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, willDismissMenuFor configuration: UIEditMenuConfiguration, animator: any UIEditMenuInteractionAnimating) {
        // Showing the menu can take first responder from the tool picker's host.
        animator.addCompletion { [weak self] in self?.updateToolPickerVisibility() }
    }
}
#endif
