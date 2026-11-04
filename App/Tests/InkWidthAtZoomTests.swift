/**
 * File: InkWidthAtZoomTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: A pen keeps its width on the page at any zoom, as on paper: on a PDF page, whose canvas
 *              draws larger to stay sharp, and in a drawing, whose canvas the person zooms.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 04/11/2026
 */
#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// A pen keeps its width on the page at any zoom, as on paper: on a PDF page, whose canvas
/// draws larger to stay sharp, and in a drawing, whose canvas the person zooms.
@MainActor
final class InkWidthAtZoomTests: XCTestCase {
    private func selection(_ ink: PencilInk, width: Double) -> PencilToolSelection {
        var preset = InkPreset(ink: ink)
        preset.width = width
        return PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 18, isRulerActive: false)
    }

    /// The memory a page may take bounds the part of the page drawn, not the scale (HUNT-320,
    /// `PDFCanvasShownRegionTests`).
    func testAPagesDrawingScaleIsTheZoomWithinTheMemoryAPageMayTake() {
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 1.36), 1.36, accuracy: 0.001, "One pixel of ink for one of the screen")
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 3.3), 3.3, accuracy: 0.001, "Past the old cap of 3")
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 0.1), PDFCanvasShownRegion.minimumRenderingScale)
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 8), 8, accuracy: 0.001, "Past the old bound of about 4.2 on A4")
    }

    /// Choosing a broad tool used to lower the scale of every canvas, in Read mode too.
    func testABroadToolKeepsItsWidthAndLeavesThePageAsSharpAsTheZoomAllows() async throws {
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "WidthAtZoom")
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()
        canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: 2.8))
        pdfView.autoScales = false
        pdfView.scaleFactor = 3.2
        try await waitUntil("the page canvas draws at the zoom") { abs(canvas.zoomScale - 3.2) < 0.01 }

        canvas.takeTool(from: toolPicker, fixedTool: selection(.pencil, width: 16))
        XCTAssertEqual(canvas.zoomScale, 3.2, accuracy: 0.01, "The ink on the page stays as sharp")
        XCTAssertEqual(try XCTUnwrap(canvas.tool as? PKInkingTool).width, 16, accuracy: 0.01, "The tool is the width chosen")
        canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: 2.8))
        XCTAssertEqual(try XCTUnwrap(canvas.tool as? PKInkingTool).width, 2.8, accuracy: 0.01)
        XCTAssertEqual(canvas.drawingSize.width, try XCTUnwrap(canvas.page).bounds(for: .cropBox).width, accuracy: 0.5)
    }

    /// The palette's tool reaches a zoomed page's canvas as the bar's does, in the turn the
    /// palette's choice changes, and nothing puts the palette's unscaled tool there later.
    func testThePalettesToolIsTheBarsToolOnAZoomedPageInTheSameTurn() async throws {
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "PaletteAtZoom")
        defer { window.isHidden = true; window.rootViewController = nil }
        pdfView.autoScales = false
        pdfView.scaleFactor = 2.2
        try await waitUntil("the page canvas draws at the zoom") { abs(canvas.zoomScale - 2.2) < 0.01 }
        let toolPicker = try XCTUnwrap(pdfView.annotationCoordinator?.toolPicker)
        // The canvas follows the PDF's palette, as with the floating palette chosen in Settings.
        canvas.takeTool(from: toolPicker, fixedTool: nil)
        XCTAssertTrue(canvas.followsToolPicker)

        (toolPicker as any SelectedToolSetting).selectedTool = PKInkingTool(.monoline, color: .black, width: 2)
        let paletteTool = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(paletteTool.inkType, .monoline)
        XCTAssertEqual(paletteTool.width, 2, accuracy: 0.001, "2 points on the page at once, not one turn later")
        // The next turn of the main queue, where the canvas used to take the scaled tool.
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(try XCTUnwrap(canvas.tool as? PKInkingTool).width, 2, accuracy: 0.001, "It stays the palette's width")
        toolPicker.isRulerActive = true
        XCTAssertTrue(canvas.isRulerActive, "The palette's ruler still reaches the canvas")
        toolPicker.isRulerActive = false

        canvas.takeTool(from: toolPicker, fixedTool: selection(.monoline, width: 2))
        let barTool = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(barTool.inkType, paletteTool.inkType)
        XCTAssertEqual(barTool.width, paletteTool.width, accuracy: 0.001)
    }

    func testADrawingZoomedInWritesAsWideInTheDrawingAsAtItsFittedSize() throws {
        let canvas = InfiniteCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 1_000))
        canvas.canvasWidth = 400
        canvas.layoutIfNeeded()
        XCTAssertEqual(canvas.zoomScale, 2, accuracy: 0.001, "Fitted: 800 points of screen for 400 of drawing")
        canvas.takeTool(from: PKToolPicker(), fixedTool: selection(.monoline, width: 1.56))
        XCTAssertEqual(try XCTUnwrap(canvas.tool as? PKInkingTool).width, 1.56, accuracy: 0.001)

        canvas.zoomScale = 6
        canvas.layoutIfNeeded()
        XCTAssertEqual(try XCTUnwrap(canvas.tool as? PKInkingTool).width, 1.56, accuracy: 0.001, "The tool is 1.56 points of the drawing at any zoom")
    }

    // MARK: Measured strokes (INK-22)

    /// Same pen, same width on the page, at every zoom, through the real canvas: what PencilKit
    /// stored and what it draws are compared with the same stroke at the page's own size, and
    /// the saved file is read back. PencilKit stores a stroke at the tool's width whatever its
    /// canvas's zoom, so a tool scaled by the zoom landed up to 1.75 times too thick in this
    /// measure and 2.64 times on the simulator's screen.
    ///
    /// The touch moves as fast on the screen at every zoom, 240 points of the screen in 30 moves,
    /// as a person's hand does: the speed PencilKit's pen thickens with (see `linesShownOnScreen`).
    /// A pencil's grain varies from stroke to stroke, which `SynthesizedStrokes.renderedWidth`
    /// averages out.
    func testTheSamePenLandsEquallyWideOnThePageAtEveryZoomAndInTheSavedFile() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "MeasuredWidth")
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()
        pdfView.autoScales = false
        let inks: [(ink: PencilInk, width: Double, renderedTolerance: CGFloat)] = [(.pen, 2.8, 0.12), (.monoline, 2, 0.02), (.pencil, 2.4, 0.25)]
        for inkCase in inks {
            canvas.takeTool(from: toolPicker, fixedTool: selection(inkCase.ink, width: inkCase.width))
            var sizeAtPageSize: CGFloat?
            var renderedAtPageSize: CGFloat?
            for zoom: CGFloat in [1, 1.5, 2, 3] {
                pdfView.scaleFactor = zoom
                try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 350)
                try await waitUntil("the canvas draws at \(zoom)") { abs(canvas.zoomScale - zoom) < 0.02 }
                let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
                let line = SynthesizedStrokes.line(from: CGPoint(x: middle.x - 120, y: middle.y), to: CGPoint(x: middle.x + 120, y: middle.y))
                let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: line, in: window)
                let stroke = try XCTUnwrap(drawnStroke, "\(inkCase.ink) at \(zoom) drew nothing")
                let sizes = Array(stroke.path).map(\.size.width).sorted()
                let size = sizes[sizes.count / 2]
                let rendered = try XCTUnwrap(SynthesizedStrokes.renderedWidth(of: stroke))
                let label = "\(inkCase.ink) \(inkCase.width) at zoom \(zoom)"
                print("INK-WIDTH \(label): tool \((canvas.tool as? PKInkingTool)?.width ?? 0) size \(size) rendered \(rendered)")
                XCTAssertEqual(stroke.transform, .identity, label)
                if let sizeAtPageSize, let renderedAtPageSize {
                    XCTAssertEqual(size / sizeAtPageSize, 1, accuracy: 0.05, "Stored size, \(label)")
                    XCTAssertEqual(rendered / renderedAtPageSize, 1, accuracy: inkCase.renderedTolerance, "Drawn pixels, \(label)")
                } else {
                    sizeAtPageSize = size
                    renderedAtPageSize = rendered
                }
            }
        }
        // The file holds what the canvas showed.
        let shownStrokes = canvas.drawing.strokes
        let session = try XCTUnwrap(canvas.annotationCoordinator?.session)
        try await session.save()
        let reopened = try XCTUnwrap(PDFDocument(url: session.location))
        let group = try XCTUnwrap(PDFInkGroups.editableGroup(on: XCTUnwrap(reopened.page(at: 0))))
        let savedStrokes = try PKDrawing(data: group.record.drawingData).strokes
        XCTAssertEqual(savedStrokes.count, shownStrokes.count)
        for (saved, shown) in zip(savedStrokes, shownStrokes) {
            XCTAssertEqual(try XCTUnwrap(saved.path.first).size.width, try XCTUnwrap(shown.path.first).size.width, accuracy: 0.001)
        }
    }

    /// The same in a drawing, whose canvas the person zooms: at the fitted zoom, zoomed in, and
    /// on a phone, where a tool scaled below an ink's narrowest width came out thicker (HUNT-012).
    func testTheSamePenLandsEquallyWideInADrawingAtEveryZoom() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let canvas = InfiniteCanvasView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        window.addSubview(canvas)
        canvas.canvasWidth = 760
        canvas.drawingPolicy = .anyInput
        canvas.layoutIfNeeded()
        canvas.takeTool(from: PKToolPicker(), fixedTool: selection(.pencil, width: 2.4))
        var sizes: [CGFloat] = []
        for zoom in [canvas.zoomScale, 1, 2, 4] as [CGFloat] {
            canvas.zoomScale = zoom
            canvas.layoutIfNeeded()
            let middle = canvas.convert(CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY), to: window)
            let line = SynthesizedStrokes.line(from: CGPoint(x: middle.x - 100, y: middle.y), to: CGPoint(x: middle.x + 100, y: middle.y))
            let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: line, in: window)
            let stroke = try XCTUnwrap(drawnStroke, "Nothing drawn at zoom \(zoom)")
            sizes.append(try XCTUnwrap(stroke.path.first).size.width)
            print("INK-WIDTH drawing pencil 2.4 at zoom \(zoom): tool \((canvas.tool as? PKInkingTool)?.width ?? 0) size \(sizes.last ?? 0)")
        }
        for size in sizes { XCTAssertEqual(size, sizes[0], accuracy: 0.05) }
    }

    // MARK: Width on the screen at zoom 1, 2 and 3 (HUNT-004)

    /// What one line drawn at one zoom showed on the screen, in points of the page: while the
    /// touch was still down, once it had settled, and what PencilKit's stored stroke draws.
    private struct LineShownOnScreen {
        let label: String
        let zoom: CGFloat
        let pageRow: CGFloat
        let widthWhileWriting: CGFloat
        let settledWidth: CGFloat
        let storedStrokeWidth: CGFloat
    }

    /// The ink of a horizontal line crossing a band of the window's columns, in the screen's
    /// points: in each column the rows of ink, each counted by how much darker it is than the
    /// paper (the column's middle value), averaged over the band. The band's picture comes too.
    private func shownInkWidth(in window: UIWindow, around point: CGPoint, bandWidth: CGFloat, inkLevel: Double) throws -> (width: CGFloat, picture: UIImage) {
        let area = CGRect(x: point.x - bandWidth / 2, y: point.y - 30, width: bandWidth, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let picture = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let image = try XCTUnwrap(picture.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var inkPixelsPerColumn: [Double] = []
        for column in 0..<image.width {
            let levels = (0..<image.height).map { row in
                let offset = (row * image.width + column) * 4
                return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / 3
            }
            let paper = levels.sorted()[levels.count / 2]
            guard paper > inkLevel + 1 else { continue }
            inkPixelsPerColumn.append(levels.reduce(0) { total, level in total + min(max((paper - level) / (paper - inkLevel), 0), 1) })
        }
        let averagePixels = inkPixelsPerColumn.isEmpty ? 0 : inkPixelsPerColumn.reduce(0, +) / Double(inkPixelsPerColumn.count)
        return (CGFloat(averagePixels) / window.screen.scale, picture)
    }

    private func attach(_ picture: UIImage, named name: String) {
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Brings a row of the page into view, well below the top of the PDF's view, and returns
    /// the window's point of a point of the page on it.
    private func showPageRow(_ pageRow: CGFloat, of page: PDFPage, in pdfView: PDFView, window: UIWindow) async throws -> (CGPoint) -> CGPoint {
        let pageTop = page.bounds(for: .cropBox).maxY
        let lineY = pageTop - pageRow
        // PDFKit brings a rectangle in at the view's top: the line lands 200 points of the screen below it.
        let aboveTheLine = 200 / pdfView.scaleFactor
        pdfView.go(to: CGRect(x: 180, y: lineY - 20, width: 160, height: 20 + aboveTheLine), on: page)
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 350)
        return { pagePoint in pdfView.convert(pdfView.convert(pagePoint, from: page), to: window) }
    }

    /// Draws a pen line 120 points of the page long at each zoom, each on its own row of the
    /// page, through the real canvas, and measures it on the screen while the touch is down and
    /// once it has settled. Ends at zoom 1 with every line shown, to be measured again.
    private func linesShownOnScreen(_ ink: PencilInk, width: Double, firstRow: CGFloat,
                                    canvas: PDFPageCanvasView, pdfView: GraphitePDFDisplayView, window: UIWindow) async throws -> [LineShownOnScreen] {
        var preset = InkPreset(ink: ink)
        preset.width = width
        preset.colorHex = "#1c1c1e"
        let inkLevel = Double(0x1c)
        canvas.takeTool(from: PKToolPicker(), fixedTool: PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 18, isRulerActive: false))
        let page = try XCTUnwrap(canvas.page)
        var lines: [LineShownOnScreen] = []
        for (zoomIndex, zoom) in ([1, 2, 3] as [CGFloat]).enumerated() {
            let label = "\(ink) \(width) at zoom \(zoom)"
            let pageRow = firstRow + CGFloat(zoomIndex) * 90
            let lineY = page.bounds(for: .cropBox).maxY - pageRow
            pdfView.scaleFactor = zoom
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
            let windowPoint = try await showPageRow(pageRow, of: page, in: pdfView, window: window)
            try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
            XCTAssertEqual(canvas.zoomScale, zoom, accuracy: 0.02, "The page's canvas draws at the zoom, \(label)")
            let start = windowPoint(CGPoint(x: 200, y: lineY))
            let end = windowPoint(CGPoint(x: 320, y: lineY))
            let measuredPoint = windowPoint(CGPoint(x: 230, y: lineY))
            let visibleArea = pdfView.convert(pdfView.bounds.inset(by: pdfView.safeAreaInsets), to: window)
            XCTAssertTrue(visibleArea.contains(start) && visibleArea.contains(end), "The line is on screen, \(label)")
            let underTheLine = try XCTUnwrap(window.hitTest(measuredPoint, with: nil))
            XCTAssertTrue(underTheLine.isDescendant(of: pdfView), "Nothing covers the line, \(label): \(type(of: underTheLine))")
            // The band the first half of the line has crossed when the touch is halfway.
            let bandWidth = 30 * zoom
            var widthWhileWriting: CGFloat = 0
            // The hand moves as fast on the screen at every zoom, as a person's does: 4 points of the screen a move.
            // PencilKit's pen grows heavier with the speed of the touch on the screen, so the same 30 moves at every
            // zoom crossed the line 3 times as fast at zoom 3 and stored it 11% wider (2.50, 2.59 and 2.77 points of
            // the page on GitHub's iPad, 2026-11-04), where the monoline, which ignores speed, stayed 4.0 at every zoom.
            let moves = Int((30 * zoom).rounded())
            let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: start, to: end, steps: moves), in: window) {
                // PencilKit shows the stroke under way in its own time: on a busy runner the band was still blank
                // after 60 milliseconds at zoom 2 and 3. The touch stays down until two looks agree on its ink.
                var previousWidth: CGFloat = 0
                var shown: (width: CGFloat, picture: UIImage)?
                try await waitUntil("the stroke under way shows in the band, \(label)", timeoutSeconds: 5, pollingIntervalSeconds: 0.05) {
                    let look = try self.shownInkWidth(in: window, around: measuredPoint, bandWidth: bandWidth, inkLevel: inkLevel)
                    defer { previousWidth = look.width }
                    shown = look
                    return look.width > 0 && abs(look.width - previousWidth) <= look.width * 0.05
                }
                if let shown {
                    widthWhileWriting = shown.width / zoom
                    self.attach(shown.picture, named: "While writing, \(label)")
                }
            }
            let stroke = try XCTUnwrap(drawnStroke, "\(label) drew nothing")
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 500)
            let settled = try shownInkWidth(in: window, around: measuredPoint, bandWidth: bandWidth, inkLevel: inkLevel)
            attach(settled.picture, named: "Settled, \(label)")
            let storedStrokeWidth = try XCTUnwrap(SynthesizedStrokes.renderedWidth(of: stroke))
            let line = LineShownOnScreen(label: label, zoom: zoom, pageRow: pageRow, widthWhileWriting: widthWhileWriting,
                                         settledWidth: settled.width / zoom, storedStrokeWidth: storedStrokeWidth)
            print("INK-WIDTH on screen \(label): while writing \(line.widthWhileWriting) settled \(line.settledWidth) stored stroke \(storedStrokeWidth) points of the page, screen scale \(window.screen.scale)")
            lines.append(line)
        }
        pdfView.scaleFactor = 1
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        return lines
    }

    /// The page's canvas of a blank PDF, the PDF's view and its window, fingers drawing, for the
    /// on-screen measures. The caller restores the finger preference and hides the window.
    private func canvasForOnScreenWidths(named name: String) async throws -> (PDFPageCanvasView, GraphitePDFDisplayView, UIWindow) {
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: name)
        pdfView.autoScales = false
        return (canvas, pdfView, window)
    }

    /// The owner's complaint (HUNT-004): ink written while zoomed in is thicker on the page.
    /// The same pen and monoline line, drawn through the real canvas at zoom 1, 2 and 3, is as
    /// wide on the page once it has settled, measured in the screen's own pixels: as wide as
    /// at zoom 1, as wide as its stored stroke draws, and as wide again at zoom 1 afterwards.
    /// Before the fix pen 2.8 drew 1.60 times too wide at zoom 3 in the stored stroke.
    func testInkWrittenAtZoomOneTwoAndThreeShowsEquallyWideOnTheScreenOnceSettledAndZoomedBackOut() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (canvas, pdfView, window) = try await canvasForOnScreenWidths(named: "SettledWidthOnScreen")
        defer { window.isHidden = true; window.rootViewController = nil }
        let page = try XCTUnwrap(canvas.page)
        for (inkIndex, inkCase) in ([(PencilInk.pen, 2.8), (PencilInk.monoline, 2)] as [(PencilInk, Double)]).enumerated() {
            let lines = try await linesShownOnScreen(inkCase.0, width: inkCase.1, firstRow: 150 + CGFloat(inkIndex) * 300,
                                                     canvas: canvas, pdfView: pdfView, window: window)
            let atZoomOne = try XCTUnwrap(lines.first)
            XCTAssertGreaterThan(atZoomOne.settledWidth, 0.5, "The line shows at zoom 1, \(atZoomOne.label)")
            for line in lines {
                XCTAssertEqual(line.settledWidth / atZoomOne.settledWidth, 1, accuracy: 0.15, "Settled on the screen as at zoom 1, \(line.label)")
                XCTAssertEqual(line.settledWidth / line.storedStrokeWidth, 1, accuracy: 0.2, "On the screen as its stored stroke draws, \(line.label)")
            }
            // Back at zoom 1 every line shows as heavy as the one written there.
            for line in lines {
                let lineY = page.bounds(for: .cropBox).maxY - line.pageRow
                let windowPoint = try await showPageRow(line.pageRow, of: page, in: pdfView, window: window)
                let shown = try shownInkWidth(in: window, around: windowPoint(CGPoint(x: 260, y: lineY)), bandWidth: 60 * pdfView.scaleFactor, inkLevel: Double(0x1c))
                attach(shown.picture, named: "Zoomed back out, \(line.label)")
                let widthBackAtZoomOne = shown.width / pdfView.scaleFactor
                print("INK-WIDTH on screen back at zoom 1, \(line.label): \(widthBackAtZoomOne) points of the page")
                XCTAssertEqual(widthBackAtZoomOne / atZoomOne.settledWidth, 1, accuracy: 0.15, "Back at zoom 1, \(line.label)")
            }
        }
    }

    /// The same lines measured on the screen while the touch is still down, halfway along: the
    /// ink PencilKit shows as it is written is as wide on the page at zoom 2 and 3 as at zoom 1,
    /// and does not change weight when the touch lifts.
    func testInkWrittenAtZoomOneTwoAndThreeShowsEquallyWideOnTheScreenWhileItIsWritten() async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (canvas, pdfView, window) = try await canvasForOnScreenWidths(named: "LiveWidthOnScreen")
        defer { window.isHidden = true; window.rootViewController = nil }
        for (inkIndex, inkCase) in ([(PencilInk.pen, 2.8), (PencilInk.monoline, 2)] as [(PencilInk, Double)]).enumerated() {
            let lines = try await linesShownOnScreen(inkCase.0, width: inkCase.1, firstRow: 150 + CGFloat(inkIndex) * 300,
                                                     canvas: canvas, pdfView: pdfView, window: window)
            let atZoomOne = try XCTUnwrap(lines.first)
            XCTAssertGreaterThan(atZoomOne.widthWhileWriting, 0.5, "The line shows while it is written at zoom 1, \(atZoomOne.label)")
            for line in lines {
                XCTAssertEqual(line.widthWhileWriting / atZoomOne.widthWhileWriting, 1, accuracy: 0.15, "While writing as at zoom 1, \(line.label)")
                XCTAssertEqual(line.widthWhileWriting / line.settledWidth, 1, accuracy: 0.25, "No change of weight at the lift, \(line.label)")
            }
        }
    }

    // MARK: Sharp settled ink, and what a page may take

    /// How many rows of a column of the window cross a stroke's edge, neither page nor ink: the
    /// softness of what is on screen, in the screen's pixels.
    private func softEdgeRows(in window: UIWindow, atWindowPoint point: CGPoint) throws -> Double {
        let area = CGRect(x: point.x - 1, y: point.y - 30, width: 2, height: 60)
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let picture = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let image = try XCTUnwrap(picture.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let reds = (0..<image.height).map { row in Double(bytes[row * image.width * 4]) }
        guard let darkest = reds.min(), let lightest = reds.max(), lightest > darkest else { return 0 }
        // A row that is half ink counts one; a row of paper or of ink counts nothing.
        return reds.reduce(0) { softness, red in softness + 2 * min(red - darkest, lightest - red) / (lightest - darkest) }
    }

    /// At a zoom between the old half steps a page's ink was drawn larger and shrunk to the
    /// screen: its edges spread over more of the screen's pixels than when one pixel of ink is
    /// one of the screen. A broad tool in hand no longer softens anything.
    func testSettledInkIsAsSharpAtAnyZoomAsAtAWholeOne() async throws {
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "SharpInk")
        defer { window.isHidden = true; window.rootViewController = nil }
        pdfView.autoScales = false
        let overlay = try XCTUnwrap(canvas.overlayView)
        var points: [PKStrokePoint] = []
        for step in 0...40 {
            points.append(PKStrokePoint(location: CGPoint(x: 100 + CGFloat(step) * 10, y: 300), timeOffset: Double(step) / 60, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        func softness(atZoom zoom: CGFloat, drawnAt scale: CGFloat?) async throws -> Double {
            pdfView.scaleFactor = zoom
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 500)
            if let scale {
                overlay.setRenderingScale(scale)
                overlay.layoutIfNeeded()
                try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 500)
            }
            let page = try XCTUnwrap(canvas.page)
            let inkOnPage = CGRect(x: 280, y: page.bounds(for: .cropBox).maxY - 300, width: 40, height: 1)
            pdfView.go(to: inkOnPage, on: page)
            try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 300)
            // What is measured is the scale it is said to be: the canvas takes a new zoom only once no stroke is under
            // way. On the iPad on 2026-11-04 a real Apple Pencil touched the page while this test read it (a pen stroke
            // of 202 points, the palette's, at 20:14:17), the canvas stayed at zoom 2 under the PDF's 3.3, and the ink
            // measured 3.47 rows soft where 2.67 were allowed.
            if let scale {
                try await waitUntil("the canvas draws at \(scale)") { abs(canvas.zoomScale - scale) < 0.02 }
            } else {
                try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
            }
            XCTAssertEqual(canvas.drawing.strokes.count, 1, "Only the measured line is on the page at zoom \(zoom), nothing drawn by a touch meanwhile")
            let point = canvas.convert(CGPoint(x: 300 * canvas.zoomScale, y: 300 * canvas.zoomScale), to: window)
            return try softEdgeRows(in: window, atWindowPoint: point)
        }
        let atTheZoom = try await softness(atZoom: 1.36, drawnAt: nil)
        let atTheOldStep = try await softness(atZoom: 1.36, drawnAt: 1.5)
        let atAWholeOne = try await softness(atZoom: 2, drawnAt: nil)
        let pastTheOldCap = try await softness(atZoom: 3.3, drawnAt: nil)
        let magnifiedPastTheOldCap = try await softness(atZoom: 3.3, drawnAt: 3)
        // A broad pencil in hand used to draw the whole page at its own size.
        let atThePagesSize = try await softness(atZoom: 3.3, drawnAt: 1)
        print("INK-SHARP rows: 1.36 at the zoom \(atTheZoom), at 1.5 \(atTheOldStep), 2 at the zoom \(atAWholeOne), 3.3 at the zoom \(pastTheOldCap), at 3 \(magnifiedPastTheOldCap), at 1 \(atThePagesSize)")
        XCTAssertLessThanOrEqual(atTheZoom, atTheOldStep + 0.1)
        XCTAssertLessThanOrEqual(pastTheOldCap, magnifiedPastTheOldCap + 0.1)
        XCTAssertLessThan(pastTheOldCap, atThePagesSize, "Magnified ink is softer than ink drawn at the zoom")
    }

    /// The pixel eraser cuts the same gap on the page at any zoom (HUNT-023), up to the 80.4
    /// points of the screen PencilKit makes it at most.
    ///
    /// The canvas takes a new zoom a moment after the PDF view, and not while a stroke is under
    /// way: the touches UIKit gave the drawing recognizer hold the change back. The stand-in
    /// touches told straight to the recognizer are not among them, so a line begun on a busy
    /// machine before the canvas had the zoom was laid out again under PencilKit's live stroke,
    /// and the eraser then cut nothing. The strokes wait for the canvas to draw at the zoom.
    func testThePixelEraserCutsTheSameGapOnThePageAtEveryZoom() async throws {
        try await assertThePixelEraserCuts(widths: [24, 64], atZooms: [1.5, 3], named: "EraserAtZoom")
    }

    /// The smallest size of the bar's eraser (HUNT-319) reaches PencilKit as chosen, and PencilKit makes it
    /// the narrowest fixed-width eraser it has, 16.4 points of the screen. On a page zoomed in it cuts
    /// a gap of that many screen points, so the page's own width, about the one point chosen, comes at a high zoom.
    func testTheSmallestPixelEraserReachesPencilKitUnchangedAndCutsAGapAboutItsWidth() async throws {
        let smallest = PencilEraserWidths.range.lowerBound
        var chosen = PencilToolbox(defaults: try XCTUnwrap(UserDefaults(suiteName: "SmallestEraser-\(UUID().uuidString)"))).selection
        chosen.kind = .eraser
        chosen.erasesWholeStrokes = false
        chosen.eraserWidth = smallest
        let tool = try XCTUnwrap(chosen.tool as? PKEraserTool)
        XCTAssertEqual(tool.eraserType, .fixedWidthBitmap)
        XCTAssertEqual(Double(tool.width), PencilEraserWidths.pencilKitWidthOnScreen.lowerBound, accuracy: 0.0001, "The narrowest PencilKit makes.")
        try await assertThePixelEraserCuts(widths: [smallest], atZooms: [2, 3], named: "SmallestEraser")
    }

    /// Draws a line on a zoomed page, cuts it with the pixel eraser of each width, and checks the gap on the page
    /// against `PencilEraserWidths.widthOnPage`: the chosen width, within PencilKit's limits on the screen.
    private func assertThePixelEraserCuts(widths: [Double], atZooms zooms: [CGFloat], named name: String) async throws {
        let restoreFingers = SynthesizedStrokes.letFingersDraw()
        defer { restoreFingers() }
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: name)
        defer { window.isHidden = true; window.rootViewController = nil }
        let toolPicker = PKToolPicker()
        pdfView.autoScales = false
        for eraserWidth in widths {
            for zoom in zooms {
                canvas.takeTool(from: toolPicker, fixedTool: selection(.monoline, width: 2))
                pdfView.scaleFactor = zoom
                try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
                try await waitUntil("the canvas draws at \(zoom)") { abs(canvas.zoomScale - zoom) < 0.02 }
                canvas.drawing = PKDrawing()
                let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
                let drawnLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x - 240, y: middle.y), to: CGPoint(x: middle.x + 240, y: middle.y), steps: 60), in: window)
                XCTAssertNotNil(drawnLine, "The line at zoom \(zoom) is drawn")
                XCTAssertEqual(canvas.zoomScale, zoom, accuracy: 0.02, "The canvas kept the zoom under the line")
                let inkBounds = canvas.drawing.bounds
                canvas.takeTool(from: toolPicker, fixedTool: PencilToolSelection(kind: .eraser, preset: InkPreset(ink: .pen), erasesWholeStrokes: false, eraserWidth: eraserWidth, isRulerActive: false))
                // The line cut in two is the erase having reached PencilKit's drawing.
                let cutLine = try await SynthesizedStrokes.draw(on: canvas, through: SynthesizedStrokes.line(from: CGPoint(x: middle.x, y: middle.y - 160), to: CGPoint(x: middle.x, y: middle.y + 160), steps: 30), in: window)
                XCTAssertNotNil(cutLine, "Eraser \(eraserWidth) at zoom \(zoom) cut the line in two")
                try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 150)
                let picture = try XCTUnwrap(canvas.drawing.image(from: inkBounds, scale: 4).cgImage)
                var bytes = [UInt8](repeating: 0, count: picture.width * picture.height * 4)
                let context = try XCTUnwrap(CGContext(data: &bytes, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: picture.width * 4,
                                                      space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
                let middleRow = picture.height / 2
                let gap = Double((0..<picture.width).filter { column in bytes[(middleRow * picture.width + column) * 4 + 3] < 64 }.count) / 4
                print("INK-WIDTH eraser \(eraserWidth) at zoom \(zoom): canvas \(canvas.zoomScale) gap \(gap)")
                let expectedGap = PencilEraserWidths.widthOnPage(chosen: eraserWidth, screenPointsPerPagePoint: Double(zoom))
                XCTAssertEqual(gap, expectedGap, accuracy: max(expectedGap * 0.2, 1.5), "Eraser \(eraserWidth) at zoom \(zoom)")
            }
        }
    }

    /// A scale change that lands while the Pencil is down waits for the lift (HUNT-013).
    func testAChangeOfZoomWhileThePencilIsDownLeavesTheCanvasAloneUntilTheLift() async throws {
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "ZoomDuringStroke")
        defer { window.isHidden = true; window.rootViewController = nil; PencilActivity.forgetPencil() }
        pdfView.autoScales = false
        pdfView.scaleFactor = 2
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
        try await waitUntil("the canvas draws at 2") { abs(canvas.zoomScale - 2) < 0.01 }

        let follower = PencilActivityRecognizer(target: nil, action: nil)
        let followedView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        followedView.addGestureRecognizer(follower)
        let pencil = StandInTouch(type: .pencil, phase: .began, timestamp: PencilActivity.now)
        let event = UIEvent()
        follower.touchesBegan([pencil], with: event)
        pdfView.scaleFactor = 3
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 500)
        XCTAssertEqual(canvas.zoomScale, 2, accuracy: 0.01, "The canvas keeps its size under the stroke.")

        pencil.standInPhase = .ended
        follower.touchesEnded([pencil], with: event)
        try await waitUntil("the canvas takes the new scale after the lift") { abs(canvas.zoomScale - 3) < 0.01 }
    }

    /// A page scrolled away takes no more than a page's memory; a memory warning lets the kept
    /// pages go, their ink already in the PDF, and draws those on screen smaller (HUNT-014).
    func testAKeptPageDrawsAtItsOwnSizeAndAMemoryWarningLetsItGo() async throws {
        let location = try makeHostedBlankNotebook(named: "KeptPages", pageCount: 6)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let coordinator = try XCTUnwrap(pdfView.annotationCoordinator)
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        try await waitUntil("the first page's canvas") { coordinator.editingCanvas(for: firstPage) != nil }
        let firstCanvas = try XCTUnwrap(coordinator.editingCanvas(for: firstPage))
        pdfView.autoScales = false
        pdfView.scaleFactor = 3
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 400)
        try await waitUntil("the page draws at the zoom") { abs(firstCanvas.zoomScale - 3) < 0.01 }
        var points: [PKStrokePoint] = []
        for step in 0...5 { points.append(PKStrokePoint(location: CGPoint(x: 100 + CGFloat(step) * 10, y: 100), timeOffset: Double(step) / 60, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)) }
        firstCanvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        try await waitUntil("the ink reaches the page") { firstPage.annotations.contains { annotation in annotation.type == "Ink" } }
        session.go(to: 5)
        try await waitUntil("the first page is not shown") { !coordinator.isDisplaying(firstPage) }
        try await waitUntil("the kept page draws at its own size") { abs(firstCanvas.zoomScale - 1) < 0.01 }

        let shownPage = try XCTUnwrap(session.document.page(at: 5))
        try await waitUntil("the shown page's canvas") { coordinator.editingCanvas(for: shownPage) != nil }
        let shownCanvas = try XCTUnwrap(coordinator.editingCanvas(for: shownPage))
        try await waitUntil("the shown page draws at the zoom") { abs(shownCanvas.zoomScale - 3) < 0.01 }
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await SynthesizedStrokes.waitForPageToDraw(milliseconds: 100)
        XCTAssertNil(coordinator.editingCanvas(for: firstPage), "The kept page's canvas has gone")
        XCTAssertTrue(firstPage.annotations.contains { annotation in annotation.type == "Ink" }, "Its ink is in the PDF")
        // Still at the zoom, over less of the page (HUNT-320): a quarter of the usual pixels.
        let screenScale = window.traitCollection.displayScale
        try await waitUntil("the shown page takes less memory") {
            shownCanvas.bounds.width * shownCanvas.bounds.height * screenScale * screenScale <= PDFCanvasShownRegion.maximumCanvasPixelCount / 4 * 1.01
        }
        XCTAssertEqual(shownCanvas.zoomScale, 3, accuracy: 0.01, "The shown page still draws at the zoom")
    }

    /// The Pencil's first touch while reading draws (HUNT-024): the recognizer tells the page's
    /// canvas's own drawing recognizer of it.
    ///
    /// The strokes wait for the canvas to draw at the PDF's fitted zoom: it took that zoom a moment
    /// after opening, which on a busy machine came under the third stroke, whose stand-in touches
    /// do not hold the change back, and PencilKit dropped the stroke.
    func testThePencilsFirstTouchWhileReadingDraws() async throws {
        let (canvas, pdfView, window) = try await hostedPageCanvas(named: "FirstTouch")
        defer { window.isHidden = true; window.rootViewController = nil }
        let session = try XCTUnwrap(canvas.annotationCoordinator?.session)
        session.isWriting = false
        try await waitUntil("reading") { !canvas.isUserInteractionEnabled }
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        let recognizer = try XCTUnwrap(pdfView.annotationCoordinator?.pencilTouchWhileReadingRecognizer)
        XCTAssertNotNil(recognizer.drawingRecognizerUnderTouch)
        canvas.drawingPolicy = .pencilOnly
        print("INK-WIDTH first touch: state \(recognizer.state.rawValue) enabled \(recognizer.isEnabled) policy \(canvas.drawingPolicy.rawValue) drawing \(canvas.isDrawingEnabled) restored \(canvas.hasRestoredStoredInk) restoring \(canvas.isRestoringStoredInk) hidden \(canvas.isHidden)")
        let middle = pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: window)
        let line = SynthesizedStrokes.line(from: CGPoint(x: middle.x - 80, y: middle.y), to: CGPoint(x: middle.x + 80, y: middle.y))
        let drawnDirectly = try await SynthesizedStrokes.draw(on: canvas, through: line, in: window, touchType: .pencil)
        print("INK-WIDTH first touch: told directly, interaction off: \(drawnDirectly != nil)")
        canvas.isUserInteractionEnabled = true
        let drawnEnabled = try await SynthesizedStrokes.draw(on: canvas, through: line, in: window, touchType: .pencil)
        print("INK-WIDTH first touch: told directly, interaction on: \(drawnEnabled != nil)")
        canvas.isUserInteractionEnabled = false
        try await SynthesizedStrokes.waitForCanvasToDrawAtTheZoom(of: canvas, in: pdfView)
        let drawnStroke = try await SynthesizedStrokes.draw(on: canvas, through: line, in: window, touchType: .pencil, toldTo: recognizer)
        print("INK-WIDTH first touch: through the recognizer: \(drawnStroke != nil) state \(recognizer.state.rawValue) interaction \(canvas.isUserInteractionEnabled) writing \(session.isWriting)")
        XCTAssertNotNil(drawnStroke, "The touch that switched to writing is a stroke")
    }

    /// The first page's canvas of a blank PDF shown in a window, with the PDF's view.
    private func hostedPageCanvas(named name: String) async throws -> (PDFPageCanvasView, GraphitePDFDisplayView, UIWindow) {
        let location = try makeHostedBlankNotebook(named: name)
        temporaryLocations.append(location)
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        try await waitUntil("the page's canvas is shown") { self.canvases(in: controller.view).contains { !$0.isHidden } }
        let canvas = try XCTUnwrap(canvases(in: controller.view).first { !$0.isHidden })
        return (canvas, try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView), window)
    }

    private var temporaryLocations: [URL] = []

    override func tearDown() async throws {
        for location in temporaryLocations { try? FileManager.default.removeItem(at: location) } // A file left in the temporary folder harms nothing.
        temporaryLocations = []
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }
}
#endif
