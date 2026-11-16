/**
 * File: MermaidDiagramContent.swift
 * ---------------------------------
 * Layer: Core
 * Description: Whether a diagram read holds anything to draw.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

extension MermaidDiagram {
    /// Whether the diagram declares nothing that is drawn: a flowchart without nodes, a pie chart without slices, a Gantt
    /// chart without tasks. Laid out, such a diagram is an empty page that looks as if the block failed to draw, so a
    /// reader shows its source instead. A quadrant chart (its four quadrants) and a Git graph (its `main` lane) always
    /// draw something; a mindmap, an XY chart and a Sankey diagram with nothing in them are refused while read or laid out.
    public var hasNothingToDraw: Bool {
        switch self {
        case .flowchart(let diagram): diagram.nodes.isEmpty
        case .stateDiagram(let diagram): diagram.states.isEmpty
        case .classDiagram(let diagram): diagram.classes.isEmpty && diagram.notes.isEmpty
        case .sequence(let diagram): diagram.participants.isEmpty
        case .entityRelationship(let diagram): diagram.entities.isEmpty
        case .mindmap(let diagram): diagram.nodes.isEmpty
        case .timeline(let diagram): diagram.periods.isEmpty
        case .pieChart(let chart): chart.slices.isEmpty
        case .ganttChart(let chart): chart.tasks.isEmpty
        case .userJourney(let diagram): diagram.tasks.isEmpty
        case .sankey(let diagram): diagram.links.isEmpty
        case .gitGraph, .quadrantChart, .xyChart: false
        }
    }
}
