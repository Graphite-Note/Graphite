/**
 * File: DenseHandwritingNotebook.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A notebook whose pages are written as densely as a formula sheet: thousands of small handwritten strokes a
 *              page, in Graphite's own ink, made in the test so no person's note is needed to measure such a page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import CoreGraphics
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteApple

/// Pages written as densely as the formula sheet imported from Goodnotes on 2026-11-12 (5,159 and 6,145 strokes on two
/// A3 landscape pages, about 20 points and 14 points across a stroke): rows of small letter-like strokes, a few long
/// rules between them, made from a fixed seed so every run writes the same page. The strokes are PencilKit pen strokes
/// whose pressure varies along them, written as Graphite writes a page's ink: one `/Ink` annotation a stroke, with its
/// outline as appearance, `/NM` name and the page's re-editing record.
public enum DenseHandwritingNotebook {
    /// The formula sheet's page: A3 landscape, in points.
    public static let pageSize = CGSize(width: 1_190.55, height: 841.89)
    /// The strokes of the formula sheet's fuller page.
    public static let formulaSheetStrokeCount = 6_000

    /// `strokeCount` strokes over a page of `pageSize`, in the page overlay's points from its top-left corner.
    public static func drawing(strokeCount: Int, pageSize: CGSize = pageSize, seed: UInt64 = 1) -> PKDrawing {
        var generator = SeededGenerator(seed: seed)
        let margin = 24.0
        let lineHeight = 15.0
        let lineCount = max(1, Int((pageSize.height - 2 * margin) / lineHeight))
        let lettersPerLine = max(1, (strokeCount + lineCount - 1) / lineCount)
        let letterAdvance = (pageSize.width - 2 * margin) / Double(lettersPerLine)
        var strokes: [PKStroke] = []
        strokes.reserveCapacity(strokeCount)
        for strokeIndex in 0..<strokeCount {
            let lineIndex = strokeIndex / lettersPerLine
            let letterIndex = strokeIndex % lettersPerLine
            let baseline = CGPoint(x: margin + Double(letterIndex) * letterAdvance, y: margin + Double(lineIndex % lineCount) * lineHeight + lineHeight * 0.8)
            // One stroke in sixty is a rule or a fraction bar across part of the line, as a formula sheet has.
            let isRule = strokeIndex % 60 == 59
            strokes.append(isRule ? rule(from: baseline, length: letterAdvance * 12, generator: &generator)
                                  : letter(at: baseline, size: 6 + generator.fraction() * 8, generator: &generator, creationIndex: strokeIndex))
        }
        return PKDrawing(strokes: strokes)
    }

    /// A PDF of `pageCount` such pages, each with `strokesPerPage` strokes, written to `destination` as Graphite writes a
    /// notebook's ink. Returns the seconds the ink took to be made into annotations and the seconds PDFKit took to write.
    @discardableResult
    public static func write(pageCount: Int, strokesPerPage: Int, to destination: URL, pageSize: CGSize = pageSize)
        throws -> (annotatingSeconds: Double, writingSeconds: Double) {
        guard let document = PDFDocument(data: try blankPages(count: pageCount, size: pageSize)) else {
            throw GraphiteError.invalidFile("The blank pages could not be read.")
        }
        PDFPageManager.prepareForWriting(document)
        let annotatingStart = Date()
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: pageSize)
            var tracker = PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page))
            let update = tracker.update(for: drawing(strokeCount: strokesPerPage, pageSize: pageSize, seed: UInt64(pageIndex + 1)),
                                        pageIndex: pageIndex, coordinates: coordinates)
            try PDFPageManager.apply(.updateInk(update), to: document, drawsInkOutlines: true)
        }
        let writingStart = Date()
        guard document.write(to: destination) else { throw GraphiteError.invalidFile("The dense notebook could not be written.") }
        return (writingStart.timeIntervalSince(annotatingStart), Date().timeIntervalSince(writingStart))
    }

    /// Empty pages of `size`, made by Core Graphics.
    public static func blankPages(count: Int, size: CGSize) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw GraphiteError.invalidFile("A PDF context could not be made.")
        }
        for _ in 0..<count {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    /// A small looping stroke like a handwritten letter, about `size` points high, its pressure rising and falling.
    private static func letter(at baseline: CGPoint, size: Double, generator: inout SeededGenerator, creationIndex: Int) -> PKStroke {
        let pointCount = 14 + Int(generator.fraction() * 12)
        let loops = 1 + generator.fraction() * 1.5
        let slant = 0.25 + generator.fraction() * 0.2
        let points = (0..<pointCount).map { pointIndex -> PKStrokePoint in
            let progress = Double(pointIndex) / Double(pointCount - 1)
            let angle = progress * loops * 2 * Double.pi
            let height = -size * (0.5 - 0.5 * cos(angle))
            let location = CGPoint(x: baseline.x + size * 0.35 * (progress + 0.5 * sin(angle)) - height * slant, y: baseline.y + height)
            let force = 0.6 + 0.6 * sin(progress * Double.pi)
            return PKStrokePoint(location: location, timeOffset: progress * 0.25, size: CGSize(width: 2.8 * force, height: 2.8 * force),
                                 opacity: 1, force: force, azimuth: 0, altitude: .pi / 2)
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(creationIndex)))
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    /// A slightly wavering straight line, like a rule drawn by hand under a formula.
    private static func rule(from start: CGPoint, length: Double, generator: inout SeededGenerator) -> PKStroke {
        let pointCount = 40
        let points = (0..<pointCount).map { pointIndex -> PKStrokePoint in
            let progress = Double(pointIndex) / Double(pointCount - 1)
            let location = CGPoint(x: start.x + progress * length, y: start.y + 2 + sin(progress * 9) * 0.6 + generator.fraction() * 0.3)
            return PKStrokePoint(location: location, timeOffset: progress * 0.6, size: CGSize(width: 2.4, height: 2.4),
                                 opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_000)))
    }
}

/// A fixed sequence of fractions from a seed (a linear congruential generator), so every run makes the same page.
private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    /// The next fraction, from 0 up to 1.
    mutating func fraction() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
