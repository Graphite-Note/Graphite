import Foundation
import CoreGraphics

/// Counts the finger gestures on a PDF that the PDF did not answer, to tell when it stopped
/// taking touches (`PDFPaneHealthMonitor`). A gesture counts only when it moved far enough to
/// scroll or zoom, could have scrolled, and Apple Pencil was not in use around it, so a hand
/// resting while writing never counts. One the PDF answered starts the count again.
struct UnansweredGestureCount {
    /// Gestures in a row the PDF did not answer before it is taken to have stopped.
    static let limit = 3
    /// They count in a row only within this long of each other.
    static let windowSeconds: TimeInterval = 30
    /// How far a finger, or two fingers apart, move before a gesture is one to answer.
    static let answerableMovementPoints: CGFloat = 40
    /// A gesture this soon after Apple Pencil was on the screen may be a hand resting to write.
    static let pencilQuietSeconds: TimeInterval = 2

    struct Gesture {
        var fingerCount: Int
        /// The vertical drag, or the change of the distance between two fingers, in points.
        var largestMovement: CGFloat
        var wasAnswered: Bool
        /// Whether the PDF could scroll up or down, or the gesture was a pinch.
        var couldMove: Bool
        var drawsWithFinger: Bool
        /// Seconds since Apple Pencil was last seen on the screen when the gesture ended.
        var secondsSincePencil: TimeInterval
        /// Whether it began on the frame around a picture, a text box or selected ink, which
        /// takes the drag itself and changes the page only once the finger lifts.
        var beganOnSelectionFrame = false
        /// Whether it began at the top or bottom edge of the screen, where the system's own
        /// gestures begin and the touch is held back from the page.
        var beganAtSystemGestureEdge = false
    }

    /// Whether a touch at a height of the window is in the strip at its top or bottom edge that
    /// the system keeps for its own gestures (Home, the Dock, Notification Centre): the window's
    /// safe area insets there.
    static func isAtSystemGestureEdge(locationY: CGFloat, windowHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> Bool {
        (topInset > 0 && locationY < topInset) || (bottomInset > 0 && locationY > windowHeight - bottomInset)
    }

    private(set) var unansweredTimes: [TimeInterval] = []

    /// Where the pages are: the scroll offset and the zoom.
    struct PagePosition: Equatable {
        var offset: CGPoint
        var scale: CGFloat
    }

    /// A gesture's result is checked again this long after the gesture ends.
    static let undoneWithinSeconds: TimeInterval = 1
    /// How far a gesture must have moved the pages, or changed the zoom, for its result to be
    /// one that can be undone.
    static let undoableMovementPoints: CGFloat = 20
    static let undoableZoomFraction: CGFloat = 0.05
    /// Back within this of where the gesture began is back where it began.
    static let sameOffsetPoints: CGFloat = 2
    static let sameZoomFraction: CGFloat = 0.005

    /// Whether something put the pages back where a gesture found them after the gesture had
    /// moved them: a gesture that moves the page and then springs back answered nothing,
    /// though it changed the offset or the zoom while the finger was down.
    static func wasUndone(from start: PagePosition, movedTo end: PagePosition, nowAt current: PagePosition) -> Bool {
        guard start.scale > 0 else { return false }
        let moved = hypot(end.offset.x - start.offset.x, end.offset.y - start.offset.y) >= undoableMovementPoints
            || abs(end.scale / start.scale - 1) >= undoableZoomFraction
        let isBack = hypot(current.offset.x - start.offset.x, current.offset.y - start.offset.y) <= sameOffsetPoints
            && abs(current.scale / start.scale - 1) < sameZoomFraction
        return moved && isBack
    }

    /// Adds a gesture that ended at `time`; true when the PDF is taken to have stopped taking
    /// touches, after which the count starts again.
    mutating func add(_ gesture: Gesture, at time: TimeInterval) -> Bool {
        // With finger drawing one finger draws, and may rightly change nothing (an eraser
        // over blank paper); only two fingers, which scroll and zoom, count then.
        // A drag of a selection frame and a swipe from the screen's edge are answered by
        // something other than the pages; on the owner's iPad they made up most of the times
        // the PDF was taken to have stopped (records of 2026-10-25 to 2026-11-08).
        guard !gesture.beganOnSelectionFrame, !gesture.beganAtSystemGestureEdge else { return false }
        guard !(gesture.drawsWithFinger && gesture.fingerCount < 2),
              gesture.largestMovement >= Self.answerableMovementPoints, gesture.couldMove,
              gesture.secondsSincePencil >= Self.pencilQuietSeconds else { return false }
        guard !gesture.wasAnswered else {
            unansweredTimes.removeAll()
            return false
        }
        unansweredTimes = unansweredTimes.filter { unansweredTime in time - unansweredTime <= Self.windowSeconds } + [time]
        guard unansweredTimes.count >= Self.limit else { return false }
        unansweredTimes.removeAll()
        return true
    }
}

/// Tells when a page's scrolling was left finished after its gesture. UIKit puts a recognizer
/// back to "possible" once its gesture is over; on the owner's iPad on 2026-11-10 it did not,
/// after a gesture that began while something was presented over the window: the scroll
/// view's pan stayed "ended" and its pinch "failed" with no touch for minutes, so neither
/// could begin again, and the monitor's own recognizer on the window stayed "failed", so
/// the monitor saw no gesture. Checked once a second: left finished at two checks in a row,
/// the finished recognizers are reset; still left finished two checks after that, the view
/// is built again.
struct FinishedGestureWatch {
    enum Step: Equatable {
        case leave
        case resetRecognizers
        case buildViewAgain
    }

