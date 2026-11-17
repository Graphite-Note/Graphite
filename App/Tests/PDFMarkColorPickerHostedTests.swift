/**
 * File: PDFMarkColorPickerHostedTests.swift
 * -----------------------------------------
 * Layer: Tests
 * Description: The iPad's colour picker for text marks (Other Color… in the mark menus, the "+" beside the text
 *              highlighter) presented as a popover in the hosted app: a colour picked then the popover closed by a tap
 *              outside it is saved and handed back once; closed with nothing picked, nothing is; for the "+" beside the
 *              text highlighter each colour picked is saved at once; one picker is made ahead and kept.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */
#if os(iOS)
import XCTest
import UIKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// A popover colour picker has no close button, so UIKit never reports it finishing: closing it by a tap outside, the
/// only way a person closes it, must save and hand back the colour picked (`PDFMarkColorPicker`). Found 2026-11-17 in the
/// installed app: a colour picked with the "+" beside the text highlighter was neither saved nor used.
@MainActor
final class PDFMarkColorPickerHostedTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var preferences: UserDefaults!
    private var suiteName = ""

    override func setUp() async throws {
        // A tap outside the popover is what these tests are about: without touches they fail rather than pass unseen.
        guard SynthesizedTouches.unavailableReason == nil else { throw TouchesUnavailable() }
        suiteName = "PDFMarkColorPicker-\(UUID().uuidString)"
        preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        preferences?.removePersistentDomain(forName: suiteName)
        preferences = nil
    }

    func testAColourPickedThenThePopoverClosedByATapOutsideIsSavedAndHandedBackOnce() async throws {
        let picker = PDFMarkColorPicker(preferences: preferences)
        let (window, anchor) = try showAnchor()
        var chosenColors: [PDFMarkupColor] = []
        picker.present(with: .yellow, from: anchor, at: CGPoint(x: anchor.bounds.midX, y: anchor.bounds.maxY)) { chosen in
            chosenColors.append(chosen)
        }
        let shownPicker = try await waitForPicker(in: window)
        let orange = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: orange, continuously: false)

        try await tapOutsideThePopover(in: window)

        let pickedColor = PDFMarkupColor(platformColor: orange)
        XCTAssertEqual(chosenColors.map(\.hex), [pickedColor.hex], "Handed back once, in the colour picked.")
        let saved = PDFTextMarkColors(decoding: preferences.data(forKey: PDFAnnotationPreferenceKey.textMarkColors))
        XCTAssertEqual(saved.colors.last?.hex, pickedColor.hex, "Saved with the text-mark colours.")
    }

    func testThePopoverClosedWithNothingPickedSavesAndHandsBackNothing() async throws {
        let picker = PDFMarkColorPicker(preferences: preferences)
        let (window, anchor) = try showAnchor()
        var chosenColors: [PDFMarkupColor] = []
        picker.present(with: .yellow, from: anchor, at: CGPoint(x: anchor.bounds.midX, y: anchor.bounds.maxY)) { chosen in
            chosenColors.append(chosen)
        }
        _ = try await waitForPicker(in: window)

        try await tapOutsideThePopover(in: window)

        XCTAssertTrue(chosenColors.isEmpty)
        XCTAssertNil(preferences.data(forKey: PDFAnnotationPreferenceKey.textMarkColors))
    }

    /// In a compact width the popover becomes a sheet with a close button: its finishing and the dismissal after it
    /// hand the colour back once, not twice.
    func testTheCloseButtonAndTheDismissalAfterItHandTheColourBackOnce() async throws {
        let picker = PDFMarkColorPicker(preferences: preferences)
        let (window, anchor) = try showAnchor()
        var chosenColors: [PDFMarkupColor] = []
        picker.present(with: .yellow, from: anchor, at: CGPoint(x: anchor.bounds.midX, y: anchor.bounds.maxY)) { chosen in
            chosenColors.append(chosen)
        }
        let shownPicker = try await waitForPicker(in: window)
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: .blue, continuously: false)

        shownPicker.delegate?.colorPickerViewControllerDidFinish?(shownPicker)
        let presentation = try XCTUnwrap(shownPicker.presentationController)
        presentation.delegate?.presentationControllerDidDismiss?(presentation)
        shownPicker.dismiss(animated: false)

        XCTAssertEqual(chosenColors.map(\.hex), [PDFMarkupColor(platformColor: .blue).hex])
    }

    /// The "+" beside the text highlighter takes each colour as it is picked: saved at once, in place of the one picked
    /// before it, so the row shows it while the picker is open; a colour still being dragged over is not taken; closing
    /// saves nothing more.
    func testEachColourPickedIsSavedAtOnceInPlaceOfTheOnePickedBefore() async throws {
        let picker = PDFMarkColorPicker(preferences: preferences)
        let (window, anchor) = try showAnchor()
        var takenColors: [PDFMarkupColor] = []
        var chosenOnClose: [PDFMarkupColor] = []
        picker.present(with: .yellow, from: anchor, at: CGPoint(x: anchor.bounds.midX, y: anchor.bounds.maxY),
                       pickedColorDidChange: { picked in takenColors.append(picked) }, choose: { chosen in chosenOnClose.append(chosen) })
        let shownPicker = try await waitForPicker(in: window)
        let orange = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        let teal = UIColor(red: 0, green: 0.5, blue: 0.5, alpha: 1)

        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: orange, continuously: false)
        XCTAssertEqual(savedColors().last?.hex, PDFMarkupColor(platformColor: orange).hex, "Saved at once, while the picker is open.")
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: .purple, continuously: true)
        XCTAssertEqual(takenColors.count, 1, "A colour dragged over is not taken.")
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: teal, continuously: false)

        let savedWhileOpen = savedColors()
        XCTAssertEqual(savedWhileOpen.last?.hex, PDFMarkupColor(platformColor: teal).hex)
        XCTAssertFalse(savedWhileOpen.contains(PDFMarkupColor(platformColor: orange)), "The colour picked before is replaced.")
        XCTAssertEqual(savedWhileOpen.count, PDFMarkupColor.highlightColors.count + 1)
        XCTAssertEqual(takenColors.map(\.hex), [orange, teal].map { PDFMarkupColor(platformColor: $0).hex })

        try await tapOutsideThePopover(in: window)
        XCTAssertEqual(savedColors(), savedWhileOpen, "Closing saves nothing more.")
        XCTAssertTrue(chosenOnClose.isEmpty)
    }

    /// A standard colour picked is not saved twice, and the colour this picking added before it goes.
    func testAStandardColourPickedAfterANewOneLeavesTheStandardColours() async throws {
        let picker = PDFMarkColorPicker(preferences: preferences)
        let (window, anchor) = try showAnchor()
        picker.present(with: .yellow, from: anchor, at: .zero, pickedColorDidChange: { _ in }, choose: { _ in })
        let shownPicker = try await waitForPicker(in: window)
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: .brown, continuously: false)
        shownPicker.delegate?.colorPickerViewController?(shownPicker, didSelect: PDFMarkupColor.green.platformColor, continuously: false)

        XCTAssertEqual(savedColors(), PDFMarkupColor.highlightColors)
        try await tapOutsideThePopover(in: window)
    }

    /// The picker made ahead is the one shown, and shown again the next time: the "+" opens it without making one.
    func testThePreparedPickerIsTheOneShownEachTime() async throws {
        let picker = PDFMarkColorPicker(preferences: preferences)
        picker.prepare()
        let (window, anchor) = try showAnchor()
        picker.present(with: .yellow, from: anchor, at: .zero) { _ in }
        let first = try await waitForPicker(in: window)
        try await tapOutsideThePopover(in: window)
        picker.present(with: .green, from: anchor, at: .zero) { _ in }
        let second = try await waitForPicker(in: window)
        XCTAssertTrue(first === second, "One picker, kept.")
        XCTAssertEqual(PDFMarkupColor(platformColor: second.selectedColor), .green, "Shown with the colour it was given.")
        try await tapOutsideThePopover(in: window)
    }

    private func savedColors() -> [PDFMarkupColor] {
        PDFTextMarkColors(decoding: preferences.data(forKey: PDFAnnotationPreferenceKey.textMarkColors)).colors
    }

    // MARK: Fixture

    private struct TouchesUnavailable: Error {}

    /// A window with a small view near its top, where the bar's "+" or a mark's menu is.
    private func showAnchor() throws -> (UIWindow, UIView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let anchor = UIView(frame: CGRect(x: window.bounds.midX - 22, y: 140, width: 44, height: 44))
        controller.view.addSubview(anchor)
        windows.append(window)
        return (window, anchor)
    }

    private func waitForPicker(in window: UIWindow) async throws -> UIColorPickerViewController {
        var picker: UIColorPickerViewController?
        try await waitUntil("the colour picker is shown") {
            picker = window.rootViewController?.presentedViewController as? UIColorPickerViewController
            return picker != nil && picker?.isBeingPresented == false
        }
        let shownPicker = try XCTUnwrap(picker)
        XCTAssertEqual(shownPicker.modalPresentationStyle, .popover, "A popover, which has no close button.")
        return shownPicker
    }

    /// A finger's tap near the window's bottom corner, far from the popover under the anchor, and the popover gone.
    private func tapOutsideThePopover(in window: UIWindow) async throws {
        let touches = SynthesizedTouches(window: window)
        touches.begin(at: [CGPoint(x: 40, y: window.bounds.maxY - 60)])
        await touches.hold(seconds: 0.05)
        touches.end()
        try await waitUntil("the popover is closed") { window.rootViewController?.presentedViewController == nil }
    }
}
#endif
