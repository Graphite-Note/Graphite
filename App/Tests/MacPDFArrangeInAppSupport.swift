/**
 * File: MacPDFArrangeInAppSupport.swift
 * -------------------------------------
 * Layer: Tests
 * Description: What MacPDFArrangeMenusInAppHostedTests checks against: the layers of its test page, the order the six
 *              Arrange commands should leave them in, the points where objects overlap and the colour each should show;
 *              and the app's own window it runs in.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import PDFKit
import GraphiteCore
@testable import GraphiteApple
@testable import GraphiteUI

/// A layer of the test page, each in a colour of its own so the screen tells which is on top.
enum ArrangedLayer: String, CaseIterable {
    case redPicture = "red picture", bluePicture = "blue picture", ink, textBox = "text box", shape

    var colour: ScreenColour {
        switch self {
        case .redPicture: .red
        case .bluePicture: .blue
        case .ink: .green
        case .textBox: .yellow
        case .shape: .purple
        }
    }

    /// The layers in a page's annotation order, the lowest first; the ink's strokes, which follow one another, are one.
    static func layers(of page: PDFPage, pictureNames: [String: ArrangedLayer]) -> [ArrangedLayer] {
        var layers: [ArrangedLayer] = []
        for annotation in page.annotations {
            guard let layer = layer(of: annotation, pictureNames: pictureNames), !(layer == .ink && layers.last == .ink) else { continue }
            layers.append(layer)
        }
        return layers
    }

    /// The layer an annotation draws, read from the file's own keys; nil for anything else on the page.
    static func layer(of annotation: PDFAnnotation, pictureNames: [String: ArrangedLayer]) -> ArrangedLayer? {
        if annotation.value(forAnnotationKey: PDFPageManager.groupKey) != nil { return .ink }
        if PDFPageManager.isPicture(annotation) { return annotation.persistentName.flatMap { name in pictureNames[name] } }
        if annotation.type == PDFTextBox.annotationTypeName { return .textBox }
        return annotation.type == PDFShapeKind.rectangle.annotationTypeName ? .shape : nil
    }
}

/// The colours the test page is drawn in, and the nearest of them to a colour read from the screen.
enum ScreenColour: String, CaseIterable {
    case white, red, blue, green, yellow, purple

    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .white: (1, 1, 1)
        case .red: (1, 0, 0)
        case .blue: (0, 0, 1)
        case .green: (0, 0.6, 0)
        case .yellow: (1, 1, 0)
        case .purple: (0.55, 0.1, 0.75)
        }
    }

    var textColor: PDFTextColor { PDFTextColor(red: components.red, green: components.green, blue: components.blue) }

    var nsColor: NSColor { NSColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: 1) }

    /// The nearest colour, and how far it is (0 to √3), or nil for a colour that has no sRGB form.
    static func nearest(to color: NSColor) -> (colour: ScreenColour, distance: Double)? {
        guard let sRGB = color.usingColorSpace(.sRGB) else { return nil }
        return allCases.map { candidate -> (colour: ScreenColour, distance: Double) in
            let (red, green, blue) = candidate.components
            let squared = (sRGB.redComponent - red) * (sRGB.redComponent - red) + (sRGB.greenComponent - green) * (sRGB.greenComponent - green)
                + (sRGB.blueComponent - blue) * (sRGB.blueComponent - blue)
            return (colour: candidate, distance: squared.squareRoot())
        }.min { left, right in left.distance < right.distance }
    }
}

/// One of the six items of Tools › Arrange: the selected object's four and the page's ink's two; an object's right-click
/// menu has the first four.
struct ArrangeCommand: Hashable, CustomStringConvertible {
    let arrangement: PDFArrangement
    let movesInk: Bool

    /// Its title in Tools › Arrange, and the name of its step in Undo.
    var title: String { movesInk ? arrangement.inkTitle : arrangement.title }
    var description: String { title }

    /// Its title in an object's right-click menu, which names the object ("Bring Item to Front") and has no ink items
    /// (Docs/PDF-annotation-todo.md, section 8).
    func menuTitle(naming objects: PDFArrangement.Objects) -> String {
        movesInk ? arrangement.inkTitle : arrangement.title(of: objects)
    }

    /// The selected object's four.
    static let objectCommands: [ArrangeCommand] = PDFArrangement.menuArrangements.map { arrangement in ArrangeCommand(arrangement: arrangement, movesInk: false) }
    /// The page's ink's two.
    static let inkCommands: [ArrangeCommand] = PDFArrangement.inkMenuArrangements.map { arrangement in ArrangeCommand(arrangement: arrangement, movesInk: true) }
    static let all: [ArrangeCommand] = objectCommands + inkCommands
}

/// Where an object is among the page's objects, for the dimmed items.
enum PlaceAmongObjects: String { case top, middle, bottom }

/// The order the page's layers should be in, worked out here from the rules the menus promise (Docs/PDF-annotation-todo.md,
/// section 2), not from the app's own `PDFStackingOrder`: Bring Forward passes the next object up and Send Backward the
/// next one down, Bring to Front goes right over the topmost other object and Send to Back right under the lowest; an
/// object passes the ink only on its way past another object; the ink goes over or under every object.
struct ExpectedStacking: Equatable {
    var layers: [ArrangedLayer]

    /// The layers once `command` is chosen with `selected` selected, or nil when it would move nothing (a dimmed item).
    func applying(_ command: ArrangeCommand, to selected: ArrangedLayer) -> ExpectedStacking? {
        let moved = command.movesInk ? .ink : selected
        guard let formerIndex = layers.firstIndex(of: moved) else { return nil }
        var others = layers
        others.remove(at: formerIndex)
        let newIndex = command.movesInk ? inkIndex(command.arrangement, amongTheOthers: others)
            : objectIndex(of: moved, command.arrangement, amongTheOthers: others)
        guard let newIndex else { return nil }
        others.insert(moved, at: newIndex)
        return others == layers ? nil : ExpectedStacking(layers: others)
    }

    private func inkIndex(_ arrangement: PDFArrangement, amongTheOthers others: [ArrangedLayer]) -> Int? {
        switch arrangement {
        case .bringToFront: others.count
        case .sendToBack: 0
        case .bringForward, .sendBackward, .position: nil
        }
    }

    private func objectIndex(of moved: ArrangedLayer, _ arrangement: PDFArrangement, amongTheOthers others: [ArrangedLayer]) -> Int? {
        let objects = layers.filter { layer in layer != .ink }
        guard let place = objects.firstIndex(of: moved) else { return nil }
        let goesUp = arrangement == .bringToFront || arrangement == .bringForward
        let passed: ArrangedLayer? = switch arrangement {
        case .bringToFront: place < objects.count - 1 ? objects.last : nil
        case .bringForward: place < objects.count - 1 ? objects[place + 1] : nil
        case .sendBackward: place > 0 ? objects[place - 1] : nil
        case .sendToBack: place > 0 ? objects.first : nil
        case .position: nil
        }
        return passed.flatMap { passedLayer in others.firstIndex(of: passedLayer) }.map { passedIndex in goesUp ? passedIndex + 1 : passedIndex }
    }

    /// The items an Arrange menu should leave enabled for `selected`.
    func possibleCommands(for selected: ArrangedLayer) -> Set<ArrangeCommand> {
        Set(ArrangeCommand.all.filter { command in applying(command, to: selected) != nil })
    }

    func place(of layer: ArrangedLayer) -> PlaceAmongObjects {
        let objects = layers.filter { candidate in candidate != .ink }
        if objects.last == layer { return .top }
        return objects.first == layer ? .bottom : .middle
    }

    /// The colour a point covered by `covering` should show: its topmost layer's, white where nothing covers it.
    func colour(where covering: Set<ArrangedLayer>) -> ScreenColour {
        layers.last { layer in covering.contains(layer) }?.colour ?? .white
    }
}

/// A point of the page where two or more layers overlap, away from every edge, and the layers that cover it.
struct OverlapSample {
    let pagePoint: CGPoint
    let covering: Set<ArrangedLayer>

    /// Points on a grid over the layers' rectangles (on the ink's rows, so a point on the ink is on a stroke's middle),
    /// kept where two or more layers cover them and no edge, frame or handle is within `margin` points.
    static func overlaps(of rectangles: [ArrangedLayer: CGRect], inkRows: [CGFloat], margin: CGFloat = 8) -> [OverlapSample] {
        let union = rectangles.values.reduce(CGRect.null) { union, rectangle in union.union(rectangle) }
        let rowStep = inkRows.count > 1 ? abs(inkRows[1] - inkRows[0]) : 4
        let lowestRow = inkRows.min() ?? union.minY
        let firstY = lowestRow - ((lowestRow - union.minY) / rowStep).rounded(.down) * rowStep
        var samples: [OverlapSample] = []
        for y in stride(from: firstY, through: union.maxY, by: rowStep) {
            for x in stride(from: union.minX, through: union.maxX, by: 6) {
                let point = CGPoint(x: x, y: y)
                let nearAnEdge = rectangles.values.contains { rectangle in
                    rectangle.insetBy(dx: -margin, dy: -margin).contains(point) && !rectangle.insetBy(dx: margin, dy: margin).contains(point)
                }
                let covering = Set(rectangles.filter { _, rectangle in rectangle.contains(point) }.keys)
                if !nearAnEdge, covering.count >= 2 { samples.append(OverlapSample(pagePoint: point, covering: covering)) }
            }
        }
        return samples
    }
}

/// A picture of the window's content, read point by point.
struct WindowPicture {
    let bitmap: NSBitmapImageRep

    init(pngData: Data) throws {
        bitmap = try XCTUnwrap(NSBitmapImageRep(data: pngData), "the window's picture reads back")
    }

    /// The colour at a point of the window (its coordinates, from the bottom left; the picture is a pixel a point).
    func colour(atWindowPoint point: CGPoint) -> NSColor? {
        let column = Int(point.x.rounded(.down)), row = bitmap.pixelsHigh - 1 - Int(point.y.rounded(.down))
        guard (0..<bitmap.pixelsWide).contains(column), (0..<bitmap.pixelsHigh).contains(row) else { return nil }
        return bitmap.colorAt(x: column, y: row)
    }
}

/// The app's own window, which SwiftUI's scene made at launch: the menu bar's commands read the focused values of such
/// windows only, not of a window a test makes (2026-11-17).
@MainActor
enum AppSceneWindow {
    /// The first window of the scene of workspaces, with no vault in a hosted launch.
    static func workspaceWindow() -> NSWindow? {
        NSApp.windows.first { window in window.contentView.map { view in "\(type(of: view))".contains("GraphiteWindowScene") } ?? false }
    }

    /// The window's workspace. SwiftUI keeps it in the window's view state and offers no way to it, so it is looked for
    /// among what the window's hosting view holds, by reflection (on 2026-11-17 after 237 objects, in a binding the root
    /// view hands a presentation). Only this test needs it, and it fails, rather than misleads, if SwiftUI keeps it elsewhere.
    static func workspace(of window: NSWindow) -> WorkspaceModel? {
        guard let contentView = window.contentView else { return nil }
        var search = ReflectedSearch()
        return search.firstWorkspace(in: contentView, depth: 0)
    }

    private struct ReflectedSearch {
        var visitedObjects: Set<ObjectIdentifier> = []

        mutating func firstWorkspace(in value: Any, depth: Int) -> WorkspaceModel? {
            if let workspace = value as? WorkspaceModel { return workspace }
            guard depth < 18, visitedObjects.count < 100_000 else { return nil }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .class, !visitedObjects.insert(ObjectIdentifier(value as AnyObject)).inserted { return nil }
            var level: Mirror? = mirror
            while let current = level {
                for child in current.children {
                    if let workspace = firstWorkspace(in: child.value, depth: depth + 1) { return workspace }
                }
                level = current.superclassMirror
            }
            return nil
        }
    }
}

/// The test page: a blank letter page written as a PDF, and solid pictures to place on it.
enum ArrangeTestPage {
    static let mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func writeBlankPDF(to location: URL) throws {
        var box = mediaBox
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &box, nil), "a PDF context")
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
    }

    /// A PNG of one solid colour, 120 by 80 pixels.
    static func solidPNG(_ colour: ScreenColour) throws -> Data {
        let representation = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 80, bitsPerSample: 8, samplesPerPixel: 4,
                                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        colour.nsColor.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    /// The ink's rows, in the page's space: a bold stroke back and forth every 4 points, which fills the band it covers.
    static let inkRows: [CGFloat] = Array(stride(from: CGFloat(600), through: 520, by: -4))
    static let inkLeftEdge: CGFloat = 180, inkRightEdge: CGFloat = 400

    /// The stroke's points, row after row, every 20 points along a row.
    static var inkStrokePoints: [CGPoint] {
        inkRows.enumerated().flatMap { rowIndex, y in
            let xs = Array(stride(from: inkLeftEdge, through: inkRightEdge, by: 20))
            return (rowIndex.isMultiple(of: 2) ? xs : xs.reversed()).map { x in CGPoint(x: x, y: y) }
        }
    }

    /// The band the stroke covers: its rows and half the bold width (5 points) beyond the first and last.
    static var inkBand: CGRect {
        CGRect(x: inkLeftEdge, y: (inkRows.min() ?? 0) - 2.5, width: inkRightEdge - inkLeftEdge, height: (inkRows.max() ?? 0) - (inkRows.min() ?? 0) + 5)
    }
}
#endif
