/**
 * File: WebLinkPreviewTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: YouTube addresses become video cards, page titles are read from oEmbed and HTML, and a bare address's
 *              menu writes a titled link or a preview.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import XCTest
@testable import GraphiteCore

final class WebLinkPreviewTests: XCTestCase {
    private func video(_ address: String) -> WebVideo? { URL(string: address).flatMap(WebVideo.init(address:)) }

    func testYouTubeVideosAndPlaylistsAreRecognized() {
        XCTAssertEqual(video("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.content, .video(identifier: "dQw4w9WgXcQ"))
        XCTAssertEqual(video("https://youtu.be/dQw4w9WgXcQ?t=42")?.content, .video(identifier: "dQw4w9WgXcQ"))
        XCTAssertEqual(video("https://m.youtube.com/shorts/abcdefGHIJK")?.content, .video(identifier: "abcdefGHIJK"))
        XCTAssertEqual(video("https://www.youtube.com/playlist?list=PL5Q2soXY2Zi9OtbGJyUVHp1Gp3c_0Dymh")?.content,
                       .playlist(identifier: "PL5Q2soXY2Zi9OtbGJyUVHp1Gp3c_0Dymh"), "The request's first playlist.")
        XCTAssertEqual(video("https://www.youtube.com/playlist?list=PLcQYzfBAwuFs")?.isPlaylist, true, "The request's second playlist.")
        XCTAssertNil(video("https://www.youtube.com/@SAFARI"), "A channel has no card.")
        XCTAssertNil(video("https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(video("https://www.youtube.com/watch?v=<script>"))
    }

    func testAVideoHasAFixedThumbnailAndEveryAddressAnOEmbedRequest() throws {
        let watched = try XCTUnwrap(video("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertEqual(watched.directThumbnail, URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"))
        let playlist = try XCTUnwrap(video("https://www.youtube.com/playlist?list=PLcQYzfBAwuFs"))
        XCTAssertNil(playlist.directThumbnail, "A playlist's picture comes from oEmbed.")
        let request = try XCTUnwrap(playlist.oEmbedRequest?.absoluteString)
        XCTAssertTrue(request.hasPrefix("https://www.youtube.com/oembed?url=https://www.youtube.com/playlist?list%3DPLcQYzfBAwuFs"), request)
    }

    func testAYouTubeEmbedOnItsLineIsABlockInBothRenderers() throws {
        let note = "Lectures\n\n![Computer Architecture](https://www.youtube.com/playlist?list=PLcQYzfBAwuFs)\n\n![](https://example.com/photo.png)\n"
        let livePreviewEmbeds = LivePreviewBlockScanner.blocks(in: note as NSString).compactMap { block -> EmbedReference? in
            if case .embed(let embed) = block.kind { return embed }
            return nil
        }
        XCTAssertEqual(livePreviewEmbeds.count, 1, "The web image stays Markdown; the video is a block.")
        let embed = try XCTUnwrap(livePreviewEmbeds.first)
        XCTAssertEqual(embed.label, "Computer Architecture")
        XCTAssertNotNil(WebVideo(embed: embed))
        let readingEmbeds = NotePreviewDocument.blocks(from: note).filter { block in
            if case .embed = block { return true }
            return false
        }
        XCTAssertEqual(readingEmbeds.count, 1)
    }

    func testTitlesAreReadFromOEmbedAndFromPages() {
        let oEmbed = Data(#"{"title":"Computer Architecture - Fall 2026","thumbnail_url":"https://i.ytimg.com/vi/abc/hqdefault.jpg","type":"video"}"#.utf8)
        XCTAssertEqual(WebLinkDetails.fromOEmbed(oEmbed),
                       WebLinkDetails(title: "Computer Architecture - Fall 2026", thumbnail: URL(string: "https://i.ytimg.com/vi/abc/hqdefault.jpg")))
        XCTAssertNil(WebLinkDetails.fromOEmbed(Data("Not Found".utf8)))
        let page = """
        <html><head><title>projects_and_seminars:fall2026:modern_ssds [SAFARI Research Group]</title>
        <meta property="og:title" content="Modern SSDs &amp; Storage &#8211; Fall 2026"></head></html>
        """
        XCTAssertEqual(WebLinkDetails.fromHTML(page)?.title, "Modern SSDs & Storage – Fall 2026", "og:title first, its references read.")
        XCTAssertEqual(WebLinkDetails.fromHTML("<TITLE>\n  Plain   page\n</TITLE>")?.title, "Plain page")
        XCTAssertNil(WebLinkDetails.fromHTML("<html><body>No title</body></html>"))
    }

    func testUsePageTitleWritesAMarkdownLinkInPlaceOfTheAddress() throws {
        let text = "Course page: https://safari.ethz.ch/projects_and_seminars/fall2026/doku.php?id=modern_ssds now" as NSString
        let address = try XCTUnwrap(WebLinkEditing.bareAddress(at: text.range(of: "safari").location, in: text))
        let edit = try XCTUnwrap(WebLinkEditing.titledLink(address, title: "Modern SSDs [Fall]", in: text))
        let edited = text.replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(edited, "Course page: [Modern SSDs \\[Fall\\]](https://safari.ethz.ch/projects_and_seminars/fall2026/doku.php?id=modern_ssds) now")
        XCTAssertEqual((edited as NSString).substring(to: edit.selectionAfter.location).hasSuffix(")"), true, "The cursor goes after the link.")
    }

    func testShowPreviewPutsTheEmbedOnALineOfItsOwn() throws {
        let alone = "- https://www.youtube.com/playlist?list=PLcQYzfBAwuFs\n" as NSString
        let aloneAddress = try XCTUnwrap(WebLinkEditing.bareAddress(at: 5, in: alone))
        let aloneEdit = try XCTUnwrap(WebLinkEditing.preview(aloneAddress, title: "Lectures", in: alone))
        XCTAssertEqual(alone.replacingCharacters(in: aloneEdit.range, with: aloneEdit.replacement),
                       "- ![Lectures](https://www.youtube.com/playlist?list=PLcQYzfBAwuFs)\n", "A list item's embed is a block already.")
        let inSentence = "Watch https://youtu.be/dQw4w9WgXcQ tonight" as NSString
        let address = try XCTUnwrap(WebLinkEditing.bareAddress(at: 8, in: inSentence))
        let edit = try XCTUnwrap(WebLinkEditing.preview(address, title: "", in: inSentence))
        XCTAssertEqual(inSentence.replacingCharacters(in: edit.range, with: edit.replacement), "Watch \n![](https://youtu.be/dQw4w9WgXcQ)\n tonight")
    }

    func testNoEditWhenTheAddressChangedOrIsNotBare() throws {
        let text = "See https://example.com/a here" as NSString
        let address = try XCTUnwrap(WebLinkEditing.bareAddress(at: 6, in: text))
        XCTAssertNil(WebLinkEditing.titledLink(address, title: "A", in: "See https://example.com/b here"), "The note changed since the menu opened.")
        XCTAssertNil(WebLinkEditing.bareAddress(at: 3, in: "[x](https://example.com)"), "A link's address is not bare.")
        XCTAssertNil(WebLinkEditing.bareAddress(at: 8, in: "`https://example.com`"), "Nor is one in code.")
    }
}
