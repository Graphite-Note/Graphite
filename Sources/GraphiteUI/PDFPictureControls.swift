/**
 * File: PDFPictureControls.swift
 * ------------------------------
 * Layer: UI
 * Description: Where an image to place on a PDF page comes from, and the selected picture's frame over an iPad PDF
 *              view, with its floating toolbar (`PDFPictureToolbar`) and two-finger turn and pinch.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */
#if canImport(UIKit)
import SwiftUI
import UIKit
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteApple

/// Where an image to place on a PDF page comes from.
enum PDFPictureSource: Identifiable {
    case photoLibrary, file
    var id: Self { self }
}

/// The "Add Image" choices, for a menu of a PDF pane or an embedded PDF.
struct PDFAddImageMenuContent: View {
    let session: PDFSession
    @Binding var source: PDFPictureSource?

    var body: some View {
        Button("Photo Library…", systemImage: "photo.on.rectangle") { source = .photoLibrary }
        Button("Choose File…", systemImage: "folder") { source = .file }
        if UIPasteboard.general.hasImages {
            Button("Paste Image", systemImage: "doc.on.clipboard") {
                // At its own size where that fits, as ⌘V and the lasso's Paste place it.
                guard case .image(let imageData) = LassoPasteboard.content(ignoringInk: true) else { return }
                session.pastePicture(imageData, placement: nil)
            }
        }
    }
}

/// Presents the photo picker or the file picker for `source`, and places what was picked
/// on the page in view.
struct PDFPictureAdding: ViewModifier {
    let session: PDFSession
    @Binding var source: PDFPictureSource?
    @State private var pickedPhoto: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: isPresenting(.photoLibrary), selection: $pickedPhoto, matching: .images)
            .fileImporter(isPresented: isPresenting(.file), allowedContentTypes: [.image]) { pickedFile in
                guard case .success(let location) = pickedFile else { return }
                Task {
                    do {
                        let imageData = try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: location) }.value
                        Self.addPicture(imageData: imageData, to: session)
                    } catch { session.errorMessage.report(error) }
                }
            }
            .onChange(of: pickedPhoto) { _, photo in
                guard let photo else { return }
                pickedPhoto = nil
                Task {
                    do {
                        guard let imageData = try await photo.loadTransferable(type: Data.self) else { throw GraphiteError.invalidFile("This photo could not be read.") }
                        Self.addPicture(imageData: imageData, to: session)
                    } catch { session.errorMessage.report(error) }
                }
            }
    }

    private func isPresenting(_ presentedSource: PDFPictureSource) -> Binding<Bool> {
        Binding(get: { source == presentedSource }, set: { isPresented in if !isPresented, source == presentedSource { source = nil } })
    }

    static func addPicture(imageData: Data, to session: PDFSession) {
        Task {
            do { try await session.addPicture(imageData: imageData) }
            catch { session.errorMessage.report(error) }
        }
    }
}

/// Rotate Right, Crop, Arrange and Delete for the image being arranged, on a drawing or a PDF page.
struct PictureEditingButtons: View {
    let isEnabled: Bool
    /// The items of the Arrange menu: a drawing's pictures are only brought to the front or sent to the back.
    let offeredArrangements: [PDFArrangement]
    /// Those that would move the image; the others are dimmed.
    let possibleArrangements: Set<PDFArrangement>
    /// Ink to Front and Ink to Back for a PDF page; none on a drawing.
    var ink = PDFInkArrangeOptions.none
    let rotateRight: () -> Void
    let crop: () -> Void
    let arrange: (PDFArrangement) -> Void
    let delete: () -> Void

    var body: some View {
        Group {
            Button("Rotate Image Right", systemImage: "rotate.right", action: rotateRight)
            Button("Crop Image", systemImage: "crop", action: crop)
            PDFArrangeMenu(offeredArrangements: offeredArrangements, possibleArrangements: possibleArrangements, ink: ink, arrange: arrange)
            Button("Delete Image", systemImage: "trash", role: .destructive, action: delete)
        }
        .labelStyle(.iconOnly)
        .tint(.primary)
        .disabled(!isEnabled)
    }
}

