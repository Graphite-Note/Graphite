/**
 * File: NeuralVoiceDownloaderResumeDataTests.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: Checks that a voice download whose saved resume data is no good starts the file again instead of failing every time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteCore
@testable import GraphiteVoices
import GraphiteTestSupport

/// Answers every download request by never finishing, and tells the test which address was asked for. No network is used
/// and nothing is played: the downloader only moves files.
private final class StalledRequestProtocol: URLProtocol {
    nonisolated(unsafe) static var onRequest: (@Sendable (URL?) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onRequest?(request.url) }
    override func stopLoading() {}
}

/// HUNT-230: a stale `.resume` file was read for every attempt and deleted only after a successful file, so one that no
/// longer worked made every automatic retry and every Resume fail the same way until the voice was deleted.
final class NeuralVoiceDownloaderResumeDataTests: XCTestCase {
    private var voicesFolder: URL!

    override func setUpWithError() throws {
        voicesFolder = try TemporaryVault.make(prefix: "NeuralVoiceResumeData", for: self).root
    }

    override func tearDownWithError() throws {
        StalledRequestProtocol.onRequest = nil
        try? FileManager.default.removeItem(at: voicesFolder) // Best-effort removal of a temporary folder.
    }

    private func makeVoice() -> NeuralVoiceDescription {
        NeuralVoiceDescription(
            id: "test-voice", name: "Test Voice", modelName: "Test model", modelFamily: .pocketTTS, speaker: nil, language: "en",
            qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "Test", address: URL(string: "https://example.com/license")!),
            sources: [NeuralVoiceSource(repository: "owner/model", revision: "abc123", files: [
                NeuralVoiceFile(path: "weights/model.safetensors", byteCount: 1_000, sha256: String(repeating: "0", count: 64))
            ])],
            platforms: ["macOS", "iOS"], minimumPhysicalMemoryBytes: 0)
    }

    func testResumeDataThatIsNoUseIsDroppedAndTheFileStartsAgainFromItsAddress() async throws {
        let voice = makeVoice()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StalledRequestProtocol.self]
        let installation = NeuralVoiceInstallation(voicesFolder: voicesFolder)
        let manifest = NeuralVoiceManifest(downloadHost: URL(string: "https://voices.example.com")!, voices: [voice])
        let downloader = NeuralVoiceDownloader(manifest: manifest, installation: installation, configuration: configuration) { _, _ in }
        let resumeFile = installation.stagingFolder(of: voice).appendingPathComponent("weights/model.safetensors.resume")
        try FileManager.default.createDirectory(at: resumeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not resume data".utf8).write(to: resumeFile)
        let requested = expectation(description: "The file is requested from its address")
        nonisolated(unsafe) var address: URL?
        StalledRequestProtocol.onRequest = { requestedAddress in address = requestedAddress; requested.fulfill() }

        downloader.download(voice)
        await fulfillment(of: [requested], timeout: 30)

        XCTAssertEqual(address?.absoluteString, "https://voices.example.com/owner/model/resolve/abc123/weights/model.safetensors")
        XCTAssertFalse(FileManager.default.fileExists(atPath: resumeFile.path), "Resume data is used once, so a bad copy cannot fail every attempt.")
        downloader.remove(voice)
    }
}
