/**
 * File: MenuItemLabelTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: Toolbar menus whose entries carry made symbol images appear faster than the same
 *              menus with named symbols, and an unknown symbol still draws.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 10/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// The owner's Library → List switch spent about 1 s laying out the window's toolbar again, half of
/// it SwiftUI looking up the named symbols of the toolbar menus' entries at each of about 20 reads
/// of the toolbar items (sampled 2026-11-10). `MenuItemLabel` hands the Mac made images instead.
@MainActor
final class MenuItemLabelTests: XCTestCase {
    @Observable final class ToolbarSwitch { var showsItems = false }

    private static let symbolNames = ["bold", "italic", "strikethrough", "highlighter", "function", "eye.slash", "list.bullet",
                                      "list.number", "checklist", "text.quote", "tablecells", "text.bubble", "curlybraces", "minus",
                                      "number", "link", "photo.on.rectangle", "camera", "doc.viewfinder", "doc.badge.plus"]

    /// Four toolbar menus of 18 entries each, about as many as a note's Format, Insert and More menus hold.
    private struct ToolbarWithMenus: View {
        let toolbarSwitch: ToolbarSwitch
        let usesMadeImages: Bool

        var body: some View {
            Text("Page").frame(width: 900, height: 500)
                .toolbar {
                    if toolbarSwitch.showsItems {
                        ToolbarItemGroup(placement: .primaryAction) {
                            ForEach(0..<4, id: \.self) { menuIndex in
                                Menu("Menu \(menuIndex)", systemImage: "textformat") {
                                    ForEach(0..<18, id: \.self) { entryIndex in
                                        let symbolName = MenuItemLabelTests.symbolNames[(entryIndex + menuIndex) % MenuItemLabelTests.symbolNames.count]
                                        if usesMadeImages {
                                            Button("Entry \(entryIndex)", menuSymbol: symbolName) {}
                                        } else {
                                            Button("Entry \(entryIndex)", systemImage: symbolName) {}
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }

    /// The shortest of five times the toolbar's items take to appear and be laid out.
    private func shortestTimeForItemsToAppear(usesMadeImages: Bool) throws -> Duration {
        let toolbarSwitch = ToolbarSwitch()
        let controller = NSHostingController(rootView: ToolbarWithMenus(toolbarSwitch: toolbarSwitch, usesMadeImages: usesMadeImages))
        controller.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .resizable]
        window.isReleasedWhenClosed = false
        window.showInvisibly()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        var shortest = Duration.seconds(60)
        for _ in 0..<5 {
            let start = ContinuousClock.now
            toolbarSwitch.showsItems = true
            for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            window.layoutIfNeeded()
            window.displayIfNeeded()
            shortest = min(shortest, ContinuousClock.now - start)
            XCTAssertEqual(window.toolbar?.items.count, 4, "The four menus are in the window's toolbar.")
            toolbarSwitch.showsItems = false
            for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            window.layoutIfNeeded()
        }
        return shortest
    }

    func testToolbarMenusWithMadeSymbolImagesAppearFasterThanWithNamedSymbols() throws {
        let namedSymbols = try shortestTimeForItemsToAppear(usesMadeImages: false)
        let madeImages = try shortestTimeForItemsToAppear(usesMadeImages: true)
        // Measured 2026-11-10 on the owner's Mac: about 255 ms named, 155 ms made, 100 ms for plain buttons (50 ms of it the waits above).
        XCTAssertLessThan(madeImages, namedSymbols * 0.85, "Made images \(madeImages), named symbols \(namedSymbols).")
    }

    func testAnUnknownSymbolStillDrawsItsTitle() throws {
        let host = NSHostingView(rootView: MenuItemLabel(title: "Entry", systemImage: "no.such.symbol.anywhere").fixedSize())
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 20, "The title is drawn when the symbol does not exist.")
    }
}
#endif
