/**
 * File: NotePresentationExternalDisplayHostedTests.swift
 * ------------------------------------------------------
 * Layer: Tests
 * Description: A presented note on the iPad simulator's external display: the display's scene gets the slide only
 *              while the presentation runs, the device shows the presenter's view, and the Pencil's marks and the
 *              moves reach the display. Runs only with an external display connected to the simulator
 *              (`simctl io <device> screenConfig --display=external power on`, at its 720 by 480 mode) and
 *              TEST_RUNNER_GRAPHITE_EXTERNAL_DISPLAY given to xcodebuild as a folder, where it writes its pictures.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class NotePresentationExternalDisplayHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_EXTERNAL_DISPLAY"
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private static let lecture = "# Sampling\n\nA signal read every $T$ seconds.\n\n---\n\n## Nyquist\n\n$$\nf_s > 2 f_{max}\n$$\n"

    private func externalDisplayScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }
            .filter { scene in PresentationExternalDisplays.isExternalDisplay(scene.session.role) }
    }

    private func save(_ view: UIView, named name: String, in folder: URL) throws {
        let picture = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        try picture.pngData()?.write(to: folder.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// iOS makes the external display's scene with the delegate Info.plist names; the name must reach the class.
    func testInfoPlistNamesTheDisplaySceneDelegateForTheExternalDisplayRole() throws {
        let manifest = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
        let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: [[String: Any]]])
        let displayConfiguration = try XCTUnwrap(configurations[UISceneSession.Role.windowExternalDisplayNonInteractive.rawValue]?.first)
        let className = try XCTUnwrap(displayConfiguration["UISceneDelegateClassName"] as? String)
        XCTAssertTrue(NSClassFromString(className) === PresentationDisplaySceneDelegate.self, className)
    }

    func testTheExternalDisplayShowsTheSlideOnlyWhilePresentingAndTheDeviceThePresentersView() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        let folder = URL(fileURLWithPath: outputPath)
        // The display's scene comes from the presentation's scene accessory, so none exists before.
        XCTAssertTrue(externalDisplayScenes().isEmpty, "No scene on the display before presenting.")

        let vault = try TemporaryVault.make(prefix: "NotePresentationExternalDisplay", for: self)
        _ = try vault.writeFile("Sampling.md", text: Self.lecture)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        addTeardownBlock { try? FileManager.default.removeItem(at: vault.cacheDirectory) } // Best-effort removal of a temporary folder.
        let source = NotePresentationSource(text: Self.lecture, path: try VaultPath("Sampling.md"), vault: try XCTUnwrap(ReadingVault(vault.root, index)),
                                            configuration: ReadingConfiguration())
        let presentation = NotePresentation.started(from: source, clock: LiveApplicationClock(),
                                                    pencil: PresentationPencilChoices(tool: .fadingInk, inkColor: .blue, laserStyle: .line))
        try await waitUntil("every slide is built") { presentation.slides.allSatisfy { content in if case .built = content { true } else { false } } }

        let deviceScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { scene in !PresentationExternalDisplays.isExternalDisplay(scene.session.role) })
        let deviceWindow = UIWindow(windowScene: deviceScene)
        deviceWindow.rootViewController = UIHostingController(rootView: NotePresentationScreen(presentation: presentation, end: {}))
        deviceWindow.makeKeyAndVisible()
        window = deviceWindow
        let displays = PresentationExternalDisplays(presentation: presentation,
                                                    appearance: PresentationAppearance(noteTheme: nil, typography: .standard, codeColorTheme: .obsidian,
                                                                                       accent: .blue, colorScheme: .light))
        displays.start(in: UIApplication.shared)
        try await waitUntil("the simulator's external display gets the presentation's scene", timeoutSeconds: 15) { !externalDisplayScenes().isEmpty }
        let displayScene = try XCTUnwrap(externalDisplayScenes().first)
        XCTAssertTrue(displayScene.delegate is PresentationDisplaySceneDelegate, "The scene goes to the presentation's scene delegate.")
        try await waitUntil("the display shows the slide", timeoutSeconds: 5) { presentation.hasAudienceDisplay }
        let displayWindow = try XCTUnwrap(displayScene.windows.first { shown in !shown.isHidden })
        XCTAssertEqual(displayWindow.bounds.size, displayScene.screen.bounds.size)
        try await waitUntil("the display has laid out the slide") { displayWindow.rootViewController?.view.layer.sublayers?.isEmpty == false }
        try await waitUntil("the device shows the presenter's view", timeoutSeconds: 5) {
            deviceWindow.layoutIfNeeded()
            return Self.touchSurface(in: deviceWindow) != nil
        }
        try save(deviceWindow, named: "1 Presenter view on the device", in: folder)
        try save(displayWindow, named: "1 Slide on the external display", in: folder)

        // Ink drawn on the presenter's slide shows on the display, and moving clears it there too.
        let surface = try XCTUnwrap(Self.touchSurface(in: deviceWindow))
        let frame = surface.convert(surface.bounds, to: deviceWindow)
        await SynthesizedTouches(window: deviceWindow, touchType: .pencil)
            .drag(from: CGPoint(x: frame.midX - 120, y: frame.midY), to: CGPoint(x: frame.midX + 120, y: frame.midY + 40), steps: 20, holdSeconds: 0)
        let displayMarks = try XCTUnwrap(Self.marksLayer(in: displayWindow))
        XCTAssertTrue(displayMarks.showsInk, "The presenter's ink shows on the display.")
        try save(displayWindow, named: "2 Ink on the external display", in: folder)
        presentation.move(.next)
        XCTAssertFalse(displayMarks.showsMarks)
        displayWindow.layoutIfNeeded()
        deviceWindow.layoutIfNeeded()
        try save(deviceWindow, named: "3 Second slide, presenter view", in: folder)
        try save(displayWindow, named: "3 Second slide on the external display", in: folder)

        // The presentation ends: its screen goes, the display is given back.
        displays.stop()
        deviceWindow.isHidden = true
        deviceWindow.rootViewController = nil
        XCTAssertFalse(presentation.hasAudienceDisplay)
        XCTAssertFalse(displayScene.windows.contains { shown in !shown.isHidden }, "The display is given back when the presentation ends.")
        try await waitUntil("the display's scene goes with the presentation", timeoutSeconds: 10) { externalDisplayScenes().isEmpty }
        presentation.end()
    }

    private static func touchSurface(in view: UIView) -> PresentationTouchSurfaceView? {
        (view as? PresentationTouchSurfaceView) ?? view.subviews.lazy.compactMap(touchSurface(in:)).first
    }

    private static func marksLayer(in view: UIView) -> PresentationMarksView? {
        (view as? PresentationMarksView) ?? view.subviews.lazy.compactMap(marksLayer(in:)).first
    }
}
#endif
