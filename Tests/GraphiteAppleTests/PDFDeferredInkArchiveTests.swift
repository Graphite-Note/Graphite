/**
 * File: PDFDeferredInkArchiveTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: A page's re-editing record archived away from the main actor is the record archiving
 *              there gives, and is dropped when a stroke came after it was asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 02/11/2026
 */
import XCTest
import PDFKit
import PencilKit
import GraphiteCore
@testable import GraphiteApple

/// A page's re-editing record archived away from the main actor is the record archiving there
/// gives, and is dropped when a stroke came after it was asked for (HUNT-017).
final class PDFDeferredInkArchiveTests: XCTestCase {
    private func stroke(atHeight height: CGFloat, creationSeconds: TimeInterval) -> PKStroke {
        let points = (0..<8).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 40 + CGFloat(pointIndex) * 9, y: height), timeOffset: Double(pointIndex) / 120, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: creationSeconds)))
    }

    private let coordinates: PageCoordinates = {
        let page = CGRect(x: 0, y: 0, width: 300, height: 400)
        return try! PageCoordinates(cropBox: page, overlaySize: page.size) // A valid size, stated here.
    }()

    func testARecordArchivedAwayFromTheMainActorIsTheOneItWouldHaveBeen() async throws {
        let drawing = PKDrawing(strokes: [stroke(atHeight: 50, creationSeconds: 10), stroke(atHeight: 90, creationSeconds: 20)])
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        _ = tracker.update(for: drawing, pageIndex: 0, coordinates: coordinates, defersEditableRecord: true)
        var trackerArchivingHere = tracker

        let archive = try XCTUnwrap(tracker.deferredRecordArchive(for: drawing))
        let record = await Task.detached { archive.archived() }.value
        let update = try XCTUnwrap(tracker.deferredEditableRecordUpdate(archived: record, from: archive, pageIndex: 0))
        let updateHere = try XCTUnwrap(trackerArchivingHere.deferredEditableRecordUpdate(for: drawing, pageIndex: 0))
        XCTAssertEqual(update.editableRecord?.strokeNames, updateHere.editableRecord?.strokeNames)
        let archivedStrokes = try PKDrawing(data: XCTUnwrap(update.editableRecord).drawingData).strokes
        XCTAssertEqual(archivedStrokes.count, 2)
        XCTAssertFalse(tracker.hasDeferredEditableRecord)
        XCTAssertNil(tracker.deferredRecordArchive(for: drawing), "Nothing is pending any more")
    }

    /// Its names would not match the annotations; the record stays deferred, for the next ask.
    func testARecordArchivedBeforeAnotherStrokeIsDroppedAndStaysDeferred() async throws {
        let firstStroke = stroke(atHeight: 50, creationSeconds: 10)
        let drawing = PKDrawing(strokes: [firstStroke])
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        _ = tracker.update(for: drawing, pageIndex: 0, coordinates: coordinates, defersEditableRecord: true)
        let archive = try XCTUnwrap(tracker.deferredRecordArchive(for: drawing))
        let record = await Task.detached { archive.archived() }.value

        let nextStroke = stroke(atHeight: 90, creationSeconds: 20)
        XCTAssertNotNil(tracker.updateAppending(nextStroke, at: 1, pageIndex: 0, coordinates: coordinates))
        XCTAssertNil(tracker.deferredEditableRecordUpdate(archived: record, from: archive, pageIndex: 0))
        XCTAssertTrue(tracker.hasDeferredEditableRecord)
        let later = try XCTUnwrap(tracker.deferredEditableRecordUpdate(for: PKDrawing(strokes: [firstStroke, nextStroke]), pageIndex: 0))
        XCTAssertEqual(later.editableRecord?.strokeNames.count, 2)
    }

    func testAPageWithNoStrokesLeftHasNoRecord() async throws {
        var tracker = PDFPageInkTracker(group: PDFInkGroups.defaultGroup)
        _ = tracker.update(for: PKDrawing(), pageIndex: 0, coordinates: coordinates, defersEditableRecord: true)
        let archive = try XCTUnwrap(tracker.deferredRecordArchive(for: PKDrawing()))
        XCTAssertNil(archive.archived())
    }
}
