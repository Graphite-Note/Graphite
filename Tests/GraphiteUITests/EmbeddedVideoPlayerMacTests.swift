/**
 * File: EmbeddedVideoPlayerMacTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: A video embed that starts playing shows the system player on the Mac (HUNT-398): SwiftUI's VideoPlayer
 *              subclasses AVKit's AVPlayerView, and without AVKit linked the Swift runtime aborts as it builds it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// This file imports neither AVKit nor AVFoundation and names none of their types, so the test bundle links AVKit only
/// through GraphiteUI's own linker settings, as the app does: a GraphiteUI that stops linking AVKit aborts this test.
@MainActor
final class EmbeddedVideoPlayerMacTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        try await super.tearDown()
    }

    /// The crash of TestFlight's build 20261128.1856: "failed to demangle superclass of VideoPlayerView from mangled name
    /// 'So12AVPlayerViewC'" as soon as a video embed swapped its poster for the system player.
    func testAVideoEmbedThatIsPlayingShowsTheSystemsPlayerView() async throws {
        // No file is there, so nothing can be heard; the player is built whether the file plays or not.
        let location = try TemporaryVault.make(prefix: "EmbeddedVideo", for: self).root.appendingPathComponent("Clip.mp4")
        let mediaPlayers = ReadingMediaPlayers()
        // A video that started playing earlier: the embed shows the system player in place of its poster.
        _ = mediaPlayers.playback(for: location)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        // Swift owns the window; closing it in tearDown must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EmbeddedMediaPlayer(location: location)
            .environment(\.readingMediaPlayers, mediaPlayers)
            .frame(width: 480, height: 270))
        window.showInvisibly()
        windows.append(window)

        let playerViewClass: AnyClass = try XCTUnwrap(NSClassFromString("AVPlayerView"), "AVKit is loaded, so AVPlayerView is found.")
        try await waitUntil("the embed shows AVKit's player view") {
            Self.firstView(in: window.contentView) { view in view.isKind(of: playerViewClass) } != nil
        }
    }

    private static func firstView(in view: NSView?, where matches: (NSView) -> Bool) -> NSView? {
        guard let view else { return nil }
        if matches(view) { return view }
        for subview in view.subviews {
            if let match = firstView(in: subview, where: matches) { return match }
        }
        return nil
    }
}
#endif
