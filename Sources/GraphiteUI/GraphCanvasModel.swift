import Foundation
import Observation
import GraphiteCore

/// Runs a graph layout away from the main thread. Dragging a node goes through it too, so
/// a pin never races a step.
actor GraphSimulator {
    private var layout: GraphLayout

    init(layout: GraphLayout) {
        self.layout = layout
    }

    /// Calms the layout as `GraphLayout.calm()` does, within its budget, and returns where its
    /// nodes are then.
    func calm() async -> [SIMD2<Double>] {
        let maximumSteps = GraphLayout.calmingStepLimit(nodeCount: layout.positions.count)
        var steps = 0
        while !layout.isCalm, steps < maximumSteps {
            await step()
            steps += 1
        }
        return layout.positions
    }

    func advance(steps: Int) async -> (positions: [SIMD2<Double>], isSettled: Bool) {
        for _ in 0..<steps where !layout.isSettled { await step() }
        return (layout.positions, layout.isSettled)
    }

    /// One step, its repulsion shared between the cores. A pin or a change of forces that comes
    /// in meanwhile applies from this step on; the pushes were worked out for the positions
    /// before it, as they would have been.
    private func step() async {
        let pushes = await layout.repulsionPushesSharingWork()
        layout.step(repulsionPushes: pushes)
    }

    func pin(_ identifier: String, at position: SIMD2<Double>) {
        layout.pin(identifier, at: position)
        layout.reheat(to: 0.3)
    }

    func unpin(_ identifier: String) {
        layout.unpin(identifier)
    }

    func change(forces: GraphLayout.Forces) {
        layout.forces = forces
        layout.reheat(to: 0.5)
    }

    var positionsByIdentifier: [String: SIMD2<Double>] { layout.positionsByIdentifier }
}

/// The nodes on screen and where they are, updated as the layout settles.
@MainActor @Observable
final class GraphCanvasModel {
    private(set) var graph = LinkGraph(nodes: [], edges: [])
    private(set) var positions: [SIMD2<Double>] = []
    /// Each edge as the indexes of its nodes.
    private(set) var edgeIndexes: [(source: Int, target: Int)] = []
    private(set) var radii: [Double] = []
    private(set) var neighborIndexes: [Set<Int>] = []
    private(set) var isSettled = true
    /// Whether a graph laid out from nothing is being calmed before it is shown, or the first
    /// graph made ready.
    private(set) var isCalming = false
    /// What the graph shows, counted once when it is loaded.
    private(set) var counts = LinkGraph.Counts()
    /// The group that colors each node, by the node's index; nil where no group does.
    private(set) var groupIndexes: [Int?] = []
    @ObservationIgnored private var indexByIdentifier: [String: Int] = [:]
    /// Each node's name as measured at the names' font, filled as the names are drawn, which
    /// needs their sizes every frame to keep them apart; as long as the graph's nodes.
    @ObservationIgnored private var measuredNameSizes: [CGSize?] = []
    /// How many characters each node's name has, for the room the fit leaves for names.
    @ObservationIgnored private var nameCharacterCounts: [Int] = []
    /// Counts the loads, so a load that a later one replaced while it waited stops.
    @ObservationIgnored private var loadCount = 0
    @ObservationIgnored private var simulator: GraphSimulator?
    @ObservationIgnored private var runTask: Task<Void, Never>?

    /// Shows a graph. Nodes with a known place start there and the layout adjusts on screen;
    /// a graph laid out from nothing is first calmed off the main thread, so it appears in
    /// place rather than flying apart. The nodes shown until now keep where they are, winning
    /// over `previousPositions`. Everything the canvas needs of the graph is worked out away
    /// from the main thread (`GraphCanvasContents`); the graph shown until then stays. Returns
    /// once the graph is shown, or at once when a later load or the view's going replaced it
    /// meanwhile.
    func load(_ graph: LinkGraph, forces: GraphLayout.Forces, previousPositions: [String: SIMD2<Double>],
              groupIndexByIdentifier: [String: Int]) async {
        runTask?.cancel()
        runTask = nil
        // With nothing shown yet, the progress shows while the graph is made ready too.
        isCalming = self.graph.nodes.isEmpty && !graph.nodes.isEmpty
        loadCount += 1
        let load = loadCount
        let contents = await GraphCanvasContents.made(from: graph, forces: forces, previousPositions: previousPositions,
                                                      shownNodes: self.graph.nodes, shownPositions: positions)
        guard loadCount == load, !Task.isCancelled else { return }
        self.graph = graph
        measuredNameSizes = Array(repeating: nil, count: graph.nodes.count)
        colorNodes(by: groupIndexByIdentifier)
        indexByIdentifier = contents.indexByIdentifier
        edgeIndexes = contents.edgeIndexes
        neighborIndexes = contents.neighborIndexes
        counts = contents.counts
        radii = contents.radii
        nameCharacterCounts = contents.nameCharacterCounts
        let simulator = GraphSimulator(layout: contents.layout)
        self.simulator = simulator
        guard contents.startsFromNothing, !graph.nodes.isEmpty else {
            isCalming = false
            positions = contents.layout.positions
            run()
            return
        }
        positions = []
        isCalming = true
        let calmedPositions = await simulator.calm()
        guard self.simulator === simulator, !Task.isCancelled else { return }
        isCalming = false
        positions = calmedPositions
        run()
    }

