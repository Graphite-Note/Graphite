/**
 * File: PhoneAndLibraryLayoutHostedTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the window's layout that wait on a person in the bug hunt: a phone's file list after a
 *              rename, Library mode's top row and a folder's first row, Move to… with nowhere to go, and the black
 *              swatch of the Pencil bar in dark appearance with the size of its buttons.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// The whole window, found by what an assistive technology reads, on the iPad simulator; a compact width stands in
/// for an iPhone. Nothing here plays sound or shows anything on a screen a person looks at.
@MainActor
final class PhoneAndLibraryLayoutHostedTests: SettingsHostedTestCase {
    private func makeVault(files: [String: String]) throws -> URL {
        try TemporaryVault.make(prefix: "PhoneAndLibraryHosted", files: files, for: self).root
    }

    private func texts(of object: NSObject) -> [String] {
        [object.accessibilityLabel, object.accessibilityValue].compactMap { $0 }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first element of what the window presents over its root (a sheet), not of the root itself.
    private func presentedElement(in controller: UIViewController, _ description: String, matching matches: @escaping (NSObject) -> Bool) async throws -> NSObject {
        var found: NSObject?
        try await waitUntil(description, timeoutSeconds: 10) {
            var shown = controller.presentedViewController
            while let current = shown, found == nil {
                found = self.accessibilityElements(in: current.view).first(where: matches)
                shown = current.presentedViewController
            }
            return found != nil
        }
        if found == nil { attachWhatIsOnScreen(in: controller, named: description) }
        return try XCTUnwrap(found)
    }

    // MARK: HUNT-183: a phone's file list stays in front after a rename

    /// Whether a note's editor is on the window's screen: in a phone's single stack the document's column is either
    /// in front or out of the window.
    private func isNoteEditorShown() -> Bool {
        guard let window else { return false }
        return descendants(of: window, matching: MarkdownTextView.self).contains { editor in
            editor.window === window && !editor.isHidden && editor.convert(editor.bounds, to: window).intersection(window.bounds).width > 100
        }
    }

    func testRenamingTheOpenFileLeavesAPhonesFileListInFrontAndOpeningAFileStillShowsIt() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Old.md": "# Old\n\nText.\n", "Other.md": "Other.\n"]))
        await workspace.open(try VaultPath("Old.md"))
        _ = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 402, height: 874), horizontalSizeClass: .compact)
        try await waitUntil("the open note is in front") { self.isNoteEditorShown() }

        // Any search asked for shows the file list, as the back button does.
        workspace.searchFocusRequest += 1
        try await waitUntil("the file list comes to the front") { !self.isNoteEditorShown() }
        attachScreenshot(named: "Phone's file list before the rename")

        await workspace.rename(try VaultPath("Old.md"), to: "New")
        XCTAssertEqual(workspace.selection?.rawValue, "New.md", "The rename changed the selection, as before the fix.")
        let quietUntil = ContinuousClock.now + .seconds(2)
        var documentCameBack = false
        try await waitUntil("two seconds after the rename") {
            if self.isNoteEditorShown() { documentCameBack = true }
            return ContinuousClock.now >= quietUntil
        }
        attachScreenshot(named: "Phone's file list after the rename")
        XCTAssertFalse(documentCameBack, "A rename does not slide the document over the list the person is working in.")

        await workspace.open(try VaultPath("Other.md"))
        try await waitUntil("opening a file still shows it at once") { self.isNoteEditorShown() }
    }

    // MARK: HUNT-211, HUNT-204: Library mode on the iPad

    /// A vault in Library mode with forty notes at its root and a folder of thirty, enough for both to scroll.
    private func libraryWorkspace() async throws -> WorkspaceModel {
        var files: [String: String] = [:]
        for noteNumber in 1...40 { files[String(format: "Note %02d.md", noteNumber)] = "# Note \(noteNumber)\n" }
        for weekNumber in 1...30 { files[String(format: "Course/Week %02d.md", weekNumber)] = "# Week \(weekNumber)\n" }
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .library
        try await workspace.openFolderAsVault(try makeVault(files: files))
        return workspace
    }

    private func visibleNavigationBarHeight() -> CGFloat {
        guard let window else { return 0 }
        return descendants(of: window, matching: UINavigationBar.self)
            .filter { bar in !bar.isHidden && bar.alpha > 0.01 && bar.window === window }
            .map { bar in bar.convert(bar.bounds, to: window).intersection(window.bounds).height }
            .max() ?? 0
    }

    func testLibraryModeHasNoBandAboveItsRowAndKeepsBackAndForwardThere() async throws {
        let workspace = try await libraryWorkspace()
        let controller = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 1194, height: 834), horizontalSizeClass: .regular)
        let back = try await element(in: controller, "Back, in the library's own row") { object in
            object.accessibilityLabel == "Back" && object.accessibilityTraits.contains(.button)
        }
        _ = try await element(in: controller, "Forward, beside it") { object in object.accessibilityLabel == "Forward" && object.accessibilityTraits.contains(.button) }
        try await waitUntil("no navigation bar over the library") { self.visibleNavigationBarHeight() < 4 }
        attachScreenshot(named: "Library mode on an iPad in landscape")
        let window = try XCTUnwrap(window)
        XCTAssertLessThan(back.accessibilityFrame.minY, window.safeAreaInsets.top + 44, "Back is in the top row, not under a band of 70 points.")
    }

    /// The library's grid: the largest view that scrolls up and down.
    private func libraryGrid() -> UIScrollView? {
        guard let window else { return nil }
        return descendants(of: window, matching: UIScrollView.self)
            .filter { scrollView in scrollView.window === window && scrollView.contentSize.height > scrollView.bounds.height + 1 }
            .max { first, second in first.bounds.width * first.bounds.height < second.bounds.width * second.bounds.height }
    }

    func testAFolderOpenedInTheLibraryStartsAtItsTopWhateverTheVaultsScroll() async throws {
        let workspace = try await libraryWorkspace()
        let controller = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 1194, height: 834), horizontalSizeClass: .regular)
        let folderTile = try await element(in: controller, "the Course folder's tile") { object in
            (object.accessibilityLabel ?? "").hasPrefix("Course") && object.accessibilityTraits.contains(.button)
        }
        try await waitUntil("the vault's grid scrolls") { self.libraryGrid() != nil }
        let rootGrid = try XCTUnwrap(libraryGrid())
        // The vault's root scrolled a little, as in the report.
        rootGrid.setContentOffset(CGPoint(x: rootGrid.contentOffset.x, y: rootGrid.contentOffset.y + 120), animated: false)
        await follow(folderTile)

        _ = try await element(in: controller, "the folder is shown") { object in (object.accessibilityLabel ?? "").hasPrefix("Back to ") }
        let firstWeek = try await element(in: controller, "the folder's first tile") { object in (object.accessibilityLabel ?? "").hasPrefix("Week 01") }
        var folderGrid: UIScrollView?
        try await waitUntil("the folder's grid") {
            folderGrid = self.libraryGrid()
            return folderGrid != nil && folderGrid !== rootGrid
        }
        let grid = try XCTUnwrap(folderGrid)
        attachScreenshot(named: "Library folder opened after scrolling the vault")
        XCTAssertLessThanOrEqual(grid.contentOffset.y, -grid.adjustedContentInset.top + 1, "The folder starts at its top.")
        let gridTop = grid.convert(grid.bounds, to: nil).minY + grid.adjustedContentInset.top
        XCTAssertGreaterThanOrEqual(firstWeek.accessibilityFrame.minY, gridTop - 1, "The first row of icons is not under the header.")
    }

    // MARK: HUNT-295: Move to… with nowhere else to go

    func testMoveToWithNoOtherFolderOffersANewFolderInsteadOfAnEmptySearch() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Note.md": "x"]))
        let controller = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 1194, height: 834), horizontalSizeClass: .regular)
        workspace.fileSheet = .move(try VaultPath("Note.md"))
        _ = try await presentedElement(in: controller, "No Other Folders") { object in
            self.texts(of: object).contains { text in text.contains("No Other Folders") }
        }
        attachScreenshot(named: "Move to… with no other folder")
        let presented = try XCTUnwrap(controller.presentedViewController)
        XCTAssertFalse(accessibilityElements(in: presented.view).contains { object in self.texts(of: object).contains { text in text.contains("No Results") } },
                       "Not “No Results for” an empty search.")
        let newFolder = try await presentedElement(in: controller, "the New Folder button") { object in
            object.accessibilityLabel == "New Folder" && object.accessibilityTraits.contains(.button)
        }
        await follow(newFolder)
        try await waitUntil("the New Folder sheet, at the vault's root") {
            if case .newFolder(let directory) = workspace.fileSheet { return directory == .root }
            return false
        }
    }

    // MARK: HUNT-284: the black swatch on the dark bar

    /// The relative luminance WCAG defines, of a pixel's sRGB components from 0 to 255.
    private func luminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        func linear(_ component: UInt8) -> Double {
            let value = Double(component) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func testTheBlackSwatchShowsOnTheDarkBar() async throws {
        let toolbox = PencilToolbox(defaults: try XCTUnwrap(UserDefaults(suiteName: "DarkSwatch-\(UUID().uuidString)")))
        let width: CGFloat = 1_100
        let row = PencilToolRow(toolbox: toolbox, drawsShapes: .constant(false), addImage: {}, offersReadAloudPen: true, offersTextBoxes: true)
            .frame(width: width, height: PencilToolbarMetrics.height)
            .background(Color(uiColor: .systemBackground))
        let controller = try host(row, size: CGSize(width: width, height: 120))
        let window = try XCTUnwrap(window)
        window.overrideUserInterfaceStyle = .dark
        let swatch = try await element(in: controller, "the black swatch") { object in object.accessibilityLabel == "black" }
        let frame = swatch.accessibilityFrame
        attachScreenshot(named: "Pencil bar in dark appearance")

        let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let image = try XCTUnwrap(picture.cgImage)
        let scale = CGFloat(image.width) / window.bounds.width
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func pixelLuminance(at point: CGPoint) -> Double {
            let column = min(max(Int(point.x * scale), 0), image.width - 1)
            let row = min(max(Int(point.y * scale), 0), image.height - 1)
            let offset = (row * image.width + column) * 4
            return luminance(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
        }
        // The bar beside the swatch, and the swatch's edge: its 20-point disc and the ring on it, not the 28-point
        // ring that marks the color in use.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let bar = pixelLuminance(at: CGPoint(x: center.x, y: frame.minY + 2))
        var brightestEdge = 0.0
        for step in 0..<72 {
            let angle = Double(step) * .pi / 36
            for radius in stride(from: 8.6, through: 9.8, by: 0.3) {
                brightestEdge = max(brightestEdge, pixelLuminance(at: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))))
            }
        }
        let contrast = (max(brightestEdge, bar) + 0.05) / (min(brightestEdge, bar) + 0.05)
        XCTAssertGreaterThanOrEqual(contrast, 3, "The black swatch's ring reads on the dark bar (3 to 1, WCAG 1.4.11); without it the disc was about 1.1 to 1.")

        // HUNT-282: the colors and the widths are 36 points wide and as tall as the 44-point bar; they were 30 and 28.
        XCTAssertGreaterThanOrEqual(frame.width, 35.5, "The swatch's button is 36 points wide.")
        XCTAssertGreaterThanOrEqual(frame.height, 43.5, "And as tall as the bar.")
        for widthName in ["Fine", "Medium", "Broad"] {
            let widthButton = try await element(in: controller, "the \(widthName) width") { object in object.accessibilityLabel == widthName }
            XCTAssertGreaterThanOrEqual(widthButton.accessibilityFrame.width, 35.5, "\(widthName) is 36 points wide.")
        }
    }
}
#endif
