/**
 * File: GuideMacScreenshotsTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Takes the Graphite Guide's pictures of the Mac app in the dark appearance, from the guide vault itself,
 *              in Graphite's window as the release pass shows it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import GraphiteCore
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
@testable import GraphiteUI

/// Docs/Guide-vault-todo.md, section 2: the guide's pictures of the Mac in the dark appearance, taken from
/// `Guide/Graphite Guide` in the release pass's window (`ReleaseVaultPass`) with Graphite's own Base Color Scheme set to
/// Dark, so they show Graphite as it is now and can be taken again after it changes. Runs only with
/// `GRAPHITE_GUIDE_SCREENSHOTS` naming a folder, where each picture is written as a JPEG; it checks nothing else.
@MainActor
final class GuideMacScreenshotsTests: XCTestCase {
    static let folderVariable = "GRAPHITE_GUIDE_SCREENSHOTS"

    private struct Shot {
        let name: String
        let file: String
        let view: NoteViewMode?
    }

    private let shots = [
        Shot(name: "Mac - A drawing in a note, dark", file: "6 Everyday examples/Everyday Electronics/Week 2 - Capacitors.md", view: .livePreview),
        Shot(name: "Mac - Recipes gallery, dark", file: "6 Everyday examples/Recipes/Recipes.base", view: nil),
    ]

    func testTakeTheGuidesDarkMacPictures() async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let folder = ProcessInfo.processInfo.environment[Self.folderVariable] else { return }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let pass = try await ReleaseVaultPass.open(for: self, vault: FixtureFolders.guideVault)
        pass.workspace.preferences.appearanceMode = .dark
        // A second of a quiet main thread after each change: pictures load and diagrams draw off it, then arrive on it.
        let quietWatch = MainThreadQuietWatch(window: pass.window, quietStepsToStop: 200)
        for shot in shots {
            _ = await pass.workspace.open(try VaultPath(shot.file), placement: .currentTab)
            _ = try await quietWatch.measure({}, until: { pass.workspace.activeDocument.loadedPath?.rawValue == shot.file })
            if let view = shot.view {
                let session = try XCTUnwrap(pass.workspace.markdownSession, shot.file)
                _ = try await quietWatch.measure({ session.viewMode = view })
            }
            let png = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: pass.window))
            let image = try XCTUnwrap(NSBitmapImageRep(data: png))
            let jpeg = try XCTUnwrap(image.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.62]))
            try jpeg.write(to: output.appendingPathComponent("\(shot.name).jpg"))
        }
    }
}
#endif