    /// Checks in a row before anything is done: a state seen once may be the instant between
    /// a gesture's end and UIKit's reset.
    static let checksBeforeActing = 2
    private var checksLeftFinished = 0
    private var hasReset = false

    mutating func check(isLeftFinished: Bool) -> Step {
        guard isLeftFinished else {
            checksLeftFinished = 0
            hasReset = false
            return .leave
        }
        checksLeftFinished += 1
        guard checksLeftFinished >= Self.checksBeforeActing else { return .leave }
        checksLeftFinished = 0
        guard !hasReset else {
            hasReset = false
            return .buildViewAgain
        }
        hasReset = true
        return .resetRecognizers
    }
}

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import PDFKit
import PencilKit
import os
import GraphiteApple

/// Keeps a PDF that is shown taking touches, and leaves evidence when it stops.
///
/// On the owner's iPad (2026-10-13) a PDF being written on stopped taking any touch: no
/// scrolling, no zooming, while the rest of Graphite worked; showing another tab and coming
/// back, which builds the PDF's view again, revived it. The cause was not seen on a
/// simulator, which cannot send Apple Pencil touches. This watches for it from outside the
/// PDF view:
///
/// - Every finger gesture that starts on the PDF is followed by a passive recognizer on the
///   window (`UnansweredGestureCount` says which count). When the touches reached the PDF
///   and several such gestures in a row changed nothing (no scroll, no zoom, no edit, no
///   text selected), the PDF stopped taking touches: a record is written and the view is
///   built again, as switching tabs does, after every canvas's ink is recorded. A gesture
///   that moved the pages counts as not answered too when something put them back where
///   it found them within a second (a page that springs back after every drag or pinch,
///   reported by the owner, 2026-10-13), unless it was pulled past an edge or a zoom limit,
///   where the scroll view rightly springs back. When they
///   reached another view over the PDF, only a record is written: that view may be a
///   control the person meant to use.
/// - Once a second, the page canvases and the recognizers of the PDF are checked for states
///   that cannot last, a canvas on screen that is not the page's own or that records
///   nothing, a gesture still under way with no touch left. Each is put right and recorded.
@MainActor
final class PDFPaneHealthMonitor {
    /// A gesture still under way with no touch left this long is stuck.
    static let stuckGestureSeconds: TimeInterval = 2
    /// A record of touches reaching a view over the PDF is written at most this often.
    static let coveredRecordIntervalSeconds: TimeInterval = 300
    private static let log = Logger(subsystem: "com.graphite.study", category: "PDFPaneHealth")

