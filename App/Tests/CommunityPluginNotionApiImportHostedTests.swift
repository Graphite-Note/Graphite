/**
 * File: CommunityPluginNotionApiImportHostedTests.swift
 * -----------------------------------------------------
 * Layer: Tests
 * Description: Obsidian's Importer importing a made-up Notion workspace through Notion's API in WebKit, inside the app,
 *              with Graphite's own native requests answered as Notion answers them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */
import XCTest
import os
import SwiftUI
import WebKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Notion import, 3.2, in the app: Importer's Notion account import walked on the plugin panel, its token linked with the
/// secret control (the keychain), its requests made by Graphite natively (`requestUrl`) and answered, as the Node tests'
/// made-up workspace answers them, by `NotionAnswersURLProtocol` from `fixtures/notion-api-answers.json`. The vault must come
/// out byte for byte as the Node tests expect (`notion-api-import-expected.json`), and Graphite's index must resolve the
/// page's embed of its database's base. Skipped, as the other real plugins' tests here, when Importer is not built.
@MainActor
extension CommunityPluginHostTests {
    private static let apiImporterIdentifier = "obsidian-importer"
    private static let apiExpectedImport = runtimeTestsFolder.appendingPathComponent("fixtures/notion-api-import-expected.json")

    func testImporterImportsTheNotionWorkspaceThroughGraphitesNativeRequestsAsTheNodeTestsExpect() async throws {
        let answers = try NotionAnswers.load(from: runtimeTestsFolder.appendingPathComponent("fixtures/notion-api-answers.json"))
        NotionAnswersURLProtocol.answers.replace(with: answers)
        XCTAssertTrue(URLProtocol.registerClass(NotionAnswersURLProtocol.self))
        addTeardownBlock { URLProtocol.unregisterClass(NotionAnswersURLProtocol.self) }
        let (workspace, vault) = try await workspaceAndVaultWithBuiltPlugins([Self.apiImporterIdentifier], notes: ["Welcome.md": "# Welcome\n"])
        let host = workspace.communityPlugins

        let summary = try await runNotionApiImport(in: host, token: NotionAnswers.token)

        XCTAssertEqual(summary["imported"] as? Int, 3, "\(summary)")
        XCTAssertEqual(summary["failed"] as? Int, 0, "\(summary)")
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Self.apiExpectedImport)) as? [String: String])
        for (path, contents) in expected {
            XCTAssertEqual(try? String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8), contents, path)
        }
        XCTAssertEqual(NotionAnswersURLProtocol.answers.unansweredRequests(), [], "every request had a recorded answer")
        let index = try XCTUnwrap(workspace.index)
        let page = try VaultPath("Notion/Signals and Systems/Signals and Systems.md")
        try await waitUntil("the index has the imported page", timeoutSeconds: 30) { (try? await index.outgoingLinks(from: page))?.isEmpty == false }
        let targets = try await index.outgoingLinks(from: page)
        let resolved = try await index.resolve(wikilinks: targets, from: page)
        XCTAssertEqual(targets.filter { target in resolved[target] == nil }, [], "the base embed resolves")
    }

    /// Walks Importer's Notion account import as a person does: its settings, Notion, Notion account, the token saved as a
    /// secret and linked, the pages loaded and all chosen, then Continue until Done.
    private func runNotionApiImport(in host: CommunityPluginHost, token: String) async throws -> [String: Any] {
        let hasSettings = await host.showSettings(of: Self.apiImporterIdentifier)
        XCTAssertTrue(hasSettings, "Importer has its settings tab")
        let webView = try XCTUnwrap(host.webView)
        let script = """
            const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
            const waitFor = async (condition, what) => {
                const deadline = Date.now() + 120000;
                while (!condition()) {
                    if (Date.now() > deadline) throw new Error('Waited for ' + what + ': ' + topPage().textContent.slice(0, 300));
                    await pause(200);
                }
            };
            const clickSetting = (name) => {
                const row = Array.from(document.querySelectorAll('.setting-item'))
                    .find((element) => (element.querySelector('.setting-item-name') || {}).textContent === name);
                if (!row) throw new Error('No setting named ' + name);
                row.click();
            };
            const topPage = () => Array.from(document.querySelectorAll('.setting-page')).at(-1);
            const pageButtons = () => Array.from(topPage().querySelectorAll('button'));
            const buttons = () => Array.from(document.querySelectorAll('.importer-button-bar button.mod-cta'));
            const type = (field, text) => { field.value = text; field.dispatchEvent(new Event('input')); };
            await pause(100);
            clickSetting('Notion');
            await pause(100);
            clickSetting('Notion account (recommended)');
            await pause(500);
            topPage().querySelector('button.graphite-secret-link').click();
            await pause(200);
            const secretWindow = Array.from(document.querySelectorAll('.modal-container .modal')).at(-1);
            const [nameField, secretField] = secretWindow.querySelectorAll('input');
            type(nameField, 'notion-token');
            type(secretField, token);
            Array.from(secretWindow.querySelectorAll('button')).find((button) => button.textContent === 'Save and link').click();
            await pause(500);
            await waitFor(() => !pageButtons().some((button) => /Loading/.test(button.textContent)), 'the page list');
            await waitFor(() => pageButtons().some((button) => button.textContent === 'Select all'), 'the pages');
            pageButtons().find((button) => button.textContent === 'Select all').click();
            await pause(300);
            const deadline = Date.now() + 300000;
            while (!buttons().some((button) => button.textContent === 'Done')) {
                if (Date.now() > deadline) throw new Error('The import did not finish: ' + topPage().textContent.slice(0, 300));
                const button = buttons()[0];
                if (button && !button.disabled && !button.dataset.graphiteClicked) {
                    button.dataset.graphiteClicked = 'yes';
                    button.click();
                }
                await pause(200);
            }
            const count = (name) => {
                const element = document.querySelector('.importer-stat.mod-' + name + ' .importer-stat-count');
                return element ? Number(element.textContent.replace(/[^0-9]/g, '')) : -1;
            };
            return { imported: count('imported'), failed: count('failed'),
                     log: Array.from(topPage().querySelectorAll('.importer-log .list-item')).map((element) => element.textContent) };
            """
        let answer = try await webView.callAsyncJavaScript(script, arguments: ["token": token], in: nil, contentWorld: .page)
        return try XCTUnwrap(answer as? [String: Any])
    }
}

