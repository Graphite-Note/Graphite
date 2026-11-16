/**
 * File: MeasuredBlockHeightCache.swift
 * ------------------------------------
 * Layer: UI
 * Description: The heights rendered blocks' views measured, shared by every editor, by column width and by the
 *              settings a height depends on; the height a block last measured at any width; and how far each kind
 *              of block measured from the estimate its source gave.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import CoreGraphics
import GraphiteCore

/// Heights rendered blocks measured, shared by every editor, so a note opened again lays
/// its blocks out at their measured heights at once instead of at estimates that each
/// block then corrects with a restyle and a visible jump. A height holds for one column
/// width and text size. Past the capacity, the heights recorded longest ago go first.
struct MeasuredBlockHeightCache {
    struct Key: Hashable {
        let blockKey: LivePreviewBlockKey
        let columnWidth: Int
        let textSize: Double
        /// A block's height also changes with the fonts it is drawn in.
        let typography: NoteTypography
        /// And with the theme's sizes, spacing and borders.
        let themeFingerprint: String

        /// Nil for a width that is not a finite number of points, as before the first layout.
        init?(blockKey: LivePreviewBlockKey, columnWidth: CGFloat, textSize: Double, typography: NoteTypography = .standard, themeFingerprint: String = "") {
            guard let wholeColumnWidth = Int(exactly: columnWidth.rounded()), wholeColumnWidth > 0 else { return nil }
            self.blockKey = blockKey
            self.columnWidth = wholeColumnWidth
            self.textSize = textSize
            self.typography = typography
            self.themeFingerprint = themeFingerprint
        }

        var settings: Settings {
            Settings(blockKey: blockKey, textSize: textSize, typography: typography, themeFingerprint: themeFingerprint)
        }
    }

    /// A block and what its height depends on besides the column's width.
    struct Settings: Hashable {
        let blockKey: LivePreviewBlockKey
        let textSize: Double
        var typography: NoteTypography = .standard
        var themeFingerprint = ""
    }

    /// How the views of each kind of block measured against their sources' estimates.
    var estimates = BlockEstimateLearning()
    private var heightsByKey: [Key: CGFloat] = [:]
    /// Oldest first.
    private var recordingOrder: [Key] = []
    /// The key each block was last measured under, with its settings.
    private var latestKeyBySettings: [Settings: Key] = [:]
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    var count: Int { heightsByKey.count }

    func height(for key: Key) -> CGFloat? {
        heightsByKey[key]
    }

    /// The height the block last measured with these settings, at whatever width: closer than an
    /// estimate from its source for a note styled before its view has a width, as one opening
    /// does, which is most often the width it was measured at.
    func latestHeight(for settings: Settings) -> CGFloat? {
        latestKeyBySettings[settings].flatMap { key in heightsByKey[key] }
    }

    mutating func record(_ height: CGFloat, for key: Key) {
        if heightsByKey.updateValue(height, forKey: key) == nil { recordingOrder.append(key) }
        latestKeyBySettings[key.settings] = key
        guard recordingOrder.count > capacity else { return }
        // Dropping a quarter at a time keeps the cost of shifting the order off most records.
        let droppedKeys = recordingOrder.prefix(max(1, capacity / 4))
        for droppedKey in droppedKeys {
            heightsByKey[droppedKey] = nil
            if latestKeyBySettings[droppedKey.settings] == droppedKey { latestKeyBySettings[droppedKey.settings] = nil }
        }
        recordingOrder.removeFirst(droppedKeys.count)
    }
}

/// What the views of one kind of block measured against the estimates their sources gave, at
/// one width and with one set of settings, so a block of that kind not yet shown is estimated
/// closer to its height. In a lecture note every table, formula and callout first reserved the
/// same wrong estimate (a three-row table 176 points for 155), and its view's first reports (8,
/// then 135, then 155 points) restyled it three times as it scrolled in; a block whose estimate
/// was corrected so waits for its view's height to settle, as a block measured before does.
struct BlockEstimateLearning {
    /// The kinds whose estimate counts their lines, and of which a note has many: how tall the
    /// ones measured were tells how tall a line of the next is. The note's properties are one
    /// block a note, whose view reports one height; other kinds are estimated from what they
    /// show (a picture's size, a frame's height) or do not grow with their source.
    enum Kind: Hashable {
        case table, formula, callout

        init?(_ kind: LivePreviewBlock.Kind) {
            switch kind {
            case .table: self = .table
            case .mathBlock: self = .formula
            case .callout: self = .callout
            case .frontmatter, .embed, .imageLine, .baseDefinition, .horizontalRule, .pluginCodeBlock, .mermaidDiagram, .webFrame: return nil
            }
        }
    }

    struct Key: Hashable {
        let kind: Kind
        let columnWidth: Int
        let textSize: Double
        var typography: NoteTypography = .standard
        var themeFingerprint = ""
    }

    private struct Measurement {
        let blockKey: LivePreviewBlockKey
        let estimate: CGFloat
        var measured: CGFloat
    }

    /// The blocks of one kind measured last, oldest first, with their sums.
    private struct KindMeasurements {
        var blocks: [Measurement] = []
        var estimateTotal: CGFloat = 0
        var measuredTotal: CGFloat = 0
    }

    private var measurementsByKind: [Key: KindMeasurements] = [:]
    /// The blocks a kind's correction is worked out from, the latest ones.
    static let blocksPerKind = 32
    /// A view reports a few points before SwiftUI has laid its content out (a table 8 of its 155):
    /// such a report says nothing of the block's height.
    static let smallestMeasurementOfEstimate: CGFloat = 0.25

    /// How much taller this kind's views are than their estimates: the sum of their heights over
    /// the sum of their estimates, between half and twice; nil before any was measured.
    func scale(for key: Key) -> CGFloat? {
        guard let measurements = measurementsByKind[key], measurements.estimateTotal > 0 else { return nil }
        return min(2, max(0.5, measurements.measuredTotal / measurements.estimateTotal))
    }

    /// Records a block's latest height against the estimate its source gave.
    mutating func record(_ measured: CGFloat, estimate: CGFloat, forBlockWithKey blockKey: LivePreviewBlockKey, under key: Key) {
        guard estimate > 0, measured >= estimate * Self.smallestMeasurementOfEstimate else { return }
        var measurements = measurementsByKind[key, default: KindMeasurements()]
        if let index = measurements.blocks.firstIndex(where: { block in block.blockKey == blockKey }) {
            measurements.measuredTotal += measured - measurements.blocks[index].measured
            measurements.blocks[index].measured = measured
        } else {
            measurements.blocks.append(Measurement(blockKey: blockKey, estimate: estimate, measured: measured))
            measurements.estimateTotal += estimate
            measurements.measuredTotal += measured
            if measurements.blocks.count > Self.blocksPerKind {
                let oldest = measurements.blocks.removeFirst()
                measurements.estimateTotal -= oldest.estimate
                measurements.measuredTotal -= oldest.measured
            }
        }
        measurementsByKind[key] = measurements
    }

    /// Whether an estimate corrected by `scale` still holds where the correction is now `current`.
    static func isUnchanged(_ scale: CGFloat?, now current: CGFloat?) -> Bool {
        switch (scale, current) {
        case (nil, nil): true
        case (let scale?, let current?): abs(scale - current) <= 0.02
        case (nil, _?), (_?, nil): false
        }
    }
}

extension BlockEstimateLearning.Key {
    /// Nil for a kind that learns nothing, and for a width that is not a whole number of points
    /// above zero, as before the first layout.
    init?(blockKind: LivePreviewBlock.Kind, columnWidth: CGFloat, textSize: Double, typography: NoteTypography, themeFingerprint: String) {
        guard let kind = BlockEstimateLearning.Kind(blockKind), let wholeColumnWidth = Int(exactly: columnWidth.rounded()), wholeColumnWidth > 0 else {
            return nil
        }
        self.init(kind: kind, columnWidth: wholeColumnWidth, textSize: textSize, typography: typography, themeFingerprint: themeFingerprint)
    }
}