    private weak var coordinator: PDFAnnotationCoordinator?
    private weak var pdfView: GraphitePDFDisplayView?
    private weak var observedWindow: UIWindow?
    private let observer = PDFTouchSequenceObserver()
    let gestureLog = PDFGestureLog()
    private var finishedGestureWatch = FinishedGestureWatch()
    private var timer: Timer?
    private var unansweredInPDF = UnansweredGestureCount()
    private var unansweredOverPDF = UnansweredGestureCount()
    private var lastCoveredRecordTime: TimeInterval = -.infinity
    /// When each recognizer was first seen under way without touches, by identity.
    private var gesturesWithoutTouchesSince: [ObjectIdentifier: TimeInterval] = [:]
    /// What the PDF looked like when the gesture followed now began.
    private var gestureStart: GestureStart?
    /// Set once the view is to be built again, so the old one is left alone meanwhile.
    private(set) var hasRequestedRebuild = false
    /// The last gesture that moved the pages, until it is checked again a moment after it
    /// ended (`UnansweredGestureCount.wasUndone`).
    private var movedGesture: MovedGesture?
    private var undoneCheck: DispatchWorkItem?

    private struct MovedGesture {
        let gesture: UnansweredGestureCount.Gesture
        let start: UnansweredGestureCount.PagePosition
        let end: UnansweredGestureCount.PagePosition
        let locationInWindow: CGPoint
    }

    private struct GestureStart {
        let contentOffset: CGPoint
        let scaleFactor: CGFloat
        let changeVersion: Int
        let selectedText: String?
        let touchCount: Int
        let startLocations: [CGPoint]
        let locationInWindow: CGPoint
        /// Whether the touch reached the PDF view or a view inside it.
        let reachedPDF: Bool
        let couldScrollVertically: Bool
        let beganOnSelectionFrame: Bool
        let beganAtSystemGestureEdge: Bool
        var largestMovement: CGFloat = 0
        var wasPinch = false
        var wasAnswered = false
    }

    init(coordinator: PDFAnnotationCoordinator, pdfView: GraphitePDFDisplayView) {
        self.coordinator = coordinator
        self.pdfView = pdfView
        observer.sequenceBegan = { [weak self] touches in self?.gestureBegan(touches) }
        observer.sequenceMoved = { [weak self] touches in self?.gestureMoved(touches) }
        observer.sequenceEnded = { [weak self] in self?.gestureEnded() }
        PDFTouchCapture.monitors.add(self)
    }

    /// Follows the window the PDF view is in now, or none.
    func windowDidChange(to window: UIWindow?) {
        guard window !== observedWindow else { return }
        undoneCheck?.cancel()
        undoneCheck = nil
        movedGesture = nil
        observedWindow?.removeGestureRecognizer(observer)
        observedWindow = window
        window?.addGestureRecognizer(observer)
        timer?.invalidate()
        timer = nil
        gestureStart = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStates() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        windowDidChange(to: nil)
    }

    // MARK: Gestures the PDF should answer

    private var mainScrollView: UIScrollView? { pdfView?.documentView?.enclosingScrollViewForHealth }

    private func gestureBegan(_ touches: [UITouch]) {
        // The gesture before is settled now, before this one moves the pages again.
        settleMovedGesture()
        gestureStart = nil
        // A finger on a PDF embedded in a note may scroll the note instead, rightly; a sheet
        // or popover over the PDF takes the touches meant for it.
        guard let pdfView, let coordinator, !coordinator.isEmbedded, let window = pdfView.window, !hasRequestedRebuild else {
            return gestureLog.note("Not followed: embedded, or being built again")
        }
        // Named, because the PDF that stopped scrolling on 2026-11-10 did so after a gesture under one.
        if let presented = window.rootViewController?.presentedViewController {
            return gestureLog.note("Not followed: under \(type(of: presented)), being dismissed \(presented.isBeingDismissed)")
        }
        let fingerTouches = touches.filter { touch in touch.type == .direct }
        guard !fingerTouches.isEmpty, fingerTouches.count == touches.count else { return gestureLog.note("Not followed: not fingers alone") }
        let locations = fingerTouches.map { touch in touch.location(in: pdfView) }
        guard locations.allSatisfy({ location in pdfView.bounds.contains(location) }) else { return }
        let touchedViews = fingerTouches.compactMap(\.view)
        let reachedPDF = !touchedViews.isEmpty && touchedViews.allSatisfy { view in view.isDescendant(of: pdfView) }
        // Another scroll view or a control over the PDF answers the gesture itself.
        if !reachedPDF, touchedViews.contains(where: { view in view is UIControl || view.enclosingScrollViewForHealth.map { scrollView in !scrollView.isDescendant(of: pdfView) } ?? false }) {
            let touchedNames = touchedViews.map { view in String(describing: type(of: view)) }
            return gestureLog.note("Not followed: it began on \(touchedNames), a control or another scroll view over the PDF")
        }
        let scrollView = mainScrollView
        let couldScrollVertically = scrollView.map { scrollView in
            scrollView.contentSize.height > scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom + 1
        } ?? false
        gestureStart = GestureStart(contentOffset: scrollView?.contentOffset ?? .zero, scaleFactor: pdfView.scaleFactor,
                                    changeVersion: coordinator.session.changeVersion, selectedText: pdfView.currentSelection?.string,
                                    touchCount: fingerTouches.count, startLocations: locations,
                                    locationInWindow: fingerTouches[0].location(in: nil), reachedPDF: reachedPDF,
                                    couldScrollVertically: couldScrollVertically,
                                    beganOnSelectionFrame: touchedViews.contains(where: \.isInSelectionFrameForHealth),
                                    beganAtSystemGestureEdge: fingerTouches.contains(where: window.isAtSystemGestureEdgeForHealth))
    }

