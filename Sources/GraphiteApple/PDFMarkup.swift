/**
 * File: PDFMarkup.swift
 * ---------------------
 * Layer: Apple
 * Description: Text markup (highlight, underline, strike-out) as standard PDF annotations.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 16/11/2026
 */
import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Text markup Graphite writes as standard `/Highlight`, `/Underline`, and `/StrikeOut`
/// annotations, the same kinds Preview and other readers create and display.
public enum PDFMarkupKind: String, Sendable, CaseIterable, Identifiable {
    case highlight, underline, strikeOut
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeOut: "Strikethrough"
        }
    }

    public var annotationSubtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        }
    }

    /// The `/Subtype` name, as `PDFAnnotation.type` reports it.
    public var annotationTypeName: String {
        switch self {
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeOut: "StrikeOut"
        }
    }

    /// The kind for an annotation read from a PDF, or nil for other annotation types.
    public init?(annotationType: String?) {
        guard let kind = Self.allCases.first(where: { kind in kind.annotationTypeName == annotationType }) else { return nil }
        self = kind
    }
}

/// The colour of a highlight, underline or strikethrough: any colour, kept as eight bits a
/// component in device RGB, which is how PDFKit writes `/C`. Eight bits make a colour read
/// back from a file equal to the one written, and give the hex text it is kept under.
/// Highlights are opaque and readers draw them with multiply blending, so light tints keep
/// the text underneath readable.
public struct PDFMarkupColor: Hashable, Sendable, Identifiable {
    public let redLevel: UInt8
    public let greenLevel: UInt8
    public let blueLevel: UInt8

    private static let maximumLevel = 255.0

    public init(redLevel: UInt8, greenLevel: UInt8, blueLevel: UInt8) {
        self.redLevel = redLevel
        self.greenLevel = greenLevel
        self.blueLevel = blueLevel
    }

    /// The colour nearest to components between 0 and 1; others are taken to the nearest end.
    public init(red: Double, green: Double, blue: Double) {
        func level(_ component: Double) -> UInt8 {
            guard component.isFinite else { return 0 }
            return UInt8((min(max(component, 0), 1) * Self.maximumLevel).rounded())
        }
        self.init(redLevel: level(red), greenLevel: level(green), blueLevel: level(blue))
    }

    public static let yellow = PDFMarkupColor(red: 1.0, green: 0.91, blue: 0.26)
    public static let green = PDFMarkupColor(red: 0.56, green: 0.89, blue: 0.47)
    public static let blue = PDFMarkupColor(red: 0.52, green: 0.78, blue: 1.0)
    public static let pink = PDFMarkupColor(red: 1.0, green: 0.62, blue: 0.79)
    public static let purple = PDFMarkupColor(red: 0.78, green: 0.64, blue: 1.0)
    public static let red = PDFMarkupColor(red: 0.89, green: 0.18, blue: 0.18)

    /// The colours highlights start with, before any is saved or removed (`PDFTextMarkColors`).
    public static let highlightColors: [PDFMarkupColor] = [.yellow, .green, .blue, .pink, .purple]
    /// Graphite's named colours, in their order, with their names.
    private static let namedColors: [(color: PDFMarkupColor, name: String)] = [
        (.yellow, "yellow"), (.green, "green"), (.blue, "blue"), (.pink, "pink"), (.purple, "purple"), (.red, "red"),
    ]

    public var red: Double { Double(redLevel) / Self.maximumLevel }
    public var green: Double { Double(greenLevel) / Self.maximumLevel }
    public var blue: Double { Double(blueLevel) / Self.maximumLevel }

    /// The name of one of Graphite's colours, such as `yellow`; nil for any other colour.
    public var name: String? { Self.namedColors.first { named in named.color == self }?.name }

    /// The colour's name for a menu: "Yellow", or its hex text, "#FF8000".
    public var title: String { name?.capitalized ?? hex }

    /// `#RRGGBB`, upper case.
    public var hex: String { String(format: "#%02X%02X%02X", redLevel, greenLevel, blueLevel) }

    public var id: String { hex }

