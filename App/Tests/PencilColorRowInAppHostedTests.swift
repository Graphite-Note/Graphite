/**
 * File: PencilColorRowInAppHostedTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the Pencil bar's colour row inside the whole app, a PDF open and written on, in the
 *              window sizes of the owner's 11-inch iPad at full screen and side by side with another app: the fixed bar
 *              shows in each, a sideways swipe scrolls the colours that run past the strip's edge and moves none, and a
 *              colour held then dragged by a finger or Apple Pencil moves along the bar.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 17/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The owner's report of 2026-11-16 on main 44d09330: side by side, the colours "won't scroll". A window beside another
/// app is a compact width, which showed Apple's palette instead of the fixed bar, so the bar's strip was not there. The
/// bar is shown by the app itself (GraphiteRootView with a PDF written on), with the owner's eight favourites and the
/// fixed bar chosen, in windows as wide as the 11-inch iPad's Split View gives. Nothing here plays sound.
@MainActor
final class PencilColorRowInAppHostedTests: XCTestCase {
    private let ownersFavorites = [("yellow", "#e0ac00"), ("red", "#e93147"), ("orange", "#ec7500"), ("green", "#08b94e"),
                                   ("cyan", "#00bfbc"), ("blue", "#086ddd"), ("purple", "#7852ee"), ("pink", "#d53984")]
        .map { name, hex in PaletteColor(name: name, hex: hex) }
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private var scene: UIWindowScene {
        get throws { try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first) }
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    /// A vault holding a four-page PDF, open and written on.
    private func pdfWorkspace(named name: String) async throws -> WorkspaceModel {
        let directory = try TemporaryVault.make(prefix: name, for: self).root
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 4)
            .write(to: directory.appendingPathComponent("Paper.pdf"))
        // A preferences suite of its own, holding the owner's favourites and the fixed bar the owner's iPad uses.
        let workspace = WorkspaceModel(processServices: .make(for: .hostedTests), clock: LiveApplicationClock())
        let defaults = workspace.deviceDefaults
        defaults.set(try JSONEncoder().encode(ownersFavorites), forKey: GraphitePreferences.colorPaletteKey)
        defaults.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Paper.pdf"))
        try XCTUnwrap(workspace.pdfSession).isWriting = true
        return workspace
    }

    private func host(_ workspace: WorkspaceModel, size: CGSize, horizontalSizeClass: UIUserInterfaceSizeClass) throws -> UIWindow {
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = horizontalSizeClass
        let shownWindow = UIWindow(windowScene: try scene)
        shownWindow.frame = CGRect(origin: .zero, size: size)
        shownWindow.rootViewController = controller
        shownWindow.makeKeyAndVisible()
        window = shownWindow
        return shownWindow
    }

    private func colorStrip(of rowView: UIView) -> UIScrollView? {
        var ancestor = rowView.superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        return ancestor as? UIScrollView
    }

    /// Waits until `measure` keeps its answer for 600 ms: the bar settles on its form, a regular width's sidebar sliding in.
    private func waitUntilSettled<Answer: Equatable>(_ description: String, _ measure: () -> Answer) async throws {
        var lastAnswer = measure()
        var lastChange = ContinuousClock.now
        try await waitUntil(description) {
            let answer = measure()
            if answer != lastAnswer {
                lastAnswer = answer
                lastChange = ContinuousClock.now
                return false
            }
            return ContinuousClock.now - lastChange >= .milliseconds(600)
        }
    }

    /// The colour row once it shows and its strip keeps its width and its content's.
    private func settledColorRow(in window: UIWindow, named name: String) async throws -> PencilColorRowTouchView {
        let shownRows = { self.descendants(of: window, matching: PencilColorRowTouchView.self).filter { $0.window != nil && !$0.bounds.isEmpty } }
        try await waitUntil("the colour row shows, \(name)") { !shownRows().isEmpty }
        try await waitUntilSettled("the bar settles, \(name)") {
            shownRows().first.flatMap(self.colorStrip(of:)).map { strip in [strip.bounds.width, strip.contentSize.width] } ?? []
        }
        return try XCTUnwrap(shownRows().first)
    }

    /// Every scroll view and gesture recognizer from the strip up to the window, for the attachment that explains a
    /// swipe that did not scroll.
    private func describeChain(from rowView: UIView) -> String {
        var lines: [String] = []
        var ancestor: UIView? = rowView
        while let view = ancestor {
            let recognizers = (view.gestureRecognizers ?? []).map { recognizer in
                "\(type(of: recognizer)) enabled=\(recognizer.isEnabled) state=\(recognizer.state.rawValue)"
            }
            var line = "\(type(of: view)) frame=\(view.frame)"
            if let scrollView = view as? UIScrollView {
                line += " scroll(enabled=\(scrollView.isScrollEnabled) content=\(scrollView.contentSize) offset=\(scrollView.contentOffset))"
            }
            if !recognizers.isEmpty { line += " recognizers=[\(recognizers.joined(separator: ", "))]" }
            lines.append(line)
            ancestor = view.superview
        }
        return lines.joined(separator: "\n")
    }

    /// Full screen and the 11-inch iPad's Split View widths, sideways (834 tall) and upright (1,194 tall).
    private let windows: [(name: String, size: CGSize, sizeClass: UIUserInterfaceSizeClass)] = [
        ("full screen sideways", CGSize(width: 1_194, height: 834), .regular),
        ("full screen upright", CGSize(width: 834, height: 1_194), .regular),
        ("two thirds sideways", CGSize(width: 790, height: 834), .regular),
        ("half sideways", CGSize(width: 590, height: 834), .compact),
        ("two thirds upright", CGSize(width: 504, height: 1_194), .compact),
        ("half upright", CGSize(width: 410, height: 1_194), .compact),
        ("one third sideways", CGSize(width: 375, height: 834), .compact),
        ("one third upright", CGSize(width: 320, height: 1_194), .compact),
    ]

    /// The owner's report of 2026-11-17 on the iPad, running main b2eab0cd at full screen sideways on a PDF with the pen
    /// chosen: "I can't seem to switch colors around, they seem to be fixed." A color held a moment then dragged two
    /// places along the bar moves there, whether the PDF is written on or read.
    func testAColorHeldThenDraggedInTheAppMovesAlongTheBar() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { return }
        try await waitUntil("the app's scene is connected") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        XCTAssertTrue(SynthesizedTouches.canMakePencilTouches, "UIKit lets a made touch be marked as Apple Pencil's.")
        for (isWriting, touchType) in [(true, UITouch.TouchType.direct), (false, .direct), (true, .pencil), (false, .pencil)] {
            let workspace = try await pdfWorkspace(named: "ColorDragInApp")
            try XCTUnwrap(workspace.pdfSession).isWriting = isWriting
            PencilToolRowForm.lastShown = nil
            let window = try host(workspace, size: CGSize(width: 1_194, height: 834), horizontalSizeClass: .regular)
            let rowView = try await settledColorRow(in: window, named: "writing \(isWriting)")
            let pitch = try XCTUnwrap(rowView.touches?.swatchPitch)
            // Yellow, the first favorite, after black.
            let start = rowView.convert(CGPoint(x: 1.5 * pitch, y: rowView.bounds.midY), to: nil)
            let touches = SynthesizedTouches(window: window, touchType: touchType)
            touches.begin(at: [start])
            await touches.hold(seconds: PencilColorRowTouches.holdSeconds + 0.15)
            attachScreenshot(of: window, named: "writing \(isWriting): yellow held")
            await touches.slide(to: [CGPoint(x: start.x + 2 * pitch, y: start.y)], steps: 12)
            await touches.hold(seconds: 0.3)
            touches.end()
            let storedNames = {
                GraphitePreferences.colorPalette(decoding: workspace.deviceDefaults.data(forKey: GraphitePreferences.colorPaletteKey)).map(\.name)
            }
            // The order is stored once, when the drag ends; a hold that never lifted stores nothing, and the assertion
            // below says so after the wait's own failure.
            try await waitUntil("yellow is stored third, writing \(isWriting)", timeoutSeconds: 2) { storedNames().firstIndex(of: "yellow") == 2 }
            attachScreenshot(of: window, named: "writing \(isWriting): after the drag")
            let names = storedNames()
            if names.firstIndex(of: "yellow") != 2 {
                let chain = XCTAttachment(string: describeChain(from: rowView))
                chain.name = "writing \(isWriting): views and recognizers above the row"
                chain.lifetime = .keepAlways
                add(chain)
            }
            XCTAssertEqual(names.firstIndex(of: "yellow"), 2, "writing \(isWriting), \(touchType == .pencil ? "Pencil" : "finger"): yellow held then dragged two places moves there (\(names)).")
            window.isHidden = true
            window.rootViewController = nil
            self.window = nil
        }
    }

    func testASidewaysSwipeScrollsTheColorsInTheAppAtFullScreenAndSideBySide() async throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { return }
        try await waitUntil("the app's scene is connected") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        var report: [String] = []
        for shown in windows {
            let workspace = try await pdfWorkspace(named: "ColorRowInApp")
            PencilToolRowForm.lastShown = nil
            let window = try host(workspace, size: shown.size, horizontalSizeClass: shown.sizeClass)
            // The iPad keeps the fixed bar in every width, beside another app too (owner, 2026-11-16).
            try await waitUntil("the fixed bar shows, \(shown.name)") { PencilToolRowForm.lastShown != nil }
            // The bar settles on its form: a regular width's sidebar slides in, and the bar beside it is condensed
            // until the slide ends. The form must stay the same for 600 ms.
            try await waitUntilSettled("the bar's form settles, \(shown.name)") { String(describing: PencilToolRowForm.lastShown?.arrangement) }
            if PencilToolRowForm.lastShown?.arrangement == .condensed {
                // A third of the screen: fewer than three colours fit beside the tools, so they are behind the
                // condensed bar's one control (PencilToolRowLayout.minimumVisibleSwatchCount).
                attachScreenshot(of: window, named: "\(shown.name): the condensed bar")
                XCTAssertLessThan(shown.size.width, 400, "\(shown.name): only a third of the screen condenses the bar.")
                report.append("\(shown.name): the condensed bar, its colours behind one control")
                window.isHidden = true
                window.rootViewController = nil
                self.window = nil
                continue
            }
            let rowView = try await settledColorRow(in: window, named: shown.name)
            let pitch = try XCTUnwrap(rowView.touches?.swatchPitch)
            let strip = try XCTUnwrap(colorStrip(of: rowView), "\(shown.name): the colours sit in a strip")
            attachScreenshot(of: window, named: "\(shown.name) before the swipe")
            let overflows = strip.contentSize.width > strip.bounds.width + 1
            let offsetBefore = strip.contentOffset
            // A finger on the second visible colour swiping three colours towards the start. The row's own middle: the
            // strip's scroll view reaches up under the bars above it.
            let start = rowView.convert(CGPoint(x: strip.contentOffset.x + 1.5 * pitch, y: rowView.bounds.midY), to: nil)
            await SynthesizedTouches(window: window).drag(from: start, to: CGPoint(x: start.x - 3 * pitch, y: start.y), steps: 10, holdSeconds: 0.3)
            try await waitUntil("the strip comes to rest, \(shown.name)") { !strip.isDecelerating && !strip.isDragging }
            attachScreenshot(of: window, named: "\(shown.name) after the swipe")
            let line = "\(shown.name): form \(String(describing: PencilToolRowForm.lastShown?.arrangement)), strip \(Int(strip.bounds.width)) of "
                + "\(Int(strip.contentSize.width)) points, offset \(Int(offsetBefore.x)) → \(Int(strip.contentOffset.x))"
            report.append(line)
            print(line)
            let names = GraphitePreferences.colorPalette(decoding: workspace.deviceDefaults.data(forKey: GraphitePreferences.colorPaletteKey)).map(\.name)
            XCTAssertEqual(names, ownersFavorites.map(\.name), "\(shown.name): a swipe moves no colour.")
            if overflows {
                if strip.contentOffset.x <= offsetBefore.x {
                    let chain = XCTAttachment(string: describeChain(from: rowView))
                    chain.name = "\(shown.name): views and recognizers above the strip"
                    chain.lifetime = .keepAlways
                    add(chain)
                }
                XCTAssertGreaterThan(strip.contentOffset.x, offsetBefore.x, "\(shown.name): a swipe scrolls the colours past the edge.")
            }
            window.isHidden = true
            window.rootViewController = nil
            self.window = nil
        }
        let summary = XCTAttachment(string: report.joined(separator: "\n"))
        summary.name = "Strips by window"
        summary.lifetime = .keepAlways
        add(summary)
    }
}
#endif
