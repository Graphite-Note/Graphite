/**
 * File: PDFMarkupToolbarRowTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: The Mac markup row's layout: each folding is narrower than the one before, a wide pane shows every
 *              tool and colour as a button, the Sign menu only with a store, and screenshots of the row in light and
 *              dark, wide and narrow.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 13/11/2026
 */

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class PDFMarkupToolbarRowTests: XCTestCase {
    /// A store of one signature, so the row shows its Sign menu.
    private lazy var signatureStore: PDFSignatureStore = {
        // Nothing is saved in it: a folder that does not exist stays empty.
        PDFSignatureStore(directory: URL(fileURLWithPath: "/nonexistent/PDFMarkupToolbarRowTests/Signatures"))
    }()

    private func content(_ toolbar: PDFMarkupToolbar, folding: PDFMarkupRowFolding) -> some View {
        PDFMarkupRowContent(toolbar: toolbar, style: .constant(.highlight(.green)), inkStyle: .constant(.default), shapeStyle: .constant(.default),
                            textFormat: PDFMarkupTextFormatSource(boxFormat: nil, applyToBox: nil), markSelection: { _ in }, folding: folding)
            .environment(\.pdfSignatureStore, signatureStore)
    }

    private func fittingWidth(_ view: some View) -> CGFloat {
        let hostingView = NSHostingView(rootView: view)
        return hostingView.fittingSize.width
    }

    func testEachFoldingIsNarrowerThanTheOneBefore() {
        for tool in [PDFMarkupTool.draw, .textBox, .highlight, .shapes] {
            let toolbar = PDFMarkupToolbar()
            toolbar.choose(tool)
            let widths = PDFMarkupRowFolding.allCases.map { folding in fittingWidth(content(toolbar, folding: folding)) }
            for (wider, narrower) in zip(widths, widths.dropFirst()) {
                XCTAssertGreaterThanOrEqual(wider, narrower, "\(tool): \(widths)")
            }
            XCTAssertLessThan(widths.last ?? 0, widths.first ?? 0, "\(tool): folding all saves room, \(widths)")
            XCTAssertLessThan(widths.last ?? .infinity, 440, "\(tool): the most folded row fits a narrow pane, \(widths)")
        }
    }

    func testAWidePaneLaysEveryToolAndColourOutAsAButton() {
        // `ViewThatFits` takes the first layout whose width fits, and the unfolded one comes first.
        // Shapes shows two palettes, border and fill, and needs a wider window before its choices fold into menus.
        for (tool, widest) in [(PDFMarkupTool.draw, 1000), (.shapes, 1200)] as [(PDFMarkupTool, CGFloat)] {
            let toolbar = PDFMarkupToolbar()
            toolbar.choose(tool)
            XCTAssertLessThan(fittingWidth(content(toolbar, folding: .none)), widest, "\(tool): a wide window shows the whole row.")
        }
    }

    func testTheRowHasAShapesButtonAndASignMenuOnlyWhereSignaturesCanBeKept() {
        let toolbar = PDFMarkupToolbar()
        let withStore = fittingWidth(content(toolbar, folding: .none))
        let withoutStore = fittingWidth(PDFMarkupRowContent(toolbar: toolbar, style: .constant(.highlight(.green)), inkStyle: .constant(.default),
                                                            shapeStyle: .constant(.default), textFormat: PDFMarkupTextFormatSource(boxFormat: nil, applyToBox: nil),
                                                            markSelection: { _ in }, folding: .none))
        XCTAssertGreaterThan(withStore, withoutStore, "The Sign menu takes room in the row only with a place to keep signatures.")
    }

    /// Writes the row in light and dark, wide and narrow, with Draw, Text Box and Highlight chosen, when a folder is
    /// named in `GRAPHITE_MARKUP_ROW_SCREENSHOTS`, for a person to look at; it checks nothing otherwise.
    func testScreenshotsOfTheRow() throws {
        guard let folder = ProcessInfo.processInfo.environment["GRAPHITE_MARKUP_ROW_SCREENSHOTS"] else { return }
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            for tool in [PDFMarkupTool.draw, .textBox, .highlight, .shapes] {
                for width in [1100, 760, 560, 360] as [CGFloat] {
                    let toolbar = PDFMarkupToolbar()
                    toolbar.choose(tool)
                    let row = PDFMarkupToolbarRow(toolbar: toolbar, style: .constant(.highlight(.green)), inkStyle: .constant(.default),
                                                  shapeStyle: .constant(.default),
                                                  textFormat: PDFMarkupTextFormatSource(boxFormat: nil, applyToBox: nil), markSelection: { _ in })
                    let hostingView = NSHostingView(rootView: row.frame(width: width).environment(\.pdfSignatureStore, signatureStore))
                    hostingView.appearance = NSAppearance(named: appearanceName)
                    hostingView.frame = CGRect(x: 0, y: 0, width: width, height: PDFMarkupToolbarRow.rowHeight)
                    let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: true)
                    window.appearance = NSAppearance(named: appearanceName)
                    window.contentView = hostingView
                    window.showInvisibly()
                    hostingView.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
                    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
                    let name = "row-\(appearanceName == .aqua ? "light" : "dark")-\(tool.title.replacingOccurrences(of: " ", with: ""))-\(Int(width)).png"
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
                    window.orderOut(nil)
                }
            }
        }
    }
}
#endif
