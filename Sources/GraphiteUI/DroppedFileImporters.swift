import Foundation
import GraphiteCore

/// An importer for one kind of file dropped on the library or the file list, or chosen with Import: it takes the files
/// of its types, and folders when it says so, instead of the plain copy into the folder. A new format adds one entry to
/// the importers `WorkspaceModel.importFiles` asks: Goodnotes and Notability notebooks are the workspace's own entry
/// (`WorkspaceModel.notebookFileImporter`), and `DroppedFileImporters.registered` lists the others.
struct FileTypeImporter {
    /// The lowercased file extensions this importer takes.
    let fileExtensions: Set<String>
    /// Whether it also takes folders, which have no extension to route by: a library export of notebooks.
    let takesFolders: Bool
    /// Imports the files into the folder and reports a failure itself. The batch holds the temporary copies of a drop
    /// that the files point into: the importer returns the ones it is done with, which the caller removes at once, and
    /// removes the others itself once it no longer reads them (a conversion that goes on after this returns).
    let importFiles: @MainActor ([URL], VaultPath, DroppedFileBatch) async -> DroppedFileBatch

    /// An importer that is done with its files when it returns.
    init(fileExtensions: Set<String>, importFiles: @escaping @MainActor ([URL], VaultPath) async -> Void) {
        self.fileExtensions = fileExtensions
        takesFolders = false
        self.importFiles = { files, folder, stagedCopies in
            await importFiles(files, folder)
            return stagedCopies
        }
    }

    /// An importer that may go on reading its files after it returns, and so may keep their temporary copies.
    init(fileExtensions: Set<String>, takesFolders: Bool,
         importFilesKeepingCopies: @escaping @MainActor ([URL], VaultPath, DroppedFileBatch) async -> DroppedFileBatch) {
        self.fileExtensions = fileExtensions
        self.takesFolders = takesFolders
        importFiles = importFilesKeepingCopies
    }

    func takes(_ source: URL) -> Bool {
        source.hasDirectoryPath ? takesFolders : fileExtensions.contains(source.pathExtension.lowercased())
    }
}

enum DroppedFileImporters {
    /// The importers asked before the plain copy after the workspace's own, in order; the first that takes a file takes it.
    static let registered: [FileTypeImporter] = []

    /// Which files and folders each importer takes, and those left for the plain copy.
    static func route(_ sources: [URL], through importers: [FileTypeImporter]) -> (routed: [(importer: FileTypeImporter, files: [URL])], remaining: [URL]) {
        var filesByImporter: [Int: [URL]] = [:]
        var remaining: [URL] = []
        for source in sources {
            if let position = importers.firstIndex(where: { importer in importer.takes(source) }) {
                filesByImporter[position, default: []].append(source)
            } else {
                remaining.append(source)
            }
        }
        let routed = filesByImporter.keys.sorted().map { position in (importer: importers[position], files: filesByImporter[position] ?? []) }
        return (routed, remaining)
    }
}

/// The name an imported file gets: its own, except that text files become notes, which is what
/// Obsidian opens.
enum ImportedFileName {
    private static let noteExtensions: Set<String> = ["txt", "text", "markdown", "mdown", "mkd"]

    static func fileExtension(forSourceExtension sourceExtension: String) -> String {
        noteExtensions.contains(sourceExtension.lowercased()) ? "md" : sourceExtension
    }
}
