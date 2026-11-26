/**
 * File: MacPresentationInAppHostedTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A note presented in the running Mac app: the presentation's window covers the screen with the menu bar
 *              and the Dock hidden, keys posted through the app's event queue move between the slides, a click goes
 *              forward, Escape ends it and gives the screen back. Runs only with TEST_RUNNER_GRAPHITE_MAC_PRESENTATION
 *              given to xcodebuild as a folder, where it writes its pictures.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class MacPresentationInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_PRESENTATION"

    private static let lecture = """
    # Sampling a signal

    A continuous signal is read every **T** seconds, at the sampling rate $f_s = 1/T$.

    ---

    ## Nyquist

    $$
    f_s > 2 f_{max}
    $$

    ---

    ```mermaid
    flowchart LR
        Signal --> Sampler --> Quantizer --> Bits
    ```

    """

    private func save(_ window: NSWindow, named name: String, in folder: URL) throws {
        let view = try XCTUnwrap(window.contentView)
        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        try representation.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
    }

    private func post(key keyCode: UInt16, characters: String, to window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, characters: characters,
                                               charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    /// A click as a person makes it: the button pressed, held a moment, then let go.
    private func click(at point: CGPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            NSApp.postEvent(event, atStart: false)
            let pressedAt = ContinuousClock.now
            try await waitUntil("the press is held", timeoutSeconds: 1) { ContinuousClock.now - pressedAt > .milliseconds(80) }
        }
    }

    func testThePresentationCoversTheScreenMovesWithKeysAndClicksAndEndsWithEscape() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return }
        let folder = URL(fileURLWithPath: outputPath)
        let vault = try TemporaryVault.make(prefix: "MacPresentationInApp", for: self)
        _ = try vault.writeFile("Sampling.md", text: Self.lecture)
        let index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        addTeardownBlock { try? FileManager.default.removeItem(at: vault.cacheDirectory) } // Best-effort removal of a temporary folder.
        let source = NotePresentationSource(text: Self.lecture, path: try VaultPath("Sampling.md"), root: vault.root, index: index,
                                            configuration: ReadingConfiguration())
        let presentation = NotePresentation.started(from: source, clock: LiveApplicationClock(),
                                                    pencil: PresentationPencilChoices(tool: .laser, inkColor: .red, laserStyle: .dot))
        try await waitUntil("every slide is built") { presentation.slides.allSatisfy { content in if case .built = content { true } else { false } } }

        var hasEnded = false
        let optionsBefore = NSApp.presentationOptions
        let windows = MacPresentationWindows(presentation: presentation,
                                             appearance: PresentationAppearance(noteTheme: nil, typography: .standard, codeColorTheme: .obsidian,
                                                                                accent: .blue, colorScheme: .dark),
                                             end: { hasEnded = true })
        let screen = try XCTUnwrap(NSScreen.main)
        windows.show(mainScreen: screen)
        defer { windows.close() }
        let presenter = try XCTUnwrap(NSApp.windows.first { window in window is MacPresentationWindow && window.screen == screen && window.isVisible })
        XCTAssertEqual(presenter.frame, screen.frame, "The window covers the whole screen.")
        XCTAssertTrue(NSApp.presentationOptions.contains(.hideMenuBar))
        XCTAssertEqual(presentation.hasAudienceDisplay, NSScreen.screens.count > 1)
        try await waitUntil("the window draws the slide") { presenter.contentView?.subviews.isEmpty == false }
        try save(presenter, named: "1 First slide", in: folder)

        presenter.makeKey()
        post(key: 124, characters: "\u{F703}", to: presenter)
        try await waitUntil("the right arrow shows the second slide", timeoutSeconds: 5) { presentation.position.index == 1 }
        try save(presenter, named: "2 Second slide after the right arrow", in: folder)
        post(key: 49, characters: " ", to: presenter)
        try await waitUntil("space shows the third slide", timeoutSeconds: 5) { presentation.position.index == 2 }
        try save(presenter, named: "3 Third slide after space", in: folder)
        post(key: 115, characters: "\u{F729}", to: presenter)
        try await waitUntil("Home shows the first slide", timeoutSeconds: 5) { presentation.position.index == 0 }
        if !presentation.hasAudienceDisplay {
            try await click(at: CGPoint(x: presenter.frame.width * 0.7, y: presenter.frame.height / 2), in: presenter)
            try await waitUntil("a click goes forward", timeoutSeconds: 5) { presentation.position.index == 1 }
        }
        post(key: 53, characters: "\u{1B}", to: presenter)
        try await waitUntil("Escape ends the presentation", timeoutSeconds: 5) { hasEnded }
        windows.close()
        XCTAssertEqual(NSApp.presentationOptions, optionsBefore, "The menu bar and the Dock come back.")
        XCTAssertFalse(presenter.isVisible)
    }
}
#endif
