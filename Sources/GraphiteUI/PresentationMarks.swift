/**
 * File: PresentationMarks.swift
 * -----------------------------
 * Layer: UI
 * Description: The Pencil's marks on a presented slide, the laser and fading ink, sent in canvas points to every
 *              screen that shows the slide, each drawing them in a layer over its slide that takes no touches.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if canImport(UIKit)
import UIKit
import GraphiteCore

/// One mark of the Pencil on the slide, in canvas points (`PresentationCanvasMapping`).
enum PresentationMark {
    /// A stroke begins; `width` is the line's width in canvas points.
    case begin(point: CGPoint, width: CGFloat)
    case extend(point: CGPoint, width: CGFloat)
    case end
    /// The laser's dot where the Pencil hovers or touches, or nil to hide it.
    case dot(point: CGPoint?, isHovering: Bool)
}

/// Sends the Pencil's marks to every screen showing the presentation: the device's slide and the external
/// display's. Each screen registers its layer, held weakly and keyed by identity (FR-42), and drops out when it
/// goes. Nothing is kept: the marks exist only in the layers, which fade them, and changing slides clears them.
@MainActor @Observable
final class PresentationMarks {
    private struct Registration {
        weak var layerView: PresentationMarksView?
    }

    @ObservationIgnored private var registrations: [ObjectIdentifier: Registration] = [:]
    private(set) var tool: PresentationPencilTool
    private(set) var inkColor: PresentationInkColor
    @ObservationIgnored let laserStyle: LaserPointerStyle

    init(choices: PresentationPencilChoices) {
        tool = choices.tool
        inkColor = choices.inkColor
        laserStyle = choices.laserStyle
    }

    func register(_ layerView: PresentationMarksView) {
        registrations[ObjectIdentifier(layerView)] = Registration(layerView: layerView)
        layerView.prepare(laserStyle: laserStyle)
    }

    func unregister(_ layerView: PresentationMarksView) {
        registrations[ObjectIdentifier(layerView)] = nil
    }

    func choose(_ newTool: PresentationPencilTool) {
        guard newTool != tool else { return }
        clear()
        tool = newTool
    }

    func choose(_ newColor: PresentationInkColor) {
        inkColor = newColor
    }

    /// Draws `mark` on every registered screen.
    func draw(_ mark: PresentationMark) {
        for layerView in liveLayerViews { layerView.draw(mark, tool: tool, inkColor: inkColor) }
    }

    /// Takes every mark off every screen at once, as when the slide changes.
    func clear() {
        for layerView in liveLayerViews { layerView.clearMarks() }
    }

    private var liveLayerViews: [PresentationMarksView] {
        registrations = registrations.filter { _, registration in registration.layerView != nil }
        return registrations.values.compactMap(\.layerView)
    }
}

/// The layer over one screen's slide that the marks are drawn in, in its own points: the laser's dot and lines
/// (`LaserPointerOverlayView`) and the fading ink (`FadingInkView`). It takes no touches.
@MainActor
final class PresentationMarksView: UIView {
    private var laserView = LaserPointerOverlayView(frame: .zero)
    private let inkView: FadingInkView
    private var laserStyle = LaserPointerStyle.dot

    init(idleClock: any ApplicationClock) {
        inkView = FadingInkView(idleClock: idleClock)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        for layerView in [inkView, laserView] as [UIView] { addLayerView(layerView) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PresentationMarksView is created in code.") }

    private func addLayerView(_ layerView: UIView) {
        layerView.frame = bounds
        layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(layerView)
    }

    func prepare(laserStyle: LaserPointerStyle) {
        self.laserStyle = laserStyle
    }

    private var mapping: PresentationCanvasMapping { PresentationCanvasMapping(viewSize: bounds.size) }

    func draw(_ mark: PresentationMark, tool: PresentationPencilTool, inkColor: PresentationInkColor) {
        switch (tool, mark) {
        case (.laser, .begin(let point, let width)):
            if laserStyle == .line {
                laserView.hideDot()
                laserView.beginTrail(at: mapping.viewPoint(fromCanvasPoint: point), width: width * mapping.scale)
            } else {
                laserView.showDot(at: mapping.viewPoint(fromCanvasPoint: point))
            }
        case (.laser, .extend(let point, let width)):
            if laserStyle == .line {
                laserView.extendTrail(to: mapping.viewPoint(fromCanvasPoint: point), width: width * mapping.scale)
            } else {
                laserView.showDot(at: mapping.viewPoint(fromCanvasPoint: point))
            }
        case (.laser, .end):
            laserView.hideDot()
            laserView.endTrail()
        case (.laser, .dot(let point, let isHovering)):
            if let point { laserView.showDot(at: mapping.viewPoint(fromCanvasPoint: point), isHovering: isHovering) } else { laserView.hideDot() }
        case (.fadingInk, .begin(let point, let width)):
            inkView.beginStroke(at: mapping.viewPoint(fromCanvasPoint: point), width: width * mapping.scale, color: inkColor)
        case (.fadingInk, .extend(let point, let width)):
            inkView.extendStroke(to: mapping.viewPoint(fromCanvasPoint: point), width: width * mapping.scale)
        case (.fadingInk, .end):
            inkView.endStroke()
        case (.fadingInk, .dot):
            break
        }
    }

    /// Every mark off at once: the laser's layer is made again, and the ink is emptied.
    func clearMarks() {
        laserView.removeFromSuperview()
        laserView = LaserPointerOverlayView(frame: bounds)
        addLayerView(laserView)
        inkView.clearStrokes()
    }

    /// Whether the layer shows any mark, and whether it shows ink, for tests.
    var showsMarks: Bool { laserView.isShowingDot || !laserView.lines.isEmpty || showsInk }
    var showsInk: Bool { !inkView.strokes.isEmpty }
}

/// Ink that fades: strokes in a colour, broader where the Pencil presses harder, which stay after each lift so a
/// word can be circled and underlined, and all fade together a few seconds after the last lift.
@MainActor
final class FadingInkView: UIView {
    /// How long the ink stays after the last lift, and how long its fade takes.
    static let idleDelay = Duration.seconds(3)
    static let fadeDuration: TimeInterval = 0.6

    struct Stroke {
        var points: [CGPoint]
        var widths: [CGFloat]
        let color: PresentationInkColor
    }

    private(set) var strokes: [Stroke] = [] { didSet { setNeedsDisplay() } }
    private var isDrawingStroke = false
    private var fadeTask: Task<Void, Never>?
    private let idleClock: any ApplicationClock

    init(idleClock: any ApplicationClock) {
        self.idleClock = idleClock
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FadingInkView is created in code.") }

    func beginStroke(at point: CGPoint, width: CGFloat, color: PresentationInkColor) {
        cancelFade()
        isDrawingStroke = true
        strokes.append(Stroke(points: [point], widths: [width], color: color))
    }

    func extendStroke(to point: CGPoint, width: CGFloat) {
        guard isDrawingStroke, !strokes.isEmpty else { return }
        strokes[strokes.count - 1].points.append(point)
        strokes[strokes.count - 1].widths.append(width)
    }

    func endStroke() {
        guard isDrawingStroke else { return }
        isDrawingStroke = false
        fadeTask?.cancel()
        let clock = idleClock
        fadeTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: Self.idleDelay) } catch { return } // Cancelled by a new stroke: no fade.
            self?.fade()
        }
    }

    func clearStrokes() {
        cancelFade()
        isDrawingStroke = false
        strokes = []
    }

    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        layer.removeAllAnimations()
        alpha = 1
    }

    private func fade() {
        fadeTask = nil
        guard !strokes.isEmpty, !isDrawingStroke else { return }
        UIView.animate(withDuration: Self.fadeDuration, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
        } completion: { [weak self] isFinished in
            guard let self, isFinished, !self.isDrawingStroke else { return }
            self.strokes = []
            self.alpha = 1
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            let (red, green, blue) = stroke.color.components
            context.setStrokeColor(UIColor(red: red, green: green, blue: blue, alpha: 1).cgColor)
            guard let first = stroke.points.first else { continue }
            guard stroke.points.count > 1 else {
                context.setLineWidth(stroke.widths.first ?? 1)
                context.move(to: first)
                context.addLine(to: first)
                context.strokePath()
                continue
            }
            for index in 1..<stroke.points.count {
                context.setLineWidth((stroke.widths[index - 1] + stroke.widths[index]) / 2)
                context.move(to: stroke.points[index - 1])
                context.addLine(to: stroke.points[index])
                context.strokePath()
            }
        }
    }
}
#endif
