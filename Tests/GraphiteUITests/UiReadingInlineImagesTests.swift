/**
 * File: UiReadingInlineImagesTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The reading view turns every image embed of a Photos-style section into a picture of the vault,
 *              in paragraph lines, a list item, a table cell (wiki and Markdown forms, `\|` escaped) and a callout,
 *              once the index has read the pictures (issue #102).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class UiReadingInlineImagesTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    private static let notePath = "Recipes/Butter-basted steak.md"
    private static let pictureNames = ["IMG_3599.jpg", "IMG_3598.PNG", "IMG_6652.JPG", "IMG_6653.JPG", "Step_1.jpg", "Step_2.jpg",
                                       "Raw.png", "Seared.png", "Done.png", "Rest_1.png", "Rest_2.png"]
    private static let note = """
        ## Photos

        ![[IMG_3599.jpg|300]] ![[IMG_3598.PNG|200]]

        ![[IMG_6652.JPG|250]] ![[IMG_6653.JPG|250]]

        - ![[Step_1.jpg|120]] ![[Step_2.jpg|120]]

        | Before | After |
        | --- | --- |
        | ![[Raw.png\\|100]] ![[Seared.png\\|100]] | ![Done\\|100](../Attachments/Done.png) |

        > [!tip] Resting
        > ![[Rest_1.png|100]] ![[Rest_2.png|100]]

        """

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "ReadingInlineImages", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let attachments = vault.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        // The reading view does not decode the pictures to build the note; any bytes name a file.
        for name in Self.pictureNames { try Data("picture".utf8).write(to: attachments.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Recipes"), withIntermediateDirectories: true)
        try Data(Self.note.utf8).write(to: vault.appendingPathComponent(Self.notePath))
    }

    override func tearDown() async throws {
        index = nil
    }

    private func build() async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: Self.note, note: try VaultPath(Self.notePath), root: vault, index: index, configuration: ReadingConfiguration())
    }

    /// The Markdown text of every block, callout bodies included.
    private func markdownTexts(_ blocks: [RenderedBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .markdown(_, let text), .heading(_, _, let text, _): [text]
            case .callout(_, _, let title, _, let body): [title] + markdownTexts(body)
            default: []
            }
        }
    }

    func testEveryPictureIsAPictureOfTheVaultOnceTheIndexHasReadThem() async throws {
        try await index.refresh(paths: [try VaultPath(Self.notePath)], root: vault)
        let beforeIndexing = try await build()
        XCTAssertTrue(beforeIndexing.hasUnresolvedEmbeds, "Pictures the index has not read yet are looked up again when it has.")

        try await index.refresh(paths: Self.pictureNames.map { name in try VaultPath("Attachments/" + name) }, root: vault)
        let built = try await build()
        let text = markdownTexts(built.blocks).joined(separator: "\n")
        XCTAssertFalse(built.hasUnresolvedEmbeds)
        XCTAssertFalse(text.contains("![["), "No embed is left as written: \(text)")
        XCTAssertFalse(text.contains("](../Attachments"), "The Markdown image is a picture of the vault: \(text)")
        for name in Self.pictureNames {
            let stem = (name as NSString).deletingPathExtension
            XCTAssertTrue(text.contains("![\(stem)](file://"), "\(name) is a picture: \(text)")
        }
    }
}
