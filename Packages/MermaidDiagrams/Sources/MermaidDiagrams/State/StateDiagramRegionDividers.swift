/**
 * File: StateDiagramRegionDividers.swift
 * --------------------------------------
 * Layer: Core
 * Description: The dashed lines between the concurrent regions of a composite state's body.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import CoreGraphics

/// The dashed lines Mermaid draws between the concurrent regions (`--`) of a composite state's body: one in the middle of
/// the gap between each two neighbouring regions, as long as the two together. The layout puts regions side by side
/// across their body's flow, which has no transition between them; regions that overlap both ways get no line.
enum StateDiagramRegionDividers {
    static func dividers(between regionFrames: [CGRect]) -> [DiagramPath] {
        guard regionFrames.count > 1 else { return [] }
        let acrossX = regionFrames.sorted { first, second in first.minX < second.minX }
        if zip(acrossX, acrossX.dropFirst()).allSatisfy({ first, second in first.maxX <= second.minX }) {
            return zip(acrossX, acrossX.dropFirst()).map { first, second in
                let x = (first.maxX + second.minX) / 2
                return DiagramPath(start: CGPoint(x: x, y: min(first.minY, second.minY)), segments: [.line(to: CGPoint(x: x, y: max(first.maxY, second.maxY)))])
            }
        }
        let downY = regionFrames.sorted { first, second in first.minY < second.minY }
        guard zip(downY, downY.dropFirst()).allSatisfy({ first, second in first.maxY <= second.minY }) else { return [] }
        return zip(downY, downY.dropFirst()).map { first, second in
            let y = (first.maxY + second.minY) / 2
            return DiagramPath(start: CGPoint(x: min(first.minX, second.minX), y: y), segments: [.line(to: CGPoint(x: max(first.maxX, second.maxX), y: y))])
        }
    }
}
