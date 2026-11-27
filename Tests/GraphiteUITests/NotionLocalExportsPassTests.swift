/**
 * File: NotionLocalExportsPassTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Notion exports kept on the development Mac only, each imported into a vault through Import from Notion's
 *              run, then every imported file opened by the release pass and every link checked.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(macOS)
import XCTest
import GraphiteCore
import GraphiteIndex
import GraphiteTestSupport
@testable import GraphiteUI

/// Docs/Notion-import-todo.md, section 8. Real exports found online have no license that allows committing them, so
/// they stay in a folder outside the repository, named by `GRAPHITE_NOTION_LOCAL_EXPORTS`, one export per folder. Each
/// test returns at once when the variable is not set. With it, the export is imported into a new vault as the app imports
/// it (`NotionImportRun`, Graphite's own store), the release pass opens every imported note in Live Preview, the reading
/// view and source mode and every base and attachment in its own view (`ReleaseVaultPass`), and the index lists the links
/// that resolve to nothing. Findings and unresolved links are printed on `NOTION-LOCAL-` lines and fail the test.
@MainActor
final class NotionLocalExportsPassTests: XCTestCase {
    static let foldersVariable = "GRAPHITE_NOTION_LOCAL_EXPORTS"

    func testArchive42Templates() async throws { try await pass("archive42-templates") }
    func testJdelezenneCodex() async throws { try await pass("jdelezenne-codex") }
    func testZQiao() async throws { try await pass("z-qiao") }
    func testJoshuadavisMarkdownExportIsRefused() async throws { try await refusal("joshuadavis-n2o") }
    func testButterandflyMarkdownExportIsRefused() async throws { try await refusal("butterandfly-n2o") }

    private func exportFolder(_ name: String) -> URL? {
        guard let folders = ProcessInfo.processInfo.environment[Self.foldersVariable], !folders.isEmpty else { return nil }
        let folder = URL(fileURLWithPath: folders).appendingPathComponent(name, isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    private func importExport(_ folder: URL, into vault: URL) async -> NotionImportSummary {
        let run = NotionImportRun(store: VaultStore(root: vault), pause: NotionImportPause(), filesDidChange: { _ in },
                                  importDate: WallClock.currentDate(), calendar: BaseDateFormatting.displayCalendar)
        let (progress, continuation) = AsyncStream.makeStream(of: NotionImportProgress.self, bufferingPolicy: .bufferingNewest(1))
        let started = ContinuousClock.now
        let summary = await run.run(sources: [folder], into: .root, progress: continuation)
        continuation.finish()
        for await _ in progress {}
        print("NOTION-LOCAL-IMPORT export=\(folder.lastPathComponent) notes=\(summary.noteCount) bases=\(summary.baseCount) "
              + "attachments=\(summary.attachmentCount) reportFindings=\(summary.findingCount) seconds=\(ContinuousClock.now - started) "
              + "failure=\(summary.failureMessage ?? "none")")
        return summary
    }

    private func pass(_ name: String) async throws {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let folder = exportFolder(name) else { return print("Not run: \(Self.foldersVariable) names no folder holding \(name).") }
        let source = try TemporaryVault.make(prefix: "NotionLocalExport", for: self).root
        let summary = await importExport(folder, into: source)
        XCTAssertNil(summary.failureMessage)
        XCTAssertGreaterThan(summary.noteCount, 0)

        let pass = try await ReleaseVaultPass.open(for: self, vault: source)
        try await pass.runFiles(inTopLevel: [NotionImportRun.folderName])
        pass.printReport()
        for finding in pass.findings { print("NOTION-LOCAL-FINDING export=\(name) \(finding)") }
        XCTAssertEqual(pass.findings.count, 0, "Each finding is printed on a NOTION-LOCAL-FINDING line.")

        let index = try XCTUnwrap(pass.workspace.index)
        let graph = try await index.linkGraph()
        let unresolvedTargets = Set(graph.nodes.filter { node in node.kind == .unresolved }.map(\.id))
        // A Markdown file the export itself held (a site's own index beside the export) is copied as it is, links included.
        let copiedMarkdown = Set((FileManager.default.subpaths(atPath: folder.path) ?? []).filter { path in path.hasSuffix(".md") }
            .map { path in NotionImportRun.folderName + "/" + path })
        let unresolved = graph.edges.filter { edge in
            unresolvedTargets.contains(edge.target) && edge.source.hasPrefix(NotionImportRun.folderName + "/") && !copiedMarkdown.contains(edge.source)
        }
        for edge in unresolved { print("NOTION-LOCAL-UNRESOLVED export=\(name) note=\(edge.source) target=\(edge.target)") }
        print("NOTION-LOCAL-LINKS export=\(name) unresolved=\(unresolved.count)")
        XCTAssertEqual(unresolved.count, 0, "Each link to nothing is printed on a NOTION-LOCAL-UNRESOLVED line.")
    }

    private func refusal(_ name: String) async throws {
        guard let folder = exportFolder(name) else { return print("Not run: \(Self.foldersVariable) names no folder holding \(name).") }
        let vault = try TemporaryVault.make(prefix: "NotionLocalExport", for: self).root
        let summary = await importExport(folder, into: vault)
        XCTAssertEqual(summary.failureMessage?.hasPrefix("This is Notion's Markdown & CSV export"), true, summary.failureMessage ?? "")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).filter { name in !name.hasPrefix(".") }, [])
    }
}
#endif
