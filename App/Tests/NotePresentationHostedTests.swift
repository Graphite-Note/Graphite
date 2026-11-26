/**
 * File: NotePresentationHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A note presented as slides in the app on the iPad simulator: finger swipes and taps move between its
 *              slides, Apple Pencil draws the laser and fading ink without moving them, and the marks show on a second
 *              screen's slide too and go when the slide changes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class NotePresentationHostedTests: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.isHidden = true
            window.rootViewController = nil
        }
        windows = []
    }

    private static let lecture = """
    # Sampling

    A signal read every $T$ seconds.

    ---

    ## Nyquist

    $$
    f_s > 2 f_{max}
    $$

    ---

    > [!note] Aliasing
    > Too slow, and frequencies fold over.

    """

    private func presentation(choosing tool: PresentationPencilTool = .laser) async throws -> NotePresentation {
        let vault = try TemporaryVault.make(prefix: "NotePresentationHosted", for: self)
        _ = try vault.writeFile("Sampling.md", text: Self.lecture)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        addTeardownBlock { try? FileManager.default.removeItem(at: vault.cacheDirectory) } // Best-effort removal of a temporary folder.
        let source = NotePresentationSource(text: Self.lecture, path: try VaultPath("Sampling.md"), root: vault.root, index: index,
                                            configuration: ReadingConfiguration())
        let presentation = NotePresentation.started(from: source, clock: LiveApplicationClock(),
                                                    pencil: PresentationPencilChoices(tool: tool, inkColor: .red, laserStyle: .line))
        try await waitUntil("every slide is built") {
            presentation.slides.allSatisfy { content in if case .built = content { true } else { false } }
        }
        return presentation
    }

    /// A window of the 11-inch iPad's size in landscape, showing `content`.
    private func show(_ content: some View) async throws -> UIWindow {
        try await waitUntil("the app's scene is connected") { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1_194, height: 834)
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        windows.append(window)
        window.layoutIfNeeded()
        return window
    }

    private func touchSurface(in window: UIWindow) throws -> PresentationTouchSurfaceView {
        func search(_ view: UIView) -> PresentationTouchSurfaceView? {
            if let surface = view as? PresentationTouchSurfaceView { return surface }
            for subview in view.subviews { if let found = search(subview) { return found } }
            return nil
        }
        return try XCTUnwrap(search(window), "The slide's touch surface is shown.")
    }

    private func marksLayers(in window: UIWindow) -> [PresentationMarksView] {
        func search(_ view: UIView) -> [PresentationMarksView] {
            (view as? PresentationMarksView).map { layerView in [layerView] } ?? view.subviews.flatMap(search)
        }
        return search(window)
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The simulator always makes touches; a missing one is a failure here, not a reason to skip.
    private func requireTouches() throws {
        XCTAssertNil(SynthesizedTouches.unavailableReason)
        guard SynthesizedTouches.unavailableReason == nil else { throw SynthesizedTouchesUnavailable() }
    }

    private struct SynthesizedTouchesUnavailable: Error {}

    private func swipe(in window: UIWindow, from start: CGPoint, to end: CGPoint) async {
        await SynthesizedTouches(window: window).drag(from: start, to: end, steps: 6, stepSeconds: 0.012, holdSeconds: 0)
    }

    private func tap(at point: CGPoint, in window: UIWindow) async {
        await SynthesizedTouches(window: window).move(paths: [(point, point)], steps: 1, stepSeconds: 0.03, holdSeconds: 0)
    }

    func testFingerSwipesAndTapsMoveBetweenTheSlides() async throws {
        try requireTouches()
        let presentation = try await presentation()
        let window = try await show(NotePresentationScreen(presentation: presentation, end: {}))
        let surface = try touchSurface(in: window)
        let frame = surface.convert(surface.bounds, to: window)
        XCTAssertGreaterThan(frame.width, 1_000, "The slide fills the screen: \(frame)")
        attachScreenshot(of: window, named: "First slide")

        await swipe(in: window, from: CGPoint(x: frame.maxX - 200, y: frame.midY), to: CGPoint(x: frame.minX + 200, y: frame.midY))
        try await waitUntil("a swipe to the left shows the second slide") { presentation.position.index == 1 }
        attachScreenshot(of: window, named: "Second slide after a swipe")

        await tap(at: CGPoint(x: frame.midX + 200, y: frame.midY), in: window)
        try await waitUntil("a tap on the right shows the third slide") { presentation.position.index == 2 }
        await tap(at: CGPoint(x: frame.maxX - 40, y: frame.midY), in: window)
        await swipe(in: window, from: CGPoint(x: frame.minX + 200, y: frame.midY), to: CGPoint(x: frame.maxX - 200, y: frame.midY))
        try await waitUntil("a swipe to the right goes back, past the last slide's tap") { presentation.position.index == 1 }

        await tap(at: CGPoint(x: frame.minX + 60, y: frame.midY), in: window)
        try await waitUntil("a tap on the left quarter goes back") { presentation.position.index == 0 }
        XCTAssertEqual(presentation.moveCount, 4)
    }

    func testThePencilDrawsOnEveryScreenWithoutMovingAndTheMarksGoWithTheSlide() async throws {
        try requireTouches()
        XCTAssertTrue(SynthesizedTouches.canMakePencilTouches, "UIKit lets a made touch be marked as Apple Pencil's.")
        for tool in PresentationPencilTool.allCases {
            let presentation = try await presentation(choosing: tool)
            let window = try await show(NotePresentationScreen(presentation: presentation, end: {}))
            // A second screen, as an external display shows it.
            let audienceWindow = try await show(AudienceSlideView(presentation: presentation))
            let surface = try touchSurface(in: window)
            let frame = surface.convert(surface.bounds, to: window)
            let pencil = SynthesizedTouches(window: window, touchType: .pencil)
            await pencil.drag(from: CGPoint(x: frame.midX - 150, y: frame.midY), to: CGPoint(x: frame.midX + 150, y: frame.midY + 60),
                              steps: 20, holdSeconds: 0)
            XCTAssertEqual(presentation.position.index, 0, "The Pencil never moves the slides (\(tool)).")
            XCTAssertTrue(surface.marksLayer.showsMarks, "The device's slide shows the \(tool) mark.")
            XCTAssertEqual(surface.marksLayer.showsInk, tool == .fadingInk, "The \(tool) draws as itself.")
            let audienceLayers = marksLayers(in: audienceWindow)
            XCTAssertEqual(audienceLayers.count, 1)
            XCTAssertTrue(audienceLayers.allSatisfy(\.showsMarks), "The other screen's slide shows the \(tool) mark too.")
            attachScreenshot(of: window, named: "\(tool.title) on the device")
            attachScreenshot(of: audienceWindow, named: "\(tool.title) on the other screen")
            presentation.move(.next)
            XCTAssertFalse(surface.marksLayer.showsMarks, "Changing slides clears the \(tool) mark.")
            XCTAssertFalse(audienceLayers.contains(where: \.showsMarks), "On every screen.")
            presentation.end()
            for shown in windows { shown.isHidden = true }
            windows = []
        }
    }

    func testWithAnotherDisplayTheDeviceShowsThePresentersViewAndBackWithout() async throws {
        let presentation = try await presentation()
        let window = try await show(NotePresentationScreen(presentation: presentation, end: {}))
        presentation.setAudienceDisplay(isShown: true)
        try await waitUntil("the presenter's view leaves room for the next slide and the time") {
            let width = (try? self.touchSurface(in: window))?.bounds.width ?? 0
            return width > 0 && width < window.bounds.width - 300
        }
        attachScreenshot(of: window, named: "Presenter's view")
        presentation.move(.last)
        attachScreenshot(of: window, named: "Presenter's view on the last slide")
        presentation.setAudienceDisplay(isShown: false)
        try await waitUntil("the slide alone again") { (try? self.touchSurface(in: window))?.bounds.width ?? 0 > 1_000 }
        XCTAssertEqual(presentation.position.index, 2, "Switching views keeps the slide.")
        attachScreenshot(of: window, named: "Slide alone after the display went")
    }
}
#endif