    /// The colour of `#RRGGBB` (the `#` may be left out), or nil for other text.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(redLevel: UInt8(value >> 16 & 0xFF), greenLevel: UInt8(value >> 8 & 0xFF), blueLevel: UInt8(value & 0xFF))
    }

    /// The colour kept under a name: one of Graphite's names, such as `yellow`, or hex text.
    public init?(storedName: String) {
        if let named = Self.namedColors.first(where: { named in named.name == storedName }) {
            self = named.color
            return
        }
        self.init(hex: storedName)
    }

    /// The name the colour is kept under: Graphite's name for one of its colours, so a
    /// style kept by an older build reads the same, and hex text for any other.
    public var storedName: String { name ?? hex }

    #if canImport(UIKit)
    public var platformColor: UIColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, 1].map { component in CGFloat(component) })
            .map { color in UIColor(cgColor: color) } ?? UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    /// The colour a colour picker chose, as PDFKit writes it.
    public init(platformColor: UIColor) {
        self.init(cgColor: platformColor.cgColor)
    }
    #else
    public var platformColor: NSColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, 1].map { component in CGFloat(component) })
            .flatMap { color in NSColor(cgColor: color) } ?? NSColor(deviceRed: red, green: green, blue: blue, alpha: 1)
    }

    /// The colour a colour panel chose, as PDFKit writes it.
    public init(platformColor: NSColor) {
        self.init(cgColor: platformColor.cgColor)
    }
    #endif

    /// A colour in any colour space, in device RGB.
    public init(cgColor: CGColor) {
        let components = PDFMarkupDetails.deviceRGBComponents(of: cgColor)
        self.init(red: components[0], green: components[1], blue: components[2])
    }
}

/// What a reader shows of markup read from a file beyond its kind and lines: its exact
/// color, its note (`/Contents`) and its author (`/T`).
public struct PDFMarkupDetails: Sendable, Equatable {
    /// Components in device RGB, which PDFKit writes to `/C` unchanged.
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public let note: String?
    public let author: String?

    public init(red: Double, green: Double, blue: Double, alpha: Double, note: String?, author: String?) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        self.note = note
        self.author = author
    }

    init(annotation: PDFAnnotation) {
        let components = Self.deviceRGBComponents(of: annotation.color.cgColor)
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3],
                  note: annotation.contents, author: annotation.userName)
    }

    /// Red, green, blue and alpha of a colour. Gray, CMYK and other colours are converted;
    /// RGB components are kept exactly. Yellow, the usual highlight colour, when the colour
    /// cannot be read at all.
    static func deviceRGBComponents(of color: CGColor) -> [Double] {
        var components = color.components ?? []
        if color.colorSpace?.model != .rgb || components.count != 4 {
            components = CGColorSpace(name: CGColorSpace.sRGB)
                .flatMap { sRGB in color.converted(to: sRGB, intent: .defaultIntent, options: nil) }?.components ?? []
        }
        if components.count != 4 { components = [1, 1, 0, 1] }
        return components.map { component in Double(component) }
    }

    /// The colour as Graphite's colours are kept, eight bits a component.
    public var color: PDFMarkupColor { PDFMarkupColor(red: red, green: green, blue: blue) }

    /// What a mark joining `marks` keeps of them: their notes, one after another, with the
    /// author of the first that has one, in `color`. Nil when none has a note, so the joined
    /// mark is the current user's, as any new mark is.
    public static func joiningNotes(of marks: [PDFMarkup], in color: PDFMarkupColor) -> PDFMarkupDetails? {
        let annotatedMarks = marks.compactMap { mark in mark.originalDetails }.filter { details in !(details.note ?? "").isEmpty }
        guard let firstAnnotated = annotatedMarks.first else { return nil }
        return PDFMarkupDetails(red: color.red, green: color.green, blue: color.blue, alpha: 1,
                                note: annotatedMarks.compactMap(\.note).joined(separator: "\n\n"), author: firstAnnotated.author)
    }

    #if canImport(UIKit)
    var platformColor: UIColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha].map { component in CGFloat(component) })
            .map { color in UIColor(cgColor: color) } ?? UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    #else
    var platformColor: NSColor {
        CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [red, green, blue, alpha].map { component in CGFloat(component) })
            .flatMap { color in NSColor(cgColor: color) } ?? NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
    #endif
}

