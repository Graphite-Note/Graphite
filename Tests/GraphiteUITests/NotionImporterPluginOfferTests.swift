/**
 * File: NotionImporterPluginOfferTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: Import from Notion's offer of the Notion Importer plugin: the question names its version, size and source
 *              before anything is downloaded, a no downloads nothing, a yes installs the release asked about, and a
 *              vault that has it already is told so.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import XCTest
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteUI

/// The offer against GitHub answered by a script, with the plugin's real repository and identifier, so the addresses
/// asked for are the ones the app asks for.
@MainActor
final class NotionImporterPluginOfferTests: XCTestCase {
    private var vaultFolder: URL!
    private var store: VaultStore!
    private static let headManifestAddress = "https://raw.githubusercontent.com/Graphite-Note/Importer/HEAD/manifest.json"
    private static let releaseDataAddress = "https://api.github.com/repos/Graphite-Note/Importer/releases/tags/0.2.1"
    private static let releaseBase = "https://github.com/Graphite-Note/Importer/releases/download/0.2.1/"

    override func setUpWithError() throws {
        vaultFolder = try TemporaryVault.make(prefix: "NotionImporterPluginOffer", for: self).root
        store = VaultStore(root: vaultFolder)
        OfferGitHubProtocol.script.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vaultFolder)
        OfferGitHubProtocol.script.reset()
    }

    private func manifest(version: String) -> String {
        #"{"id": "graphite-notion-importer", "name": "Notion Importer", "version": ""# + version
            + #"", "minAppVersion": "1.4.0", "author": "Bahey Shalash", "description": "Imports Notion's HTML export."}"#
    }

    private func answerTheRelease() {
        OfferGitHubProtocol.script.answer(Self.headManifestAddress, manifest(version: "0.2.1"))
        OfferGitHubProtocol.script.answer(Self.releaseDataAddress,
            #"{"assets": [{"name": "main.js", "size": 1252087}, {"name": "manifest.json", "size": 485}, {"name": "styles.css", "size": 673}]}"#)
        OfferGitHubProtocol.script.answer(Self.releaseBase + "main.js", "module.exports = class {};")
        OfferGitHubProtocol.script.answer(Self.releaseBase + "manifest.json", manifest(version: "0.2.1"))
        OfferGitHubProtocol.script.answer(Self.releaseBase + "styles.css", ".notion-importer {}")
    }

    private func makeOffer(installedVersion: String? = nil, installed: @escaping @MainActor (CommunityPluginInstaller.Installation) -> Void = { _ in }) -> NotionImporterPluginOffer {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfferGitHubProtocol.self]
        return NotionImporterPluginOffer(installer: CommunityPluginInstaller(store: store, session: URLSession(configuration: configuration)),
                                         installedVersion: { installedVersion }, pluginsDidChange: { installation in
            installed(installation)
            return "Installed \(installation.manifest.name) \(installation.manifest.version)."
        })
    }

    private func pluginFileExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: vaultFolder.appendingPathComponent(".obsidian/plugins/graphite-notion-importer/\(name)").path)
    }

    func testTheQuestionNamesTheVersionSizeAndSourceBeforeAnythingIsDownloaded() async throws {
        answerTheRelease()
        let offer = makeOffer()

        await offer.ask()

        guard case .asking(let question) = offer.state else { return XCTFail("expected the question, got \(offer.state)") }
        XCTAssertEqual(question.release.version, "0.2.1")
        XCTAssertEqual(question.byteCount, 1_253_245)
        XCTAssertEqual(NotionImportWording.pluginQuestionTitle(question), "Download Notion Importer 0.2.1?")
        let message = NotionImportWording.pluginQuestion(question)
        XCTAssertTrue(message.contains("from github.com/Graphite-Note/Importer"), message)
        XCTAssertTrue(message.contains(1_253_245.formatted(.byteCount(style: .file))), message)
        XCTAssertEqual(OfferGitHubProtocol.script.requestedAddresses, [Self.headManifestAddress, Self.releaseDataAddress],
                       "only the manifest and the release's sizes are read before the yes")
        XCTAssertFalse(pluginFileExists("main.js"))
    }

    func testANoDownloadsNothingAndTheOfferIsBack() async throws {
        answerTheRelease()
        let offer = makeOffer()
        await offer.ask()

        offer.decline()

        XCTAssertEqual(offer.state, .offered)
        XCTAssertFalse(OfferGitHubProtocol.script.requestedAddresses.contains { address in address.hasPrefix(Self.releaseBase) })
        XCTAssertFalse(pluginFileExists("main.js"))
    }

    func testAYesInstallsTheReleaseAskedAboutEvenIfTheRepositoryMovedOn() async throws {
        answerTheRelease()
        var installations: [String] = []
        let offer = makeOffer { installation in installations.append(installation.manifest.version) }
        await offer.ask()
        OfferGitHubProtocol.script.answer(Self.headManifestAddress, manifest(version: "0.3.0"))

        let installing = offer.install()
        XCTAssertEqual(offer.state, .installing, "the yes is taken before the alert closes")
        offer.decline()
        XCTAssertEqual(offer.state, .installing, "an alert closing after its button changes nothing")
        await installing?.value

        XCTAssertEqual(offer.state, .finished("Installed Notion Importer 0.2.1."))
        XCTAssertEqual(installations, ["0.2.1"])
        XCTAssertEqual(try String(contentsOf: vaultFolder.appendingPathComponent(".obsidian/plugins/graphite-notion-importer/main.js"), encoding: .utf8),
                       "module.exports = class {};")
        XCTAssertTrue(pluginFileExists("manifest.json"))
        XCTAssertTrue(pluginFileExists("styles.css"))
    }

    func testAVaultWithTheNewestReleaseIsToldSoAndNotAsked() async throws {
        answerTheRelease()
        let offer = makeOffer(installedVersion: "0.2.1")

        await offer.ask()

        XCTAssertEqual(offer.state, .finished(NotionImportWording.pluginIsInstalled(name: "Notion Importer", version: "0.2.1")))
        XCTAssertEqual(OfferGitHubProtocol.script.requestedAddresses, [Self.headManifestAddress])
    }

    func testAnOlderInstalledReleaseIsOfferedAsAnUpdateThatKeepsItsSettings() async throws {
        answerTheRelease()
        let offer = makeOffer(installedVersion: "0.2.0")

        await offer.ask()

        guard case .asking(let question) = offer.state else { return XCTFail("expected the question, got \(offer.state)") }
        XCTAssertEqual(NotionImportWording.pluginQuestionTitle(question), "Update Notion Importer 0.2.1?")
        XCTAssertTrue(NotionImportWording.pluginQuestion(question).contains("replacing version 0.2.0"))
    }

    func testWithoutTheSizeTheQuestionSaysSoAndAnUnreachableReleaseDownloadsNothing() async throws {
        OfferGitHubProtocol.script.answer(Self.headManifestAddress, manifest(version: "0.2.1"))
        let offer = makeOffer()
        await offer.ask()
        guard case .asking(let question) = offer.state else { return XCTFail("expected the question, got \(offer.state)") }
        XCTAssertNil(question.byteCount)
        XCTAssertTrue(NotionImportWording.pluginQuestion(question).hasPrefix("From github.com/Graphite-Note/Importer, whose size GitHub did not give"))

        offer.decline()
        OfferGitHubProtocol.script.reset()
        await offer.ask()

        guard case .finished(let outcome) = offer.state else { return XCTFail("expected an outcome, got \(offer.state)") }
        XCTAssertTrue(outcome.hasPrefix("The plugin's release could not be read, so nothing was downloaded."), outcome)
        XCTAssertTrue(outcome.hasSuffix("Downloading manifest.json failed (HTTP 404)."), "the installer's own reason, not the error's description: \(outcome)")
        XCTAssertEqual(NotionImportWording.pluginFailureReason(URLError(.notConnectedToInternet)),
                       "GitHub could not be reached. Check the connection and try again.")
        XCTAssertFalse(pluginFileExists("main.js"))
    }
}

/// GitHub answered from a script: 404 for an address without an answer.
private final class OfferGitHubProtocol: URLProtocol {
    final class Script: @unchecked Sendable {
        // Requests arrive on URL loading threads; the lock orders them.
        private let lock = NSLock()
        private var bodiesByAddress: [String: Data] = [:]
        private var addresses: [String] = []
        var requestedAddresses: [String] { lock.withLock { addresses } }
        func answer(_ address: String, _ body: String) { lock.withLock { bodiesByAddress[address] = Data(body.utf8) } }
        func record(_ address: String) -> Data? { lock.withLock { addresses.append(address); return bodiesByAddress[address] } }
        func reset() { lock.withLock { bodiesByAddress = [:]; addresses = [] } }
    }

    static let script = Script()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.script.record(url.absoluteString)
        guard let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
