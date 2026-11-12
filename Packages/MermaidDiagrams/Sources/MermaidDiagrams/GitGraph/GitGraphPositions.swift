import CoreGraphics

/// Where a Git graph's commits stand along the history and its lanes across it, before the page is placed around
/// them: commits one after another in the order they were made, each a step or the room it and its neighbour need
/// after the last, and lanes as far apart as their content needs, at least a lane's gap.
struct GitGraphPositions {
    /// Each commit's place along the history, the first at 0.
    let along: [CGFloat]
    /// Each lane's place across the history, the first at 0.
    let across: [CGFloat]
    /// The place of the farthest commit along the history, 0 without commits.
    let lastAlong: CGFloat
    /// Each lane's commits' places along the history, in increasing order.
    private let alongByLane: [[CGFloat]]

    init(diagram: GitGraphDiagram, room: GitGraphRoom) {
        var along: [CGFloat] = []
        var lastCommitOfLane = [Int?](repeating: nil, count: diagram.branches.count)
        for index in diagram.commits.indices {
            let lane = diagram.commits[index].branchIndex
            defer { if lane < lastCommitOfLane.count { lastCommitOfLane[lane] = index } }
            guard let previous = along.last else {
                along.append(0)
                continue
            }
            // In parallel (`parallelCommits`), a commit is a step past the farthest of its parents, and past the last
            // commit of its own lane; else a step past the commit made before it.
            let laneBefore = lane < lastCommitOfLane.count ? lastCommitOfLane[lane] : nil
            let predecessors = diagram.options.placesCommitsInParallel
                ? Self.parallelPredecessors(of: index, in: diagram, laneBefore: laneBefore) : [index - 1]
            along.append(predecessors.map { predecessor in along[predecessor] + Self.step(from: predecessor, to: index, room: room) }.max() ?? previous)
        }
        lastAlong = along.max() ?? 0
        var across: [CGFloat] = []
        for lane in diagram.branches.indices {
            guard let previous = across.last else {
                across.append(0)
                continue
            }
            across.append(previous + max(GitGraphGeometry.laneGap, room.laneReachAfter[lane - 1] + room.laneReachBefore[lane] + GitGraphGeometry.gap))
        }
        var alongByLane = diagram.branches.map { _ in [CGFloat]() }
        for (index, commit) in diagram.commits.enumerated() { alongByLane[commit.branchIndex].append(along[index]) }
        self.along = along
        self.across = across
        self.alongByLane = alongByLane
    }

    /// The room between a commit and one before it along the history: a step, or the room the two and the tags of the
    /// second need.
    private static func step(from earlier: Int, to later: Int, room: GitGraphRoom) -> CGFloat {
        let halfLengths = room.halfLengths[earlier] + room.halfLengths[later]
        let lead = room.tagLeads[later]
        return max(GitGraphGeometry.commitStep, halfLengths + GitGraphGeometry.gap,
                   lead > 0 ? room.halfLengths[earlier] + GitGraphGeometry.curveLength + lead : 0)
    }

    /// The commits a commit placed in parallel stands past: its parents and the commit made before it on its lane.
    private static func parallelPredecessors(of index: Int, in diagram: GitGraphDiagram, laneBefore: Int?) -> [Int] {
        let predecessors = diagram.commits[index].parentIndices + (laneBefore.map { before in [before] } ?? [])
        return predecessors.isEmpty ? [index - 1] : predecessors
    }

    /// Whether a commit of `lane` stands strictly between `start` and `end` along the history, where a connector
    /// running along the lane would cross it.
    func isOccupied(lane: Int, after start: CGFloat, before end: CGFloat) -> Bool {
        let places = alongByLane[lane]
        var low = 0
        var high = places.count
        while low < high {
            let middle = (low + high) / 2
            if places[middle] <= start { low = middle + 1 } else { high = middle }
        }
        return low < places.count && places[low] < end
    }
}
