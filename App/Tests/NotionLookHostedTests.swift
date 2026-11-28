/**
 * File: NotionLookHostedTests.swift
 * ---------------------------------
 * Layer: Tests
 * Description: Pictures, in the app's window on the iPad and iPhone simulators, of a made-up course page of the shape the Notion importer writes:
 *              picture icons of the vault and of the web, a GIF cover, a large PNG cover, three columns of coloured
 *              headings over lines that each link to a page, and a page of Notion's text and background colours as HTML
 *              spans in text, a heading, a list of links and a table, with columns of uneven widths, in the reading view and Live Preview, light and dark.
 *
 * Authors: Bahey Shalash
 * Version: 0.6
 * Date: 28/11/2026
 */

#if os(iOS)
import XCTest
import UIKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI

/// The page's large icon and its cover are drawn while the plugin is on and not while it is off; the pictures are kept
/// with the result bundle. The web icon comes from a loopback server, so nothing leaves the Mac.
@MainActor
final class NotionLookHostedTests: XCTestCase {

    /// A small clock drawn as an SVG, as Notion's own icon set draws its icons.
    static let clockSVG = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="#6b6b6b" stroke-width="2"/>\
        <path d="M12 7v5l3 2" fill="none" stroke="#6b6b6b" stroke-width="2" stroke-linecap="round"/></svg>
        """

    /// Notion's text and background colours as the importer writes them, in columns two and one wide (`wide-2`).
    static let colouredPage = """
        ---
        icon: 🎨
        ---
        Text in <span style="color:#787774">gray</span>, <span style="color:#9F6B53">brown</span>, \
        <span style="color:#D9730D">orange</span>, <span style="color:#CB912F">yellow</span>, <span style="color:#448361">green</span>, \
        <span style="color:#337EA9">blue</span>, <span style="color:#9065B0">purple</span>, <span style="color:#C14C8A">pink</span> \
        and <span style="color:#D44C47">red</span>.

        Backgrounds: <span style="background-color:#F1F1EF">gray</span>, <span style="background-color:#FBECDD">orange</span>, \
        <span style="background-color:#FBF3DB">yellow</span>, <span style="background-color:#EDF3EC">green</span>, \
        <span style="background-color:#E7F3F8">blue</span>, <span style="background-color:rgba(244, 240, 247, 0.8)">purple</span> \
        and <span style="background-color:#FDEBEC">red</span>, and <span style="color:#D44C47;background-color:#FDEBEC">both at once</span>.

        > [!tip] 💡
        > Office hours on Tuesdays in the lab. A Notion callout: its icon on the first line, no title row, and a long
        > enough body to wrap onto a second line under the first.

        > [!warning] ⚠️
        > Bring your own cables.

        > [!info|no-title]
        > A Notion callout whose icon is one of Notion's own pictures: the type's glyph stands for it.

        > [!multi-column]
        > > [!blank|wide-2]
        > > ## <span style="color:#337EA9">Wide column</span>
        > > This column is twice as wide as the one beside it, as a Notion column dragged wider.
        > > <span style="background-color:#FBF3DB">A highlighted sentence in a column.</span>
        >
        > > [!blank]
        > > ## Narrow
        > > [[Lab 1]]

        ## <span style="color:#e05a52">Admin</span>
        [[Lab 1]]  
        [[Lab 2]] <span style="color:#d9730d">due Monday</span>  
        [[Midterm]]  

        | Week | Topic |
        | --- | --- |
        | 1 | <span style="background-color:#FBF3DB">Intro</span> |
        | 2 | <span style="color:#337EA9">Lists</span> |

        > [!note] A callout with <span style="color:#D9730D">orange</span> words
        > And a <span style="background-color:#E7F3F8">blue background</span> inside it.

        `<span style="color:#D44C47">code stays text</span>`

        """

    private static func writePicture(to location: URL, type: UTType, width: Int, height: Int, frames: [(CGFloat, CGFloat, CGFloat)]) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, type.identifier as CFString, frames.count, nil))
        for (red, green, blue) in frames {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let gradient = try XCTUnwrap(CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: [red, green, blue, 1, blue, red, green, 1],
                                                    locations: [0, 1], count: 2))
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
            CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makeVault(webIcon: URL) throws -> URL {
        let page = """
            ---
            icon: "[[clock.svg]]"
            banner: "[[stars.gif]]"
            ---
            A made-up course page in the shape the Notion importer writes.

            **Lab input** → `Sensor readings from the bench` + `reset commands`

            > [!multi-column]
            > > [!blank]
            > > ## ~={#E03E3E}Lectures=~
            > > [[Lecture 1]]
            > >
            > > [[Lecture 2]]
            >
            > > [!blank]
            > > ## ~={#0B6E99}Labs=~
            > > [[Lab 1]]
            > >
            > > [[Lab 2]]
            > >
            > > [[Signals and systems of the lab bench, its instruments and their calibration]]
            >
            > > [!blank]
            > > ## Exams
            > > [[Midterm]]

            ## Resources

