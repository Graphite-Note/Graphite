/**
 * File: ReadingDiagram.swift
 * --------------------------
 * Layer: UI
 * Description: A mermaid block as the reading view shows it: the diagram drawn, or its source with why.
 *
 * Authors: Félix Chevalier
 * Version: 0.24
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block as the reading view shows it, made off the main actor while the note's blocks are
/// built, so that the main actor only draws.
enum ReadingDiagram: Sendable {
    /// A flowchart drawn natively.
    case flowchart(ReadingFlowchart)
    /// A pie chart drawn natively.
    case pieChart(ReadingPieChart)
    /// A Gantt chart drawn natively.
    case ganttChart(ReadingGanttChart)
    /// A diagram of a type drawn natively whose text could not be read or laid out: its source is shown with why.
    case unreadable(source: String, failure: ReadingDiagramFailure)
    /// A state diagram drawn natively.
    case stateDiagram(ReadingStateDiagram)
    /// A class diagram drawn natively.
    case classDiagram(ReadingClassDiagram)
    /// A sequence diagram drawn natively.
    case sequence(ReadingSequence)
    /// An entity relationship diagram drawn natively.
    case entityRelationship(ReadingEntityRelationshipDiagram)
    /// A mindmap drawn natively.
    case mindmap(ReadingMindmap)
    /// A timeline drawn natively.
    case timeline(ReadingTimeline)
    /// A Git graph drawn natively.
    case gitGraph(ReadingGitGraph)
    /// A user journey drawn natively.
    case userJourney(ReadingUserJourney)
    /// A quadrant chart drawn natively.
    case quadrantChart(ReadingQuadrantChart)
    /// An XY chart drawn natively.
    case xyChart(ReadingXYChart)
    /// A Sankey diagram drawn natively.
    case sankey(ReadingSankeyDiagram)

    /// The diagram a block's text describes, laid out in `typography`. A diagram that cannot be read, or holds what its
    /// type does not lay out yet (a flowchart's collapsed group, a state diagram's composite state, a class diagram's
    /// namespace, a sequence diagram's box, a Git graph's options, a Sankey diagram's circular links), or is of a type not
    /// drawn yet, is its source with a line that says why (`unreadable`), never a bare code block that looks as if nothing
    /// was meant to be drawn.
    /// A diagram that declares nothing to draw, or whose layout is past `MermaidDiagramLimits.maximumDrawingSideLength`, is its
    /// source with why too, never an empty or a giant view.
    init(source: String, typography: DiagramTypography) {
        let diagram: MermaidDiagram
        do {
            diagram = try MermaidDiagramReader.read(source, limits: .standard)
        } catch {
            self = .unreadable(source: source, failure: .reading(error))
            return
        }
        let drawn = Self.drawn(diagram, source: source, typography: typography)
        // A layout's own refusal says more than "nothing to draw", so it is kept.
        if drawn.drawingSize != nil, diagram.hasNothingToDraw {
            self = .unreadable(source: source, failure: .nothingToDraw)
        } else if let size = drawn.drawingSize, !MermaidDiagramLimits.standard.allowsDrawing(size) {
            self = .unreadable(source: source, failure: .tooLargeToDraw(maximumSideLength: MermaidDiagramLimits.standard.maximumDrawingSideLength))
        } else {
            self = drawn
        }
    }

    /// `diagram` laid out in `typography`, or its source with why when its layout fails or holds what its type does not
    /// lay out yet.
    private static func drawn(_ diagram: MermaidDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        switch diagram {
        case .flowchart(let flowchart): drawnFlowchart(flowchart, source: source, typography: typography)
        case .stateDiagram(let stateDiagram): drawnStateDiagram(stateDiagram, source: source, typography: typography)
        case .classDiagram(let classDiagram): drawnClassDiagram(classDiagram, source: source, typography: typography)
        case .sequence(let sequence): drawnSequence(sequence, source: source, typography: typography)
        case .entityRelationship(let entityRelationship): drawnEntityRelationship(entityRelationship, source: source, typography: typography)
        case .mindmap(let mindmap): .mindmap(ReadingMindmap(diagram: mindmap, layout: MindmapLayoutEngine.layout(mindmap, typography: typography)))
        case .timeline(let timeline): drawnTimeline(timeline, typography: typography)
        case .pieChart(let chart): .pieChart(ReadingPieChart(chart: chart, layout: PieChartLayoutEngine.layout(chart, typography: typography)))
        case .ganttChart(let chart):
            ReadingGanttChart.diagram(source: source, chart: chart, typography: typography, now: WallClock.currentDate(),
                                      timeZone: WallClock.currentTimeZone())
        case .gitGraph(let gitGraph): ReadingGitGraph.diagram(gitGraph, source: source, typography: typography)
        case .userJourney(let journey):
            .userJourney(ReadingUserJourney(diagram: journey, layout: UserJourneyLayoutEngine.layout(journey, typography: typography)))
        case .quadrantChart(let chart):
            .quadrantChart(ReadingQuadrantChart(chart: chart, layout: QuadrantChartLayoutEngine.layout(chart, typography: typography)))
        case .xyChart(let chart): ReadingXYChart.diagram(source: source, chart: chart, typography: typography)
        case .sankey(let sankey): ReadingSankeyDiagram.diagram(source: source, diagram: sankey, typography: typography)
        }
    }

    /// A flowchart wider than the narrowest column is laid out a second time for a narrow one, as Pele lays out one that does not fit
    /// its container: turned to run down where it runs across, its gaps tightened. The view shows that layout where the
    /// column needs it (`ReadingDiagramVariant`).
    private static func drawnFlowchart(_ flowchart: FlowchartDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        let layout: FlowchartLayout
        do {
            layout = try FlowchartLayoutEngine.layout(flowchart, typography: typography, limits: .standard)
        } catch {
            return .unreadable(source: source, failure: .layout(error))
        }
        let narrowLayout = narrowLayout(of: flowchart.turnedToRunDown ?? flowchart, regularSize: layout.size, size: \.size) { turned in
            try FlowchartLayoutEngine.layout(turned, typography: typography, limits: .standard, spacing: .compact)
        }
        return .flowchart(ReadingFlowchart(diagram: flowchart, layout: layout, narrowLayout: narrowLayout))
    }

    /// Whether a layout for a narrow column is worth keeping: narrower than the regular one and within the drawing limit.
    static func isNarrower(_ narrowSize: CGSize, than regularSize: CGSize) -> Bool {
        narrowSize.width < regularSize.width && MermaidDiagramLimits.standard.allowsDrawing(narrowSize)
    }

    /// `turned` (a diagram turned to run down) laid out for a narrow column, when the regular layout is wider than the
    /// narrowest column and the turned one is narrower than it; else nil, and nothing is laid out a second time.
    static func narrowLayout<Diagram, Layout>(of turned: Diagram?, regularSize: CGSize, size: KeyPath<Layout, CGSize>,
                                              laidOut: (Diagram) throws -> Layout) -> Layout? {
        guard regularSize.width > ReadingDiagramVariant.narrowestColumnWidth, let turned,
              let layout = try? laidOut(turned), // A turned diagram that cannot be laid out keeps its regular layout alone.
              isNarrower(layout[keyPath: size], than: regularSize) else { return nil }
        return layout
    }

    private static func drawnTimeline(_ timeline: TimelineDiagram, typography: DiagramTypography) -> ReadingDiagram {
        let layout = TimelineLayoutEngine.layout(timeline, typography: typography)
        let narrowLayout = narrowLayout(of: timeline.turnedToRunDown, regularSize: layout.size, size: \.size) { turned in
            TimelineLayoutEngine.layout(turned, typography: typography)
        }
        return .timeline(ReadingTimeline(diagram: timeline, layout: layout, narrowLayout: narrowLayout))
    }

    private static func drawnStateDiagram(_ stateDiagram: StateDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        do {
            let layout = try StateDiagramLayoutEngine.layout(stateDiagram, typography: typography, limits: .standard)
            let narrowLayout = narrowLayout(of: stateDiagram.turnedToRunDown, regularSize: layout.size, size: \.size) { turned in
                try StateDiagramLayoutEngine.layout(turned, typography: typography, limits: .standard)
            }
            return .stateDiagram(ReadingStateDiagram(diagram: stateDiagram, layout: layout, narrowLayout: narrowLayout))
        } catch {
            return .unreadable(source: source, failure: .stateLayout(error))
        }
    }

    private static func drawnClassDiagram(_ classDiagram: ClassDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        do {
            let layout = try ClassDiagramLayoutEngine.layout(classDiagram, typography: typography, limits: .standard)
            let narrowLayout = narrowLayout(of: classDiagram.turnedToRunDown, regularSize: layout.size, size: \.size) { turned in
                try ClassDiagramLayoutEngine.layout(turned, typography: typography, limits: .standard)
            }
            return .classDiagram(ReadingClassDiagram(diagram: classDiagram, layout: layout, narrowLayout: narrowLayout))
        } catch {
            return .unreadable(source: source, failure: .classLayout(error))
        }
    }

    private static func drawnSequence(_ sequence: SequenceDiagram, source: String, typography: DiagramTypography) -> ReadingDiagram {
        do {
            return .sequence(ReadingSequence(diagram: sequence, layout: try SequenceLayoutEngine.layout(sequence, typography: typography)))
        } catch {
            return .unreadable(source: source, failure: .sequenceLayout(error))
        }
    }
}

extension ReadingDiagram {
    /// How many statements of the diagram are read and not applied (styling a diagram type does not draw yet, `click`), for
    /// the diagrams that count them; 0 for the others.
    var unappliedStatementCount: Int {
        switch self {
        case .flowchart(let flowchart): flowchart.unappliedStatementCount
        case .stateDiagram(let stateDiagram): stateDiagram.unappliedStatementCount
        case .classDiagram(let classDiagram): classDiagram.unappliedStatementCount
        case .entityRelationship(let entityRelationship): entityRelationship.unappliedStatementCount
        case .pieChart, .ganttChart, .unreadable, .sequence, .mindmap, .timeline, .gitGraph, .userJourney, .quadrantChart, .xyChart, .sankey: 0
        }
    }

    /// The size the diagram was laid out at for the width it was written for, or nil for a source shown with why.
    var drawingSize: CGSize? {
        switch self {
        case .flowchart(let flowchart): flowchart.layout.size
        case .pieChart(let chart): chart.layout.size
        case .ganttChart(let chart): chart.layout.size
        case .unreadable: nil
        case .stateDiagram(let diagram): diagram.layout.size
        case .classDiagram(let diagram): diagram.layout.size
        case .sequence(let sequence): sequence.layout.size
        case .entityRelationship(let diagram): diagram.layout.size
        case .mindmap(let mindmap): mindmap.layout.size
        case .timeline(let timeline): timeline.layout.size
        case .gitGraph(let gitGraph): gitGraph.layout.size
        case .userJourney(let journey): journey.layout.size
        case .quadrantChart(let chart): chart.layout.size
        case .xyChart(let chart): chart.layout.size
        case .sankey(let diagram): diagram.layout.size
        }
    }
}

/// Why a diagram drawn natively was not drawn.
enum ReadingDiagramFailure: Equatable, Sendable {
    case reading(MermaidDiagramReadError)
    /// The diagram declares nothing that is drawn (`MermaidDiagram.hasNothingToDraw`).
    case nothingToDraw
    /// Its layout is longer than `maximumSideLength` points on a side.
    case tooLargeToDraw(maximumSideLength: CGFloat)
    case layout(FlowchartLayoutError)
    case sequenceLayout(SequenceLayoutError)
    case gitGraphLayout(GitGraphLayoutError)
    case sankeyLayout(SankeyLayoutError)
    case stateLayout(StateDiagramLayoutError)
    case classLayout(ClassDiagramLayoutError)
    case entityRelationshipLayout(EntityRelationshipLayoutError)
    case ganttLayout(GanttLayoutError)
    case xyChartLayout(XYChartLayoutError)
}

/// A flowchart laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingFlowchart: Sendable {
    let layout: FlowchartLayout
    let shapes: ReadingFlowchartShapes
    /// The flowchart laid out for a narrow column, or nil when it is narrow enough already.
    let narrow: ReadingNarrowLayout<FlowchartLayout, ReadingFlowchartShapes>?
    /// `accTitle`, else the front matter's title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// The text of each node drawn, in the order the diagram names them, then each group's title.
    let nodeTexts: [String]
    /// Statements read and not applied (`FlowchartDiagram.unappliedStatementCount`).
    let unappliedStatementCount: Int

    init(diagram: FlowchartDiagram, layout: FlowchartLayout, narrowLayout: FlowchartLayout? = nil) {
        self.layout = layout
        shapes = ReadingFlowchartShapes(parts: FlowchartDrawingParts(layout: layout), font: layout.font)
        narrow = narrowLayout.map { narrowLayout in
            ReadingNarrowLayout(layout: narrowLayout,
                                shapes: ReadingFlowchartShapes(parts: FlowchartDrawingParts(layout: narrowLayout), font: narrowLayout.font))
        }
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        unappliedStatementCount = diagram.unappliedStatementCount
        let groupNodes = Set(diagram.subgraphs.compactMap(\.representingNodeIndex))
        nodeTexts = diagram.nodes.indices.filter { node in !groupNodes.contains(node) }.map { node in diagram.nodes[node].label.spokenText }
            + diagram.subgraphs.map(\.title.spokenText).filter { title in !title.isEmpty }
    }
}