    private func gestureMoved(_ touches: [UITouch]) {
        guard var start = gestureStart, let pdfView else { return }
        let fingerTouches = touches.filter { touch in touch.type == .direct }
        // A second finger joining a one-finger gesture makes it a pinch or a two-finger scroll.
        if fingerTouches.count != start.touchCount {
            gestureBegan(touches)
            return
        }
        let locations = fingerTouches.map { touch in touch.location(in: pdfView) }
        var movement: CGFloat = 0
        if let location = locations.first, let startLocation = start.startLocations.first {
            // Vertical only: a page that fits the width rightly does not move sideways.
            movement = abs(location.y - startLocation.y)
        }
        if locations.count >= 2, start.startLocations.count >= 2 {
            let distanceNow = hypot(locations[0].x - locations[1].x, locations[0].y - locations[1].y)
            let distanceAtStart = hypot(start.startLocations[0].x - start.startLocations[1].x, start.startLocations[0].y - start.startLocations[1].y)
            let pinch = abs(distanceNow - distanceAtStart)
            if pinch >= UnansweredGestureCount.answerableMovementPoints { start.wasPinch = true }
            movement = max(movement, pinch)
        }
        start.largestMovement = max(start.largestMovement, movement)
        if !start.wasAnswered, didAnswer(since: start) { start.wasAnswered = true }
        gestureStart = start
    }

    private func didAnswer(since start: GestureStart) -> Bool {
        guard let pdfView, let coordinator else { return true }
        let offset = mainScrollView?.contentOffset ?? .zero
        return abs(offset.x - start.contentOffset.x) > 0.5 || abs(offset.y - start.contentOffset.y) > 0.5
            || abs(pdfView.scaleFactor - start.scaleFactor) > 0.0001
            || coordinator.session.changeVersion != start.changeVersion
            || pdfView.currentSelection?.string != start.selectedText
    }