/// Notion's answers to the requests of one import of the made-up workspace, by method and path, as the Node tests recorded
/// them (`support/notion-api-fixture.js`); a request without one is answered as Notion answers an unknown address.
struct NotionAnswers: Sendable {
    struct Answer: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    /// The made-up token the answers expect (`notionTestToken` of the fixture); nothing real.
    static let token = "ntn_made_up_test_token"
    let answersByRequest: [String: Answer]

    static func load(from location: URL) throws -> NotionAnswers {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: location)) as? [String: [String: Any]])
        var answers: [String: Answer] = [:]
        for (request, answer) in object {
            let body = try XCTUnwrap(Data(base64Encoded: answer["bodyBase64"] as? String ?? ""), request)
            answers[request] = Answer(status: answer["status"] as? Int ?? 500, headers: answer["headers"] as? [String: String] ?? [:], body: body)
        }
        return NotionAnswers(answersByRequest: answers)
    }
}

/// The answers the protocol gives, and the requests it had none for, kept behind a lock: URL loading calls the protocol on
/// its own threads.
final class NotionAnswersStore: Sendable {
    private struct Contents: Sendable {
        var answers: NotionAnswers?
        var unanswered: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: Contents())

    func replace(with answers: NotionAnswers) { state.withLock { contents in contents = Contents(answers: answers) } }

    func answer(to request: String) -> NotionAnswers.Answer? {
        state.withLock { contents in
            guard let answer = contents.answers?.answersByRequest[request] else {
                contents.unanswered.append(request)
                return nil
            }
            return answer
        }
    }

    func unansweredRequests() -> [String] { state.withLock { contents in contents.unanswered } }
}

/// Answers Graphite's native requests to api.notion.com from `NotionAnswers`, checking the token as Notion does.
final class NotionAnswersURLProtocol: URLProtocol {
    static let answers = NotionAnswersStore()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.notion.com" }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let address = request.url else { return }
        let key = (request.httpMethod ?? "GET").uppercased() + " " + address.path
        let isAuthorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer " + NotionAnswers.token
        let unknown = NotionAnswers.Answer(status: 400, headers: ["content-type": "application/json"],
                                           body: Data(#"{"object":"error","status":400,"code":"invalid_request_url","message":"Invalid request URL."}"#.utf8))
        let unauthorized = NotionAnswers.Answer(status: 401, headers: ["content-type": "application/json"],
                                                body: Data(#"{"object":"error","status":401,"code":"unauthorized","message":"API token is invalid."}"#.utf8))
        let answer = isAuthorized ? (Self.answers.answer(to: key) ?? unknown) : unauthorized
        guard let response = HTTPURLResponse(url: address, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
