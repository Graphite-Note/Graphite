/**
 * File: MagnifyingImageScrollView.swift
 * -------------------------------------
 * Layer: UI
 * Description: A Mac view that fits a picture and magnifies it with a pinch or a double-click.
 *
 * Authors: Bahey Shalash
 * Version: 0.9
 * Date: 12/11/2026
 */

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import SwiftUI

/// A picture that fits the view and magnifies with a pinch or a double-click, on the Mac.
struct MagnifyingImageView: NSViewRepresentable {
    let image: CGImage
    /// Runs on a single click while the picture is fitted; nil does nothing.
    var singleClickWhileFitted: (() -> Void)? = nil
    /// Whether a picture smaller than the view is enlarged to fit it (`MagnifyingImageScrollView.enlargesToFit`).
    var enlargesToFit = false

    func makeNSView(context: Context) -> MagnifyingImageScrollView {
        let scrollView = MagnifyingImageScrollView()
        scrollView.enlargesToFit = enlargesToFit
        scrollView.image = image
        scrollView.singleClickWhileFitted = singleClickWhileFitted
        return scrollView
    }

    func updateNSView(_ scrollView: MagnifyingImageScrollView, context: Context) {
        if scrollView.image !== image { scrollView.image = image }
        scrollView.singleClickWhileFitted = singleClickWhileFitted
    }
}

/// Shows a picture fitted to the view, centered, never enlarged past its own size to fit
/// unless `enlargesToFit` says so.
/// A trackpad pinch magnifies up to eight times the fitted size; a double-click toggles
/// between fitted and two and a half times larger, around the point clicked. The Mac's
/// counterpart of `ZoomingImageScrollView`.
final class MagnifyingImageScrollView: NSScrollView, NSGestureRecognizerDelegate {
    private let imageView = NSImageView()
    private var fittedBoundsSize: CGSize = .zero
    private static let margin: CGFloat = 24
    static let maximumZoomFactor: CGFloat = 8
    /// Runs on a single click while the picture is fitted; nil does nothing.
    var singleClickWhileFitted: (() -> Void)?
    /// Whether a picture smaller than the view is enlarged to fit it, as the zoom over a note
    /// shows it (HUNT-331): a picture drawn wider in the note than its pixels was smaller in the
    /// zoom. A file's own tab shows a small picture at its size.
    var enlargesToFit = false
    private var singleClick: NSClickGestureRecognizer?
    private var doubleClick: NSClickGestureRecognizer?

    var image: CGImage? {
        didSet {
            magnification = 1
            imageView.image = image.map { image in NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)) }
            imageView.frame = CGRect(origin: .zero, size: image.map { image in CGSize(width: image.width, height: image.height) } ?? .zero)
            fittedBoundsSize = .zero
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        contentView = CenteringClipView()
        contentView.drawsBackground = false
        imageView.imageScaling = .scaleAxesIndependently
        imageView.isEditable = false
        documentView = imageView
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(toggleMagnification(_:)))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)
        let singleClick = NSClickGestureRecognizer(target: self, action: #selector(clickedOnce))
        singleClick.delegate = self
        addGestureRecognizer(singleClick)
        self.doubleClick = doubleClick
        self.singleClick = singleClick
    }

    required init?(coder: NSCoder) { nil }

    /// The fitted magnification, where the whole picture shows.
    private(set) var fittedMagnification: CGFloat = 1

    var isFitted: Bool { abs(magnification - fittedMagnification) < 0.001 }

    override func layout() {
        super.layout()
        guard let image, image.width > 0, image.height > 0, bounds.width > 0, bounds.size != fittedBoundsSize else { return }
        let availableSize = CGSize(width: max(bounds.width - 2 * Self.margin, 1), height: max(bounds.height - 2 * Self.margin, 1))
        let wholePictureMagnification = min(availableSize.width / CGFloat(image.width), availableSize.height / CGFloat(image.height))
        let fittingMagnification = enlargesToFit ? wholePictureMagnification : min(wholePictureMagnification, 1)
        let wasFitted = fittedBoundsSize == .zero || isFitted
        fittedMagnification = fittingMagnification
        minMagnification = fittingMagnification
        maxMagnification = max(fittingMagnification * Self.maximumZoomFactor, 1)
        if wasFitted || magnification < fittingMagnification { magnification = fittingMagnification }
        fittedBoundsSize = bounds.size
    }

    @objc private func toggleMagnification(_ recognizer: NSClickGestureRecognizer) {
        if isFitted {
            let point = recognizer.location(in: imageView)
            animatedMagnification(to: min(fittedMagnification * 2.5, maxMagnification), centeredAt: point)
        } else {
            animatedMagnification(to: fittedMagnification, centeredAt: CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY))
        }
    }

    private func animatedMagnification(to targetMagnification: CGFloat, centeredAt point: CGPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setMagnification(targetMagnification, centeredAt: point)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().setMagnification(targetMagnification, centeredAt: point)
        }
    }

    @objc func clickedOnce() {
        guard isFitted else { return }
        singleClickWhileFitted?()
    }

    /// A single click waits to know it is not the first of a double-click.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        gestureRecognizer === singleClick && otherGestureRecognizer === doubleClick
    }
}

/// Keeps a document smaller than the view in its middle rather than at the bottom-left corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)
        guard let documentFrame = documentView?.frame else { return constrainedBounds }
        if documentFrame.width < constrainedBounds.width {
            constrainedBounds.origin.x = (documentFrame.width - constrainedBounds.width) / 2
        }
        if documentFrame.height < constrainedBounds.height {
            constrainedBounds.origin.y = (documentFrame.height - constrainedBounds.height) / 2
        }
        return constrainedBounds
    }
}
#endif