/// Shows the selection frame of the session's selected picture over a PDF view, follows the
/// page as it scrolls and zooms, and moves the picture when a drag ends. Its floating toolbar
/// shows when a picture is selected and after each change, and hides while it is dragged.
@MainActor
final class PDFPictureSelectionController {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    private(set) var selectionView: SelectionFrameView?
    private(set) var twoFingerGesture: SelectionFrameTwoFingerGesture?
    private(set) var toolbar: PDFPictureToolbar?
    /// The selection the frame and the toolbar were last shown for, so a new one shows the toolbar.
    private var shownSelection: PDFPictureSelection?
    /// What the frame's VoiceOver actions were made for, so they are made again only when it changes.
    private var accessibilityActionsKey: AccessibilityActionsKey?
    private var scrollObservation: NSKeyValueObservation?
    private var notificationObservers: [NSObjectProtocol] = []
    /// Scroll views that wait for the selection's drags, so a drag does not scroll the page.
    private var waitingScrollViews: Set<ObjectIdentifier> = []

    init(session: PDFSession, pdfView: PDFView) {
        self.session = session
        self.pdfView = pdfView
        toolbar = PDFPictureToolbar(session: session, pdfView: pdfView) { [weak self] in self?.toolbarTargetRect() }
        let center = NotificationCenter.default
        // Zooming, page changes, and undo move the picture under the frame.
        for name in [Notification.Name.PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            notificationObservers.append(center.addObserver(forName: name, object: pdfView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            notificationObservers.append(center.addObserver(forName: name, object: session.undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
        }
        // Turning, cropping and reordering change the picture under the frame, and a crop
        // turns the frame into a crop frame.
        notificationObservers.append(center.addObserver(forName: PDFSession.picturesDidChange, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
    }

    func stop() {
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        notificationObservers = []
        scrollObservation = nil
        toolbar?.stop()
        toolbar = nil
        removeSelectionView()
    }

    private func removeSelectionView() {
        twoFingerGesture?.stop()
        twoFingerGesture = nil
        selectionView?.removeFromSuperview()
        selectionView = nil
        accessibilityActionsKey = nil
    }

    /// The selected picture and its page, while both still exist.
    private var selected: (picture: PDFPicture, page: PDFPage)? {
        guard let selection = session.selectedPicture, let page = selection.page.page, page.document === session.document,
              let picture = session.pictures(on: page).first(where: { picture in picture.name == selection.pictureName }) else { return nil }
        return (picture, page)
    }

    /// Shows, moves or hides the frame after the selection or the page under it changed.
    func update() {
        guard let pdfView, pdfView.window != nil, let (picture, page) = selected else {
            removeSelectionView()
            toolbar?.dismiss()
            shownSelection = nil
            // A picture that is gone (undo, a deleted page) is not selected any more.
            if session.selectedPicture != nil, selected == nil { session.selectedPicture = nil }
            return
        }
        let selection = selectionView ?? makeSelectionView(in: pdfView)
        // Not while a drag moves the frame: the picture follows when the drag ends.
        guard !selection.dragRecognizers.contains(where: { recognizer in recognizer.state == .began || recognizer.state == .changed }),
              twoFingerGesture?.isChanging != true else { return }
        // The picture's bounds before it is turned: the page's own quarter turns keep an
        // upright rectangle upright on screen, and a turn by hand looks the same on the page
        // at any of them.
        let pictureFrame = pdfView.convert(picture.bounds, from: page)
        selection.rotation = CGFloat(picture.rotationRadians)
        selection.cropLimits = session.pictureCrop == nil ? nil : pictureFrame
        selection.unrotatedFrame = session.pictureCrop.map { crop in pdfView.convert(crop, from: page) } ?? pictureFrame
        selection.centerLimits = pdfView.convert(page.bounds(for: .cropBox), from: page)
        // Two fingers can make a picture up to twice the page's longer side.
        twoFingerGesture?.maximumSideLength = max(selection.centerLimits.width, selection.centerLimits.height) * 2
        // The preview is the picture as it is shown: turned by the page's quarter turns less
        // those it was placed at or turned back by with Rotate Right. It keeps until it changes.
        let pageTurns = ((page.rotation / 90) % 4 + 4) % 4
        let previewKey = PreviewKey(pictureName: picture.name, imageByteCount: picture.imageData.count, quarterTurnsClockwise: pageTurns - picture.quarterTurns)
        if previewKey != shownPreviewKey {
            shownPreviewKey = previewKey
            selection.dragPreview = UIImage(data: picture.imageData).map { image in LassoAreaCapture.turned(image,
                quarterTurnsClockwise: previewKey.quarterTurnsClockwise) }
        }
        updateAccessibilityActions(of: selection)
        // A picture newly selected (by a tap, Add Image or a drop) shows its toolbar.
        if session.selectedPicture != shownSelection {
            shownSelection = session.selectedPicture
            toolbar?.presentAfterChange()
        } else {
            toolbar?.followPicture()
        }
    }

    /// A tap on the picture that was already selected shows or hides its toolbar.
    func selectedPictureWasTapped() {
        toolbar?.toggle()
    }

    /// Whether the frame is being dragged, turned or pinched, while the toolbar stays hidden.
    private var isFrameChanging: Bool {
        guard let selectionView else { return false }
        return twoFingerGesture?.isChanging == true
            || selectionView.dragRecognizers.contains { recognizer in recognizer.state == .began || recognizer.state == .changed }
    }

    /// The selected picture's frame with its handles, which the toolbar stands beside; none
    /// while it is out of view or dragged.
    private func toolbarTargetRect() -> CGRect? {
        guard let pdfView, let selectionView, !isFrameChanging, selected != nil else { return nil }
        let shown = selectionView.boxWithHandlesInSuperview
        let visible = pdfView.bounds.inset(by: pdfView.safeAreaInsets)
        return shown.intersects(visible) ? shown.intersection(visible) : nil
    }

    private struct AccessibilityActionsKey: Equatable {
        let selection: PDFPictureSelection?
        let changeVersion: Int
        let isCropping: Bool
    }

    /// The toolbar's commands, as the selected image's VoiceOver actions, as the bar's buttons were.
    private func updateAccessibilityActions(of selection: SelectionFrameView) {
        let key = AccessibilityActionsKey(selection: session.selectedPicture, changeVersion: session.changeVersion, isCropping: session.pictureCrop != nil)
        guard key != accessibilityActionsKey, let toolbar else { return }
        accessibilityActionsKey = key
        selection.additionalAccessibilityActions = toolbar.items().filter(\.isEnabled).map { item in
            UIAccessibilityCustomAction(name: item.title, image: UIImage(systemName: item.systemImageName)) { _ in
                item.action()
                return true
            }
        }
    }

    private struct PreviewKey: Equatable {
        let pictureName: String
        let imageByteCount: Int
        let quarterTurnsClockwise: Int
    }
    private var shownPreviewKey: PreviewKey?

    private func makeSelectionView(in pdfView: PDFView) -> SelectionFrameView {
        shownPreviewKey = nil
        let selection = SelectionFrameView(frame: .zero)
        selection.allowsRotation = true
        // The toolbar hides while the picture is dragged and comes back where it is let go.
        selection.frameChangeDidBegin = { [weak self] in self?.toolbar?.dismiss() }
        selection.frameChangeWasCancelled = { [weak self] in self?.toolbar?.presentAfterChange() }
        // The page's tap leaves touches on the frame alone, so the frame says when it was tapped.
        selection.bodyWasTapped = { [weak self] in self?.selectedPictureWasTapped() }
        selection.frameChangeDidEnd = { [weak self] frame in self?.selectionFrameChangeDidEnd(frame) }
        selection.rotationChangeDidEnd = { [weak self] rotation in self?.selectionRotationChangeDidEnd(rotation) }
        let twoFingerGesture = SelectionFrameTwoFingerGesture(frameView: selection)
        twoFingerGesture.changeDidBegin = { [weak self] in self?.toolbar?.dismiss() }
        twoFingerGesture.changeDidEnd = { [weak self] frame, rotation in self?.selectionTransformDidEnd(frame, rotation: rotation) }
        self.twoFingerGesture = twoFingerGesture
        // Only what the PDF view shows takes touches: the tab bar is at its top edge.
        selection.staysInSuperviewSafeArea = true
        pdfView.addSubview(selection)
        selectionView = selection
        if let scrollView = Self.scrollView(in: pdfView) {
            if waitingScrollViews.insert(ObjectIdentifier(scrollView)).inserted {
                scrollObservation = scrollView.observe(\.contentOffset) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
            for recognizer in selection.dragRecognizers { scrollView.panGestureRecognizer.require(toFail: recognizer) }
        }
        return selection
    }

    private func selectionFrameChangeDidEnd(_ frame: CGRect) {
        guard let pdfView, let selection = session.selectedPicture, let page = selection.page.page else { return }
        // A crop frame chooses the part to keep; the picture stays where it is until Crop.
        if session.pictureCrop != nil {
            session.pictureCrop = pdfView.convert(frame, to: page)
            toolbar?.presentAfterChange()
            return
        }
        do { try session.movePicture(selection, to: pdfView.convert(frame, to: page)) }
        catch { session.errorMessage.report(error) }
        update()
        toolbar?.presentAfterChange()
    }

    /// Two fingers moved, resized and turned the picture: one step, as the frame was left.
    private func selectionTransformDidEnd(_ frame: CGRect, rotation: CGFloat) {
        guard let pdfView, let selection = session.selectedPicture, let page = selection.page.page else { return }
        do { try session.transformPicture(selection, to: pdfView.convert(frame, to: page), rotationRadians: Double(rotation)) }
        catch { session.errorMessage.report(error) }
        update()
        toolbar?.presentAfterChange()
    }

    /// The picture keeps the angle its handle was let go at; the page shows it turned once
    /// the annotation is replaced, and the frame stays turned meanwhile.
    private func selectionRotationChangeDidEnd(_ rotation: CGFloat) {
        guard let selection = session.selectedPicture else { return }
        do { try session.rotatePicture(selection, to: Double(rotation)) }
        catch { session.errorMessage.report(error) }
        update()
        toolbar?.presentAfterChange()
    }

    /// The picture at a point of the PDF view, with its page.
    func picture(at viewPoint: CGPoint) -> PDFPictureSelection? {
        guard let pdfView, let page = pdfView.page(for: viewPoint, nearest: false),
              let picture = session.picture(at: pdfView.convert(viewPoint, to: page), on: page) else { return nil }
        return PDFPictureSelection(pictureName: picture.name, page: session.historyPage(for: page))
    }

    /// The middle of what the view shows of the page in view, in that page's coordinates.
    func visiblePageCenter() -> (pageIndex: Int, center: CGPoint)? {
        guard let pdfView, let page = pdfView.currentPage else { return nil }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let visibleRegion = pdfView.convert(pdfView.bounds, to: page).intersection(page.bounds(for: .cropBox))
        guard !visibleRegion.isNull, visibleRegion.width > 0, visibleRegion.height > 0 else { return nil }
        return (pageIndex, CGPoint(x: visibleRegion.midX, y: visibleRegion.midY))
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView { return scrollView }
            if let scrollView = scrollView(in: subview) { return scrollView }
        }
        return nil
    }
}
#endif