    private func gestureEnded() {
        guard var start = gestureStart, let coordinator else { return }
        gestureStart = nil
        if !start.wasAnswered, didAnswer(since: start) { start.wasAnswered = true }
        let now = ProcessInfo.processInfo.systemUptime
        let gesture = UnansweredGestureCount.Gesture(fingerCount: start.touchCount, largestMovement: start.largestMovement,
                                                     wasAnswered: start.wasAnswered, couldMove: start.couldScrollVertically || start.wasPinch,
                                                     drawsWithFinger: coordinator.drawsWithFinger,
                                                     secondsSincePencil: now - observer.lastPencilTouchTime,
                                                     beganOnSelectionFrame: start.beganOnSelectionFrame,
                                                     beganAtSystemGestureEdge: start.beganAtSystemGestureEdge)
        let pagesNow = mainScrollView?.contentOffset ?? start.contentOffset
        gestureLog.note(PDFTouchEvidence.summary(of: gesture, reachedPDF: start.reachedPDF,
                                                 pagesMovedPoints: hypot(pagesNow.x - start.contentOffset.x, pagesNow.y - start.contentOffset.y),
                                                 zoomBefore: start.scaleFactor, zoomAfter: pdfView?.scaleFactor ?? 0))
        if start.reachedPDF {
            if start.wasAnswered, let movedGesture = movedGestureToCheck(start, gesture: gesture) {
                // Answered by moving the pages: whether the move lasts is known a moment later.
                self.movedGesture = movedGesture
                let check = DispatchWorkItem { [weak self] in self?.settleMovedGesture() }
                undoneCheck = check
                DispatchQueue.main.asyncAfter(deadline: .now() + UnansweredGestureCount.undoneWithinSeconds, execute: check)
                return
            }
            guard unansweredInPDF.add(gesture, at: now) else { return }
            paneStoppedTakingTouches(lastTouchInWindow: start.locationInWindow)
        } else {
            guard unansweredOverPDF.add(gesture, at: now), now - lastCoveredRecordTime >= Self.coveredRecordIntervalSeconds else { return }
            lastCoveredRecordTime = now
            var fields = PDFTouchEvidence.describe(touchAt: start.locationInWindow, pdfView: pdfView, coordinator: coordinator)
            fields["action"] = "None: the touches reached a view over the PDF, which may be one the person meant to use."
            DiagnosticRecords.write(kind: "PDFTouchesReachedAnotherView", fields: fields)
        }
    }

    /// The pages as a gesture left them, when only moving them answered it and they are not
    /// pulled past their edges or zoom limits, where the scroll view rightly springs back.
    private func movedGestureToCheck(_ start: GestureStart, gesture: UnansweredGestureCount.Gesture) -> MovedGesture? {
        guard let pdfView, let coordinator, let scrollView = mainScrollView,
              coordinator.session.changeVersion == start.changeVersion, pdfView.currentSelection?.string == start.selectedText,
              Self.isWithinLimits(scrollView, pdfView: pdfView) else { return nil }
        return MovedGesture(gesture: gesture, start: UnansweredGestureCount.PagePosition(offset: start.contentOffset, scale: start.scaleFactor),
                            end: UnansweredGestureCount.PagePosition(offset: scrollView.contentOffset, scale: pdfView.scaleFactor),
                            locationInWindow: start.locationInWindow)
    }

    /// Counts the last gesture that moved the pages: answered if they stayed moved, not
    /// answered if something put them back where the gesture found them.
    private func settleMovedGesture() {
        undoneCheck?.cancel()
        undoneCheck = nil
        guard let movedGesture else { return }
        self.movedGesture = nil
        guard let pdfView, let scrollView = mainScrollView, !hasRequestedRebuild else { return }
        // A fling or a bounce still under way is the pages moving as the person sent them.
        let isMovingByItself = scrollView.isDecelerating || scrollView.isZoomBouncing
        let now = UnansweredGestureCount.PagePosition(offset: scrollView.contentOffset, scale: pdfView.scaleFactor)
        let wasUndone = !isMovingByItself && UnansweredGestureCount.wasUndone(from: movedGesture.start, movedTo: movedGesture.end, nowAt: now)
        var gesture = movedGesture.gesture
        gesture.wasAnswered = !wasUndone
        if wasUndone {
            Self.log.notice("A finger gesture moved the PDF and something put it back within a second")
        }
        guard unansweredInPDF.add(gesture, at: ProcessInfo.processInfo.systemUptime) else { return }
        paneStoppedTakingTouches(lastTouchInWindow: movedGesture.locationInWindow,
                                 cause: "Finger gestures moved the pages, and something put them back where they were within a second.")
    }

