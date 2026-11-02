/**
 * File: FlowchartDiagramBuilder.swift
 * -----------------------------------
 * Layer: Core
 * Description: Collects a flowchart as its statements are read.
 *
 * Authors: Félix Chevalier
 * Version: 0.3
 * Date: 01/11/2026
 */

/// Collects a flowchart as its statements are read: nodes by identifier, edges within the limits, and the groups open
/// at each point, which take the names written inside them. A group's members are settled when it ends, and the
/// groups' nesting once the whole text is read (`finishedDiagram()`).
struct FlowchartDiagramBuilder {
    private var diagram = FlowchartDiagram()
    private let limits: MermaidDiagramLimits
    private var nodeIndexByIdentifier: [String: Int] = [:]
    /// Identifiers given to edges (`e1@-->`), whose `e1@{ … }` sets an edge's attributes rather than a node's.
    private var edgeIdentifiers: Set<String> = []
    /// The groups open now, outermost first.
    private var openSubgraphs: [OpenSubgraph] = []
    /// The groups ended so far, in the order they ended; a group ended again under the same identifier is merged.
    private var endedSubgraphs: [EndedFlowchartSubgraph] = []
    private var endedSubgraphIndexByIdentifier: [String: Int] = [:]
    /// Names a group took as it ended: a node or group belongs to the first group that ends with it named inside.
    private var takenMemberNames: Set<String> = []
    /// How many groups have opened, and how many have ended (the number in an identifier Mermaid makes, `subGraph0`).
    private var openedSubgraphCount = 0
    private var endedSubgraphCount = 0
    /// Identifiers given `@{ view: collapsed }`.
    private var collapsedIdentifiers: Set<String> = []
    /// What each `classDef` sets, by class name (a class defined again keeps what it set and takes what the new one sets).
    private var classStyles: [String: DiagramElementStyle] = [:]
    /// The classes given to nodes by `class` and `:::`, in the order written; resolved when the text ends, since `classDef`
    /// may come after them.
    private var classAssignments: [(identifier: String, className: String)] = []
    /// What `style` sets, by node identifier, in the order written.
    private var nodeStyleStatements: [(identifier: String, style: DiagramElementStyle)] = []
    /// What `linkStyle` sets for every edge (`default`) or for the edges at some indexes, in the order written.
    private var linkStyleStatements: [(indices: [Int]?, style: DiagramElementStyle)] = []

    /// A group open at the reading position.
    private struct OpenSubgraph {
        /// The identifier written after `subgraph`, or nil when Mermaid makes one as the group ends.
        let writtenIdentifier: String?
        let title: DiagramLabel
        let openingOrder: Int
        var direction: FlowchartDirection?
        var memberNames: [String] = []
        var memberNameSet: Set<String> = []

        mutating func add(memberName: String) {
            guard memberNameSet.insert(memberName).inserted else { return }
            memberNames.append(memberName)
        }
    }

    init(limits: MermaidDiagramLimits) {
        self.limits = limits
    }