    func index(of identifier: String) -> Int? { indexByIdentifier[identifier] }

    /// A node's name size, measured by `measure` the first time it is asked for.
    func nameSize(ofNodeAt index: Int, measuring measure: () -> CGSize) -> CGSize {
        guard measuredNameSizes.indices.contains(index) else { return measure() }
        if let size = measuredNameSizes[index] { return size }
        let size = measure()
        measuredNameSizes[index] = size
        return size
    }

    /// A node's radius on screen: its size from its links, the person's node size and the
    /// zoom. The drawing and the hit testing both use it.
    func screenRadius(ofNodeAt index: Int, in viewport: GraphViewport, display: GraphDisplayOptions) -> Double {
        viewport.screenRadius(ofNodeRadius: radii[index] * display.nodeSizeMultiplier)
    }

    /// The viewport that shows the whole graph in a view of this size, with room for the names
    /// drawn at its zoom (`GraphViewport.fitting`); nil before the graph is shown.
    func fittingViewport(in size: CGSize, display: GraphDisplayOptions, alwaysShowsNames: Bool) -> GraphViewport? {
        guard nameCharacterCounts.count == graph.nodes.count else { return nil }
        let names = graph.nodes.indices.map { index in
            GraphViewport.NameRoom(characterCount: nameCharacterCounts[index],
                                   shownFromScale: alwaysShowsNames ? 0 : display.nameFadeStartScale(of: graph.nodes[index].kind))
        }
        return GraphViewport.fitting(positions, names: names, in: size)
    }

    /// Takes the groups' coloring of the files, as after a group's search changes.
    func colorNodes(by groupIndexByIdentifier: [String: Int]) {
        groupIndexes = graph.nodes.map { node in groupIndexByIdentifier[node.id] }
    }

    /// What a tap does: on a tag, chooses it or lets it go, so its notes stand out rather
    /// than the graph giving way to a search; on another node, opens it, keeping a chosen
    /// tag so its notes can be opened one after another. Beside the nodes, lets the tag go.
    func tap(nodeAt index: Int?, chosenTag: String?) -> GraphTap {
        guard let index, graph.nodes.indices.contains(index) else { return .choose(nil) }
        let node = graph.nodes[index]
        guard node.kind == .tag else { return .open(node) }
        return .choose(chosenTag == node.id ? nil : node.id)
    }

    func pin(_ identifier: String, at position: SIMD2<Double>) {
        guard let simulator else { return }
        if let index = indexByIdentifier[identifier], positions.indices.contains(index) { positions[index] = position }
        Task {
            await simulator.pin(identifier, at: position)
            run()
        }
    }

    func unpin(_ identifier: String) {
        guard let simulator else { return }
        Task { await simulator.unpin(identifier) }
    }

    func change(forces: GraphLayout.Forces) {
        guard let simulator else { return }
        Task {
            await simulator.change(forces: forces)
            run()
        }
    }

    /// Where each node is shown; none while the graph is being calmed.
    var positionsByIdentifier: [String: SIMD2<Double>] {
        guard positions.count == graph.nodes.count else { return [:] }
        return Dictionary(uniqueKeysWithValues: graph.nodes.indices.map { index in (graph.nodes[index].id, positions[index]) })
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
    }

    /// How many steps the layout takes between two drawings. Two steps a frame settle a small
    /// graph in about three seconds; a larger one takes longer per step and to draw, so it is
    /// drawn less often. With its steps shared between the cores, a graph of 100,000 notes was
    /// drawn after every eighth step, and drawing it took most of the main thread while it
    /// settled (`GraphBenchmarkTests`, frames of 180 to 210 ms on the iPad simulator).
    static func stepsPerUpdate(nodeCount: Int) -> Int {
        if nodeCount > 20_000 { return 24 }
        return nodeCount > 3_000 ? 8 : 2
    }

    private func run() {
        guard runTask == nil || isSettled, let simulator else { return }
        isSettled = false
        let stepsPerUpdate = Self.stepsPerUpdate(nodeCount: graph.nodes.count)
        runTask = Task { [weak self] in
            while !Task.isCancelled {
                let (positions, isSettled) = await simulator.advance(steps: stepsPerUpdate)
                guard let self, !Task.isCancelled else { return }
                self.positions = positions
                if isSettled {
                    self.isSettled = true
                    self.runTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

/// What a tap on the graph does.
enum GraphTap: Equatable {
    case open(GraphNode)
    /// The tag that stands out with its notes from now on; nil lets it go.
    case choose(String?)
}
