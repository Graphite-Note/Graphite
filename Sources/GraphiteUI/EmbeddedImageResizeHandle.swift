/**
 * File: EmbeddedImageResizeHandle.swift
 * -------------------------------------
 * Layer: UI
 * Description: The corner handle of an image in Live Preview, which resizes it as Obsidian's does:
 *              the image follows the drag, and its width goes into the embed when the drag ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI

/// Resizes an image by its bottom-right corner. While the drag lasts the image is drawn at
/// `draggedWidth`, never narrower than `minimumWidth` nor wider than the column it is in;
/// when it ends, `commitWidth` writes the width in whole points into the note, one edit
/// that can be undone. The image keeps its shape, as its height follows from its width.
///
/// The handle's glyph shows while the pointer or Apple Pencil is over the image, and always
/// where touch is the only way to reach it, since a finger does not hover.
struct EmbeddedImageResizeHandle: ViewModifier {
    /// The narrowest an image can be made, so its handle stays on it.
    static let minimumWidth: CGFloat = 48

    /// Nil shows no handle.
    let commitWidth: ((Int) -> Void)?
    let isPointerOver: Bool
    /// The width of the column the image is in, the widest it can be made.
    let columnWidth: CGFloat?
    @Binding var draggedWidth: CGFloat?
    /// The width the image is drawn at, read when a drag begins.
    @State private var shownWidth: CGFloat = 0
    @State private var widthAtDragStart: CGFloat?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in shownWidth = width }
            // The corner takes a drag even before the pointer's hover shows its glyph.
            .overlay(alignment: .bottomTrailing) {
                if commitWidth != nil { handle }
            }
    }

    private var showsGlyph: Bool {
        #if os(iOS)
        return true
        #else
        return isPointerOver || widthAtDragStart != nil
        #endif
    }

    /// The width a drag of `horizontalTranslation` points gives an image that was
    /// `startWidth` wide.
    static func width(from startWidth: CGFloat, horizontalTranslation: CGFloat, columnWidth: CGFloat?) -> CGFloat {
        let widest = max(minimumWidth, columnWidth ?? .infinity)
        return min(max(startWidth + horizontalTranslation, minimumWidth), widest)
    }

    private var handle: some View {
        ResizeCornerShape()
            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.55), radius: 1.5)
            .frame(width: 14, height: 14)
            .opacity(showsGlyph ? 1 : 0)
            .padding(8)
            .frame(width: Self.touchSide, height: Self.touchSide, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            #if os(macOS)
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .highPriorityGesture(resizeDrag)
            #else
            // A view of UIKit's own, which the note's text view knows not to scroll for.
            .overlay { ImageResizeTouchArea(changed: dragChanged(horizontalTranslation:), ended: dragEnded) }
            #endif
            .help("Drag to resize")
            .accessibilityElement()
            .accessibilityLabel("Resize Image")
            .accessibilityValue("\(Int(shownWidth.rounded())) points wide")
            .accessibilityAdjustableAction { direction in
                let step: CGFloat = direction == .increment ? 50 : -50
                commitWidth?(Int(Self.width(from: shownWidth, horizontalTranslation: step, columnWidth: columnWidth).rounded()))
            }
    }

    private static var touchSide: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    private var resizeDrag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in dragChanged(horizontalTranslation: drag.translation.width) }
            .onEnded { _ in dragEnded() }
    }

    private func dragChanged(horizontalTranslation: CGFloat) {
        let startWidth = widthAtDragStart ?? shownWidth
        widthAtDragStart = startWidth
        draggedWidth = Self.width(from: startWidth, horizontalTranslation: horizontalTranslation, columnWidth: columnWidth)
    }

    private func dragEnded() {
        widthAtDragStart = nil
        guard let draggedWidth else { return }
        commitWidth?(Int(draggedWidth.rounded()))
    }
}

#if os(iOS)
/// Takes a finger's drag on an image's corner with a pan of its own. The note's text view
/// scrolls for a drag over any other rendered block; it leaves this view's touches alone
/// (`ImageResizeTouchView`), so the drag resizes the image instead of scrolling the note.
private struct ImageResizeTouchArea: UIViewRepresentable {
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeUIView(context: Context) -> ImageResizeTouchView {
        let view = ImageResizeTouchView()
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        return view
    }

    func updateUIView(_ view: ImageResizeTouchView, context: Context) {
        context.coordinator.changed = changed
        context.coordinator.ended = ended
    }

    func makeCoordinator() -> Coordinator { Coordinator(changed: changed, ended: ended) }

    final class Coordinator: NSObject {
        var changed: (CGFloat) -> Void
        var ended: () -> Void

        init(changed: @escaping (CGFloat) -> Void, ended: @escaping () -> Void) {
            self.changed = changed
            self.ended = ended
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .changed: changed(recognizer.translation(in: nil).x)
            case .ended, .cancelled, .failed: ended()
            case .began, .possible: break
            @unknown default: break
            }
        }
    }
}

/// The view an image's resize handle takes touches with on iOS.
final class ImageResizeTouchView: UIView {}
#endif

/// The width a picture is drawn at while its corner is dragged, nil otherwise; read by a line of
/// pictures side by side (`LivePreviewImageLineView`), which offers the picture that width.
struct DraggedPictureWidthKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// The bottom-right corner of a frame with a rounded bend, as the system draws a window's.
private struct ResizeCornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bend = rect.width * 0.45
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bend))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bend, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