            ---

            [[Reading list]]

            [[Office hours]]

            [[Lab 1]]

            """
        let vault = try TemporaryVault.make(prefix: "NotionLook", files: [
            "Course hub.md": page,
            "Coloured page.md": Self.colouredPage,
            "Course with photo.md": "---\nicon: 🎓\nbanner: \"[[wide.png]]\"\n---\nA page whose cover is a large photo.\n\n[[Lecture 1]]\n\n[[Lab 1]]\n",
            "Lecture 1.md": "---\nicon: \"[[clock.svg]]\"\n---\n",
            "Lecture 2.md": "---\nicon: \(webIcon.absoluteString)\n---\n",
            "Lab 1.md": "---\nicon: 🧪\n---\n",
            "Lab 2.md": "---\nicon: LiFlaskConical\n---\n",
            "Midterm.md": "---\nicon: \"[[stars.gif]]\"\n---\n",
            "Signals and systems of the lab bench, its instruments and their calibration.md": "---\nicon: 🔬\n---\n",
            "Reading list.md": "---\nicon: 📚\n---\n",
            "Office hours.md": "No icon.\n",
            "clock.svg": Self.clockSVG,
        ], for: self).root
        try Self.writePicture(to: vault.appendingPathComponent("stars.gif"), type: .gif, width: 600, height: 200,
                              frames: [(0.2, 0.3, 0.6), (0.6, 0.3, 0.2)])
        try Self.writePicture(to: vault.appendingPathComponent("wide.png"), type: .png, width: 4_000, height: 1_500, frames: [(0.1, 0.5, 0.4)])
        return vault
    }

    private func attach(_ window: UIWindow, named name: String) -> UIImage {
        let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: picture)
        attachment.name = (UIDevice.current.userInterfaceIdiom == .phone ? "iphone-" : "ipad-") + name
        attachment.lifetime = .keepAlways
        add(attachment)
        return picture
    }

    func testTheNotionShapedPageDrawsItsIconCoverColumnsAndLinkLines() async throws {
        let webServer = try await LoopbackWebServer(pages: ["/icons/clock_gray.svg": Self.clockSVG])
        addTeardownBlock { webServer.stop() }
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .list
        workspace.preferences.showsCoversOnPhone = true
        try await workspace.openFolderAsVault(try makeVault(webIcon: webServer.address("/icons/clock_gray.svg")))
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        _ = await workspace.open(try VaultPath("Course hub.md"), placement: .currentTab)
        workspace.markdownSession?.viewMode = .reading
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        let quietWatch = MainThreadQuietWatch(window: window, quietStepsToStop: 200)
        _ = try await quietWatch.measure({})
        let drawn = attach(window, named: "course-hub-light")
        workspace.preferences.appearanceMode = .dark
        _ = try await quietWatch.measure({})
        _ = attach(window, named: "course-hub-dark")
        workspace.preferences.appearanceMode = .light
        _ = await workspace.open(try VaultPath("Course with photo.md"), placement: .currentTab)
        workspace.markdownSession?.viewMode = .reading
        _ = try await quietWatch.measure({})
        _ = attach(window, named: "photo-cover-light")
        _ = await workspace.open(try VaultPath("Course hub.md"), placement: .currentTab)
        workspace.markdownSession?.viewMode = .reading
        workspace.setCorePluginEnabled(.pageLook, false)
        _ = try await quietWatch.measure({})
        let off = attach(window, named: "course-hub-plugin-off")
        XCTAssertNotEqual(drawn.pngData(), off.pngData(), "The icon, the cover and the columns are drawn only while the plugin is on.")
    }

    func testNotionsColoursAndUnevenColumnsAreDrawnInBothModes() async throws {
        let webServer = try await LoopbackWebServer(pages: ["/icons/clock_gray.svg": Self.clockSVG])
        addTeardownBlock { webServer.stop() }
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        workspace.preferences.library.presentation = .list
        try await workspace.openFolderAsVault(try makeVault(webIcon: webServer.address("/icons/clock_gray.svg")))
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        _ = await workspace.open(try VaultPath("Coloured page.md"), placement: .currentTab)
        workspace.markdownSession?.viewMode = .reading
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        let quietWatch = MainThreadQuietWatch(window: window, quietStepsToStop: 200)
        var pictures: [String: Data] = [:]
        for mode in [NoteViewMode.reading, .livePreview] {
            workspace.markdownSession?.viewMode = mode
            for appearance in [AppearanceMode.light, .dark] {
                workspace.preferences.appearanceMode = appearance
                _ = try await quietWatch.measure({})
                pictures["\(mode.rawValue)-\(appearance.rawValue)"] = attach(window, named: "colours-\(mode.rawValue)-\(appearance.rawValue)").pngData()
            }
        }
        workspace.preferences.appearanceMode = .light
        XCTAssertNotEqual(pictures["reading-light"], pictures["reading-dark"])
        XCTAssertNotEqual(pictures["livePreview-light"], pictures["livePreview-dark"])
    }
}
#endif
