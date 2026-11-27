/**
 * File: NotionImportRun.swift
 * ---------------------------
 * Layer: UI
 * Description: The work of one import from Notion, away from the main actor: the chosen zips or folder of Notion's
 *              HTML export, or the workspace read through Notion's API, written with the Importer into a new folder of
 *              the vault or over an earlier import.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore
import ImporterCore
import ImporterFileSystem
import NotionImport

/// What an import of Notion's export has done so far: the pages written of all the export's pages.
struct NotionImportProgress: Equatable, Sendable {
    var finishedPageCount = 0
    var pageCount = 0

    /// Nil while the export is still being read, before its pages are counted.
    var fractionCompleted: Double? {
        pageCount > 0 ? Double(finishedPageCount) / Double(pageCount) : nil
    }
}

/// How an import of Notion's export ended.
struct NotionImportSummary: Equatable, Sendable {
    /// The folder the import made, nil when it failed before making one.
    var folder: GraphiteCore.VaultPath?
    /// The import's report note, nil when it failed before writing one.
    var reportPath: GraphiteCore.VaultPath?
    var noteCount = 0
    var baseCount = 0
    var attachmentCount = 0
    /// The report's findings: what was left out, simplified or failed.
    var findingCount = 0
    var wasCancelled = false
    /// Why nothing could be imported, as the person reads it; nil when the import ran.
    var failureMessage: String?
    /// Why an import through the API ended before its end (a revoked token, Notion unreachable), with what it wrote kept.
    var stoppedBecause: String?
    /// Whether the import updated an earlier import of the same workspace instead of making a new folder.
    var updatedEarlierImport = false
}

/// The work of one import of Notion's HTML export. The chosen files are Notion's zip (or the `Part-N` zips of a large
/// export) or the folder it unzips to. They are read where they are, never changed, and a nested zip Notion compressed
/// is inflated into a temporary folder that is removed when the import ends. The export goes into a new folder named
/// "Notion" (a free name, "Notion 1" when it is taken) in the chosen vault folder, with its report note at its top.
struct NotionImportRun: Sendable {
    /// The name of the folder an import makes.
    static let folderName = "Notion"

    let store: VaultStore
    let pause: NotionImportPause
    /// Called on the main actor with each batch of files written, so they show while the import goes on.
    let filesDidChange: @MainActor @Sendable ([GraphiteCore.VaultPath]) async -> Void
    /// The import's day, as its report names it, and the year given to dates Notion wrote without one.
    let importDate: Date
    /// The calendar `importDate` is read in.
    let calendar: Calendar

    func run(sources: [URL], into directory: GraphiteCore.VaultPath, progress: AsyncStream<NotionImportProgress>.Continuation) async -> NotionImportSummary {
        var summary = NotionImportSummary()
        let accessedSources = sources.filter { source in source.startAccessingSecurityScopedResource() }
        defer { for source in accessedSources { source.stopAccessingSecurityScopedResource() } }
        let temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("NotionImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) } // Inflated nested zips only, never the person's files.
        progress.yield(NotionImportProgress())
        let writtenFiles = NotionImportWrittenFiles(deliver: filesDidChange)
        do {
            let tree = try await exportFileTree(of: sources, temporaryFolder: temporaryFolder)
            let folder = try await store.uniquePath(directory: directory, stem: Self.folderName, extension: "")
            summary.folder = folder
            let destination = NotionImportDestination(store: store, pause: pause, filesWritten: writtenFiles)
            let options = NotionHTMLImportOptions(destinationFolder: try Self.importerPath(of: folder), exportName: Self.exportName(of: sources),
                                                  importDate: Self.dayText(of: importDate, in: calendar),
                                                  exportYear: calendar.component(.year, from: importDate)) { finishedPageCount, pageCount in
                progress.yield(NotionImportProgress(finishedPageCount: finishedPageCount, pageCount: pageCount))
            }
            let result = try await NotionHTMLImporter.importExport(tree, into: destination, options: options)
            summary.reportPath = try NotionImportDestination.vaultPath(of: result.reportPath)
            summary.noteCount = result.report.writtenCount(of: .note)
            summary.baseCount = result.report.writtenCount(of: .base)
            summary.attachmentCount = result.report.writtenCount(of: .attachment)
            summary.findingCount = result.report.findings.count
            summary.wasCancelled = result.wasCancelled
        } catch let refusal as NotionImportError {
            summary.failureMessage = refusal.description
        } catch {
            summary.failureMessage = Self.failureMessage(for: error)
        }
        await writtenFiles.deliverPending()
        if let folder = summary.folder, (try? await store.fileExists(folder)) == true { await filesDidChange([folder]) } // Nothing to show when none was made.
        return summary
    }

    /// The files of the chosen export: one folder as it is on disk, or the zips, each read by range so that an export of
    /// gigabytes is never held whole.
    private func exportFileTree(of sources: [URL], temporaryFolder: URL) async throws -> ExportFileTree {
        if sources.count == 1, let folder = sources.first, folder.hasDirectoryPath {
            return try ExportFileTree.reading(folder: folder)
        }
        let zips = try sources.map { source in try FileRandomAccessSource(url: source) }
        return try await ExportFileTree.reading(zipArchives: zips, named: sources.map(\.lastPathComponent),
                                                temporaryStorage: try FolderTemporaryStorage(folder: temporaryFolder))
    }

    static func importerPath(of path: GraphiteCore.VaultPath) throws -> ImporterCore.VaultPath {
        let components = path.rawValue.split(separator: "/").map(String.init)
        guard let importerPath = ImporterCore.VaultPath(components: components) else {
            throw NotionImportFileFailure.notAVaultFolder(path: path.rawValue)
        }
        return importerPath
    }

    /// The export as the report names it: "Export-1a2b.zip", or "Export-1a2b.zip and 2 more" for the parts of a large one.
    static func exportName(of sources: [URL]) -> String {
        guard let first = sources.first?.lastPathComponent else { return "Notion" }
        return sources.count == 1 ? first : "\(first) and \(sources.count - 1) more"
    }

    /// The day as the report writes it, "2026-11-26".
    static func dayText(of date: Date, in calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let year = day.year ?? 0, month = day.month ?? 0, dayOfMonth = day.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    /// Imports the workspace `client` reads through Notion's API into a new folder "Notion" in `directory`, or over the
    /// earlier import in `earlierImport`, where only what nobody changed since is replaced.
    func runAPI(client: NotionAPIClient, into directory: GraphiteCore.VaultPath, updating earlierImport: GraphiteCore.VaultPath?,
                progress: AsyncStream<NotionImportProgress>.Continuation) async -> NotionImportSummary {
        var summary = NotionImportSummary()
        summary.updatedEarlierImport = earlierImport != nil
        progress.yield(NotionImportProgress())
        let writtenFiles = NotionImportWrittenFiles(deliver: filesDidChange)
        do {
            let folder: GraphiteCore.VaultPath
            if let earlierImport {
                folder = earlierImport
            } else {
                folder = try await store.uniquePath(directory: directory, stem: Self.folderName, extension: "")
            }
            summary.folder = folder
            let destination = NotionImportDestination(store: store, pause: pause, filesWritten: writtenFiles)
            let options = NotionAPIImportOptions(destinationFolder: try Self.importerPath(of: folder), importDate: Self.dayText(of: importDate, in: calendar)) {
                finishedPageCount, pageCount in
                progress.yield(NotionImportProgress(finishedPageCount: finishedPageCount, pageCount: pageCount))
            }
            let result = earlierImport == nil
                ? try await NotionAPIImporter.importWorkspace(client: client, into: destination, options: options)
                : try await NotionAPIImporter.updateImport(client: client, in: destination, options: options)
            summary.reportPath = try NotionImportDestination.vaultPath(of: result.reportPath)
            summary.noteCount = result.report.writtenCount(of: .note)
            summary.baseCount = result.report.writtenCount(of: .base)
            summary.attachmentCount = result.report.writtenCount(of: .attachment)
            summary.findingCount = result.report.findings.count
            summary.wasCancelled = result.wasCancelled
            summary.stoppedBecause = result.stoppedBecause
        } catch let refusal as NotionAPIError {
            summary.failureMessage = "Notion could not be read: \(refusal.description)"
        } catch {
            summary.failureMessage = Self.failureMessage(for: error)
        }
        await writtenFiles.deliverPending()
        if let folder = summary.folder, (try? await store.fileExists(folder)) == true { await filesDidChange([folder]) } // Nothing to show when none was made.
        return summary
    }

    /// The folders in `directory` holding an earlier import through Notion's API, which a new import can update: each
    /// keeps the record `NotionAPIImporter` leaves there.
    static func earlierImports(in directory: GraphiteCore.VaultPath, root: URL) -> [GraphiteCore.VaultPath] {
        guard let folder = try? directory.url(in: root) else { return [] } // Not a folder of the vault: nothing to update there.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] // Unlisted: the sheet offers a new folder alone.
        return names.sorted().compactMap { name in
            let record = folder.appendingPathComponent(name).appendingPathComponent(".notion-import.json")
            guard FileManager.default.fileExists(atPath: record.path) else { return nil }
            return try? GraphiteCore.VaultPath(directory.rawValue.isEmpty ? name : directory.rawValue + "/" + name) // A name no vault path takes is skipped.
        }
    }

    /// An error that stopped the import before its first page, as the person reads it.
    static func failureMessage(for error: Error) -> String {
        switch error {
        case let failure as ZipArchiveError:
            "The export could not be read as a zip file (\(failure)). Choose the .zip file Notion's export gave, or the folder it unzips to."
        default:
            "The export could not be imported (\(error))."
        }
    }
}
