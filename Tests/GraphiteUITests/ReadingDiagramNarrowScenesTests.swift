/**
 * File: ReadingDiagramNarrowScenesTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A diagram's narrow scene laid out again at the column's real width: which width, when (at once after a jump,
 *              once the column settles while it moves), off the main thread, from the diagram already read, and kept per width.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import XCTest
import SwiftUI
import Synchronization
import MermaidDiagrams
@testable import GraphiteUI

/// Obsidian draws Pele at its container's width: a diagram whose column shows its narrow scene has that scene laid out
/// again for the column's width in layout points, rounded down to 8 points, never on the main thread, once per width.
@MainActor
final class ReadingDiagramNarrowScenesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))

    private func drawn(_ source: String, as kind: MermaidDiagramKind) throws -> (PreparedMermaidDiagram, ReadingDiagramSource) {
        guard case .drawn(let prepared, let diagramSource) = ReadingDiagram(source: source, typography: typography), prepared.kind == kind else {
            throw DiagramNotDrawnAsExpected(expected: kind, shown: ReadingDiagram(source: source, typography: typography))
        }
        return (prepared, diagramSource)
    }

    /// A TCP header in rows of 32 bits, which Pele's turnToFit draws with fewer bits to a row, each as wide as the column
    /// gives it.
    static let packet = """
        packet
          0-15: "Source Port"
          16-31: "Destination Port"
          32-63: "Sequence Number"
          64-95: "Acknowledgment Number"
          96-99: "Data Offset"
          100-105: "Reserved"
          106-111: "Flags"
          112-127: "Window"
        """

    func testTheLayoutWidthIsTheColumnsInLayoutPointsRoundedDown() {
        XCTAssertEqual(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: 400, scaleAtNaturalWidth: 1), 400)
        XCTAssertEqual(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: 407, scaleAtNaturalWidth: 1), 400, "A few points more lay nothing out again")
        XCTAssertEqual(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: 400, scaleAtNaturalWidth: 0.5), 800, "At half the text size it is laid out")
        XCTAssertNil(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: 285, scaleAtNaturalWidth: 1), "The standard narrow scene's width")
        XCTAssertNil(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: 0, scaleAtNaturalWidth: 1), "Not measured yet")
        XCTAssertNil(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: 150, scaleAtNaturalWidth: 1), "Narrower than any reading column")
        XCTAssertNil(ReadingDiagramNarrowWidth.layoutWidth(columnWidth: .infinity, scaleAtNaturalWidth: 1))
    }

    /// Only a column that shows the narrow scene asks for it again: one that shrinks the regular scene does not.
    func testANarrowSceneIsLaidOutAgainOnlyWhereTheColumnShowsIt() throws {
        let (flowchart, source) = try drawn(ReadingDiagramNarrowColumnTests.fourteenShapesInARow, as: .flowchart)
        let regularWidth = flowchart.scene.size.width
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.narrowRequest(of: flowchart, source: source, inColumnWidth: 700, scaleAtNaturalWidth: 1),
                       ReadingDiagramNarrowRequest(source: source, columnWidth: 696))
        XCTAssertNil(ReadingScaledDiagram<EmptyView>.narrowRequest(of: flowchart, source: source, inColumnWidth: regularWidth * 0.83, scaleAtNaturalWidth: 1),
                     "The regular scene shrunk")
        XCTAssertNil(ReadingScaledDiagram<EmptyView>.narrowRequest(of: flowchart, source: nil, inColumnWidth: 700, scaleAtNaturalWidth: 1))
        XCTAssertNil(ReadingScaledDiagram<EmptyView>.narrowRequest(of: flowchart, source: source, inColumnWidth: 0, scaleAtNaturalWidth: 1))
        let (small, smallSource) = try drawn("flowchart LR\n  A --> B", as: .flowchart)
        XCTAssertNil(ReadingScaledDiagram<EmptyView>.narrowRequest(of: small, source: smallSource, inColumnWidth: 100, scaleAtNaturalWidth: 1))
    }

    /// The packet's bits take the column's width as Pele draws them for it: in a 400-point column it is about 400 points
    /// wide, where the standard narrow scene is laid out for 280.
    func testTheSceneLaidOutAgainFitsTheColumnsWidth() throws {
        let (packet, source) = try drawn(Self.packet, as: .packet)
        let standard = try XCTUnwrap(packet.narrowScene)
        XCTAssertLessThanOrEqual(standard.size.width, PreparedMermaidDiagram.standardNarrowestColumnWidth + 1)
        let request = try XCTUnwrap(ReadingScaledDiagram<EmptyView>.narrowRequest(of: packet, source: source, inColumnWidth: 400, scaleAtNaturalWidth: 1))
        let wider = try XCTUnwrap(ReadingDiagramNarrowRequest.narrowScene(of: request))
        XCTAssertLessThanOrEqual(wider.size.width, 401)
        XCTAssertGreaterThan(wider.size.width, standard.size.width + 60)
    }

    /// A scene laid out again is shown only where it fits the column readably: a long flowchart laid out for 750 points
    /// stays across (Pele turns it only under 640) and 2,000 points wide, so the column keeps the standard one running down.
    func testASceneLaidOutAgainIsShownOnlyWhereItFitsTheColumnReadably() throws {
        let (flowchart, source) = try drawn(ReadingDiagramNarrowColumnTests.fourteenShapesInARow, as: .flowchart)
        let at750 = try XCTUnwrap(ReadingScaledDiagram<EmptyView>.narrowRequest(of: flowchart, source: source, inColumnWidth: 750, scaleAtNaturalWidth: 1))
        let across = try XCTUnwrap(ReadingDiagramNarrowRequest.narrowScene(of: at750))
        XCTAssertGreaterThan(across.size.width, 1_500)
        XCTAssertNil(ReadingScaledDiagram<EmptyView>.readableScene(across, inColumnWidth: 750, scaleAtNaturalWidth: 1))
        let (packet, packetSource) = try drawn(Self.packet, as: .packet)
        let at400 = try XCTUnwrap(ReadingScaledDiagram<EmptyView>.narrowRequest(of: packet, source: packetSource, inColumnWidth: 400, scaleAtNaturalWidth: 1))
        let fitted = try XCTUnwrap(ReadingDiagramNarrowRequest.narrowScene(of: at400))
        XCTAssertEqual(ReadingScaledDiagram<EmptyView>.readableScene(fitted, inColumnWidth: 400, scaleAtNaturalWidth: 1)?.size, fitted.size)
        XCTAssertNil(ReadingScaledDiagram<EmptyView>.readableScene(nil, inColumnWidth: 400, scaleAtNaturalWidth: 1))
    }

    /// Asked from the main actor, as the view's task asks, the work never runs on the main thread; a width laid out once is
    /// kept, another width is laid out again.
    func testThePreparationRunsOffTheMainThreadAndIsKeptPerWidth() async throws {
        let (_, source) = try drawn(Self.packet, as: .packet)
        let scenes = ReadingDiagramNarrowScenes(settlingDelay: .zero)
        let observation = NarrowPreparationObservation()
        let preparing: @Sendable (ReadingDiagramNarrowRequest) -> DiagramScene? = { request in
            observation.record(pthread_main_np() != 0)
            return ReadingDiagramNarrowRequest.narrowScene(of: request)
        }
        let at400 = ReadingDiagramNarrowRequest(source: source, columnWidth: 400)
        let first = await scenes.prepare(at400, preparing: preparing)
        XCTAssertNotNil(first?.scene)
        XCTAssertNotNil(scenes.redrawnScene(for: at400))
        _ = await scenes.prepare(at400, preparing: preparing)
        XCTAssertEqual(observation.observations, [false], "Laid out once, off the main thread")
        _ = await scenes.prepare(ReadingDiagramNarrowRequest(source: source, columnWidth: 520), preparing: preparing)
        XCTAssertEqual(observation.observations, [false, false])
        XCTAssertNil(scenes.redrawnScene(for: ReadingDiagramNarrowRequest(source: source, columnWidth: 600)))
    }

    /// Two sources compare by their text, font and day, which the diagram is read from (the view's task compares its request
    /// at each update without walking the diagram): the same text read twice is the same source, another text another.
    func testSourcesCompareByTheirTextFontAndDayNotByWalkingTheDiagram() throws {
        let (_, source) = try drawn(Self.packet, as: .packet)
        let readAgain = try ReadingDiagramSource(text: source.text, font: source.font, now: source.now, timeZone: source.timeZone)
        XCTAssertEqual(readAgain, source)
        let other = try ReadingDiagramSource(text: "flowchart LR\n  A --> B", font: source.font, now: source.now, timeZone: source.timeZone)
        XCTAssertNotEqual(other, source)
        let laterDay = try ReadingDiagramSource(text: source.text, font: source.font, now: source.now.addingTimeInterval(86_400), timeZone: source.timeZone)
        XCTAssertNotEqual(laterDay, source)
        let otherFont = try ReadingDiagramSource(text: source.text, font: DiagramFont(postScriptName: nil, size: 22), now: source.now, timeZone: source.timeZone)
        XCTAssertNotEqual(otherFont, source)
        XCTAssertEqual(ReadingDiagramNarrowLayout.package, ReadingDiagramNarrowLayout(name: "package", layOut: { _ in nil }), "Layouts compare by name")
        XCTAssertNotEqual(ReadingDiagramNarrowLayout.package, ReadingDiagramNarrowLayout(name: "counted", layOut: ReadingDiagramNarrowRequest.narrowScene(of:)))
    }

    /// A column that jumps to a width after keeping its last one (a rotation, the view first measured) has it laid out at
    /// once, without the settling wait: with a wait of a minute, the scene still comes at once.
    func testAColumnThatJumpsToAWidthHasItLaidOutAtOnce() async throws {
        let (_, source) = try drawn(Self.packet, as: .packet)
        let scenes = ReadingDiagramNarrowScenes(settlingDelay: .seconds(60))
        let clock = ContinuousClock()
        let start = clock.now
        let redrawn = await scenes.prepare(ReadingDiagramNarrowRequest(source: source, columnWidth: 400))
        XCTAssertNotNil(redrawn?.scene)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(30), "Laid out without waiting for the column to settle")
    }

    /// A request that comes within the settling delay of the one before (a split being dragged) waits for the column to
    /// keep its width; one that changes again while it waits lays nothing out for the width it left.
    func testARequestWhileTheColumnMovesWaitsAndIsNotLaidOutWhenTheColumnMovesOn() async throws {
        let (_, source) = try drawn(Self.packet, as: .packet)
        let scenes = ReadingDiagramNarrowScenes(settlingDelay: .seconds(60))
        let observation = NarrowPreparationObservation()
        let recording: @Sendable (ReadingDiagramNarrowRequest) -> DiagramScene? = { request in
            observation.record(pthread_main_np() != 0)
            return ReadingDiagramNarrowRequest.narrowScene(of: request)
        }
        _ = await scenes.prepare(ReadingDiagramNarrowRequest(source: source, columnWidth: 400), preparing: recording)
        XCTAssertEqual(observation.observations.count, 1, "Where the drag starts")
        let moved = ReadingDiagramNarrowRequest(source: source, columnWidth: 408)
        let task = Task { await scenes.prepare(moved, preparing: recording) }
        // The view's task is cancelled when the column changes width again.
        task.cancel()
        let redrawn = await task.value
        XCTAssertNil(redrawn)
        XCTAssertEqual(observation.observations.count, 1, "Nothing laid out for a width the column left")
        XCTAssertNil(scenes.redrawnScene(for: moved))
    }

    /// The last request of a moving column is laid out once the column has kept its width for the settling delay.
    func testTheLastRequestOfAMovingColumnIsLaidOutOnceTheColumnSettles() async throws {
        let (_, source) = try drawn(Self.packet, as: .packet)
        let settlingDelay = Duration.milliseconds(50)
        let scenes = ReadingDiagramNarrowScenes(settlingDelay: settlingDelay)
        _ = await scenes.prepare(ReadingDiagramNarrowRequest(source: source, columnWidth: 400))
        let clock = ContinuousClock()
        let start = clock.now
        let settled = await scenes.prepare(ReadingDiagramNarrowRequest(source: source, columnWidth: 520))
        XCTAssertNotNil(settled?.scene)
        XCTAssertGreaterThanOrEqual(start.duration(to: clock.now), settlingDelay, "Waited for the column to keep its width")
    }

    /// A width change lays out the diagram read when the note was built: a source whose text is not a diagram at all, with
    /// the packet's diagram read, lays the packet out for the new width, as the packet's own source does.
    func testAWidthChangeLaysOutTheDiagramAlreadyReadWithoutReadingItsText() throws {
        let (_, source) = try drawn(Self.packet, as: .packet)
        let unreadableText = "not a diagram"
        XCTAssertThrowsError(try ReadingDiagramSource(text: unreadableText, font: source.font, now: source.now, timeZone: source.timeZone))
        let readAlready = ReadingDiagramSource(text: unreadableText, diagram: source.diagram, font: source.font, now: source.now, timeZone: source.timeZone)
        let fromTheDiagram = try XCTUnwrap(readAlready.narrowScene(forColumnWidth: 400))
        let fromTheSource = try XCTUnwrap(source.narrowScene(forColumnWidth: 400))
        XCTAssertEqual(fromTheDiagram.size, fromTheSource.size)
        XCTAssertEqual(fromTheDiagram.texts.count, fromTheSource.texts.count)
    }
}

/// Where a piece of work ran, recorded from whichever thread runs it.
private final class NarrowPreparationObservation: Sendable {
    private let recorded = Mutex<[Bool]>([])

    func record(_ isMainThread: Bool) {
        recorded.withLock { observations in observations.append(isMainThread) }
    }

    var observations: [Bool] {
        recorded.withLock { observations in observations }
    }
}
