/**
 * File: MacPresentationWindows.swift
 * ----------------------------------
 * Layer: UI
 * Description: A presented note on the Mac: a window over the whole screen with the slide, and with a second
 *              screen the slide on the screen Graphite's window is not on and the presenter's view on the other.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import GraphiteCore

/// Which screen shows what on the Mac (decision 8): with one screen, the slide; with more, the presenter's view
/// on the screen of Graphite's window and the slide on the first other screen.
struct MacPresentationScreenPlan: Equatable {
    /// The index, among the screens, of the screen that shows the device's view (the slide, or the presenter's
    /// view when `audienceScreenIndex` is set).
    let presenterScreenIndex: Int
    let audienceScreenIndex: Int?

    /// - Parameter mainScreenIndex: The screen of Graphite's window, or nil when it is not known.
    init?(screenCount: Int, mainScreenIndex: Int?) {
        guard screenCount > 0 else { return nil }
        let presenterIndex = mainScreenIndex.flatMap { index in (0..<screenCount).contains(index) ? index : nil } ?? 0
        presenterScreenIndex = presenterIndex
        audienceScreenIndex = (0..<screenCount).first { index in index != presenterIndex }
    }
}

/// The windows of a presentation on the Mac, made when it starts and closed when it ends. Each covers a whole
/// screen with the menu bar and the Dock hidden; the presenter's window takes the keyboard.
@MainActor
final class MacPresentationWindows {
    private weak var presentation: NotePresentation?
    private let appearance: PresentationAppearance
    private let end: () -> Void
    private var presenterWindow: MacPresentationWindow?
    private var audienceWindow: MacPresentationWindow?
    private var screensObservation: NotificationObservation?
    private var optionsBeforePresenting: NSApplication.PresentationOptions = []

    init(presentation: NotePresentation, appearance: PresentationAppearance, end: @escaping () -> Void) {
        self.presentation = presentation
        self.appearance = appearance
        self.end = end
    }

    /// Covers the screens, `mainScreen` being the one of the window that started the presentation.
    func show(mainScreen: NSScreen?) {
        optionsBeforePresenting = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        arrange(mainScreen: mainScreen)
        screensObservation = NotificationObservation(name: NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            Task { @MainActor in self?.arrange(mainScreen: self?.presenterWindow?.screen) }
        }
    }

    func close() {
        screensObservation = nil
        for window in [presenterWindow, audienceWindow].compactMap({ window in window }) { window.orderOut(nil) }
        presenterWindow = nil
        audienceWindow = nil
        NSApp.presentationOptions = optionsBeforePresenting
        presentation?.setAudienceDisplay(isShown: false)
    }

    /// Puts each window on its screen, as the screens are now: a screen connected or removed during a talk
    /// switches between the slide alone and the presenter's view without stopping it.
    private func arrange(mainScreen: NSScreen?) {
        guard let presentation, !presentation.hasEnded else { return }
        let screens = NSScreen.screens
        guard let plan = MacPresentationScreenPlan(screenCount: screens.count,
                                                   mainScreenIndex: mainScreen.flatMap { screen in screens.firstIndex(of: screen) }) else { return }
        let presenter = presenterWindow ?? makeWindow(NotePresentationScreen(presentation: presentation, end: end))
        presenterWindow = presenter
        cover(screens[plan.presenterScreenIndex], with: presenter)
        if let audienceIndex = plan.audienceScreenIndex {
            let audience = audienceWindow ?? makeWindow(AudienceSlideView(presentation: presentation))
            audienceWindow = audience
            cover(screens[audienceIndex], with: audience)
            audience.orderFront(nil)
        } else {
            audienceWindow?.orderOut(nil)
            audienceWindow = nil
        }
        presentation.setAudienceDisplay(isShown: audienceWindow != nil)
        presenter.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(_ content: some View) -> MacPresentationWindow {
        let window = MacPresentationWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .black
        window.contentView = MacPresentationHostingView(rootView: AnyView(content.presentationEnvironment(appearance)))
        window.appearance = NSAppearance(named: appearance.colorScheme == .dark ? .darkAqua : .aqua)
        window.endPresentation = end
        return window
    }

    private func cover(_ screen: NSScreen, with window: NSWindow) {
        window.setFrame(screen.frame, display: true)
    }
}

/// The view a presentation window shows its slide in. A click on the slide goes forward even while Graphite is not
/// the active app, as when the presenter last clicked another app, instead of only bringing Graphite forward.
final class MacPresentationHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless window over a whole screen that takes the keyboard, which a borderless window does not by
/// default, so the presentation's keys reach it.
final class MacPresentationWindow: NSWindow {
    /// Escape ends the presentation even before SwiftUI's focus has reached the slide.
    var endPresentation: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        endPresentation?()
    }
}
#endif
