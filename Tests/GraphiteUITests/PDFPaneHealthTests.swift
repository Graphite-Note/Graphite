import XCTest
@testable import GraphiteUI

/// When finger gestures on a PDF that changed nothing mean the PDF stopped taking touches.
final class PDFPaneHealthTests: XCTestCase {
    private func gesture(fingers: Int = 1, movement: CGFloat = 120, answered: Bool = false, couldMove: Bool = true,
                         drawsWithFinger: Bool = false, secondsSincePencil: TimeInterval = 60) -> UnansweredGestureCount.Gesture {
        UnansweredGestureCount.Gesture(fingerCount: fingers, largestMovement: movement, wasAnswered: answered, couldMove: couldMove,
                                       drawsWithFinger: drawsWithFinger, secondsSincePencil: secondsSincePencil)
    }

    /// On the owner's iPad, six of ten times the PDF was taken to have stopped a picture's or a
    /// selection's frame was being dragged: the frame changes the page only once the finger has
    /// lifted, after the gesture is judged, so three moves in a row built the PDF's view again.
    func testDragsOfASelectionFrameNeverCount() {
        var count = UnansweredGestureCount()
        for time in 0..<10 {
            var dragOfAFrame = gesture()
            dragOfAFrame.beganOnSelectionFrame = true
            XCTAssertFalse(count.add(dragOfAFrame, at: TimeInterval(time)))
        }
        XCTAssertTrue(count.unansweredTimes.isEmpty)
    }

    /// A swipe up from the Home indicator is the system's; the page rightly does not move.
    func testSwipesFromTheScreensEdgeNeverCount() {
        var count = UnansweredGestureCount()
        for time in 0..<10 {
            var swipeFromTheEdge = gesture()
            swipeFromTheEdge.beganAtSystemGestureEdge = true
            XCTAssertFalse(count.add(swipeFromTheEdge, at: TimeInterval(time)))
        }
        XCTAssertTrue(count.unansweredTimes.isEmpty)
        // The touch of the record of 2026-11-03: 822 points down a window 834 high.
        XCTAssertTrue(UnansweredGestureCount.isAtSystemGestureEdge(locationY: 822, windowHeight: 834, topInset: 24, bottomInset: 20))
        XCTAssertTrue(UnansweredGestureCount.isAtSystemGestureEdge(locationY: 10, windowHeight: 834, topInset: 24, bottomInset: 20))
        XCTAssertFalse(UnansweredGestureCount.isAtSystemGestureEdge(locationY: 400, windowHeight: 834, topInset: 24, bottomInset: 20))
        XCTAssertFalse(UnansweredGestureCount.isAtSystemGestureEdge(locationY: 830, windowHeight: 834, topInset: 0, bottomInset: 0), "A window with no strip kept for the system.")
    }

    func testThreeUnansweredScrollsInARowMeanThePDFStopped() {
        var count = UnansweredGestureCount()
        XCTAssertFalse(count.add(gesture(), at: 10))
        XCTAssertFalse(count.add(gesture(fingers: 2), at: 12))
        XCTAssertTrue(count.add(gesture(), at: 14))
        XCTAssertTrue(count.unansweredTimes.isEmpty, "The count starts again.")
    }

    func testAnAnsweredGestureStartsTheCountAgain() {
        var count = UnansweredGestureCount()
        XCTAssertFalse(count.add(gesture(), at: 10))
        XCTAssertFalse(count.add(gesture(), at: 11))
        XCTAssertFalse(count.add(gesture(answered: true), at: 12))
        XCTAssertFalse(count.add(gesture(), at: 13))
        XCTAssertFalse(count.add(gesture(), at: 14))
        XCTAssertTrue(count.add(gesture(), at: 15))
    }

    func testGesturesFarApartAreNotInARow() {
        var count = UnansweredGestureCount()
        XCTAssertFalse(count.add(gesture(), at: 0))
        XCTAssertFalse(count.add(gesture(), at: 40))
        XCTAssertFalse(count.add(gesture(), at: 80))
    }

    /// A hand resting while writing, a tap, a page that cannot scroll, and one finger that
    /// draws never count.
    func testGesturesThePDFRightlyIgnoresNeverCount() {
        var count = UnansweredGestureCount()
        for time in 0..<10 {
            XCTAssertFalse(count.add(gesture(secondsSincePencil: 0.5), at: TimeInterval(time)), "A hand resting while the Pencil writes.")
            XCTAssertFalse(count.add(gesture(movement: 10), at: TimeInterval(time)), "A tap.")
            XCTAssertFalse(count.add(gesture(couldMove: false), at: TimeInterval(time)), "A page with nowhere to scroll.")
            XCTAssertFalse(count.add(gesture(drawsWithFinger: true), at: TimeInterval(time)), "A finger that draws.")
        }
        XCTAssertTrue(count.unansweredTimes.isEmpty)
        XCTAssertFalse(count.add(gesture(fingers: 2, drawsWithFinger: true), at: 20), "Two fingers scroll even with finger drawing.")
        XCTAssertEqual(count.unansweredTimes.count, 1)
    }

    /// A drag or a pinch that moved the pages and was put back where it began springs back:
    /// it answered nothing. One that stayed, or that only moved a little, was answered.
    func testAGestureWhoseResultWasPutBackWasUndone() {
        typealias Position = UnansweredGestureCount.PagePosition
        let start = Position(offset: CGPoint(x: 300, y: 1200), scale: 2.5)
        let dragged = Position(offset: CGPoint(x: 300, y: 1450), scale: 2.5)
        XCTAssertTrue(UnansweredGestureCount.wasUndone(from: start, movedTo: dragged, nowAt: start), "Dragged, then put back.")
        XCTAssertTrue(UnansweredGestureCount.wasUndone(from: start, movedTo: dragged, nowAt: Position(offset: CGPoint(x: 301, y: 1201), scale: 2.5)))
        XCTAssertFalse(UnansweredGestureCount.wasUndone(from: start, movedTo: dragged, nowAt: dragged), "Dragged, and it stayed.")
        let pinched = Position(offset: CGPoint(x: 600, y: 1800), scale: 3.5)
        XCTAssertTrue(UnansweredGestureCount.wasUndone(from: start, movedTo: pinched, nowAt: start), "Pinched, then put back.")
        XCTAssertFalse(UnansweredGestureCount.wasUndone(from: start, movedTo: pinched, nowAt: pinched))
        let nudged = Position(offset: CGPoint(x: 300, y: 1210), scale: 2.5)
        XCTAssertFalse(UnansweredGestureCount.wasUndone(from: start, movedTo: nudged, nowAt: start), "A nudge of a few points is not a result.")
    }
}
