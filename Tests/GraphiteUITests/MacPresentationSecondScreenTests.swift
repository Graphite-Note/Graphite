/**
 * File: MacPresentationSecondScreenTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: A presentation on the Mac with a second screen connected during the talk: the slide goes to the
 *              screen Graphite's window is not on, the presenter's view fills the other, and removing the screen
 *              gives the slide back to the first without stopping. Runs only with GRAPHITE_MAC_SECOND_SCREEN set to
 *              a folder, where it writes its pictures and asks, through files, the shell running it to add and
 *              remove a screen (a virtual display on a Mac with one screen).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class MacPresentationSecondScreenTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_SECOND_SCREEN"

    private static let lecture = "# Sampling\n\nA signal read every $T$ seconds.\n\n---\n\n## Nyquist\n\n$$\nf_s > 2 f_{max}\n$$\n\n---\n\n## Bits\n\nEach sample becomes a number.\n"

    /// Leaves a file named `name` in `folder` for the shell running the check.
    private func signal(_ name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    /// Waits for the shell running the check to leave a file named `name` in `folder`.
    private func waitForSignal(_ name: String, in folder: URL) async throws {
        try await waitUntil("the shell's \(name)", timeoutSeconds: 60) { FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) }
    }

    private func save(_ window: NSWindow, named name: String, in folder: URL) throws {
        let view = try XCTUnwrap(window.contentView)
        view.layoutSubtreeIfNeeded()
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        try representation.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
    }

    /// Hands AppKit's pending events to the application, as its run loop would: a package test runs none, and a
    /// screen connected or removed reaches `NSScreen.screens` and the screens notification only through them.
    private func handPendingEvents() {
        while let event = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
    }

    private static func shownPresentationWindow(on screen: NSScreen) -> NSWindow? {
        NSApp.windows.first { window in window is MacPresentationWindow && window.isVisible && window.screen == screen }
    }

    func testASecondScreenConnectedDuringATalkTakesTheSlideAndItsRemovalGivesItBack() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        let folder = URL(fileURLWithPath: outputPath)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        XCTAssertEqual(NSScreen.screens.count, 1, "The check starts with one screen.")
        let vault = try TemporaryVault.make(prefix: "MacPresentationSecondScreen", for: self)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        let source = NotePresentationSource(text: Self.lecture, path: try VaultPath("Sampling.md"), root: vault.root, index: index,
                                            configuration: ReadingConfiguration())
        let presentation = NotePresentation.started(from: source, clock: LiveApplicationClock(),
                                                    pencil: PresentationPencilChoices(tool: .laser, inkColor: .red, laserStyle: .dot))
        try await waitUntil("every slide is built") { presentation.slides.allSatisfy { content in if case .built = content { true } else { false } } }

        var hasEnded = false
        let appearance = PresentationAppearance(noteTheme: nil, typography: .standard, codeColorTheme: .obsidian, accent: .blue, colorScheme: .light)
        let windows = MacPresentationWindows(presentation: presentation, appearance: appearance, end: { hasEnded = true })
        let screen = try XCTUnwrap(NSScreen.screens.first)
        windows.show(mainScreen: screen)
        defer { windows.close() }
        let presenter = try XCTUnwrap(Self.shownPresentationWindow(on: screen))
        XCTAssertFalse(presentation.hasAudienceDisplay, "With one screen, the slide alone.")
        presentation.move(.next)
        try save(presenter, named: "1 One screen, the slide alone", in: folder)

        try signal("connect-screen", in: folder)
        try await waitUntil("a second screen is connected", timeoutSeconds: 30) { handPendingEvents(); return NSScreen.screens.count == 2 }
        try await waitUntil("the slide goes on the second screen", timeoutSeconds: 10) { handPendingEvents(); return presentation.hasAudienceDisplay }
        let otherScreen = try XCTUnwrap(NSScreen.screens.first { candidate in candidate != screen })
        let audience = try XCTUnwrap(Self.shownPresentationWindow(on: otherScreen), "A window covers the second screen.")
        XCTAssertEqual(audience.frame, otherScreen.frame, "The slide fills the screen Graphite's window is not on.")
        XCTAssertEqual(presenter.frame, screen.frame, "The presenter's view fills the other.")
        XCTAssertEqual(presentation.position.index, 1, "The talk goes on at its slide.")
        XCTAssertFalse(hasEnded)
        try save(presenter, named: "2 Presenter view on the first screen", in: folder)
        try save(audience, named: "2 Slide on the second screen", in: folder)
        try signal("capture-two-screens", in: folder)
        try await waitForSignal("captured-two-screens", in: folder)

        presentation.move(.next)
        try save(audience, named: "3 Third slide on the second screen", in: folder)

        try signal("remove-screen", in: folder)
        try await waitUntil("the second screen is removed", timeoutSeconds: 30) { handPendingEvents(); return NSScreen.screens.count == 1 }
        try await waitUntil("the slide comes back to the first screen", timeoutSeconds: 10) { handPendingEvents(); return !presentation.hasAudienceDisplay }
        XCTAssertFalse(audience.isVisible)
        XCTAssertEqual(presenter.frame, screen.frame)
        XCTAssertEqual(presentation.position.index, 2, "The talk goes on at its slide.")
        XCTAssertFalse(hasEnded, "Removing a screen does not end the talk.")
        try save(presenter, named: "4 Screen removed, the slide alone again", in: folder)
        try FileManager.default.removeItem(at: vault.cacheDirectory)
    }
}
#endif
