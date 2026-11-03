#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// A shortcut recording ends when the keyboard goes elsewhere, so the menu bar does not keep
/// giving up its shortcuts (HUNT-238).
@MainActor
final class ShortcutRecorderEndingTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.contentView = nil
        window = nil
        try await super.tearDown()
    }

    /// A recorder view in a window that is never shown.
    private func makeRecorder(finish: @escaping (ShortcutRecording) -> Void) -> (NSWindow, KeyPressCatcherView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let recorder = KeyPressCatcherView(finish: finish)
        window.contentView?.addSubview(recorder)
        self.window = window
        return (window, recorder)
    }

    func testTheRecordingEndsWhenTheWindowLosesTheKeyboard() {
        var endings: [ShortcutRecording] = []
        let (window, recorder) = makeRecorder { recording in endings.append(recording) }
        XCTAssertTrue(window.firstResponder === recorder, "The recorder takes the keyboard when it appears.")

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)

        XCTAssertEqual(endings.count, 1)
        guard case .cancelled? = endings.first else { return XCTFail("Losing the keyboard ends the recording without a shortcut.") }
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertEqual(endings.count, 1, "A recording ends once.")
    }

    func testTheRecordingEndsWhenAnotherViewTakesTheKeyboard() {
        var endings: [ShortcutRecording] = []
        let (window, _) = makeRecorder { recording in endings.append(recording) }
        let field = NSTextField()
        window.contentView?.addSubview(field)

        window.makeFirstResponder(field)

        XCTAssertEqual(endings.count, 1)
    }

    func testAnotherWindowLosingTheKeyboardDoesNotEndIt() {
        var endings = 0
        let (_, _) = makeRecorder { _ in endings += 1 }
        let otherWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.titled], backing: .buffered, defer: true)
        otherWindow.isReleasedWhenClosed = false

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: otherWindow)

        XCTAssertEqual(endings, 0)
    }
}
#endif
