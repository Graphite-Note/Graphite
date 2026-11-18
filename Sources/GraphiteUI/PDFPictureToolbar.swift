/**
 * File: PDFPictureToolbar.swift
 * -----------------------------
 * Layer: UI
 * Description: The floating toolbar of a selected picture on an iPad PDF page (`FloatingSelectionToolbar`): Bring
 *              Image to Front, Send Image to Back, Rotate Right, Crop and Delete, with Bring Image Forward and Send
 *              Image Backward behind "…", or Cancel and Crop while it is cropped. The same commands are the selected
 *              image's VoiceOver actions.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// The floating toolbar of the session's selected picture, beside the picture in its PDF
/// view. The bar is made when a picture is first selected.
@MainActor
final class PDFPictureToolbar {
    private let session: PDFSession
    private weak var pdfView: PDFView?
    /// The selected picture's box in the PDF view, handles included; nil while it is out of view or dragged.
    private let targetRect: () -> CGRect?
    private(set) var toolbar: FloatingSelectionToolbar?

    init(session: PDFSession, pdfView: PDFView, targetRect: @escaping () -> CGRect?) {
        self.session = session
        self.pdfView = pdfView
        self.targetRect = targetRect
    }

    var isShown: Bool { toolbar?.isShown ?? false }

    func stop() {
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    /// Shows the bar beside the selected picture, if one is selected and in view.
    func present() {
        guard let pdfView, let rectangle = targetRect() else { return dismiss() }
        let items = items()
        guard !items.isEmpty else { return dismiss() }
        let toolbar = toolbar ?? FloatingSelectionToolbar()
        self.toolbar = toolbar
        toolbar.show(items, pointingAt: rectangle, in: pdfView)
    }

    /// Shows the bar once the change just made has been drawn, as after a command or a drag.
    func presentAfterChange() {
        Task { @MainActor [weak self] in self?.present() }
    }

    func dismiss() {
        toolbar?.hide()
    }

    /// A tap on the selected picture: shows its bar, or hides it if it was showing.
    func toggle() {
        if isShown { dismiss() } else { present() }
    }

    /// Keeps the bar beside the picture as the page scrolls or zooms, or as the picture changes.
    func followPicture() {
        guard isShown else { return }
        if let rectangle = targetRect() { toolbar?.follow(rectangle) } else { dismiss() }
    }

    // MARK: The commands

    /// The commands for the selected picture, in the bar's order; none while nothing is selected.
    func items() -> [FloatingToolbarItem] {
        guard let selection = session.selectedPicture else { return [] }
        if session.pictureCrop != nil {
            return [FloatingToolbarItem(title: "Cancel Crop", systemImageName: "xmark") { [weak self] in
                        self?.session.pictureCrop = nil
                        self?.presentAfterChange()
                    },
                    FloatingToolbarItem(title: "Crop", systemImageName: "checkmark", group: 1) { [weak self] in self?.cropToChosenPart(of: selection) }]
        }
        let possible = session.possibleArrangements(of: selection)
        func arrangement(_ arrangement: PDFArrangement, inMoreMenu: Bool = false) -> FloatingToolbarItem {
            FloatingToolbarItem(title: arrangement.title(of: .image), systemImageName: arrangement.systemImageName, isEnabled: possible.contains(arrangement),
                                isInMoreMenu: inMoreMenu) { [weak self] in
                self?.run { session in try session.arrangePicture(selection, arrangement) }
            }
        }
        return [
            arrangement(.bringToFront),
            arrangement(.sendToBack),
            FloatingToolbarItem(title: "Rotate Right", systemImageName: "rotate.right", group: 1) { [weak self] in
                self?.run { session in try session.rotatePictureRight(selection) }
            },
            FloatingToolbarItem(title: "Crop", systemImageName: "crop", group: 1) { [weak self] in self?.beginCropping(selection) },
            FloatingToolbarItem(title: "Delete Image", systemImageName: "trash", isDestructive: true, group: 2) { [weak self] in
                guard let self else { return }
                do { try session.removePicture(selection) } catch { session.errorMessage.report(error) }
            },
            arrangement(.bringForward, inMoreMenu: true),
            arrangement(.sendBackward, inMoreMenu: true),
        ]
    }

    private func run(_ change: (PDFSession) throws -> Void) {
        do { try change(session) } catch { session.errorMessage.report(error) }
        presentAfterChange()
    }

    /// The crop starts as the whole picture, with Cancel Crop and Crop on the bar.
    private func beginCropping(_ selection: PDFPictureSelection) {
        guard let page = selection.page.page,
              let picture = session.pictures(on: page).first(where: { picture in picture.name == selection.pictureName }) else { return }
        session.pictureCrop = picture.bounds
        presentAfterChange()
    }

    private func cropToChosenPart(of selection: PDFPictureSelection) {
        guard let crop = session.pictureCrop else { return }
        session.pictureCrop = nil
        dismiss()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await session.cropPicture(selection, to: crop) } catch { session.errorMessage.report(error) }
            present()
        }
    }
}
#endif
