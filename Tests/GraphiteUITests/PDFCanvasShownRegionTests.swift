/**
 * File: PDFCanvasShownRegionTests.swift
 * -------------------------------------
 * Layer: Tests
 * Description: A PDF page's Pencil canvas draws at the zoom at any zoom, covering the whole page
 *              while it fits its bound of pixels and otherwise the part around what is on screen.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */
import XCTest
import CoreGraphics
@testable import GraphiteUI

/// HUNT-320. Past about 4.2 times on A4 at 2x the canvas drew the whole page at a lower scale
/// than the zoom, and settled ink was magnified. The shared geometry is tested here; the canvas
/// itself in `PDFPageSharpnessHostedTests` on the iPad.
final class PDFCanvasShownRegionTests: XCTestCase {
    private let fourA = CGSize(width: 595, height: 842)

    func testTheScaleIsTheZoomAtAnyZoom() {
        XCTAssertEqual(PDFCanvasShownRegion.renderingScale(forZoom: 1.36), 1.36, accuracy: 0.0001)
        XCTAssertEqual(PDFCanvasShownRegion.renderingScale(forZoom: 8), 8, accuracy: 0.0001, "Past the old bound of about 4.2")
        XCTAssertEqual(PDFCanvasShownRegion.renderingScale(forZoom: 0.1), PDFCanvasShownRegion.minimumRenderingScale)
        XCTAssertEqual(PDFCanvasShownRegion.renderingScale(forZoom: .nan), 1)
    }

    func testThePageIsDrawnWholeWhileItFitsTheBound() {
        let region = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: CGRect(x: 100, y: 100, width: 200, height: 300), currentRegion: nil,
                                                 scale: 4, screenScale: 2, pixelBudget: PDFCanvasShownRegion.maximumCanvasPixelCount)
        XCTAssertEqual(region, CGRect(origin: .zero, size: fourA), "595 x 842 x 64 is 32 megapixels")
    }

    /// The iPad Pro 11-inch upright at eight times: the screen shows 104 by 149 points of the page.
    func testZoomedFarInThePartAroundTheScreenIsDrawnWithinTheBound() {
        let visible = CGRect(x: 250, y: 400, width: 104, height: 149)
        let region = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: visible, currentRegion: nil,
                                                 scale: 8, screenScale: 2, pixelBudget: PDFCanvasShownRegion.maximumCanvasPixelCount)
        let pixelCount = region.width * region.height * 16 * 16
        print("CANVAS-REGION at 8x: \(region), \(pixelCount / 1_000_000) megapixels")
        XCTAssertTrue(region.contains(visible), "What is on screen is drawn")
        XCTAssertLessThanOrEqual(pixelCount, PDFCanvasShownRegion.maximumCanvasPixelCount * 1.01)
        XCTAssertGreaterThan(pixelCount, PDFCanvasShownRegion.maximumCanvasPixelCount * 0.9, "As much of the page as the bound allows")
        XCTAssertTrue(CGRect(origin: .zero, size: fourA).contains(region), "Within the page")
    }

    func testTheRegionStaysWhileTheScreenIsWellInsideItAndMovesBeforeTheScreenLeavesIt() {
        let budget = PDFCanvasShownRegion.maximumCanvasPixelCount
        let visible = CGRect(x: 250, y: 400, width: 104, height: 149)
        let first = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: visible, currentRegion: nil, scale: 8, screenScale: 2, pixelBudget: budget)
        let scrolledALittle = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: visible.offsetBy(dx: 0, dy: 20), currentRegion: first,
                                                          scale: 8, screenScale: 2, pixelBudget: budget)
        XCTAssertEqual(scrolledALittle, first, "PencilKit draws nothing again for a small scroll")
        let nearTheEdge = CGRect(x: visible.minX, y: first.maxY - visible.height - 10, width: visible.width, height: visible.height)
        let moved = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: nearTheEdge, currentRegion: first, scale: 8, screenScale: 2, pixelBudget: budget)
        XCTAssertNotEqual(moved, first)
        XCTAssertTrue(moved.contains(nearTheEdge.insetBy(dx: -nearTheEdge.width * 0.25, dy: -nearTheEdge.height * 0.25).intersection(CGRect(origin: .zero, size: fourA))),
                      "The new region has room around what is on screen")
    }

    func testAVastPageAtItsOwnSizeIsDrawnInPartAndASmallBudgetStillCoversTheScreen() {
        let vast = CGSize(width: 6_000, height: 8_000)
        let visible = CGRect(x: 0, y: 0, width: 834, height: 1_194)
        let region = PDFCanvasShownRegion.region(pageSize: vast, visibleRegion: visible, currentRegion: nil, scale: 1, screenScale: 2,
                                                 pixelBudget: PDFCanvasShownRegion.maximumCanvasPixelCount)
        XCTAssertLessThanOrEqual(region.width * region.height * 4, PDFCanvasShownRegion.maximumCanvasPixelCount * 1.01, "Not 192 megapixels")
        XCTAssertTrue(region.contains(visible))
        let tight = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: CGRect(x: 0, y: 0, width: 300, height: 400), currentRegion: nil,
                                                scale: 8, screenScale: 2, pixelBudget: 1_000_000)
        XCTAssertTrue(tight.contains(CGRect(x: 0, y: 0, width: 300, height: 400)), "What is on screen is drawn even over the bound")
    }

    func testAPageNotYetOnScreenIsDrawnFromItsTop() {
        let region = PDFCanvasShownRegion.region(pageSize: fourA, visibleRegion: nil, currentRegion: nil, scale: 8, screenScale: 2,
                                                 pixelBudget: PDFCanvasShownRegion.maximumCanvasPixelCount)
        XCTAssertEqual(region.minY, 0)
        XCTAssertLessThanOrEqual(region.width * region.height * 256, PDFCanvasShownRegion.maximumCanvasPixelCount * 1.01)
    }
}
