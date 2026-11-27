/**
 * File: NotionAPIImportHostedTests.swift
 * --------------------------------------
 * Layer: Tests
 * Description: Import from Notion through Notion's API inside the app: the token kept in the app's own keychain, a
 *              made-up workspace answered without a network imported through the workspace and found by the index,
 *              imported again over the earlier import, and the sheet's API form laid out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
import NotionImport
@testable import GraphiteUI

/// A made-up workspace as Notion's API answers it, with no network: a page "Syllabus" holding a page "Week 1".
private struct HostedNotionWorkspace: NotionTransport {
    static let syllabus = "51111111-1111-4111-8111-111111111111"
    static let week = "52222222-2222-4222-8222-222222222222"
    var syllabusText = "Read [[nothing]] before the first week."

    private static func page(_ identifier: String, _ title: String, parent: String) -> String {
        """
        {"object":"page","id":"\(identifier)","parent":\(parent),"properties":{"title":{"id":"title","type":"title",\
        "title":[{"type":"text","plain_text":"\(title)","text":{"content":"\(title)"}}]}}}
        """
    }

    private static func paragraph(_ text: String) -> String {
        "{\"object\":\"block\",\"id\":\"p\",\"type\":\"paragraph\",\"has_children\":false,\"paragraph\":{\"rich_text\":"
            + "[{\"type\":\"text\",\"plain_text\":\"\(text)\",\"text\":{\"content\":\"\(text)\"},\"annotations\":{}}]}}"
    }

    private static func list(_ results: [String]) -> String {
        "{\"object\":\"list\",\"results\":[" + results.joined(separator: ",") + "],\"has_more\":false,\"next_cursor\":null}"
    }

    func send(_ request: NotionRequest) async throws -> NotionResponse {
        func answer(_ status: Int, _ json: String) -> NotionResponse { NotionResponse(status: status, body: Array(json.utf8)) }
        let path = String(request.url.dropFirst(NotionAPIClient.baseAddress.count)).split(separator: "?").first.map(String.init) ?? ""
        switch (request.method, path) {
        case ("POST", "search"):
            return answer(200, Self.list([Self.page(Self.syllabus, "Syllabus", parent: #"{"type":"workspace","workspace":true}"#),
                                          Self.page(Self.week, "Week 1", parent: "{\"type\":\"page_id\",\"page_id\":\"\(Self.syllabus)\"}")]))
        case ("GET", "blocks/\(Self.syllabus)/children"):
            let child = "{\"object\":\"block\",\"id\":\"\(Self.week)\",\"type\":\"child_page\",\"has_children\":true,\"child_page\":{\"title\":\"Week 1\"}}"
            return answer(200, Self.list([Self.paragraph(syllabusText), child]))
        case ("GET", "blocks/\(Self.week)/children"):
            return answer(200, Self.list([Self.paragraph("Vectors and matrices.")]))
        default:
            return answer(404, #"{"object":"error","code":"object_not_found","message":"Could not find it."}"#)
        }
    }
}

@MainActor
final class NotionAPIImportHostedTests: XCTestCase {
    private func makeWorkspace() async throws -> (WorkspaceModel, URL) {
        let vault = try TemporaryVault.make(prefix: "NotionAPIImportHosted", files: ["Courses/Index.md": "The [[Syllabus]]."], for: self).root
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".graphite-test-index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    private func finishedSummary(of workspace: WorkspaceModel) async throws -> NotionImportSummary {
        try await waitUntil("the Notion import has ended") { if case .finished = workspace.notionImport?.state { true } else { false } }
        guard case .finished(let summary)? = workspace.notionImport?.state else {
            XCTFail("The import did not end.")
            return NotionImportSummary()
        }
        workspace.endNotionImport()
        return summary
    }

    func testTheTokenIsKeptInTheAppsKeychainAndForgotten() throws {
        let store = NotionTokenStore(account: "hosted test \(UUID().uuidString)")
        defer { try? store.forgetToken() }
        try store.setToken("ntn_made_up_hosted_token")
        XCTAssertEqual(store.token(), "ntn_made_up_hosted_token")
        try store.forgetToken()
        XCTAssertNil(store.token())
    }

    func testTheWorkspaceImportsThroughTheAPIAndAnUpdateKeepsANoteEditedInTheVault() async throws {
        let (workspace, vault) = try await makeWorkspace()
        var notion = HostedNotionWorkspace()
        XCTAssertTrue(workspace.importFromNotionAPI(token: "", into: try VaultPath("Courses"), updating: nil, transport: notion))
        let first = try await finishedSummary(of: workspace)
        XCTAssertNil(first.failureMessage)
        XCTAssertEqual(first.folder?.rawValue, "Courses/Notion")
        XCTAssertEqual(first.noteCount, 2)
        let index = try XCTUnwrap(workspace.index)
        try await waitUntil("the index has the imported notes") {
            (try? await index.resolve("Syllabus", from: try VaultPath("Courses/Index.md")))?.first?.rawValue == "Courses/Notion/Syllabus.md"
        }
        XCTAssertEqual(workspace.earlierNotionImports(in: try VaultPath("Courses")).map(\.rawValue), ["Courses/Notion"])

        let week = vault.appendingPathComponent("Courses/Notion/Syllabus/Week 1.md")
        let edited = try String(contentsOf: week, encoding: .utf8) + "\nAsk about exercise 3.\n"
        try edited.write(to: week, atomically: true, encoding: .utf8)
        notion.syllabusText = "Read chapter 1 before the first week."
        XCTAssertTrue(workspace.importFromNotionAPI(token: "", into: try VaultPath("Courses"), updating: try VaultPath("Courses/Notion"), transport: notion))
        let update = try await finishedSummary(of: workspace)
        XCTAssertNil(update.failureMessage)
        XCTAssertTrue(update.updatedEarlierImport)
        XCTAssertTrue(try String(contentsOf: vault.appendingPathComponent("Courses/Notion/Syllabus.md"), encoding: .utf8).contains("Read chapter 1"))
        XCTAssertEqual(try String(contentsOf: week, encoding: .utf8), edited)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Courses/Notion 2").path))
    }

    #if canImport(UIKit)
    func testTheSheetsAPIFormLaysOutWithItsTokenFieldAndEarlierImports() throws {
        let directory = try VaultPath("Courses"), earlier = try VaultPath("Courses/Notion")
        let form = Form {
            NotionAPIImportForm(directory: directory, earlierImports: [earlier],
                                start: { _, _, _ in }, tokenStore: NotionTokenStore(account: "hosted layout \(UUID().uuidString)"))
        }
        let controller = UIHostingController(rootView: NavigationStack { form })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.layoutIfNeeded()
        let size = controller.sizeThatFits(in: CGSize(width: 600, height: 2_000))
        XCTAssertGreaterThan(size.height, 200, "the form's sections are laid out")
    }
    #endif
}