/// One markup annotation to add: the rectangles of the selected text lines on one page,
/// in page space. Each line becomes one quadrilateral of the same annotation, as in Preview.
public struct PDFMarkup: Sendable, Equatable {
    /// Stored as the standard `/NM` annotation name so the markup can be found again.
    public let name: String
    public let kind: PDFMarkupKind
    public let color: PDFMarkupColor
    public let lineBounds: [CGRect]
    /// The exact color, note and author of markup read from a file, written back instead
    /// of `color` and the current user. Undoing the removal of another application's
    /// markup then restores it as it was. Nil for markup Graphite creates.
    public let originalDetails: PDFMarkupDetails?

    public init(name: String = UUID().uuidString, kind: PDFMarkupKind, color: PDFMarkupColor, lineBounds: [CGRect], originalDetails: PDFMarkupDetails? = nil) {
        self.name = name
        self.kind = kind
        self.color = color
        self.lineBounds = lineBounds.filter { lineRectangle in
            !lineRectangle.isNull && lineRectangle.width > 0 && lineRectangle.height > 0
                && [lineRectangle.minX, lineRectangle.minY, lineRectangle.width, lineRectangle.height].allSatisfy(\.isFinite)
        }
        self.originalDetails = originalDetails
    }

    /// Reads a markup annotation back, for example to restore it when a removal is undone.
    /// Annotations without quadrilaterals are treated as one line covering their bounds.
    public init?(annotation: PDFAnnotation) {
        guard let kind = PDFMarkupKind(annotationType: annotation.type) else { return nil }
        let details = PDFMarkupDetails(annotation: annotation)
        self.init(name: annotation.persistentName ?? UUID().uuidString,
                  kind: kind, color: details.color,
                  lineBounds: Self.lineRectangles(of: annotation), originalDetails: details)
    }

