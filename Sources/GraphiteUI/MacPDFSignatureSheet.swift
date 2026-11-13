/**
 * File: MacPDFSignatureSheet.swift
 * --------------------------------
 * Layer: UI
 * Description: The sheet in which a signature is drawn with the trackpad or mouse on the Mac, on a line as on paper,
 *              then kept on the device and placed on the PDF's page in view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(macOS)
import SwiftUI
import AppKit
import PencilKit
import GraphiteCore

/// The strokes of a signature being drawn: the pointer's places of each, in the canvas's
/// points from its bottom-left corner, as a page's are.
struct MacSignatureDrawing: Equatable {
    var strokes: [[PDFPointerInkSample]] = []

    /// The ink of the signature: black, the Draw tool's middle width.
    static let style = PDFMarkupInkStyle(color: .black, width: .medium)

    /// The drawing of the strokes in a canvas of `size`, from its top-left corner as PencilKit's drawing space is.
    func drawing(inCanvasOf size: CGSize, creationDate: Date) -> PKDrawing? {
        let canvas = CGRect(origin: .zero, size: size)
        guard let coordinates = try? PDFPointerInk.coordinates(of: canvas) else { return nil } // A canvas of no size has nothing to keep.
        let pencilStrokes = strokes.compactMap { samples in
            PDFPointerInk.stroke(through: samples, style: Self.style, coordinates: coordinates, creationDate: creationDate)
        }
        return pencilStrokes.isEmpty ? nil : PKDrawing(strokes: pencilStrokes)
    }
}

/// The sheet of Create Signature: a canvas to sign on, Clear, Cancel and Done, which keeps
/// the signature on this Mac and places it.
struct MacPDFSignatureSheet: View {
    let save: (PKDrawing) -> Void
    let cancel: () -> Void
    /// The wall clock, for the date of the signature's strokes.
    var currentDate: () -> Date = Date.init
    @State private var signature = MacSignatureDrawing()

    static let canvasSize = CGSize(width: 440, height: 160)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Signature").font(.headline)
            Text("Sign on the line with the trackpad or mouse. The signature is kept on this Mac, not in the vault.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            MacSignatureCanvas(signature: $signature)
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 36)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.4)) }
                .accessibilityLabel("Signature")
            HStack {
                Button("Clear") { signature.strokes.removeAll() }
                    .disabled(signature.strokes.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    if let drawing = signature.drawing(inCanvasOf: Self.canvasSize, creationDate: currentDate()) { save(drawing) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(signature.strokes.isEmpty)
            }
        }
        .padding(20)
        .fixedSize()
    }
}

/// The canvas of the signature sheet, drawing each stroke as the pointer moves.
struct MacSignatureCanvas: NSViewRepresentable {
    @Binding var signature: MacSignatureDrawing

    func makeNSView(context: Context) -> MacSignatureCanvasView {
        let view = MacSignatureCanvasView()
        view.strokesChanged = { strokes in signature.strokes = strokes }
        return view
    }

    func updateNSView(_ view: MacSignatureCanvasView, context: Context) {
        view.strokesChanged = { strokes in signature.strokes = strokes }
        if view.strokes != signature.strokes { view.strokes = signature.strokes }
    }
}

/// The view that takes the pointer's places while the mouse is down, in its own points from
/// its bottom-left corner, and draws the strokes so far.
final class MacSignatureCanvasView: NSView {
    var strokes: [[PDFPointerInkSample]] = [] { didSet { needsDisplay = true } }
    var strokesChanged: (([[PDFPointerInkSample]]) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        strokes.append([sample(of: event)])
    }

    override func mouseDragged(with event: NSEvent) {
        guard !strokes.isEmpty else { return }
        strokes[strokes.count - 1].append(sample(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        strokesChanged?(strokes)
    }

    private func sample(of event: NSEvent) -> PDFPointerInkSample {
        PDFPointerInkSample(pagePoint: convert(event.locationInWindow, from: nil), timeSeconds: event.timestamp)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setStroke()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            let path = NSBezierPath()
            path.move(to: first.pagePoint)
            for sample in stroke.dropFirst() { path.line(to: sample.pagePoint) }
            if stroke.count == 1 { path.line(to: CGPoint(x: first.pagePoint.x + PDFPointerInk.dotLengthPoints, y: first.pagePoint.y)) }
            path.lineWidth = CGFloat(MacSignatureDrawing.style.width.points)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}
#endif
