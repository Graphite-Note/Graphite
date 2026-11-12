import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's state diagram documentation examples, as Pele collects them: every one is read.
final class StateDiagramCorpusTests: XCTestCase {
    func testEveryDocumentationExampleIsRead() throws {
        let examples = try StateDiagramCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 22)
        let diagrams = try examples.map { example in try StateDiagramReading.stateDiagram(example) }
        XCTAssertEqual(diagrams.filter { diagram in !diagram.composites.isEmpty }.count, 7)
        XCTAssertEqual(diagrams.filter { diagram in !diagram.notes.isEmpty }.count, 1)
        XCTAssertEqual(diagrams.filter { diagram in diagram.states.contains { state in state.kind == .choice } }.count, 1)
        XCTAssertEqual(diagrams.filter { diagram in diagram.states.contains { state in state.kind == .fork } }.count, 1)
    }

    func testEveryDocumentationExampleIsLaidOutWithoutOverlap() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        var laidOutCount = 0
        for example in try StateDiagramCorpus.documentationExamples() {
            let diagram = try StateDiagramReading.stateDiagram(example)
            let layout = try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            let frames = layout.states.map(\.frame) + layout.notes.map(\.frame)
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), example) }
            }
            XCTAssertEqual(layout.composites.count, diagram.composites.count, example)
            laidOutCount += 1
        }
        XCTAssertEqual(laidOutCount, 22)
    }

    func testTheGeneratedMachinesAreLaidOutWithoutOverlap() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        for (stateCount, extraTransitionCount) in [(50, 20), (500, 200)] {
            let diagram = try StateDiagramReading.stateDiagram(StateDiagramCorpus.machine(stateCount: stateCount, extraTransitionCount: extraTransitionCount))
            XCTAssertEqual(diagram.states.count, stateCount + 2)
            XCTAssertEqual(diagram.transitions.count, stateCount + 1 + extraTransitionCount)
            let layout = try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            let frames = layout.states.map(\.frame).sorted { first, second in first.minX < second.minX }
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] {
                    if other.minX >= frame.maxX { break }
                    XCTAssertFalse(frame.intersects(other))
                }
            }
        }
    }
}
