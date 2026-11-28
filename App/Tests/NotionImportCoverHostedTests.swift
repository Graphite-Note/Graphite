/**
 * File: NotionImportCoverHostedTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A Notion page's cover imported through the workspace as the note's `banner` property, found by the
 *              reading view in the vault and drawn above the note as its cover, in the app on the iPad.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import UIKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class NotionImportCoverHostedTests: XCTestCase {
    private static let page = "9a11111111111111aaaaaaaaaaaaaaaa"
    /// The page's identifier as its `article` element gives it, hyphenated.
    private static let hyphenatedPage = "9a111111-1111-1111-aaaa-aaaaaaaaaaaa"

    /// A made-up export as a folder, as Notion's export unzipped: a page whose cover is a red picture the export holds.
    private func makeExport() throws -> URL {
        // A folder the import reads as an unzipped export, which it knows by its directory path.
        let export = URL(fileURLWithPath: try TemporaryVault.make(prefix: "NotionCoverExport", for: self).root.path, isDirectory: true)
        let pictures = export.appendingPathComponent("Course \(Self.page)", isDirectory: true)
        try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 32)).pngData { context in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        try picture.write(to: pictures.appendingPathComponent("Hills.png"))
        let html = """
            <html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"/><title>Course</title></head><body>\
            <article id="\(Self.hyphenatedPage)" class="page sans"><header><img class="page-cover-image" src="Course%20\(Self.page)/Hills.png" \
            style="object-position:center 50%"/><h1 class="page-title">Course</h1></header>\
            <div class="page-body"><p id="p1" class="">The first week.</p></div></article></body></html>
            """
        try Data(html.utf8).write(to: export.appendingPathComponent("Course \(Self.page).html"))
        return export
    }

    /// The share of the picture's pixels that are the cover's red.
    private static func redShare(of view: UIView) -> Double {
        // Eight bits a channel at one pixel a point, so each pixel is four bytes whatever the screen's color range.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        let image = renderer.image { _ in _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        var red = 0, total = 0
        for row in 0..<cgImage.height {
            for column in 0..<cgImage.width {
                let pixel = bytes + row * cgImage.bytesPerRow + column * bytesPerPixel
                // The renderer writes BGRA or RGBA; the cover's red is the one channel near full with the other two low.
                let channels = (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
                if (channels.0 > 200 && channels.1 < 60 && channels.2 < 60) || (channels.2 > 200 && channels.1 < 60 && channels.0 < 60) { red += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(red) / Double(total)
    }

    func testAnImportedCoverIsTheNotesBannerAndTheReadingViewDrawsIt() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionImportCover", for: self).root
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".graphite-test-index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true

        XCTAssertTrue(workspace.importNotionExport([try makeExport()], into: .root))
        try await waitUntil("the Notion import has ended", timeoutSeconds: 60) {
            if case .finished = workspace.notionImport?.state { true } else { false }
        }
        guard case .finished(let summary)? = workspace.notionImport?.state else { return XCTFail("The import did not end.") }
        workspace.endNotionImport()
        XCTAssertNil(summary.failureMessage)
        let note = try String(contentsOf: vault.appendingPathComponent("Notion/Course.md"), encoding: .utf8)
        XCTAssertTrue(note.hasPrefix("---\nbanner: \"[[Hills.png]]\"\n---\n"), note)
        XCTAssertFalse(note.contains("cover:"), note)

        try await waitUntil("the index has the cover's picture", timeoutSeconds: 30) {
            (try? await index.resolve("Hills.png", from: try VaultPath("Notion/Course.md")))?.first?.rawValue == "Notion/Course/Hills.png"
        }
        var configuration = ReadingConfiguration()
        configuration.drawsCover = true
        let build = try await ReadingViewBuilder().build(source: note, note: try VaultPath("Notion/Course.md"), root: vault, index: index,
                                                         configuration: configuration)
        let picture = try VaultPath("Notion/Course/Hills.png")
        let cover = try XCTUnwrap(build.cover, "The reading view finds the imported cover.")
        let expected = ReadingCover(picture: .vaultFile(path: picture, location: try picture.url(in: vault)), verticalFocus: NoteBanner.defaultVerticalFocus)
        XCTAssertEqual(cover, expected)

        // Drawn as the reading view draws it above the note's title: the picture fills the cover's band.
        let controller = UIHostingController(rootView: ReadingCoverView(cover: cover, notePath: try VaultPath("Notion/Course.md"))
            .frame(width: 600, height: ReadingCoverView.expandedHeightPoints))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = CGRect(x: 0, y: 0, width: 600, height: ReadingCoverView.expandedHeightPoints)
        var share = 0.0
        try await waitUntil("the cover's picture is drawn", timeoutSeconds: 20) {
            share = Self.redShare(of: controller.view)
            return share > 0.5
        }
        XCTAssertGreaterThan(share, 0.5, "The share of the cover's band drawn in the picture's red.")
    }
}
#endif
