import MermaidDiagrams

/// A timeline laid out, its shapes ready to paint, and what a screen reader says of it.
struct ReadingTimeline: Sendable {
    let layout: TimelineLayout
    let shapes: ReadingTimelineShapes
    /// The diagram laid out for a narrow column, turned to run down, or nil when it is narrow enough already or runs down.
    let narrow: ReadingNarrowLayout<TimelineLayout, ReadingTimelineShapes>?
    /// `accTitle`, else the title, else nil.
    let title: String?
    /// `accDescr`, or nil.
    let description: String?
    /// Each period with its events, in the order the diagram writes them: “2004: Facebook, Google”.
    let periodTexts: [String]

    init(diagram: TimelineDiagram, layout: TimelineLayout, narrowLayout: TimelineLayout? = nil) {
        self.layout = layout
        shapes = ReadingTimelineShapes(parts: TimelineDrawingParts(layout: layout), font: layout.font)
        narrow = narrowLayout.map { narrowLayout in
            ReadingNarrowLayout(layout: narrowLayout,
                                shapes: ReadingTimelineShapes(parts: TimelineDrawingParts(layout: narrowLayout), font: narrowLayout.font))
        }
        title = diagram.accessibilityTitle ?? diagram.title
        description = diagram.accessibilityDescription
        periodTexts = diagram.periods.map { period in
            period.events.isEmpty ? period.label.spokenText
                : period.label.spokenText + ": " + period.events.map(\.spokenText).joined(separator: ", ")
        }
    }
}