    /// The page-space rectangle of each quadrilateral of a markup annotation, or its
    /// bounds when it has none.
    public static func lineRectangles(of annotation: PDFAnnotation) -> [CGRect] {
        let origin = annotation.bounds.origin
        let corners = (annotation.quadrilateralPoints ?? []).map { value in
            let corner = PDFMarkup.point(from: value)
            return CGPoint(x: corner.x + origin.x, y: corner.y + origin.y)
        }
        var lines: [CGRect] = []
        var cornerIndex = 0
        while cornerIndex + 3 < corners.count {
            let lineCorners = corners[cornerIndex..<(cornerIndex + 4)]
            let horizontalPositions = lineCorners.map(\.x), verticalPositions = lineCorners.map(\.y)
            if let minimumX = horizontalPositions.min(), let maximumX = horizontalPositions.max(),
               let minimumY = verticalPositions.min(), let maximumY = verticalPositions.max() {
                lines.append(CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: maximumY - minimumY))
            }
            cornerIndex += 4
        }
        return lines.isEmpty ? [annotation.bounds] : lines
    }

    /// Whether the mark is drawn in `color`, to eight bits a component.
    public func hasColor(_ color: PDFMarkupColor) -> Bool { self.color == color }

    public var bounds: CGRect {
        lineBounds.reduce(CGRect.null) { unionSoFar, lineRectangle in unionSoFar.union(lineRectangle) }
    }

    static func point(from value: NSValue) -> CGPoint {
        #if canImport(UIKit)
        value.cgPointValue
        #else
        value.pointValue
        #endif
    }

    /// The annotation for this markup on `page`, whose text decides which way each line runs. A markup
    /// made again from one that was in the file keeps that one's author; a new one gets `authorName`.
    func makeAnnotation(on page: PDFPage, authorName: String?) throws -> PDFAnnotation {
        let markupBounds = bounds
        guard !lineBounds.isEmpty, !markupBounds.isNull else { throw GraphiteError.invalidFile("Select some PDF text first.") }
        let annotation = PDFAnnotation(bounds: markupBounds, forType: kind.annotationSubtype, withProperties: nil)
        // QuadPoints order per line: upper left, upper right, lower left, lower right as the
        // text reads, relative to the annotation origin (PDFKit's convention; it writes
        // page space). Readers draw an underline along the lower edge.
        annotation.quadrilateralPoints = lineBounds.flatMap { lineRectangle in
            Self.quadrilateralCorners(of: lineRectangle, direction: page.markupLineDirection(of: lineRectangle)).map { corner in
                PDFMarkup.pointValue(CGPoint(x: corner.x - markupBounds.minX, y: corner.y - markupBounds.minY))
            }
        }
        if let originalDetails {
            annotation.color = originalDetails.platformColor
            annotation.contents = originalDetails.note
            PDFAnnotationAuthor.write(originalDetails.author, on: annotation)
        } else {
            annotation.color = color.platformColor
            PDFAnnotationAuthor.write(authorName, on: annotation)
        }
        annotation.shouldPrint = true
        annotation.setPersistentName(name)
        return annotation
    }

    static func quadrilateralCorners(of lineRectangle: CGRect, direction: PDFMarkupLineDirection) -> [CGPoint] {
        let minimumX = lineRectangle.minX, maximumX = lineRectangle.maxX, minimumY = lineRectangle.minY, maximumY = lineRectangle.maxY
        switch direction {
        case .leftToRight:
            return [CGPoint(x: minimumX, y: maximumY), CGPoint(x: maximumX, y: maximumY), CGPoint(x: minimumX, y: minimumY), CGPoint(x: maximumX, y: minimumY)]
        case .bottomToTop:
            // Turned a quarter counterclockwise: the tops of the glyphs face left.
            return [CGPoint(x: minimumX, y: minimumY), CGPoint(x: minimumX, y: maximumY), CGPoint(x: maximumX, y: minimumY), CGPoint(x: maximumX, y: maximumY)]
        case .topToBottom:
            // Turned a quarter clockwise: the tops of the glyphs face right.
            return [CGPoint(x: maximumX, y: maximumY), CGPoint(x: maximumX, y: minimumY), CGPoint(x: minimumX, y: maximumY), CGPoint(x: minimumX, y: minimumY)]
        }
    }

    static func pointValue(_ point: CGPoint) -> NSValue {
        #if canImport(UIKit)
        NSValue(cgPoint: point)
        #else
        NSValue(point: point)
        #endif
    }
}

/// Finds one annotation again when the edit list is replayed on the baseline snapshot.
/// Graphite's annotations carry a unique name (`persistentName`); annotations from other
/// applications may not, so the subtype and rectangle identify them instead.
public struct PDFAnnotationReference: Sendable, Equatable {
    public let pageIndex: Int
    public let name: String?
    public let annotationType: String
    public let bounds: CGRect

    public init(pageIndex: Int, name: String?, annotationType: String, bounds: CGRect) {
        self.pageIndex = pageIndex
        self.name = name
        self.annotationType = annotationType
        self.bounds = bounds
    }

    public init(annotation: PDFAnnotation, pageIndex: Int) {
        self.init(pageIndex: pageIndex, name: annotation.persistentName, annotationType: annotation.type ?? "", bounds: annotation.bounds)
    }

    /// Rectangles written to a file and read back can differ in the last digits.
    private static let boundsTolerance = 0.01

    public func matches(_ annotation: PDFAnnotation) -> Bool {
        guard annotation.type == annotationType else { return false }
        if let name { return annotation.persistentName == name }
        return hasSameBounds(as: annotation)
    }

    /// Whether `annotation` is this named reference's annotation after its name was lost:
    /// an unnamed annotation of the same subtype and rectangle. Builds before the name of
    /// another application's markup was kept wrote files whose page changes dropped `/NM`
    /// while the displayed document still reads it.
    public func matchesAfterNameWasLost(_ annotation: PDFAnnotation) -> Bool {
        guard name != nil, !bounds.isNull, annotation.type == annotationType, annotation.persistentName == nil else { return false }
        return hasSameBounds(as: annotation)
    }

