/**
 * File: PencilColorRowScrollingHostedTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the fixed Pencil bar's row of colors as the physical iPad shows it: the row scrolls sideways
 *              only, a swipe on it moves no color, a vertical drag neither scrolls nor moves it, more colors scroll inside
 *              a row that keeps its size, black stays in view before it, a shorter strip leaves no gap, and "+" saves a
 *              color as a swatch, a picked one at once, scrolling the strip to it (Docs/PDF-annotation-todo.md section 3).
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 18/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The report of 2026-11-14: the palette "can be dragged or moved in multiple directions (up, down, left, and
/// right)". The whole fixed bar is shown in a window as wide as an 11-inch iPad, sideways and upright, with the
/// the reported eight favorite colors, and touched through UIKit's event path as the screen touches it. The lists are kept in
/// settings of the test's own. Nothing here plays sound.
@MainActor
final class PencilColorRowScrollingHostedTests: XCTestCase {
    /// The reported favorite colors on 2026-11-14, read from the iPad's settings.
    private let ownersFavorites = [("yellow", "#e0ac00"), ("red", "#e93147"), ("orange", "#ec7500"), ("green", "#08b94e"),
                                   ("blue", "#086ddd"), ("purple", "#7852ee"), ("cyan", "#00bfbc"), ("pink", "#d53984")]
        .map { name, hex in PaletteColor(name: name, hex: hex) }
    /// Four colors saved past the reported ones, so the strip holds more than it shows.
    private var moreThanTheStripShows: [PaletteColor] {
        ownersFavorites + [("teal", "#2a9d8f"), ("brown", "#8d5524"), ("gray", "#7a7a7a"), ("navy", "#1d3557")]
            .map { name, hex in PaletteColor(name: name, hex: hex) }
    }
    /// The 11-inch iPad's window, sideways and upright, in points.
    private let sidewaysWidth: CGFloat = 1_194
    private let uprightWidth: CGFloat = 834
    /// A window whose bar's row is 514 points wide, as upright beside the sidebar, where the strip is narrower.
    private var besideTheSidebarWidth: CGFloat { 514 + trailingControlsWidth + 12 + 16 }
    /// About as wide as the PDF bar's Undo, Redo and Write controls at its trailing end.
    private let trailingControlsWidth: CGFloat = 130
    private let barTop: CGFloat = 120
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    // MARK: The bar

    private func makeDefaults(favorites: [PaletteColor]) throws -> UserDefaults {
        let suiteName = "PencilColorRowScrolling-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode(favorites), forKey: GraphitePreferences.colorPaletteKey)
        return defaults
    }

    private func storedNames(in defaults: UserDefaults) -> [String] {
        GraphitePreferences.colorPalette(decoding: defaults.data(forKey: GraphitePreferences.colorPaletteKey)).map(\.name)
    }

    private func storedHexes(in defaults: UserDefaults) -> [String] {
        GraphitePreferences.colorPalette(decoding: defaults.data(forKey: GraphitePreferences.colorPaletteKey)).compactMap { color in
            TextColorMarkup.canonicalHex(color.hex)
        }
    }

    /// The fixed bar as a PDF shows it, at the top of a window `width` points wide.
    private func showBar(toolbox: PencilToolbox, defaults: UserDefaults, width: CGFloat) async throws -> UIWindow {
        try await waitUntil("the app's scene is connected") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        PencilToolRowForm.lastShown = nil
        let bar = PencilToolbar(toolbox: toolbox, drawsShapes: .constant(false), addImage: {}, offersTextBoxes: true) {
            EmptyView()
        } trailingControls: {
            Color.clear.frame(width: trailingControlsWidth, height: 1)
        }
        let content = VStack(spacing: 0) {
            bar
            Spacer()
        }
        .padding(.top, barTop)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .defaultAppStorage(defaults)
        let shownWindow = UIWindow(windowScene: scene)
        shownWindow.frame = CGRect(x: 0, y: 0, width: width, height: 700)
        shownWindow.rootViewController = UIHostingController(rootView: content)
        shownWindow.makeKeyAndVisible()
        window = shownWindow
        try await waitUntil("the bar's row is shown") { PencilToolRowForm.lastShown != nil && self.colorRow(in: shownWindow) != nil }
        shownWindow.layoutIfNeeded()
        attachScreenshot(of: shownWindow, named: "The bar \(Int(width)) points wide")
        return shownWindow
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The clear view that takes the colors' touches, of the row on screen.
    private func colorRow(in window: UIWindow) -> PencilColorRowTouchView? {
        func search(_ view: UIView) -> PencilColorRowTouchView? {
            if let rowView = view as? PencilColorRowTouchView, rowView.window != nil, !rowView.bounds.isEmpty { return rowView }
            for subview in view.subviews { if let found = search(subview) { return found } }
            return nil
        }
        return search(window)
    }

    /// The scroll view the colors sit in, when they sit in one.
    private func colorStrip(of rowView: UIView) -> UIScrollView? {
        var ancestor = rowView.superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        return ancestor as? UIScrollView
    }

    /// The middle of the place `place` of the row (the first favorite is 0: black stands before the strip), in the window.
    private func center(ofPlace place: Int, in rowView: PencilColorRowTouchView) throws -> CGPoint {
        let pitch = try XCTUnwrap(rowView.touches?.swatchPitch)
        return rowView.convert(CGPoint(x: (Double(place) + 0.5) * pitch, y: rowView.bounds.midY), to: nil)
    }

    private func requireTouches() throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { throw SynthesizedTouchesUnavailable() }
    }

    private struct SynthesizedTouchesUnavailable: Error {}

    // MARK: Sideways only

    func testASidewaysSwipeOnTheColorsMovesNoColorAndScrollsOnlyColorsPastTheEdge() async throws {
        try requireTouches()
        for (width, favorites) in [(sidewaysWidth, ownersFavorites), (uprightWidth, ownersFavorites), (uprightWidth, moreThanTheStripShows),
                                   (besideTheSidebarWidth, ownersFavorites)] {
            let defaults = try makeDefaults(favorites: favorites)
            let toolbox = PencilToolbox(defaults: defaults)
            let window = try await showBar(toolbox: toolbox, defaults: defaults, width: width)
            let rowView = try XCTUnwrap(colorRow(in: window))
            let pitch = try XCTUnwrap(rowView.touches?.swatchPitch)
            let strip = colorStrip(of: rowView)
            let offsetBefore = strip?.contentOffset ?? .zero
            // A quick swipe towards the start, from the fourth favorite, as a finger scrolling the row on.
            let start = try center(ofPlace: 4, in: rowView)
            await SynthesizedTouches(window: window).drag(from: start, to: CGPoint(x: start.x - 3 * pitch, y: start.y), steps: 10, holdSeconds: 0.3)
            if let strip { try await waitUntil("the strip comes to rest") { !strip.isDecelerating && !strip.isDragging } }
            attachScreenshot(of: window, named: "After a sideways swipe, \(Int(width)) points")
            XCTAssertEqual(storedNames(in: defaults), favorites.map(\.name), "A swipe moves no color (\(Int(width)) points).")
            guard let stripView = strip else {
                XCTFail("The colors sit in a strip that scrolls (\(Int(width)) points).")
                window.isHidden = true
                continue
            }
            XCTAssertEqual(stripView.contentOffset.y, 0, "The strip never scrolls up or down.")
            if stripView.contentSize.width > stripView.bounds.width + 1 {
                XCTAssertGreaterThan(stripView.contentOffset.x, offsetBefore.x, "A swipe scrolls the colors past the strip's edge (\(Int(width)) points).")
            } else {
                XCTAssertEqual(stripView.contentOffset, offsetBefore, "Every color shows: the strip does not move (\(Int(width)) points).")
            }
            if width == besideTheSidebarWidth {
                // Upright beside the sidebar the bar is the last folded form, with a strip narrower than the nine colors.
                guard case .compactWithScrollingColors = PencilToolRowForm.lastShown?.arrangement else {
                    XCTFail("\(Int(width)) points: the bar is in its narrowest strip form, not \(String(describing: PencilToolRowForm.lastShown?.arrangement)).")
                    window.isHidden = true
                    continue
                }
                XCTAssertGreaterThan(stripView.contentSize.width, stripView.bounds.width + 1, "Beside the sidebar the ninth color scrolls into view.")
            }
            if favorites == moreThanTheStripShows {
                XCTAssertGreaterThan(stripView.contentSize.width, stripView.bounds.width + 1, "Twelve colors scroll inside the strip.")
            }
            window.isHidden = true
        }
    }

    func testAVerticalDragOnAColorNeitherScrollsNorMovesTheRow() async throws {
        try requireTouches()
        for width in [sidewaysWidth, uprightWidth, besideTheSidebarWidth] {
            let defaults = try makeDefaults(favorites: ownersFavorites)
            let toolbox = PencilToolbox(defaults: defaults)
            let window = try await showBar(toolbox: toolbox, defaults: defaults, width: width)
            let rowView = try XCTUnwrap(colorRow(in: window))
            let rowFrameBefore = rowView.convert(rowView.bounds, to: nil)
            let strip = colorStrip(of: rowView)
            let offsetBefore = strip?.contentOffset ?? .zero
            let start = try center(ofPlace: 2, in: rowView)
            for distance in [-120.0, 120.0] {
                let touches = SynthesizedTouches(window: window)
                touches.begin(at: [start])
                await touches.slide(to: [CGPoint(x: start.x, y: start.y + distance)], steps: 12)
                attachScreenshot(of: window, named: "In the middle of a drag \(distance < 0 ? "up" : "down"), \(Int(width)) points")
                // Mid-drag: nothing has moved.
                XCTAssertEqual(strip?.contentOffset ?? .zero, offsetBefore, "A vertical drag scrolls nothing (\(Int(width)) points).")
                XCTAssertEqual(rowView.convert(rowView.bounds, to: nil), rowFrameBefore, "The row stays where it is.")
                await touches.hold(seconds: 0.3)
                touches.end()
                if let strip { try await waitUntil("the strip is at rest") { !strip.isDecelerating && !strip.isDragging } }
            }
            XCTAssertEqual(storedNames(in: defaults), ownersFavorites.map(\.name), "A vertical drag removes and moves no color (\(Int(width)) points).")
            XCTAssertNotNil(strip, "The colors sit in a strip that scrolls (\(Int(width)) points).")
            XCTAssertEqual(strip?.contentOffset ?? .zero, offsetBefore)
            window.isHidden = true
        }
    }

    // MARK: A row of its size

    /// The strip's frame in the window and the bar's row's height, for the bar on screen.
    private func stripFrame(in window: UIWindow) throws -> CGRect {
        let rowView = try XCTUnwrap(colorRow(in: window))
        let strip = try XCTUnwrap(colorStrip(of: rowView))
        return strip.convert(strip.bounds, to: nil)
    }

    func testMoreColorsScrollInsideAStripThatKeepsItsSize() async throws {
        var shownForms: [PencilToolRowLayout.Arrangement] = []
        var stripFrames: [CGRect] = []
        var pitch = 0.0
        for favorites in [ownersFavorites, moreThanTheStripShows] {
            let defaults = try makeDefaults(favorites: favorites)
            let toolbox = PencilToolbox(defaults: defaults)
            let window = try await showBar(toolbox: toolbox, defaults: defaults, width: uprightWidth)
            shownForms.append(try XCTUnwrap(PencilToolRowForm.lastShown?.arrangement))
            stripFrames.append(try stripFrame(in: window))
            let rowView = try XCTUnwrap(colorRow(in: window))
            pitch = try XCTUnwrap(rowView.touches?.swatchPitch)
            let strip = try XCTUnwrap(colorStrip(of: rowView))
            XCTAssertEqual(strip.bounds.height, PencilToolbarMetrics.height, accuracy: 0.5, "The strip is as tall as the bar's row.")
            XCTAssertEqual(strip.contentSize.height, strip.bounds.height, accuracy: 0.5, "Nothing above or below the colors to scroll to.")
            window.isHidden = true
        }
        XCTAssertEqual(shownForms[0], shownForms[1], "Four more colors leave the bar in the same form.")
        XCTAssertEqual(stripFrames[0], stripFrames[1], "Four more colors leave the strip where it was and as large.")
        XCTAssertEqual(stripFrames[1].width, Double(PencilToolRowLayout.maximumVisibleSwatchCount - 1) * pitch, accuracy: 0.5,
                       "Nine colors show at once: black, and eight in the strip.")
    }

    // MARK: Black and the strip's ends

    /// The recording of 2026-11-17 on b04ceef0: with ten colors the strip scrolled black out of view, read as
    /// black "not saved", and a removal while scrolled to the end left a gap after the last color. Black stands before
    /// the strip, and a strip that gets shorter scrolls back to its new end.
    func testBlackStaysInViewWhenTheStripScrollsAndAShorterStripLeavesNoGap() async throws {
        let defaults = try makeDefaults(favorites: moreThanTheStripShows)
        let toolbox = PencilToolbox(defaults: defaults)
        let window = try await showBar(toolbox: toolbox, defaults: defaults, width: sidewaysWidth)
        let rowView = try XCTUnwrap(colorRow(in: window))
        let pitch = try XCTUnwrap(rowView.touches?.swatchPitch)
        let strip = try XCTUnwrap(colorStrip(of: rowView))
        let largestOffset = strip.contentSize.width - strip.bounds.width
        XCTAssertGreaterThan(largestOffset, pitch, "Twelve colors scroll inside the strip.")
        strip.setContentOffset(CGPoint(x: largestOffset, y: 0), animated: false)
        window.layoutIfNeeded()
        try PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(true)
        defer { try? PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(false) } // Left on, it slows later tests.
        var black: NSObject?
        try await waitUntil("black is accessible", pollingIntervalSeconds: 0.25) {
            black = PencilBarPlacementHostedTests.accessibilityElements(in: window).first { element in element.accessibilityLabel == "black" }
            return black != nil
        }
        let stripFrameInWindow = strip.convert(strip.bounds, to: nil)
        let blackFrame = try XCTUnwrap(black).accessibilityFrame
        XCTAssertEqual(blackFrame.midX, stripFrameInWindow.minX - pitch / 2, accuracy: 2, "Black stands right before the strip, scrolled or not.")
        attachScreenshot(of: window, named: "The strip scrolled to its end, black in view")
        // Two colors removed at the end, as Settings › Colors or the colors' menus remove them.
        defaults.set(try JSONEncoder().encode(Array(moreThanTheStripShows.dropLast(2))), forKey: GraphitePreferences.colorPaletteKey)
        try await waitUntil("the strip scrolls back to its new end") {
            window.layoutIfNeeded()
            let newLargest = strip.contentSize.width - strip.bounds.width
            return strip.contentSize.width < Double(self.moreThanTheStripShows.count) * pitch && abs(strip.contentOffset.x - newLargest) < 0.5
        }
        attachScreenshot(of: window, named: "Two colors removed at the end: no gap")
    }

    // MARK: The plus

    /// The middle of the plus, which stands right after the strip.
    private func plusCenter(in window: UIWindow) throws -> CGPoint {
        let frame = try stripFrame(in: window)
        let pitch = try XCTUnwrap(colorRow(in: window)?.touches?.swatchPitch)
        return CGPoint(x: frame.maxX + pitch / 2, y: frame.midY)
    }

    /// Presses the plus as VoiceOver does: synthesized touches reach UIKit's recognizers, not SwiftUI's buttons
    /// (`SettingsHostedTestCase.follow`). The plus is found by its label and checked to stand right after the strip.
    private func pressPlus(in window: UIWindow, labelled label: String = "Add to Favorite Colors") async throws {
        try PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(true)
        defer { try? PencilBarPlacementHostedTests.setAccessibilityRuntimeEnabled(false) } // Left on, it slows later tests.
        var plus: NSObject?
        try await waitUntil("the plus is accessible", pollingIntervalSeconds: 0.25) {
            plus = PencilBarPlacementHostedTests.accessibilityElements(in: window).first { element in element.accessibilityLabel == label }
            return plus != nil
        }
        let plusElement = try XCTUnwrap(plus)
        let expectedCenter = try plusCenter(in: window)
        XCTAssertEqual(plusElement.accessibilityFrame.midX, expectedCenter.x, accuracy: 2, "The plus stands right after the strip.")
        XCTAssertTrue(plusElement.accessibilityActivate(), "The plus answers a press.")
    }

    func testThePlusSavesTheColorInUseAsASwatchAtTheEndOfTheStrip() async throws {
        let defaults = try makeDefaults(favorites: ownersFavorites)
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.chooseColor(hex: "#2a9d8f")
        let window = try await showBar(toolbox: toolbox, defaults: defaults, width: uprightWidth)
        let stripBefore = try stripFrame(in: window)
        try await pressPlus(in: window)
        try await waitUntil("the color in use is saved") { self.storedHexes(in: defaults).last == "#2a9d8f" }
        XCTAssertEqual(storedHexes(in: defaults).count, ownersFavorites.count + 1, "One swatch, at the end.")
        XCTAssertNil(window.rootViewController?.presentedViewController, "A color not saved yet is saved at once, with no picker.")
        window.layoutIfNeeded()
        XCTAssertEqual(try stripFrame(in: window), stripBefore, "The tenth color scrolls inside the strip, which keeps its size.")
        let strip = try XCTUnwrap(colorRow(in: window).flatMap(colorStrip(of:)))
        XCTAssertGreaterThan(strip.contentSize.width, strip.bounds.width + 1, "The new swatch is past the strip's first colors.")
        // The strip scrolls to its end, where the new color stands, so the color saved comes into view.
        try await waitUntil("the strip scrolls to the new color") {
            window.layoutIfNeeded()
            return abs(strip.contentOffset.x - (strip.contentSize.width - strip.bounds.width)) < 0.5
        }
        attachScreenshot(of: window, named: "After the plus saved the color in use, the strip at its end")
    }

    func testThePlusOpensThePickerForANewColorWhenTheStripHasTheColorInUse() async throws {
        let defaults = try makeDefaults(favorites: ownersFavorites)
        let toolbox = PencilToolbox(defaults: defaults)
        toolbox.chooseColor(hex: "#086ddd")
        let window = try await showBar(toolbox: toolbox, defaults: defaults, width: sidewaysWidth)
        try await pressPlus(in: window)
        try await waitUntil("the plus opens the color picker") { window.rootViewController?.presentedViewController is UIColorPickerViewController }
        let picker = try XCTUnwrap(window.rootViewController?.presentedViewController as? UIColorPickerViewController)
        XCTAssertEqual(picker.title, "New Color")
        attachScreenshot(of: window, named: "The plus's color picker")
        XCTAssertEqual(storedNames(in: defaults), ownersFavorites.map(\.name), "Nothing is saved before a color is picked.")
        // A color picked in the picker goes on the strip at once (requested 2026-11-17), while the picker
        // is still open; a second pick changes that swatch, and closing the picker keeps it.
        let pickedColor = UIColor(red: 0x8d / 255, green: 0x55 / 255, blue: 0x24 / 255, alpha: 1)
        picker.selectedColor = pickedColor
        picker.delegate?.colorPickerViewController?(picker, didSelect: pickedColor, continuously: false)
        XCTAssertEqual(toolbox.presetInUse.colorHex, "#8d5524", "The ink draws in the color picked.")
        try await waitUntil("the first color picked is saved at once") { self.storedHexes(in: defaults).last == "#8d5524" }
        XCTAssertNotNil(window.rootViewController?.presentedViewController, "The picker is still open.")
        // Eight favorites fill the strip, so the ninth is past its edge: the strip scrolls to it with the picker open.
        let strip = try XCTUnwrap(colorRow(in: window).flatMap(colorStrip(of:)))
        try await waitUntil("the strip scrolls to the color picked") {
            window.layoutIfNeeded()
            let largestOffset = strip.contentSize.width - strip.bounds.width
            return largestOffset > 1 && abs(strip.contentOffset.x - largestOffset) < 0.5
        }
        attachScreenshot(of: window, named: "The first color picked, on the strip with the picker open")
        let secondColor = UIColor(red: 0x26 / 255, green: 0x46 / 255, blue: 0x53 / 255, alpha: 1)
        picker.selectedColor = secondColor
        picker.delegate?.colorPickerViewController?(picker, didSelect: secondColor, continuously: false)
        try await waitUntil("a second pick changes the new swatch") { self.storedHexes(in: defaults).last == "#264653" }
        XCTAssertEqual(storedHexes(in: defaults).count, ownersFavorites.count + 1, "One new swatch, not one per pick.")
        picker.dismiss(animated: false)
        picker.delegate?.colorPickerViewControllerDidFinish?(picker)
        XCTAssertEqual(storedHexes(in: defaults).count, ownersFavorites.count + 1, "Closing the picker adds nothing more.")
        XCTAssertEqual(storedHexes(in: defaults).last, "#264653")
    }
}
#endif
