/**
 * File: LivePreviewDiagramPreparationTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: How Live Preview prepares a mermaid block as the reading view does, away from the main thread.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.4
 * Date: 19/11/2026
 */

import XCTest
import Foundation
import Synchronization
import MermaidDiagrams
@testable import GraphiteUI

/// Live Preview prepares a ```` ```mermaid ```` block as the reading view does (`ReadingDiagram`): the diagram, laid out
/// in the note's text font and size; the source and why for one that cannot be read or is of a type not drawn yet.
final class LivePreviewDiagramPreparationTests: XCTestCase {
    private let font = DiagramFont(postScriptName: nil, size: 20)

    private func content(_ source: String) -> LivePreviewDiagramContent {
        LivePreviewDiagramPreparation.content(of: LivePreviewDiagramRequest(source: source, font: font))
    }

    private func diagram(_ source: String) -> ReadingDiagram {
        guard case .diagram(let diagram) = content(source) else { preconditionFailure("A Live Preview block is always a diagram block") }
        return diagram
    }

    func testAFlowchartIsLaidOutInTheRequestedFontAndSize() throws {
        let flowchart = try diagram("flowchart LR\n  A[Start] --> B{Done?}").drawn(as: .flowchart)
        XCTAssertEqual(flowchart.scene.font, font)
        XCTAssertEqual(flowchart.accessibility.summary, ["Start", "Done?"])
    }

    /// Every type the reading view draws is drawn. The Gantt chart is laid out on the moment it is built (`WallClock`).
    func testEveryTypeTheReadingViewDrawsIsDrawn() {
        for sample in ReadingDiagramSamples.oneOfEachType {
            XCTAssertNoThrow(try diagram(sample.source).drawn(as: sample.kind), "\(sample.kind)")
        }
    }

    func testADiagramThatCannotBeReadShowsItsSourceAndWhy() {
        let source = "flowchart TD\nA[never closed"
        guard case .unreadable(let shownSource, let failure) = diagram(source) else { return XCTFail("Shown with why") }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedShape(closingText: "]"))))
    }

    func testATypeNotDrawnNativelyShowsItsSourceAndWhy() {
        XCTAssertEqual(diagram("requirementDiagram\n  requirement test_req {\n  }").failure, .reading(.unsupportedDiagramType(keyword: "requirementDiagram")))
        XCTAssertEqual(diagram("flowchart TD\nsubgraph one\nA --> B\nend\none@{ view: collapsed }").failure, .flowchartLayout(.subgraphsNotLaidOut))
    }

    /// The preparation says which code and font it was made for, so a view drawing it knows whether it is current.
    func testAPreparationIsForTheRequestItWasMadeFor() async throws {
        let request = LivePreviewDiagramRequest(source: "pie\n  \"A\" : 1", font: font)
        let preparation = await LivePreviewDiagramPreparation.prepared(for: request)
        XCTAssertEqual(preparation.request, request)
        guard case .diagram(let diagram) = preparation.content else { return XCTFail("A diagram block") }
        XCTAssertEqual(try diagram.drawn(as: .pieChart).accessibility.summary, ["A 100%"])
    }

    /// The diagram is read and laid out away from the main thread in every case the view asks for one: its first layout,
    /// code changed, a new text size, the same request again when the view is made again. Asked from the main actor, as
    /// the view's task asks, the work never runs on the main thread.
    @MainActor
    func testThePreparationRunsOffTheMainThreadInEveryCase() async {
        let requests = [LivePreviewDiagramRequest(source: "flowchart TD\n  A --> B", font: font),
                        LivePreviewDiagramRequest(source: "flowchart TD\n  A --> C", font: font),
                        LivePreviewDiagramRequest(source: "flowchart TD\n  A --> C", font: DiagramFont(postScriptName: nil, size: 26)),
                        LivePreviewDiagramRequest(source: "flowchart TD\n  A --> C", font: DiagramFont(postScriptName: nil, size: 26))]
        for request in requests {
            let ranOnTheMainThread = MainThreadObservation()
            let preparation = await LivePreviewDiagramPreparation.prepared(for: request) { request in
                ranOnTheMainThread.record(pthread_main_np() != 0)
                return LivePreviewDiagramPreparation.content(of: request)
            }
            XCTAssertEqual(preparation.request, request)
            XCTAssertEqual(ranOnTheMainThread.observations, [false], "\(request)")
        }
    }

    /// A diagram is laid out in the note's text font and size, as the reading view lays it out.
    func testTheRequestTakesTheNotesTextSizeAndFont() {
        // The vault's folder is never read here.
        let environment = LivePreviewEnvironment(root: URL(fileURLWithPath: "/Vault", isDirectory: true), textSize: 19, colorsEnabled: true, paletteHexByName: [:],
                                                 drawingVersion: 0, resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let request = LivePreviewDiagramRequest(source: "pie", environment: environment)
        XCTAssertEqual(request.font, DiagramFont(postScriptName: NoteTypography.standard.diagramFontPostScriptName, size: 19))
        XCTAssertEqual(request.source, "pie")
    }
}

/// Where a piece of work ran, recorded from whichever thread runs it.
private final class MainThreadObservation: Sendable {
    private let recorded = Mutex<[Bool]>([])

    func record(_ isMainThread: Bool) {
        recorded.withLock { observations in observations.append(isMainThread) }
    }

    var observations: [Bool] {
        recorded.withLock { observations in observations }
    }
}