    private func hasSameBounds(as annotation: PDFAnnotation) -> Bool {
        let candidateBounds = annotation.bounds
        return abs(candidateBounds.minX - bounds.minX) < Self.boundsTolerance && abs(candidateBounds.minY - bounds.minY) < Self.boundsTolerance
            && abs(candidateBounds.width - bounds.width) < Self.boundsTolerance && abs(candidateBounds.height - bounds.height) < Self.boundsTolerance
    }
}

/// The way a line of text runs on the page. Text drawn turned by a quarter, such as a
/// vertical label or a landscape table on a portrait page, selects as a tall rectangle
/// whose baseline is one of its long sides.
public enum PDFMarkupLineDirection: Sendable, Equatable {
    case leftToRight, bottomToTop, topToBottom
}

public extension PDFPage {
    /// Room around each marked line, in points, so a tap on its edge still finds it.
    private static let markupHitTolerance: CGFloat = 2

    /// The text markup annotation under a point in page space, topmost first. Only the
    /// marked lines count, not the unmarked text inside a multi-line markup's bounds.
    func markupAnnotation(at pagePoint: CGPoint) -> PDFAnnotation? {
        annotations.reversed().first { annotation in
            guard PDFMarkupKind(annotationType: annotation.type) != nil,
                  annotation.bounds.insetBy(dx: -Self.markupHitTolerance, dy: -Self.markupHitTolerance).contains(pagePoint) else { return false }
            return PDFMarkup.lineRectangles(of: annotation).contains { lineRectangle in
                lineRectangle.insetBy(dx: -Self.markupHitTolerance, dy: -Self.markupHitTolerance).contains(pagePoint)
            }
        }
    }

    /// The direction of the text inside a selected line's rectangle. Only a rectangle
    /// taller than wide whose characters advance vertically counts as turned, so upright
    /// text in any script, including right-to-left scripts, keeps its lower edge.
    func markupLineDirection(of lineRectangle: CGRect) -> PDFMarkupLineDirection {
        guard lineRectangle.height > lineRectangle.width, let lineSelection = selection(for: lineRectangle) else { return .leftToRight }
        let rangeCount = lineSelection.numberOfTextRanges(on: self)
        guard rangeCount > 0 else { return .leftToRight }
        let firstRange = lineSelection.range(at: 0, on: self), lastRange = lineSelection.range(at: rangeCount - 1, on: self)
        guard firstRange.location != NSNotFound, lastRange.location != NSNotFound, lastRange.length > 0,
              NSMaxRange(lastRange) - 1 > firstRange.location,
              let firstCharacter = selection(for: NSRange(location: firstRange.location, length: 1))?.bounds(for: self),
              let lastCharacter = selection(for: NSRange(location: NSMaxRange(lastRange) - 1, length: 1))?.bounds(for: self),
              !firstCharacter.isEmpty, !lastCharacter.isEmpty else { return .leftToRight }
        let horizontalAdvance = lastCharacter.midX - firstCharacter.midX, verticalAdvance = lastCharacter.midY - firstCharacter.midY
        guard abs(verticalAdvance) > abs(horizontalAdvance) else { return .leftToRight }
        return verticalAdvance > 0 ? .bottomToTop : .topToBottom
    }
}

public extension PDFSelection {
    /// The selected text as markup lines per page index, in page space.
    func markupLinesByPage(in document: PDFDocument) -> [(pageIndex: Int, lineBounds: [CGRect])] {
        var linesByPage: [Int: [CGRect]] = [:]
        for lineSelection in selectionsByLine() {
            for page in lineSelection.pages {
                let lineRectangle = lineSelection.bounds(for: page)
                guard !lineRectangle.isNull, lineRectangle.width > 0, lineRectangle.height > 0 else { continue }
                linesByPage[document.index(for: page), default: []].append(lineRectangle)
            }
        }
        return linesByPage.keys.sorted().compactMap { pageIndex in
            linesByPage[pageIndex].map { lineBounds in (pageIndex: pageIndex, lineBounds: lineBounds) }
        }
    }
}
