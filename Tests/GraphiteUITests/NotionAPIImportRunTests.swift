/**
 * File: NotionAPIImportRunTests.swift
 * -----------------------------------
 * Layer: Tests
 * Description: Import from Notion through Notion's API, run as the sheet runs it on a temporary vault, against a
 *              made-up workspace answered without a network: the token sent to Notion's API alone and kept in the
 *              keychain, the workspace written into a new folder, an update of that folder keeping a note edited in the
 *              vault, and a token Notion refuses ending in a message.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import GraphiteApple
import GraphiteCore
import GraphiteTestSupport
import NotionImport
@testable import GraphiteUI

/// A made-up workspace as Notion's API answers it: a page "Course" holding a page "Lecture". Each answer is made from
/// its request alone, so the transport needs no state, and no request reaches a network.
struct NotionTestWorkspace: NotionTransport {
    static let courseIdentifier = "11111111-1111-4111-8111-111111111111"
    static let lectureIdentifier = "22222222-2222-4222-8222-222222222222"
    /// The course page's text, which a test changes to stand for an edit in Notion.
    var courseText = "Welcome to the course."
    /// The status every answer has when set, as Notion answers a revoked token.
    var refusal: Int?

    static func page(_ identifier: String, _ title: String, parent: String) -> String {
        """
        {"object":"page","id":"\(identifier)","parent":\(parent),"properties":{"title":{"id":"title","type":"title",\
        "title":[{"type":"text","plain_text":"\(title)","text":{"content":"\(title)"}}]}}}
        """
    }

    static func paragraph(_ identifier: String, _ text: String) -> String {
        """
        {"object":"block","id":"\(identifier)","type":"paragraph","has_children":false,"paragraph":{"rich_text":\
        [{"type":"text","plain_text":"\(text)","text":{"content":"\(text)"},"annotations":{}}]}}
        """
    }

    static func list(_ results: [String]) -> String {
        "{\"object\":\"list\",\"results\":[" + results.joined(separator: ",") + "],\"has_more\":false,\"next_cursor\":null}"
    }

    func send(_ request: NotionRequest) async throws -> NotionResponse {
        func answer(_ status: Int, _ json: String) -> NotionResponse { NotionResponse(status: status, body: Array(json.utf8)) }
        if let refusal { return answer(refusal, #"{"object":"error","code":"unauthorized","message":"API token is invalid."}"#) }
        let path = String(request.url.dropFirst(NotionAPIClient.baseAddress.count)).split(separator: "?").first.map(String.init) ?? ""
        let course = Self.page(Self.courseIdentifier, "Course", parent: #"{"type":"workspace","workspace":true}"#)
        let lecture = Self.page(Self.lectureIdentifier, "Lecture", parent: "{\"type\":\"page_id\",\"page_id\":\"\(Self.courseIdentifier)\"}")
        switch (request.method, path) {
        case ("POST", "search"):
            return answer(200, Self.list([course, lecture]))
        case ("GET", "blocks/\(Self.courseIdentifier)/children"):
            let child = "{\"object\":\"block\",\"id\":\"\(Self.lectureIdentifier)\",\"type\":\"child_page\",\"has_children\":true,\"child_page\":{\"title\":\"Lecture\"}}"
            return answer(200, Self.list([Self.paragraph("b1", courseText), child]))
        case ("GET", "blocks/\(Self.lectureIdentifier)/children"):
            return answer(200, Self.list([Self.paragraph("b2", "Notes of the lecture.")]))
        default:
            return answer(404, #"{"object":"error","code":"object_not_found","message":"Could not find it."}"#)
        }
    }
}

final class NotionAPIImportRunTests: XCTestCase {
    private static func makeRun(vault: TemporaryVault) -> NotionImportRun {
        NotionImportRun(store: VaultStore(root: vault.root), pause: NotionImportPause(), filesDidChange: { _ in },
                        importDate: Date(timeIntervalSince1970: 1_764_201_600), calendar: Calendar(identifier: .gregorian))
    }

    private static func runAPI(_ run: NotionImportRun, _ workspace: NotionTestWorkspace, updating earlierImport: VaultPath? = nil) async -> NotionImportSummary {
        let (_, continuation) = AsyncStream.makeStream(of: NotionImportProgress.self)
        let client = NotionAPIClient(transport: workspace, clock: NotionContinuousClock())
        let summary = await run.runAPI(client: client, into: .root, updating: earlierImport, progress: continuation)
        continuation.finish()
        return summary
    }

    func testTheTokenGoesToNotionsAPIAloneAndNeverToAFilesAddress() throws {
        let api = NotionRequest(method: "GET", url: "https://api.notion.com/v1/blocks/abc/children", isNotionAPI: true)
        XCTAssertEqual(NotionURLSessionTransport.urlRequest(for: api, token: "ntn_test")?.value(forHTTPHeaderField: "Authorization"), "Bearer ntn_test")
        let file = NotionRequest(method: "GET", url: "https://files.example.com/a.png", headers: [NotionHeader(name: "Range", value: "bytes=0-9")], isNotionAPI: false)
        let fileRequest = try XCTUnwrap(NotionURLSessionTransport.urlRequest(for: file, token: "ntn_test"))
        XCTAssertNil(fileRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(fileRequest.value(forHTTPHeaderField: "Range"), "bytes=0-9")
        // A request marked for the API but sent elsewhere, or carrying an authorization of its own, gets no token.
        let elsewhere = NotionRequest(method: "GET", url: "https://api.notion.com.example.com/v1/search", isNotionAPI: true)
        XCTAssertNil(NotionURLSessionTransport.urlRequest(for: elsewhere, token: "ntn_test")?.value(forHTTPHeaderField: "Authorization"))
        let ownHeader = NotionRequest(method: "GET", url: "https://files.example.com/a.png", headers: [NotionHeader(name: "Authorization", value: "x")], isNotionAPI: false)
        XCTAssertNil(NotionURLSessionTransport.urlRequest(for: ownHeader, token: "ntn_test")?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(NotionURLSessionTransport.urlRequest(for: NotionRequest(method: "GET", url: "http://api.notion.com/v1/search", isNotionAPI: true), token: "t"))
        // A redirect to another server loses the token.
        var redirected = URLRequest(url: try XCTUnwrap(URL(string: "https://elsewhere.example.com/file")))
        redirected.setValue("Bearer ntn_test", forHTTPHeaderField: "Authorization")
        XCTAssertNil(NotionRedirectGuard.redirected(redirected).value(forHTTPHeaderField: "Authorization"))
    }

    func testTheTokenIsKeptInTheKeychainTrimmedAndForgotten() throws {
        let store = NotionTokenStore(account: "test \(UUID().uuidString)")
        defer { try? store.forgetToken() }
        XCTAssertNil(store.token())
        try store.setToken("  ntn_made_up_token\n")
        XCTAssertEqual(store.token(), "ntn_made_up_token")
        try store.forgetToken()
        XCTAssertNil(store.token())
        try store.setToken("ntn_other")
        try store.setToken("")
        XCTAssertNil(store.token(), "An empty token forgets the stored one.")
    }

    func testTheWorkspaceGoesIntoANewFolderAndAnUpdateKeepsANoteEditedInTheVault() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionAPIImport", files: ["Notion/Kept.md": "already here"], for: self)
        let run = Self.makeRun(vault: vault)
        var workspace = NotionTestWorkspace()
        let first = await Self.runAPI(run, workspace)
        XCTAssertNil(first.failureMessage)
        XCTAssertEqual(first.folder?.rawValue, "Notion 1")
        XCTAssertEqual(first.noteCount, 2)
        XCTAssertTrue(try vault.readText(at: "Notion 1/Course.md").contains("Welcome to the course."))
        XCTAssertTrue(vault.fileExists(at: "Notion 1/Course/Lecture.md"))
        XCTAssertEqual(NotionImportRun.earlierImports(in: .root, root: vault.root).map(\.rawValue), ["Notion 1"])

        // Edited in Notion and in the vault, then imported again over the earlier import.
        workspace.courseText = "Welcome to the course, now with a syllabus."
        let lecture = vault.location(of: "Notion 1/Course/Lecture.md")
        let edited = try String(contentsOf: lecture, encoding: .utf8) + "\nMy own notes.\n"
        try edited.write(to: lecture, atomically: true, encoding: .utf8)
        let update = await Self.runAPI(run, workspace, updating: try VaultPath("Notion 1"))
        XCTAssertNil(update.failureMessage)
        XCTAssertTrue(update.updatedEarlierImport)
        XCTAssertTrue(try vault.readText(at: "Notion 1/Course.md").contains("now with a syllabus"))
        XCTAssertEqual(try vault.readText(at: "Notion 1/Course/Lecture.md"), edited)
        XCTAssertFalse(vault.fileExists(at: "Notion 2"), "an update makes no new folder")
        XCTAssertEqual(try vault.readText(at: "Notion/Kept.md"), "already here")
        XCTAssertTrue(NotionImportWording.details(of: update).contains("Notes that changed in the vault since the earlier import were kept, as the report lists."))
    }

    func testATokenNotionRefusesEndsInAMessageAndWritesNoNote() async throws {
        let vault = try TemporaryVault.make(prefix: "NotionAPIRefused", for: self)
        var workspace = NotionTestWorkspace()
        workspace.refusal = 401
        let summary = await Self.runAPI(Self.makeRun(vault: vault), workspace)
        let message = try XCTUnwrap(summary.failureMessage)
        XCTAssertTrue(message.hasPrefix("Notion could not be read: "), message)
        XCTAssertEqual(summary.noteCount, 0)
        XCTAssertFalse(vault.fileExists(at: "Notion/Course.md"))
    }
}