    /// Whether the pages are inside their scrollable range and zoom limits.
    private static func isWithinLimits(_ scrollView: UIScrollView, pdfView: PDFView) -> Bool {
        let insets = scrollView.adjustedContentInset
        let offset = scrollView.contentOffset
        let tolerance: CGFloat = 1
        let maximumX = max(-insets.left, scrollView.contentSize.width - scrollView.bounds.width + insets.right)
        let maximumY = max(-insets.top, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        let scale = pdfView.scaleFactor
        return offset.x >= -insets.left - tolerance && offset.x <= maximumX + tolerance
            && offset.y >= -insets.top - tolerance && offset.y <= maximumY + tolerance
            && scale >= pdfView.minScaleFactor * 0.999 && scale <= pdfView.maxScaleFactor * 1.001
    }

    /// Records what the PDF looked like, then builds its view again.
    private func paneStoppedTakingTouches(lastTouchInWindow: CGPoint,
                                          cause: String = "Finger gestures on the PDF changed nothing: no scroll, no zoom, no edit, no text selected.") {
        guard let coordinator, !hasRequestedRebuild else { return }
        var fields = PDFTouchEvidence.describe(touchAt: lastTouchInWindow, pdfView: pdfView, coordinator: coordinator)
        fields["cause"] = cause
        fields["action"] = "The PDF's ink was recorded and its view built again, as switching tabs does."
        DiagnosticRecords.write(kind: "PDFStoppedTakingTouches", fields: fields)
        DiagnosticContext.note("The PDF stopped taking touches; its view was built again")
        hasRequestedRebuild = true
        coordinator.rebuildViewAfterRecordingInk()
    }

    // MARK: States that cannot last

    private func checkStates() {
        guard let pdfView, let coordinator, pdfView.window != nil, !hasRequestedRebuild else { return }
        DiagnosticContext.set(String(format: "%.0f x %.0f", pdfView.window?.bounds.width ?? 0, pdfView.window?.bounds.height ?? 0), for: "window")
        DiagnosticContext.set(String(format: "PDF, %@, zoom %.2f, %d pages", coordinator.isWriting ? "writing" : "reading",
                                     pdfView.scaleFactor, coordinator.session.pageCount), for: "document")
        var repairs = coordinator.repairCanvases()
        switch repairScrollingLeftFinished(in: pdfView) {
        case .leave: break
        case .resetRecognizers: repairs.append("Reset the recognizers left finished after their gesture, the page's scrolling among them")
        case .buildViewAgain: return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var seenStuck = Set<ObjectIdentifier>()
        for recognizer in PDFTouchEvidence.recognizers(in: pdfView) where recognizer.isUnderWayWithoutTouches {
            let identifier = ObjectIdentifier(recognizer)
            seenStuck.insert(identifier)
            let since = gesturesWithoutTouchesSince[identifier] ?? now
            gesturesWithoutTouchesSince[identifier] = since
            guard now - since >= Self.stuckGestureSeconds else { continue }
            repairs.append("Reset \(type(of: recognizer)), under way for \(Int(now - since)) s without a touch")
            if let canvas = recognizer.view?.enclosingCanvasForHealth { coordinator.recordUnrecordedInk(of: canvas) }
            recognizer.isEnabled = false
            recognizer.isEnabled = true
            gesturesWithoutTouchesSince[identifier] = nil
        }
        gesturesWithoutTouchesSince = gesturesWithoutTouchesSince.filter { entry in seenStuck.contains(entry.key) }
        guard !repairs.isEmpty else { return }
        Self.log.error("Repaired the PDF: \(repairs.joined(separator: "; "), privacy: .public)")
        let middleInWindow = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: nil)
        var fields = PDFTouchEvidence.describe(touchAt: middleInWindow, pdfView: pdfView, coordinator: coordinator)
        fields["repairs"] = repairs
        fields["recentGestures"] = gestureLog.entries
        DiagnosticRecords.write(kind: "PDFRepaired", fields: fields)
    }

    /// Puts the page's scrolling right when it was left finished after its gesture and cannot
    /// begin again (`FinishedGestureWatch`): resets every finished recognizer of the PDF and
    /// the monitor's own, or, when that did not help, builds the view again.
    private func repairScrollingLeftFinished(in pdfView: GraphitePDFDisplayView) -> FinishedGestureWatch.Step {
        guard let scrollView = mainScrollView else { return .leave }
        let pan = scrollView.panGestureRecognizer
        let isLeftFinished = pan.isEnabled && pan.isFinished && pan.numberOfTouches == 0 && !scrollView.isTracking
        let step = finishedGestureWatch.check(isLeftFinished: isLeftFinished)
        switch step {
        case .leave: break
        case .resetRecognizers:
            for recognizer in PDFTouchEvidence.recognizers(in: pdfView) + [observer] where recognizer.isEnabled && recognizer.isFinished {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
        case .buildViewAgain:
            paneStoppedTakingTouches(lastTouchInWindow: pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: nil),
                                     cause: "The page's scrolling stayed finished after its gesture, also after its recognizers were reset.")
        }
        return step
    }

    // MARK: Evidence

    /// Writes down what a touch at the middle of the PDF reaches and everything that decides
    /// whether the PDF answers it, with the last gestures followed, when asked from outside.
    func captureTouchState() {
        guard let pdfView, pdfView.window != nil else { return }
        let middleInWindow = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: nil)
        var fields = PDFTouchEvidence.describe(touchAt: middleInWindow, pdfView: pdfView, coordinator: coordinator)
        fields["recentGestures"] = gestureLog.entries
        fields["monitor"] = "follows this window \(observedWindow === pdfView.window), view being built again \(hasRequestedRebuild)"
        fields["action"] = "None: captured on request."
        DiagnosticRecords.write(kind: "PDFTouchStateCaptured", fields: fields)
    }
}

extension UIView {
    /// Whether the view is a selection frame or inside one, as its corner and rotate handles are.
    var isInSelectionFrameForHealth: Bool {
        var ancestor: UIView? = self
        while let current = ancestor {
            if current is SelectionFrameView { return true }
            ancestor = current.superview
        }
        return false
    }
}

extension UIWindow {
    /// Whether a touch is in the strip the system keeps for its own gestures (`UnansweredGestureCount.isAtSystemGestureEdge`).
    func isAtSystemGestureEdgeForHealth(_ touch: UITouch) -> Bool {
        UnansweredGestureCount.isAtSystemGestureEdge(locationY: touch.location(in: self).y, windowHeight: bounds.height,
                                                     topInset: safeAreaInsets.top, bottomInset: safeAreaInsets.bottom)
    }
}

/// Follows every touch sequence of a window without taking part: it never recognizes, never
/// prevents another recognizer and never delays or cancels a touch.
final class PDFTouchSequenceObserver: UIGestureRecognizer {
    var sequenceBegan: (([UITouch]) -> Void)?
    var sequenceMoved: (([UITouch]) -> Void)?
    var sequenceEnded: (() -> Void)?
    private var activeTouches = Set<UITouch>()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// When Apple Pencil was last seen on the screen, on the uptime clock.
    private(set) var lastPencilTouchTime: TimeInterval = -.infinity

