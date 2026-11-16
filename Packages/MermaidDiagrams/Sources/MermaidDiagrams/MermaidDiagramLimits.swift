import CoreGraphics

/// The bounds every diagram is read and laid out within, so that a diagram written to exhaust memory or time fails
/// with a typed error instead. Each count is checked before anything of that count is made.
public struct MermaidDiagramLimits: Equatable, Sendable {
    /// The longest diagram text read, in UTF-8 bytes.
    public var maximumSourceBytes: Int
    /// The most nodes one diagram may declare.
    public var maximumNodeCount: Int
    /// The most edges one diagram may hold: `A & B --> C & D` makes four, so a short text can ask for many.
    public var maximumEdgeCount: Int
    /// The most points the layered layout may place: the nodes, plus one for each rank an edge crosses.
    public var maximumLayoutPointCount: Int
    /// The most days a Gantt chart's scheduling may step through to move tasks' ends past excluded days, over all
    /// its passes: a task's duration can be written in years.
    public var maximumScheduledDayCount: Int
    /// The longest side, in points, of a diagram drawn: a layout past it is refused before it is painted, whatever its
    /// counts, so that no view or bitmap is made larger than a screen can show legibly.
    public var maximumDrawingSideLength: CGFloat

    /// Half a million days stepped through (Pele bounds the same work), a fraction of a second at most.
    public static let standardMaximumScheduledDayCount = 500_000
    /// 20,000 points: a diagram this long is already shown at a twentieth of its size in a column of a thousand, and a
    /// side past it would make the views and bitmaps that paint it larger than graphics hardware draws in one piece.
    public static let standardMaximumDrawingSideLength: CGFloat = 20_000

    public init(maximumSourceBytes: Int, maximumNodeCount: Int, maximumEdgeCount: Int, maximumLayoutPointCount: Int,
                maximumScheduledDayCount: Int = standardMaximumScheduledDayCount,
                maximumDrawingSideLength: CGFloat = standardMaximumDrawingSideLength) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumNodeCount = maximumNodeCount
        self.maximumEdgeCount = maximumEdgeCount
        self.maximumLayoutPointCount = maximumLayoutPointCount
        self.maximumScheduledDayCount = maximumScheduledDayCount
        self.maximumDrawingSideLength = maximumDrawingSideLength
    }

    /// Whether a layout of `size` may be drawn: both sides finite, above zero and within `maximumDrawingSideLength`.
    public func allowsDrawing(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && size.width <= maximumDrawingSideLength && size.height <= maximumDrawingSideLength
    }

    /// Mermaid's default text size (50,000), Pele's edge limit (5,000), as many nodes, and 50,000 layout points:
    /// a diagram past them is far beyond what a note shows legibly.
    public static let standard = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 5_000, maximumEdgeCount: 5_000,
                                                      maximumLayoutPointCount: 50_000)
}
