import CoreGraphics

/// Lays a pie chart out in Pele's style: a pie 120 points in radius, its slices clockwise from the top with their
/// percentages three quarters of the way out (outside the rim for a slice too thin, the pie then 28 points wider on
/// each side), the legend 32 points to its right in rows of 26 points with 12-point swatches, and the title above.
/// Percentages and the legend are in the smaller text size, seven eighths of the title's.
public enum PieChartLayoutEngine {
    static let radius: CGFloat = 120
    /// Around the whole chart.
    static let padding: CGFloat = 8
    /// Between the title and the pie.
    static let titleGap: CGFloat = 16
    /// Between the pie and the legend.
    static let legendGap: CGFloat = 32
    static let legendRowHeight: CGFloat = 26
    static let swatchSide: CGFloat = 12
    /// Between a swatch and its label.
    static let swatchTextGap: CGFloat = 8
    /// The widest a legend label or the title is before it wraps: wide enough that it does not.
    static let wrappingWidth: CGFloat = 4_000
    /// How much of an angle short of a full turn a slice may be and still be the whole pie.
    static let wholePieTolerance: CGFloat = 1e-9
    /// 2⁵³: past it, a double holds no fraction and not every whole number.
    private static let largestExactWholeNumber = 9_007_199_254_740_992.0

    public static func layout(_ chart: PieChart, typography: DiagramTypography) -> PieChartLayout {
        layout(chart, text: typography.nodeText, smallText: typography.edgeText, font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ chart: PieChart, text: Measurer, smallText: Measurer, font: DiagramFont) -> PieChartLayout {
        let options = chart.options
        let slices = PieChartSlicePlacement(values: chart.slices.map(\.value), smallText: smallText, radius: radius,
                                            percentagePosition: options.effectivePercentagePosition)
        let legendTexts = options.legendPosition == .none ? []
            : chart.slices.map { slice in legendText(for: slice, showsValue: chart.showsValues, measurer: smallText) }
        let title = chart.title.map { title in
            DiagramTextBlock(label: DiagramLabelDecoder.label(from: title, form: .plain), measurer: text, maximumWidth: wrappingWidth)
        }.flatMap { block in block.lines.isEmpty ? nil : block }
        let arrangement = Arrangement(pieDiameter: 2 * (radius + slices.outsideLabelRoom), legendSize: legendSize(of: legendTexts),
                                      legendPosition: options.legendPosition, title: title)
        return PieChartLayout(size: arrangement.size, font: font, center: arrangement.pieCenter, radius: radius, innerRadius: radius * options.holeShare,
                              slices: slices.placed(around: arrangement.pieCenter), legend: legend(legendTexts, at: arrangement.legendOrigin),
                              title: arrangement.placedTitle)
    }

    /// The label, with ` [value]` after its last line when the chart shows its values.
    private static func legendText(for slice: PieChartSlice, showsValue: Bool, measurer: some DiagramTextMeasuring) -> DiagramTextBlock {
        var lines = slice.label.lines
        if showsValue, let last = lines.popLast() { lines.append(last + " [\(writtenValue(slice.value))]") }
        return DiagramTextBlock(label: DiagramLabel(lines: lines), measurer: measurer, maximumWidth: wrappingWidth)
    }

    /// A value as Mermaid prints it: a whole number without a fraction (`386`), else its shortest decimal (`42.96`).
    static func writtenValue(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < largestExactWholeNumber { return String(Int64(value)) }
        return String(value)
    }

    private static func legendSize(of texts: [DiagramTextBlock]) -> CGSize {
        guard let widest = texts.map(\.size.width).max() else { return .zero }
        return CGSize(width: widest + swatchSide + swatchTextGap, height: CGFloat(texts.count) * legendRowHeight)
    }

    /// One row per text from `origin` down, each swatch centered on its row and the label after it.
    private static func legend(_ texts: [DiagramTextBlock], at origin: CGPoint) -> [PieChartLegendEntry] {
        texts.enumerated().map { index, text in
            let rowMiddle = origin.y + CGFloat(index) * legendRowHeight + legendRowHeight / 2
            var placed = text
            placed.center = CGPoint(x: origin.x + swatchSide + swatchTextGap + text.size.width / 2, y: rowMiddle)
            return PieChartLegendEntry(seriesIndex: index, swatch: CGRect(x: origin.x, y: rowMiddle - swatchSide / 2, width: swatchSide, height: swatchSide),
                                       text: placed)
        }
    }

    /// Where the pie, the legend beside it (on the side `legendPosition` names) and the title above go, and the page
    /// around them.
    private struct Arrangement {
        let size: CGSize
        let pieCenter: CGPoint
        let legendOrigin: CGPoint
        let placedTitle: DiagramTextBlock?

        init(pieDiameter: CGFloat, legendSize: CGSize, legendPosition: PieChartLegendPosition, title: DiagramTextBlock?) {
            let titleHeight = title.map { title in title.size.height + PieChartLayoutEngine.titleGap } ?? 0
            let hasLegend = legendSize.width > 0
            let gap = hasLegend ? PieChartLayoutEngine.legendGap : 0
            let isBeside = legendPosition == .right || legendPosition == .left
            let contentWidth = isBeside ? pieDiameter + gap + legendSize.width : max(pieDiameter, legendSize.width)
            let bodyWidth = max(contentWidth, title?.size.width ?? 0)
            let bodyHeight = isBeside ? max(pieDiameter, legendSize.height) : pieDiameter + gap + legendSize.height
            let padding = PieChartLayoutEngine.padding
            let bodyTop = padding + titleHeight
            // Beside its legend the pie stays at the left under a wider title, as Pele keeps it; above or below it, the
            // two are centered.
            let bodyLeft = padding + (isBeside || !hasLegend ? 0 : (bodyWidth - contentWidth) / 2)
            let pageSize = CGSize(width: (bodyWidth + 2 * padding).rounded(.up), height: (bodyHeight + titleHeight + 2 * padding).rounded(.up))
            size = pageSize
            let radius = pieDiameter / 2
            switch legendPosition {
            case .right, .none:
                pieCenter = CGPoint(x: bodyLeft + radius, y: bodyTop + bodyHeight / 2)
                legendOrigin = CGPoint(x: pieCenter.x + radius + gap, y: bodyTop + (bodyHeight - legendSize.height) / 2)
            case .left:
                pieCenter = CGPoint(x: bodyLeft + legendSize.width + gap + radius, y: bodyTop + bodyHeight / 2)
                legendOrigin = CGPoint(x: bodyLeft, y: bodyTop + (bodyHeight - legendSize.height) / 2)
            case .top:
                pieCenter = CGPoint(x: bodyLeft + contentWidth / 2, y: bodyTop + legendSize.height + gap + radius)
                legendOrigin = CGPoint(x: bodyLeft + (contentWidth - legendSize.width) / 2, y: bodyTop)
            case .bottom:
                pieCenter = CGPoint(x: bodyLeft + contentWidth / 2, y: bodyTop + radius)
                legendOrigin = CGPoint(x: bodyLeft + (contentWidth - legendSize.width) / 2, y: bodyTop + pieDiameter + gap)
            }
            placedTitle = title.map { title in
                var placed = title
                placed.center = CGPoint(x: pageSize.width / 2, y: padding + title.size.height / 2)
                return placed
            }
        }
    }
}
