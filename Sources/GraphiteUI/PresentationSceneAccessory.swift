/**
 * File: PresentationSceneAccessory.swift
 * --------------------------------------
 * Layer: UI
 * Description: Asks iOS 27 and later for an external display's scene while a presentation's screen is shown. From
 *              iOS 27, an app built with its SDK gets no scene for an AirPlay or cable display from Info.plist
 *              alone: a view controller registers a scene accessory, and the system connects the display's scene
 *              to the delegate it names while the registration lasts.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(iOS)
import SwiftUI
import UIKit

/// Registers the external display's scene accessory while the presentation's screen is on the device, so the
/// display shows the slide only during a presentation and is mirrored as before at other times. On iOS 26,
/// Info.plist's `UIWindowSceneSessionRoleExternalDisplayNonInteractive` entry gives the scene instead.
struct PresentationSceneAccessory: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PresentationSceneAccessoryController {
        PresentationSceneAccessoryController()
    }

    func updateUIViewController(_ controller: PresentationSceneAccessoryController, context: Context) {}
}

/// The view controller the accessory is registered from: registered when it appears, given back when it goes.
final class PresentationSceneAccessoryController: UIViewController {
    /// The registration, kept as an object since its type exists only from iOS 27.
    private var registration: AnyObject?

    /// Whether the external display's accessory is registered now, for tests.
    var isRegistered: Bool { registration != nil }

    override func loadView() {
        let emptyView = UIView()
        emptyView.isUserInteractionEnabled = false
        emptyView.isAccessibilityElement = false
        view = emptyView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard registration == nil, #available(iOS 27.0, *) else { return }
        let configuration = UISceneConfiguration(name: PresentationSceneAccessoryController.configurationName,
                                                 sessionRole: .windowExternalDisplayNonInteractive)
        configuration.delegateClass = PresentationDisplaySceneDelegate.self
        let accessoryRegistration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: configuration))
        accessoryRegistration.isEnabled = true
        registration = accessoryRegistration
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard #available(iOS 27.0, *), let accessoryRegistration = registration as? UISceneAccessoryRegistration else { return }
        unregisterSceneAccessory(accessoryRegistration)
        registration = nil
    }

    /// The name Info.plist gives the same configuration.
    static let configurationName = "Presentation Display"
}
#endif
