/**
 * File: PencilColorDragHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the Pencil bar's colors arranged by dragging, as in Apple's markup palette: a finger
 *              dragged along the row reorders the favorite colors where Settings › Colors keeps them, a tap still
 *              chooses, a drag off the row removes a color and Undo brings it back (Docs/Pen-color-palette-todo.md 1).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The owner's request of 2026-11-13 ("not the hold and move left situation we have"). The bar's colors are shown on
/// their own in a window, at a known place, and touched through UIKit's event path as the screen touches them; their
/// lists are kept in settings of the test's own. Nothing here plays sound.
@MainActor
final class PencilColorDragHostedTests: XCTestCase {
    private let red = PaletteColor(name: "red", hex: "#e93147")
    private let orange = PaletteColor(name: "orange", hex: "#ec7500")
    private let green = PaletteColor(name: "green", hex: "#08b94e")
    private let blue = PaletteColor(name: "blue", hex: "#086ddd")
    /// Where the row's left edge stands in the window, and its height and pitch at the regular density.
    private let rowOrigin = CGPoint(x: 100, y: 200)
    private let rowHeight: CGFloat = 44
    private let swatchPitch = PencilToolRowLayout.Density.regular.swatchPitch
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "PencilColorDrag-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode([red, orange, green, blue]), forKey: GraphitePreferences.colorPaletteKey)
        return defaults
    }

    private func storedNames(in defaults: UserDefaults) -> [String] {
        GraphitePreferences.colorPalette(decoding: defaults.data(forKey: GraphitePreferences.colorPaletteKey)).map(\.name)
    }

    /// The bar's colors with Other Color and the plus, at `rowOrigin` of a window of the 11-inch iPad's size.
    private func showColors(toolbox: PencilToolbox, defaults: UserDefaults) async throws -> UIWindow {
        try await waitUntil("the app's scene is connected") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let colors = HStack(spacing: 0) { PencilColorButtons(toolbox: toolbox, rowHeight: rowHeight) }
            .fixedSize()
            .padding(.leading, rowOrigin.x)
            .padding(.top, rowOrigin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .defaultAppStorage(defaults)
        let shownWindow = UIWindow(windowScene: scene)
        shownWindow.frame = CGRect(x: 0, y: 0, width: 1_194, height: 834)
        shownWindow.rootViewController = UIHostingController(rootView: colors)
        shownWindow.makeKeyAndVisible()
        window = shownWindow
        return shownWindow
    }

    /// The middle of the swatch at `swatchIndex` of the row (black is 0, the first favorite 1).
    private func center(ofSwatchAt swatchIndex: Int) -> CGPoint {
        CGPoint(x: rowOrigin.x + (Double(swatchIndex) + 0.5) * swatchPitch, y: rowOrigin.y + rowHeight / 2)
    }

    private func tap(at point: CGPoint, in window: UIWindow) async {
        await SynthesizedTouches(window: window).move(paths: [(point, point)], steps: 1, stepSeconds: 0.03, holdSeconds: 0)
    }

    /// Waits until the window has drawn the row once, so its gestures are in place.
    private func waitForTheRow(in window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await waitUntil("the row is drawn") { window.rootViewController?.view.layer.sublayers?.isEmpty == false }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "The bar's colors before the touches"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The simulator always makes touches; a missing one is a failure here, not a reason to skip.
    private func requireTouches() throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { throw SynthesizedTouchesUnavailable() }
    }

    private struct SynthesizedTouchesUnavailable: Error {}

    func testAFingerDraggedAlongTheRowPutsTheColorWhereItLetGo() async throws {
        try requireTouches()
        let defaults = try makeDefaults()
        let toolbox = PencilToolbox(defaults: defaults)
        let window = try await showColors(toolbox: toolbox, defaults: defaults)
        try await waitForTheRow(in: window)
        // Red, the first favorite, two places on: past orange and green.
        let start = center(ofSwatchAt: 1)
        await SynthesizedTouches(window: window).drag(from: start, to: CGPoint(x: start.x + 2 * swatchPitch, y: start.y), steps: 24)
        try await waitUntil("the drop is stored") { self.storedNames(in: defaults) == ["orange", "green", "red", "blue"] }
        // And back to the start, past the first place.
        let redNow = center(ofSwatchAt: 3)
        await SynthesizedTouches(window: window).drag(from: redNow, to: CGPoint(x: redNow.x - 6 * swatchPitch, y: redNow.y), steps: 24)
        try await waitUntil("the drop past the start is stored") { self.storedNames(in: defaults) == ["red", "orange", "green", "blue"] }
    }

    func testATapStillChoosesAndADragStoresNothingUntilItEnds() async throws {
        try requireTouches()
        let defaults = try makeDefaults()
        let toolbox = PencilToolbox(defaults: defaults)
        let window = try await showColors(toolbox: toolbox, defaults: defaults)
        try await waitForTheRow(in: window)
        await tap(at: center(ofSwatchAt: 3), in: window)
        try await waitUntil("green is chosen") { toolbox.toolInUse == .ink && toolbox.presetInUse.colorHex == TextColorMarkup.canonicalHex(self.green.hex) }
        XCTAssertEqual(storedNames(in: defaults), ["red", "orange", "green", "blue"], "A tap arranges nothing.")
        // A drag held over another place stores nothing while the finger is down.
        let touches = SynthesizedTouches(window: window)
        let start = center(ofSwatchAt: 4)
        touches.begin(at: [start])
        await touches.slide(to: [CGPoint(x: start.x - 2 * swatchPitch, y: start.y)], steps: 20)
        await touches.hold(seconds: 0.4)
        XCTAssertEqual(storedNames(in: defaults), ["red", "orange", "green", "blue"], "Nothing is stored before the finger lifts.")
        touches.end()
        try await waitUntil("the lift stores blue two places earlier") { self.storedNames(in: defaults) == ["red", "blue", "orange", "green"] }
        XCTAssertEqual(toolbox.presetInUse.colorHex, TextColorMarkup.canonicalHex(green.hex), "A drag chooses no color.")
    }

    func testADragOffTheRowRemovesTheColorAndUndoPutsItBack() async throws {
        try requireTouches()
        let defaults = try makeDefaults()
        let toolbox = PencilToolbox(defaults: defaults)
        let window = try await showColors(toolbox: toolbox, defaults: defaults)
        try await waitForTheRow(in: window)
        let orangeCenter = center(ofSwatchAt: 2)
        await SynthesizedTouches(window: window).drag(from: orangeCenter, to: CGPoint(x: orangeCenter.x, y: orangeCenter.y - 3 * rowHeight), steps: 24)
        try await waitUntil("orange is removed") { self.storedNames(in: defaults) == ["red", "green", "blue"] }
        // The row closed up, and Undo stands after its last color.
        window.layoutIfNeeded()
        await tap(at: center(ofSwatchAt: 4), in: window)
        try await waitUntil("orange is back at its place") { self.storedNames(in: defaults) == ["red", "orange", "green", "blue"] }
    }

    func testASecondTapOnTheChosenColorOpensItsColorPicker() async throws {
        try requireTouches()
        let defaults = try makeDefaults()
        let toolbox = PencilToolbox(defaults: defaults)
        let window = try await showColors(toolbox: toolbox, defaults: defaults)
        try await waitForTheRow(in: window)
        await tap(at: center(ofSwatchAt: 4), in: window)
        try await waitUntil("blue is chosen") { toolbox.presetInUse.colorHex == TextColorMarkup.canonicalHex(self.blue.hex) }
        XCTAssertNil(window.rootViewController?.presentedViewController, "The first tap only chooses.")
        await tap(at: center(ofSwatchAt: 4), in: window)
        try await waitUntil("the second tap opens the color picker") {
            window.rootViewController?.presentedViewController is UIColorPickerViewController
        }
        let picker = try XCTUnwrap(window.rootViewController?.presentedViewController as? UIColorPickerViewController)
        XCTAssertEqual(picker.title, "Pen Color")
        picker.dismiss(animated: false)
    }
}
#endif
