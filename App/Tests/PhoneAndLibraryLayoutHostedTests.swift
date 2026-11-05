/**
 * File: PhoneAndLibraryLayoutHostedTests.swift
 * --------------------------------------------
 * Layer: Tests
 * Description: Hosted tests of the window's layout that wait on a person in the bug hunt: a phone's file list after a
 *              rename, Library mode's top row and a folder's first row, Move to… with nowhere to go, and the black
 *              swatch of the Pencil bar in dark appearance with the size of its buttons.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 05/11/2026
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

    /// What a device run prints of the phone's stack: whether the split view is one stack, and where the note is.
    private func describePhoneStack(in controller: UIViewController, _ moment: String) {
        func splitViews(in parent: UIViewController) -> [UISplitViewController] {
            ((parent as? UISplitViewController).map { [$0] } ?? []) + parent.children.flatMap(splitViews)
        }
        let collapsed = splitViews(in: controller).map { split in split.isCollapsed ? "collapsed" : "not collapsed" }
        let editorFrames = window.map { window in
            descendants(of: window, matching: MarkdownTextView.self).filter { editor in editor.window === window }.map { editor in editor.convert(editor.bounds, to: window) }
        } ?? []
        print("PhoneAndLibraryLayoutHostedTests rename, \(moment): split view \(collapsed), note's editor at \(editorFrames), window \(window?.bounds ?? .null)")
    }

    func testRenamingTheOpenFileLeavesAPhonesFileListInFrontAndOpeningAFileStillShowsIt() async throws {
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(try makeVault(files: ["Old.md": "# Old\n\nText.\n", "Other.md": "Other.\n"]))
        await workspace.open(try VaultPath("Old.md"))
        let controller = try host(GraphiteRootView(workspace: workspace), size: CGSize(width: 402, height: 874), horizontalSizeClass: .compact)
        try await waitUntil("the open note is in front") { self.isNoteEditorShown() }
        // The split view collapses to one stack and shows the note during the window's first layout passes; a request
        // for the file list made in the same moment, as before, was taken while that was under way and nothing moved.
        // A person asks once the note is on the screen and still.
        var lastEditorFrame = CGRect.null
        var unchangedPolls = 0
        try await waitUntil("the note has settled in front") {
            guard let window = self.window,
                  let editor = self.descendants(of: window, matching: MarkdownTextView.self).first(where: { editor in editor.window === window }) else { return false }
            let frame = editor.convert(editor.bounds, to: window)
            unchangedPolls = frame == lastEditorFrame ? unchangedPolls + 1 : 0
            lastEditorFrame = frame
            return unchangedPolls >= 15
        }

        describePhoneStack(in: controller, "the note in front")
        // Any search asked for shows the file list, as the back button does. The list's selection slid the note back
        // over it while the note was open (HUNT-183): it now marks the open file only while the note is in front.
        workspace.searchFocusRequest += 1
        try await waitUntil("the file list comes to the front") { !self.isNoteEditorShown() }
        describePhoneStack(in: controller, "the file list in front")
        attachScreenshot(named: "Phone's file list before the rename")

        // A rename plans its link updates from the index, as in the workspace's own tests of it.
        try await waitUntil("the vault is indexed") { workspace.hasCompletedIndexScan }
        await workspace.rename(try VaultPath("Old.md"), to: "New")
        XCTAssertEqual(workspace.selection?.rawValue, "New.md", "The rename changed the selection, as before the fix.")
        let quietUntil = ContinuousClock.now + .seconds(2)
        var documentCameBack = false
        try await waitUntil("two seconds after the rename") {
            if self.isNoteEditorShown() { documentCameBack = true }
            return ContinuousClock.now >= quietUntil
        }
        attachScreenshot(named: "Phone's file list after the rename")
        describePhoneStack(in: controller, "two seconds after the rename, the note came back: \(documentCameBack)")
        XCTAssertFalse(documentCameBack, "A rename does not slide the document over the list the person is working in.")

        await workspace.open(try VaultPath("Other.md"))
        try await waitUntil("opening a file still shows it at once") { self.isNoteEditorShown() }
    }

    // MARK: HUNT-211, HUNT-204: Library mode on the iPad

    /// A vault in Library mode with forty notes at its root and a folder of sixty, enough for both to scroll in an iPad's
    /// window held either way. The
    /// vault is a folder with a name as a person gives one, "Lectures": the temporary folder's name, which ends in a
    /// UUID, is too long to share the library's row with its controls, which then take a second row of their own.
    private func libraryWorkspace() async throws -> WorkspaceModel {
        var files: [String: String] = [:]
        for noteNumber in 1...40 { files[String(format: "Lectures/Note %02d.md", noteNumber)] = "# Note \(noteNumber)\n" }
        for weekNumber in 1...60 { files[String(format: "Lectures/Course/Week %02d.md", weekNumber)] = "# Week \(weekNumber)\n" }
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .library
        try await workspace.openFolderAsVault(try makeVault(files: files).appendingPathComponent("Lectures"))
        return workspace
    }

    /// The scene's own bounds, which the library's window takes: a landscape window of 1194 points on an iPad held
    /// upright (834 wide) ran past the screen, and its navigation bar was laid out for a window that is not there. The
    /// window keeps the regular width an iPad's full screen has either way.
    private func libraryWindowBounds() throws -> CGRect {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let bounds = scene.effectiveGeometry.coordinateSpace.bounds
        print("PhoneAndLibraryLayoutHostedTests library window: the scene's bounds \(bounds)")
        return bounds
    }

    private func visibleNavigationBars() -> [(bar: UINavigationBar, height: CGFloat)] {
        guard let window else { return [] }
        return descendants(of: window, matching: UINavigationBar.self)
            .filter { bar in !bar.isHidden && bar.alpha > 0.01 && bar.window === window }
            .map { bar in (bar: bar, height: bar.convert(bar.bounds, to: window).intersection(window.bounds).height) }
    }

    func testLibraryModeHasNoBandAboveItsRowAndKeepsBackAndForwardThere() async throws {
        let workspace = try await libraryWorkspace()
        let bounds = try libraryWindowBounds()
        let controller = try host(GraphiteRootView(workspace: workspace), size: bounds.size, horizontalSizeClass: .regular)
        let back = try await element(in: controller, "Back, in the library's own row") { object in
            object.accessibilityLabel == "Back" && object.accessibilityTraits.contains(.button)
        }
        _ = try await element(in: controller, "Forward, beside it") { object in object.accessibilityLabel == "Forward" && object.accessibilityTraits.contains(.button) }
        let window = try XCTUnwrap(window)
        // The window's top row is the tab strip; the library's own row, its title with Back, Forward and the rest, is
        // the next one. HUNT-211 was a band of 70 points above the tab strip, holding only those buttons. A navigation
        // bar may hold the tab strip itself (the owner's iPad, 2026-11-05, kept one there): only a bar above the strip
        // is a band.
        let tabStripButton = try await element(in: controller, "the tab strip's Show All Tabs") { object in
            object.accessibilityLabel == "Show All Tabs" && object.accessibilityTraits.contains(.button)
        }
        let tabStrip = window.convert(tabStripButton.accessibilityFrame, from: window.screen.coordinateSpace)
        func bandsAboveTheTabStrip() -> [(bar: UINavigationBar, height: CGFloat)] {
            visibleNavigationBars().filter { shown in
                shown.height >= 4 && shown.bar.convert(shown.bar.bounds, to: window).maxY <= tabStrip.minY + 1
            }
        }
        try await waitUntil("no navigation bar band above the library's tab strip") { bandsAboveTheTabStrip().isEmpty }
        for shown in visibleNavigationBars() {
            print("PhoneAndLibraryLayoutHostedTests band: a navigation bar \(shown.height) high at \(shown.bar.convert(shown.bar.bounds, to: window)), titled \(shown.bar.topItem?.title ?? "nothing")")
        }
        attachScreenshot(named: "Library mode on an iPad")
        let title = try await element(in: controller, "the library's title") { object in
            object.accessibilityLabel == "Lectures" && object.accessibilityTraits.contains(.header)
        }
        let backFrame = window.convert(back.accessibilityFrame, from: window.screen.coordinateSpace)
        let titleFrame = window.convert(title.accessibilityFrame, from: window.screen.coordinateSpace)
        print("PhoneAndLibraryLayoutHostedTests band: tab strip \(tabStrip), Back \(backFrame), title \(titleFrame), safe area top \(window.safeAreaInsets.top)")
        XCTAssertLessThan(tabStrip.minY, window.safeAreaInsets.top + 44, "The tab strip is the top row, with no band above it.")
        XCTAssertGreaterThanOrEqual(backFrame.minY, tabStrip.maxY - 1, "Back is below the tab strip, in the library's row")
        XCTAssertLessThan(backFrame.minY - tabStrip.maxY, 44, "Back is in the row right under the tab strip, not under a band.")
        XCTAssertEqual(backFrame.midY, titleFrame.midY, accuracy: 12, "Back shares the library's row with its title.")
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
        // The library itself, with a model the test holds: the window's own is private to its root view. A tile's
        // accessibility activation, and on GitHub's simulator and the owner's iPad a synthesized touch too, did not reach
        // the SwiftUI button, so the folder never opened and the scroll this test is about was never measured.
        let library = LibraryModel()
        let libraryView = LibraryView(library: library, vault: workspace.libraryVault,
                                      actions: workspace.libraryActions(openFile: { _ in }, requestCreation: { _, _ in }),
                                      entries: workspace.libraryEntryPresentation { _, _ in })
        let controller = try host(libraryView, size: try libraryWindowBounds().size, horizontalSizeClass: .regular)
        let folder = try VaultPath("Course")
        let tile = try await element(in: controller, "the Course folder's tile") { object in
            (object.accessibilityLabel ?? "").hasPrefix("Course") && object.accessibilityTraits.contains(.button)
        }
        try await waitUntil("the vault's grid scrolls") { self.libraryGrid() != nil }
        let rootGrid = try XCTUnwrap(libraryGrid())
        // The vault's root scrolled a little, as in the report.
        rootGrid.setContentOffset(CGPoint(x: rootGrid.contentOffset.x, y: rootGrid.contentOffset.y + 120), animated: false)
        print("PhoneAndLibraryLayoutHostedTests folder: the vault's grid scrolled to \(rootGrid.contentOffset.y) of \(rootGrid.contentSize.height)")

        // The tile's action opens the folder; where the activation does not reach it, the test opens it as that action does.
        let activated = tile.accessibilityActivate()
        var openedByTheTile = false
        if activated {
            let givenUpAt = ContinuousClock.now + .seconds(3)
            try await waitUntil("the tile's action, or three seconds") {
                openedByTheTile = library.folder == folder
                return openedByTheTile || ContinuousClock.now >= givenUpAt
            }
        }
        print("PhoneAndLibraryLayoutHostedTests folder: the tile's activation answered \(activated), the folder opened by it: \(openedByTheTile)")
        if !openedByTheTile { await library.show(folder) }

        _ = try await element(in: controller, "the folder is shown") { object in (object.accessibilityLabel ?? "").hasPrefix("Back to ") }
        let firstWeek = try await element(in: controller, "the folder's first tile") { object in (object.accessibilityLabel ?? "").hasPrefix("Week 01") }
        var folderGrid: UIScrollView?
        try await waitUntil("the folder's grid") {
            folderGrid = self.libraryGrid()
            return folderGrid != nil && folderGrid !== rootGrid
        }
        let grid = try XCTUnwrap(folderGrid)
        attachScreenshot(named: "Library folder opened after scrolling the vault")
        let gridTop = grid.convert(grid.bounds, to: nil).minY + grid.adjustedContentInset.top
        print("PhoneAndLibraryLayoutHostedTests folder: the folder's grid at \(grid.contentOffset.y), inset \(grid.adjustedContentInset.top); first tile at \(firstWeek.accessibilityFrame.minY), grid top \(gridTop)")
        XCTAssertLessThanOrEqual(grid.contentOffset.y, -grid.adjustedContentInset.top + 1, "The folder starts at its top.")
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

    /// The density a form of the bar sets its buttons at.
    private func density(of arrangement: PencilToolRowLayout.Arrangement) -> PencilToolRowLayout.Density {
        if case .whole(let density) = arrangement { return density }
        return .tightest
    }

    /// The black swatch's ring reads on the dark bar at every density the bar takes, the 16-point dots of the closest
    /// one too, and each color and size is as wide as the density's pitch: 36 points for a size on the regular bar, a
    /// color 32 (HUNT-284, HUNT-282). The owner's iPad (2026-11-05) measured 2.65 to 1 with the ring at 40 %, sampled
    /// inside a 22-point dot by radii set for 20, and a color 32 points wide where the test still asked for 36.
    func testTheBlackSwatchShowsOnTheDarkBar() async throws {
        let toolbox = PencilToolbox(defaults: try XCTUnwrap(UserDefaults(suiteName: "DarkSwatch-\(UUID().uuidString)")))
        let contents = PencilToolRowLayout.contents(of: toolbox, favorites: PaletteColor.defaultPalette, highlighterColors: PaletteColor.defaultHighlighterPalette,
                                                    offersTextBoxes: true, offersReadAloudPen: true, offersImages: true)
        let closerWidths = [PencilToolRowLayout.Density.tight, .tightest].compactMap { density in
            PencilToolRowLayout.width(of: .whole(density), holding: contents).map { width in CGFloat(width.rounded(.up)) + 1 }
        }
        var densitiesChecked: Set<Double> = []
        for width in [1_100] + closerWidths {
            PencilToolRowForm.lastShown = nil
            let row = PencilToolRow(toolbox: toolbox, drawsShapes: .constant(false), addImage: {}, offersReadAloudPen: true, offersTextBoxes: true)
                .frame(width: width, height: PencilToolbarMetrics.height)
                .background(Color(uiColor: .systemBackground))
            let controller = try host(row, size: CGSize(width: width, height: 120))
            let window = try XCTUnwrap(window)
            window.overrideUserInterfaceStyle = .dark
            try await waitUntil("the row shows at \(Int(width)) points") { PencilToolRowForm.lastShown != nil }
            let swatch = try await element(in: controller, "the black swatch") { object in object.accessibilityLabel == "black" }
            let shownDensity = density(of: try XCTUnwrap(PencilToolRowForm.lastShown).arrangement)
            let frame = swatch.accessibilityFrame
            attachScreenshot(named: "Pencil bar in dark appearance, \(Int(width)) points")
            let contrast = try ringContrast(around: CGPoint(x: frame.midX, y: frame.midY), dotDiameter: shownDensity.swatchDiameter,
                                            barPoint: CGPoint(x: frame.midX, y: frame.minY + 2), in: window)
            print("PhoneAndLibraryLayoutHostedTests swatch at \(Int(width)) points: \(shownDensity.swatchDiameter)-point dots, button \(frame.size), ring contrast \(contrast)")
            XCTAssertGreaterThanOrEqual(contrast, 3, "\(Int(width)) points: the black swatch's ring reads on the dark bar (3 to 1, WCAG 1.4.11).")
            XCTAssertGreaterThanOrEqual(frame.width, shownDensity.swatchPitch - 0.5, "\(Int(width)) points: the swatch's button is its density's pitch wide.")
            XCTAssertGreaterThanOrEqual(frame.height, 43.5, "And as tall as the bar.")
            for widthName in ["Fine", "Medium", "Broad"] {
                let widthButton = try await element(in: controller, "the \(widthName) width") { object in object.accessibilityLabel == widthName }
                XCTAssertGreaterThanOrEqual(widthButton.accessibilityFrame.width, shownDensity.sizePitch - 0.5, "\(widthName) is its density's pitch wide.")
            }
            densitiesChecked.insert(shownDensity.swatchDiameter)
        }
        XCTAssertTrue(densitiesChecked.contains(22), "The regular bar was checked.")
    }

    /// The contrast of the brightest point of the ring at the edge of a dot `dotDiameter` wide against the bar.
    private func ringContrast(around center: CGPoint, dotDiameter: Double, barPoint: CGPoint, in window: UIWindow) throws -> Double {
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
        let bar = pixelLuminance(at: barPoint)
        // The 1-point ring on the dot's edge, not the 2-point ring that marks the color in use outside it.
        let dotRadius = dotDiameter / 2
        var brightestEdge = 0.0
        for step in 0..<72 {
            let angle = Double(step) * .pi / 36
            for radius in stride(from: dotRadius - 0.9, through: dotRadius - 0.1, by: 0.2) {
                brightestEdge = max(brightestEdge, pixelLuminance(at: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))))
            }
        }
        return (max(brightestEdge, bar) + 0.05) / (min(brightestEdge, bar) + 0.05)
    }
}
#endif