    private func notePencil(in touches: Set<UITouch>) {
        if touches.contains(where: { touch in touch.type == .pencil }) { lastPencilTouchTime = ProcessInfo.processInfo.systemUptime }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        notePencil(in: touches)
        let isNewSequence = activeTouches.isEmpty
        activeTouches.formUnion(touches)
        if isNewSequence { sequenceBegan?(Array(activeTouches)) } else { sequenceMoved?(Array(activeTouches)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        notePencil(in: touches)
        sequenceMoved?(Array(activeTouches))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches) }

    override func reset() {
        super.reset()
        if !activeTouches.isEmpty { sequenceEnded?() }
        activeTouches.removeAll()
    }

    private func finish(_ touches: Set<UITouch>) {
        notePencil(in: touches)
        sequenceMoved?(Array(activeTouches))
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty else { return }
        sequenceEnded?()
        // Never recognizing, it fails once the sequence is over, so UIKit resets it.
        state = .failed
    }
}

extension UIGestureRecognizer {
    /// Under way, yet following no touch: a state UIKit leaves only when told. A hover is
    /// under way without touching by nature, and does not count.
    /// Ended, cancelled or failed: where a recognizer is between its gesture's end and UIKit's reset.
    var isFinished: Bool { state == .ended || state == .cancelled || state == .failed }

    var isUnderWayWithoutTouches: Bool {
        !(self is UIHoverGestureRecognizer) && isEnabled && (state == .began || state == .changed) && numberOfTouches == 0
    }
}

extension UIView {
    var enclosingScrollViewForHealth: UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

    var enclosingCanvasForHealth: PDFPageCanvasView? {
        var current: UIView? = self
        while let view = current {
            if let canvas = view as? PDFPageCanvasView { return canvas }
            current = view.superview
        }
        return nil
    }
}
#endif