    /// The index of the node named `identifier`, added with its identifier as its text the first time it is named.
    /// A node named inside a group joins the innermost one.
    mutating func nodeIndex(for identifier: String) throws(MermaidDiagramReadError) -> Int {
        let index: Int
        if let existing = nodeIndexByIdentifier[identifier] {
            index = existing
        } else {
            guard diagram.nodes.count < limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
            index = diagram.nodes.count
            diagram.nodes.append(FlowchartNode(identifier: identifier, label: DiagramLabel(identifier)))
            nodeIndexByIdentifier[identifier] = index
        }
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: identifier) }
        return index
    }

    /// A later definition of a node replaces what an earlier one set, as in Mermaid.
    mutating func define(nodeAt index: Int, as definition: FlowchartNodeDefinition) {
        if let shape = definition.shape { diagram.nodes[index].shape = shape }
        if let label = definition.label { diagram.nodes[index].label = label }
        if definition.asksForCollapsedView { collapsedIdentifiers.insert(diagram.nodes[index].identifier) }
    }

    /// One edge from each source to each target, as `A & B --> C & D` asks.
    mutating func addEdges(from sourceIndices: [Int], to targetIndices: [Int], link: FlowchartLink) throws(MermaidDiagramReadError) {
        guard diagram.edges.count + sourceIndices.count * targetIndices.count <= limits.maximumEdgeCount else {
            throw .tooManyEdges(limit: limits.maximumEdgeCount)
        }
        for sourceIndex in sourceIndices {
            for targetIndex in targetIndices {
                diagram.edges.append(FlowchartEdge(sourceIndex: sourceIndex, targetIndex: targetIndex, stroke: link.stroke,
                                                   sourceArrowhead: link.sourceArrowhead, targetArrowhead: link.targetArrowhead,
                                                   minimumRankSpan: link.minimumRankSpan, label: link.label))
            }
        }
    }

    mutating func recordEdgeIdentifier(_ identifier: String) {
        edgeIdentifiers.insert(identifier)
    }

    func isEdgeIdentifier(_ identifier: String) -> Bool {
        edgeIdentifiers.contains(identifier)
    }

    /// Opens a group; `identifier` is nil when the text gives none, and Mermaid's is made as the group ends.
    mutating func openSubgraph(identifier: String?, title: DiagramLabel) {
        openSubgraphs.append(OpenSubgraph(writtenIdentifier: identifier, title: title, openingOrder: openedSubgraphCount))
        openedSubgraphCount += 1
    }

    /// Ends the innermost group: it takes the names written inside it that no group ended before it took, never its
    /// own, and its identifier joins the group around it. False when no group is open.
    mutating func closeSubgraph() -> Bool {
        guard let group = openSubgraphs.popLast() else { return false }
        let identifier = group.writtenIdentifier ?? "subGraph\(endedSubgraphCount)"
        endedSubgraphCount += 1
        let members = group.memberNames.filter { name in !takenMemberNames.contains(name) && name != identifier }
        takenMemberNames.formUnion(members)
        if let existing = endedSubgraphIndexByIdentifier[identifier] {
            endedSubgraphs[existing].memberNames.append(contentsOf: members)
        } else {
            endedSubgraphIndexByIdentifier[identifier] = endedSubgraphs.count
            endedSubgraphs.append(EndedFlowchartSubgraph(identifier: identifier, title: group.title, direction: group.direction,
                                                         openingOrder: group.openingOrder, memberNames: members))
        }
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].add(memberName: identifier) }
        return true
    }

    /// The identifier of the innermost group still open (as Mermaid would make it, when the text gives none), or nil.
    var innermostOpenSubgraphIdentifier: String? {
        openSubgraphs.last.map { group in group.writtenIdentifier ?? "subGraph\(endedSubgraphCount)" }
    }

    var hasOpenSubgraph: Bool { !openSubgraphs.isEmpty }

    /// `direction` inside the innermost open group.
    mutating func setInnermostSubgraphDirection(_ direction: FlowchartDirection) {
        guard !openSubgraphs.isEmpty else { return }
        openSubgraphs[openSubgraphs.count - 1].direction = direction
    }

    /// The flowchart read, its groups nested and ordered (`FlowchartSubgraphNesting`), its nodes and edges styled.
    func finishedDiagram() -> FlowchartDiagram {
        var finished = diagram
        finished.subgraphs = FlowchartSubgraphNesting.subgraphs(endedSubgraphs, nodeIndexByIdentifier: nodeIndexByIdentifier,
                                                                collapsedIdentifiers: collapsedIdentifiers)
        finished.unappliedStatementCount += applyStyles(to: &finished)
        return finished
    }

    /// Gives `diagram`'s nodes and edges the styles the statements set, and returns how many statements named a node or a
    /// link that is not there.
    private func applyStyles(to diagram: inout FlowchartDiagram) -> Int {
        styleNodes(of: &diagram) + styleEdges(of: &diagram)
    }

    /// A node takes the `default` class, then its classes in the order they were given, then its own `style`. Returns how
    /// many `class` and `style` statements named no node (a group's, whose box is not styled yet, or none at all).
    private func styleNodes(of diagram: inout FlowchartDiagram) -> Int {
        var unappliedCount = 0
        var classNamesByNode: [Int: [String]] = [:]
        for assignment in classAssignments {
            guard let node = nodeIndexByIdentifier[assignment.identifier] else {
                unappliedCount += 1
                continue
            }
            classNamesByNode[node, default: []].append(assignment.className)
        }
        var ownStylesByNode: [Int: DiagramElementStyle] = [:]
        for statement in nodeStyleStatements {
            guard let node = nodeIndexByIdentifier[statement.identifier] else {
                unappliedCount += 1
                continue
            }
            ownStylesByNode[node] = (ownStylesByNode[node] ?? DiagramElementStyle()).overridden(by: statement.style)
        }
        let defaultStyle = classStyles["default"] ?? DiagramElementStyle()
        for node in diagram.nodes.indices {
            var style = defaultStyle
            for className in classNamesByNode[node] ?? [] { style = style.overridden(by: classStyles[className] ?? DiagramElementStyle()) }
            style = style.overridden(by: ownStylesByNode[node] ?? DiagramElementStyle())
            diagram.nodes[node].style = style.isEmpty ? nil : style
        }
        return unappliedCount
    }

    /// An edge takes `linkStyle default`, then the `linkStyle` of its index. Returns how many indexes named no edge.
    private func styleEdges(of diagram: inout FlowchartDiagram) -> Int {
        var unappliedCount = 0
        var defaultEdgeStyle = DiagramElementStyle()
        var edgeStyles: [Int: DiagramElementStyle] = [:]
        for statement in linkStyleStatements {
            guard let indices = statement.indices else {
                defaultEdgeStyle = defaultEdgeStyle.overridden(by: statement.style)
                continue
            }
            for index in indices {
                guard diagram.edges.indices.contains(index) else {
                    unappliedCount += 1
                    continue
                }
                edgeStyles[index] = (edgeStyles[index] ?? DiagramElementStyle()).overridden(by: statement.style)
            }
        }
        for edge in diagram.edges.indices {
            let style = defaultEdgeStyle.overridden(by: edgeStyles[edge] ?? DiagramElementStyle())
            diagram.edges[edge].style = style.isEmpty ? nil : style
        }
        return unappliedCount
    }

    /// Records what a statement that styles the diagram sets; a statement that could not be read is counted as not applied.
    mutating func apply(_ statement: FlowchartStyleStatement?) {
        guard let statement else {
            countUnappliedStatement()
            return
        }
        switch statement {
        case .classDefinition(let names, let declarations):
            let (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            for name in names { classStyles[name] = (classStyles[name] ?? DiagramElementStyle()).overridden(by: style) }
            if hasUnappliedDeclaration { countUnappliedStatement() }
        case .classAssignment(let identifiers, let className):
            for identifier in identifiers { classAssignments.append((identifier, className)) }
        case .nodeStyle(let identifier, let declarations):
            let (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            nodeStyleStatements.append((identifier, style))
            if hasUnappliedDeclaration { countUnappliedStatement() }
        case .linkStyle(let indices, let declarations):
            var (style, hasUnappliedDeclaration) = DiagramElementStyle.reading(declarations)
            // An edge has no inside to fill; its text color is not set from here.
            style.fill = nil
            if style.textColor != nil {
                style.textColor = nil
                hasUnappliedDeclaration = true
            }
            linkStyleStatements.append((indices, style))
            if hasUnappliedDeclaration { countUnappliedStatement() }
        }
    }

    /// `A:::name`: the node at `index` takes the class.
    mutating func assignClass(_ className: String, toNodeAt index: Int) {
        classAssignments.append((diagram.nodes[index].identifier, className))
    }

    mutating func setDirection(_ direction: FlowchartDirection) {
        diagram.direction = direction
    }

    mutating func setAccessibilityTitle(_ title: String) {
        diagram.accessibilityTitle = title
    }

    mutating func setAccessibilityDescription(_ description: String) {
        diagram.accessibilityDescription = description
    }

    mutating func countUnappliedStatement() {
        diagram.unappliedStatementCount += 1
    }
}
