/**
 * File: PieChartOptions.swift
 * ---------------------------
 * Layer: Core
 * Description: The options of a pie chart its front matter sets under `config:` and `pie:`.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import CoreGraphics

/// The options of pie charts a diagram's front matter sets (`config:`, then `pie:`): how far out the percentages stand,
/// the hole that makes the pie a donut, and where the legend goes. A value out of its range, or of the wrong kind, is
/// left at its default, as Mermaid's schema leaves it.
public struct PieChartOptions: Equatable, Sendable {
    /// `textPosition`: how far out a percentage inside its slice stands, as a share of the radius from 0 to 1; nil for
    /// the default, three quarters, or the middle of the ring of a donut.
    public internal(set) var percentagePosition: CGFloat?
    /// `donutHole`: the hole's radius as a share of the pie's, from 0 (a full pie) to 0.9.
    public internal(set) var holeShare: CGFloat = 0
    /// `legendPosition`: where the legend stands beside the pie.
    public internal(set) var legendPosition: PieChartLegendPosition = .right

    /// The largest hole: a thinner ring leaves no room for the percentages.
    static let largestHoleShare: CGFloat = 0.9

    /// Options that set nothing: a full pie, percentages three quarters of the way out, the legend on the right.
    public init() {}

    init(_ options: MermaidFrontMatterOptions) {
        if case .number(let position) = options.values["textPosition"], position >= 0, position <= 1 { percentagePosition = CGFloat(position) }
        if case .number(let hole) = options.values["donutHole"], hole >= 0, hole <= Self.largestHoleShare { holeShare = CGFloat(hole) }
        if case .text(let written) = options.values["legendPosition"], let position = PieChartLegendPosition(rawValue: written.lowercased()) {
            legendPosition = position
        }
    }

    /// How far out a percentage inside its slice stands: as written, else the middle of a donut's ring when that is
    /// farther out than three quarters, else three quarters.
    var effectivePercentagePosition: CGFloat {
        percentagePosition ?? max(PieChartSlicePlacement.percentagePosition, (1 + holeShare) / 2)
    }
}

/// Where a pie chart's legend stands.
public enum PieChartLegendPosition: String, Equatable, Sendable, CaseIterable {
    case right, left, top, bottom
    /// No legend.
    case none
}
