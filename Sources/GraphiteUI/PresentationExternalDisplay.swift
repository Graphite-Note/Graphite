/**
 * File: PresentationExternalDisplay.swift
 * ---------------------------------------
 * Layer: UI
 * Description: A presented note's slide on an external display of the iPad or the iPhone, through AirPlay or a
 *              cable: the display's scene is given a window only while a presentation runs, so the screen is
 *              mirrored as before at other times.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit

/// The delegate of the scene iOS makes for an external display (AirPlay or a cable), named in Info.plist under
/// `UIWindowSceneSessionRoleExternalDisplayNonInteractive`. It holds the window a presentation puts on the
/// display, and only while one runs (`PresentationExternalDisplays`); with no window, iOS mirrors the device's
/// screen there as it does for an app that takes no external display.
@objc(GraphitePresentationDisplaySceneDelegate)
public final class PresentationDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// The presentation's window on the display, or nil while none is shown there.
    public var window: UIWindow?
}

/// Puts a presentation's slide on every external display connected while it runs, and takes it off when the
/// presentation ends or the display goes (decision 8, section 4 of Docs/Present-a-note-todo.md). Made when a
/// presentation starts on the iPad or the iPhone and stopped when it ends; it tells the presentation whether a
/// display shows the slide, which turns the device's screen into the presenter's view.
@MainActor
final class PresentationExternalDisplays {
    private weak var presentation: NotePresentation?
    private let appearance: PresentationAppearance
    private weak var application: UIApplication?
    /// The scenes given a window, by their session's identifier.
    private var scenesBySessionIdentifier: [String: UIWindowScene] = [:]
    private var observations: [NotificationObservation] = []

    init(presentation: NotePresentation, appearance: PresentationAppearance) {
        self.presentation = presentation
        self.appearance = appearance
    }

    /// Shows the slide on the displays connected now and on those that connect later.
    func start(in application: UIApplication) {
        self.application = application
        observations = [UIScene.willConnectNotification, UIScene.didDisconnectNotification].map { name in
            // Read again on the next turn of the main queue, once the scene is connected or gone.
            NotificationObservation(name: name) { [weak self] _ in Task { @MainActor in self?.showOnConnectedDisplays() } }
        }
        showOnConnectedDisplays()
    }

    /// Takes the slide off every display, which mirrors the device's screen again, and stops watching.
    func stop() {
        observations = []
        for scene in scenesBySessionIdentifier.values { removeWindow(from: scene) }
        scenesBySessionIdentifier = [:]
        presentation?.setAudienceDisplay(isShown: false)
    }

    /// Whether a scene of `role` is an external display's, the only scenes a slide goes on.
    static func isExternalDisplay(_ role: UISceneSession.Role) -> Bool {
        role == .windowExternalDisplayNonInteractive
    }

    /// Gives each external display connected now a window with the slide, and forgets those that went.
    private func showOnConnectedDisplays() {
        guard let application, let presentation, !presentation.hasEnded else { return }
        let displayScenes = application.connectedScenes.compactMap { scene in scene as? UIWindowScene }
            .filter { scene in Self.isExternalDisplay(scene.session.role) }
        let connectedIdentifiers = Set(displayScenes.map(\.session.persistentIdentifier))
        for (identifier, scene) in scenesBySessionIdentifier where !connectedIdentifiers.contains(identifier) {
            removeWindow(from: scene)
            scenesBySessionIdentifier[identifier] = nil
        }
        for scene in displayScenes where scenesBySessionIdentifier[scene.session.persistentIdentifier] == nil {
            show(presentation, on: scene)
        }
        presentation.setAudienceDisplay(isShown: !scenesBySessionIdentifier.isEmpty)
    }

    private func show(_ presentation: NotePresentation, on scene: UIWindowScene) {
        let window = UIWindow(windowScene: scene)
        let slide = AudienceSlideView(presentation: presentation).presentationEnvironment(appearance)
        window.rootViewController = UIHostingController(rootView: slide)
        window.overrideUserInterfaceStyle = appearance.userInterfaceStyle
        window.isHidden = false
        (scene.delegate as? PresentationDisplaySceneDelegate)?.window = window
        scenesBySessionIdentifier[scene.session.persistentIdentifier] = scene
    }

    private func removeWindow(from scene: UIWindowScene) {
        for window in scene.windows { window.isHidden = true }
        (scene.delegate as? PresentationDisplaySceneDelegate)?.window = nil
    }
}
#endif

/// The slide as the audience sees it on another display: the slide alone, with the Pencil's marks drawn over it
/// where the presenter makes them.
struct AudienceSlideView: View {
    let presentation: NotePresentation

    var body: some View {
        NoteSlideView(content: presentation.currentSlide, root: presentation.root)
            #if canImport(UIKit)
            .overlay { PresentationMarksLayer(presentation: presentation) }
            #endif
            .ignoresSafeArea()
    }
}

#if canImport(UIKit)
/// The layer the Pencil's marks are drawn in on a screen that takes no touches.
private struct PresentationMarksLayer: UIViewRepresentable {
    let presentation: NotePresentation

    func makeUIView(context: Context) -> PresentationMarksView {
        let layerView = PresentationMarksView(idleClock: presentation.clock)
        presentation.marks.register(layerView)
        return layerView
    }

    func updateUIView(_ layerView: PresentationMarksView, context: Context) {}

    static func dismantleUIView(_ layerView: PresentationMarksView, coordinator: ()) {
        // The registration is weak: a dismantled layer drops out of the marks by itself.
    }
}
#endif
