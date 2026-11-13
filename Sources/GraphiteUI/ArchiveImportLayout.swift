/**
 * File: ArchiveImportLayout.swift
 * -------------------------------
 * Layer: UI
 * Description: Where the files of an opened ZIP archive go in the vault, as Archive Utility lays them out in the Finder,
 *              and how the import words what it could not do.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import GraphiteApple

/// Where the files of an unpacked archive go, as Archive Utility puts them in the Finder: a single file at the
/// archive's top goes where the archive was opened, by itself; anything else goes into one new folder, the archive's
/// own top folder when everything is inside one (a zipped folder of notebooks), else a folder named after the archive
/// (a Goodnotes export of several notebooks). Below that folder, the archive's folders are kept.
struct ArchiveImportLayout: Equatable {
    struct PlacedFile: Equatable {
        let location: URL
        /// The folder names between the archive's new folder and the file; empty for a file directly in it.
        let folderNames: [String]
    }

    /// The name of the folder made for the archive; nil for a single file, which goes into the destination itself.
    let folderName: String?
    /// The unpacked folder whose contents are the new folder's: the notebook import lists its notebooks from here.
    let contentsFolder: URL
    /// In the archive's order.
    let files: [PlacedFile]

    init(_ unpacked: UnpackedArchive, archiveStem: String) {
        let topNames = Set(unpacked.files.map { file in file.pathComponents[0] })
        let everyFileIsInAFolder = unpacked.files.allSatisfy { file in file.pathComponents.count > 1 }
        if unpacked.files.count == 1, let file = unpacked.files.first, file.pathComponents.count == 1 {
            folderName = nil
            contentsFolder = unpacked.folder
            files = [PlacedFile(location: file.location, folderNames: [])]
        } else if topNames.count == 1, everyFileIsInAFolder, let topName = topNames.first {
            folderName = topName
            contentsFolder = unpacked.folder.appendingPathComponent(topName, isDirectory: true)
            files = unpacked.files.map { file in PlacedFile(location: file.location, folderNames: Array(file.pathComponents.dropFirst().dropLast())) }
        } else {
            folderName = archiveStem
            contentsFolder = unpacked.folder
            files = unpacked.files.map { file in PlacedFile(location: file.location, folderNames: Array(file.pathComponents.dropLast())) }
        }
    }

    /// The files grouped by their folder, the groups in the order their first file comes in the archive.
    var filesByFolder: [(folderNames: [String], files: [PlacedFile])] {
        var groups: [(folderNames: [String], files: [PlacedFile])] = []
        var groupIndexByFolder: [[String]: Int] = [:]
        for file in files {
            if let groupIndex = groupIndexByFolder[file.folderNames] {
                groups[groupIndex].files.append(file)
            } else {
                groupIndexByFolder[file.folderNames] = groups.count
                groups.append((file.folderNames, [file]))
            }
        }
        return groups
    }
}

/// What the import of an opened archive tells the person when it could not do everything.
enum ArchiveImportWording {
    /// How many names a message lists before it counts the rest.
    private static let listedNameCount = 5

    static func failure(_ failure: ArchiveUnpackingFailure, archiveName: String) -> String {
        let reason = switch failure {
        case .unreadable: "the file could not be read"
        case .notAZipArchive: "it is not a ZIP archive, or its end is missing"
        case .damaged: "the archive is damaged"
        case .needsZip64: "it is larger than 4 GB or holds more than 65,535 files, which Graphite does not unpack"
        case .tooManyFiles(let count, let limit): "it holds \(count.formatted()) files, more than the \(limit.formatted()) Graphite unpacks"
        case .tooLarge(let byteCount, let limitBytes): "it unpacks to \(size(byteCount)), more than the \(size(limitBytes)) Graphite unpacks"
        case .notEnoughRoom(let byteCount): "it unpacks to \(size(byteCount)), more than this device has free"
        }
        return "Graphite could not import “\(archiveName)”: \(reason)."
    }

    static func noUnpackingFolder(archiveName: String) -> String {
        "Graphite could not import “\(archiveName)”: no temporary folder could be made to unpack it, as when the device is full."
    }

    static func holdsNothing(archiveName: String) -> String {
        "“\(archiveName)” holds no files to import."
    }

    /// The entries that were not unpacked and the files that were not copied; nil when there are none.
    static func leftOut(_ entries: [UnpackedArchive.LeftOutEntry], notCopied failedNames: [String], archiveName: String) -> String? {
        let descriptions = entries.map { entry in "“\(entry.name)” (\(reason(entry.reason)))" } + failedNames.map { name in "“\(name)”" }
        guard !descriptions.isEmpty else { return nil }
        let listed = descriptions.prefix(listedNameCount).joined(separator: ", ")
        let others = descriptions.count - listedNameCount
        let rest = others > 0 ? " and \(others.formatted()) more" : ""
        return "Some files of “\(archiveName)” were not imported: \(listed)\(rest)."
    }

    private static func reason(_ reason: UnpackedArchive.LeftOutEntry.Reason) -> String {
        switch reason {
        case .pathOutsideArchive: "its name leads outside the archive"
        case .encrypted: "it is encrypted"
        case .tooLarge(let limitBytes): "larger than \(size(limitBytes))"
        case .compressionNotSupported: "compressed in a way Graphite does not read"
        case .damaged: "damaged"
        case .nameTaken: "another file of the archive has its name"
        case .notWritten: "it could not be written"
        }
    }

    private static func size(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
