/**
 * File: PageLookMacWindowTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: Icons, covers and columns in a Mac window of the app: the release vault's two page look notes opened in
 *              the reading view draw a cover and icons that are gone with the core plugin off, and the Mac file list's
 *              cells show the notes' icons. Pictures are written when a folder is named.
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
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif
@testable import GraphiteUI

/// With `GRAPHITE_PAGE_LOOK_PICTURES` naming a folder, each picture of the window is written there as a PNG.
@MainActor
final class PageLookMacWindowTests: XCTestCase {
    private static let folderVariable = "GRAPHITE_PAGE_LOOK_PICTURES"

    private func makeVault() throws -> URL {
        let release = FixtureFolders.releaseVault
        let vault = try TemporaryVault.make(prefix: "PageLookMac", files: [
            "Courses/Page look.md": try String(contentsOf: release.appendingPathComponent("Page look.md"), encoding: .utf8),
            "Courses/Page look linked.md": try String(contentsOf: release.appendingPathComponent("Page look linked.md"), encoding: .utf8),
            "Courses/Physics/Magnetism.md": "---\nicon: 🧲\n---\n# Magnetism\n",
            "Courses/Physics/Optics.md": "# Optics\n",
        ], for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: release.appendingPathComponent("Attachments/Sunset over hills.png"),
                                         to: vault.appendingPathComponent("Attachments/Sunset over hills.png"))
        return vault
    }

    private func save(_ picture: Data, named name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment[Self.folderVariable] else { return }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try picture.write(to: output.appendingPathComponent("mac-\(name).png"))
    }

    private func fileTreeCells(in view: NSView) -> [FileTreeCellView] {
        ((view as? FileTreeCellView).map { [$0] } ?? []) + view.subviews.flatMap(fileTreeCells)
    }

    /// A picture of `view` in an invisible borderless window of `size`, once the main thread is quiet.
    private func windowPicture(of view: some View, size: CGSize) async throws -> Data {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        window.showInvisibly()
        defer { window.close() }
        _ = try await MainThreadQuietWatch(window: window, quietStepsToStop: 100).measure({})
        let contentView = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds))
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    /// The rows whose cell shows an image before its name; the conflict mark sits at the cell's other end.
    private func rowsShowingAnIcon(in view: NSView) -> Int {
        fileTreeCells(in: view).filter { cell in
            cell.subviews.contains { subview in
                guard let imageView = subview as? NSImageView else { return false }
                return !imageView.isHidden && imageView.image != nil && imageView.frame.minX < 10
            }
        }.count
    }

    /// How many sampled pixels of the window's top band differ between two pictures of it.
    private func differingPixels(inTopBandOf first: Data, and second: Data) throws -> Int {
        func pixels(_ picture: Data) throws -> [UInt8] {
            let image = try XCTUnwrap(NSBitmapImageRep(data: picture)?.cgImage)
            let width = 160, height = 60
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let band = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: image.height * 2 / 5)))
            context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: height))
            return bytes
        }
        let firstPixels = try pixels(first), secondPixels = try pixels(second)
        return stride(from: 0, to: firstPixels.count, by: 4).filter { index in abs(Int(firstPixels[index]) - Int(secondPixels[index])) > 24 }.count
    }

    func testTheReadingViewDrawsTheCoverAndTheFileListTheIconsWhileThePluginIsOn() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .list
        try await workspace.openFolderAsVault(try makeVault())
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        workspace.expandedFolders.formUnion([try VaultPath("Courses"), try VaultPath("Courses/Physics")])
        await workspace.open(try VaultPath("Courses/Page look linked.md"), placement: .currentTab)
        await workspace.open(try VaultPath("Courses/Page look.md"), placement: .newTab)
        try XCTUnwrap(workspace.markdownSession).viewMode = .reading
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        let quietWatch = MainThreadQuietWatch(window: window, quietStepsToStop: 200)
        _ = try await quietWatch.measure({}, until: { self.fileTreeCells(in: window.contentView ?? NSView()).count >= 6 })

        let drawnTitles = fileTreeCells(in: try XCTUnwrap(window.contentView)).map(\.drawnTitle.string)
        XCTAssertTrue(drawnTitles.contains { title in title.hasPrefix("Magnetism") }, "\(drawnTitles)")
        XCTAssertEqual(rowsShowingAnIcon(in: try XCTUnwrap(window.contentView)), 3, "Page look, Page look linked and Magnetism have an icon; Optics and the folders have none.")

        let on = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        try save(on, named: "light")
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .livePreview
        _ = try await quietWatch.measure({})
        try save(try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window)), named: "live-preview-light")
        session.viewMode = .reading
        _ = try await quietWatch.measure({})
        workspace.setCorePluginEnabled(.pageLook, false)
        _ = try await quietWatch.measure({})
        let off = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        try save(off, named: "light-plugin-off")
        XCTAssertGreaterThan(try differingPixels(inTopBandOf: on, and: off), 300, "The cover is drawn only while the plugin is on.")
        XCTAssertEqual(rowsShowingAnIcon(in: try XCTUnwrap(window.contentView)), 0, "Off, no row shows an icon.")
    }

    func testTheQuickSwitcherListsANotesIconAndThePickerItsSymbols() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault())
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        await workspace.open(try VaultPath("Courses/Physics/Magnetism.md"), placement: .currentTab)
        await workspace.open(try VaultPath("Courses/Physics/Optics.md"), placement: .currentTab)
        await workspace.open(try VaultPath("Courses/Page look.md"), placement: .currentTab)
        let catalog = NoteIconCatalog()
        await catalog.reload(from: workspace.index)
        XCTAssertEqual(catalog.icon(of: try VaultPath("Courses/Physics/Magnetism.md")), .emoji("🧲"))

        func switcherPicture(icons: NoteIconCatalog?) async throws -> Data {
            try await windowPicture(of: QuickSwitcher(workspace: workspace) {}.environment(\.noteIcons, icons), size: CGSize(width: 620, height: 320))
        }
        let withIcons = try await switcherPicture(icons: catalog)
        try save(withIcons, named: "quick-switcher")
        let withoutIcons = try await switcherPicture(icons: nil)
        XCTAssertNotEqual(withIcons, withoutIcons, "The recent notes' rows show their icons.")

        let pickerPicture = try await windowPicture(of: NoteIconPicker(currentIcon: .symbol(systemName: "atom")) { _ in }, size: CGSize(width: 340, height: 400))
        try save(pickerPicture, named: "icon-picker")
        let emptyPicture = try await windowPicture(of: Color.clear, size: CGSize(width: 340, height: 400))
        XCTAssertNotEqual(pickerPicture, emptyPicture)
        XCTAssertEqual(NoteIconPicker.spokenName(ofLucideName: "GraduationCap"), "Graduation Cap")
    }
}
#endif
