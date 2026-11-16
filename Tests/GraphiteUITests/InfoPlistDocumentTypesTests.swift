/**
 * File: InfoPlistDocumentTypesTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: The document types App/Info.plist declares, so that the share sheet, Files, the Finder's Open With and the
 *              Dock offer Graphite for notebooks, archives, PDFs, pictures and notes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import XCTest
import UniformTypeIdentifiers
import NotebookImport
import GraphiteFixtures

/// The system offers an app for a file only for the types it declares (`CFBundleDocumentTypes`), and knows a type
/// of another app only while that app is installed unless the app imports its declaration (`UTImportedTypeDeclarations`).
/// The identifiers are Goodnotes' and Notability's own, as their apps' Info.plists export them (read from both apps
/// on 2026-11-13, and the type Spotlight gives the synthetic notebooks): `com.goodnotesapp.goodnotes.v5` and
/// `com.gingerlabs.notability.notearchive`.
final class InfoPlistDocumentTypesTests: XCTestCase {
    private func infoPropertyList() throws -> [String: Any] {
        let data = try Data(contentsOf: FixtureFolders.repositoryRoot.appendingPathComponent("App/Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private func documentTypes() throws -> [[String: Any]] {
        try XCTUnwrap(try infoPropertyList()["CFBundleDocumentTypes"] as? [[String: Any]])
    }

    private func importedTypes() throws -> [[String: Any]] {
        try XCTUnwrap(try infoPropertyList()["UTImportedTypeDeclarations"] as? [[String: Any]])
    }

    func testGraphiteIsOfferedForNotebooksArchivesPDFsPicturesAndNotes() throws {
        let declared = try documentTypes().flatMap { type in type["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(declared, ["com.goodnotesapp.goodnotes.v5", "com.gingerlabs.notability.notearchive", "public.zip-archive",
                                  "com.adobe.pdf", "public.image", "net.daringfireball.markdown", "public.plain-text"])
    }

    /// An alternate viewer: offered beside the app that owns the type (Goodnotes, Preview), never instead of it, and
    /// never as the app that edits the file, since Graphite imports a copy.
    func testEveryTypeIsOpenedAsAnAlternateViewer() throws {
        for type in try documentTypes() {
            let name = type["CFBundleTypeName"] as? String ?? "unnamed"
            XCTAssertEqual(type["LSHandlerRank"] as? String, "Alternate", name)
            XCTAssertEqual(type["CFBundleTypeRole"] as? String, "Viewer", name)
        }
        XCTAssertEqual(try documentTypes().compactMap { type in type["CFBundleTypeName"] as? String }.count, try documentTypes().count, "Each type is named.")
    }

    func testTheNotebookTypesAreImportedWithTheExtensionsTheImportReads() throws {
        let extensionsByType = Dictionary(uniqueKeysWithValues: try importedTypes().compactMap { declaration -> (String, [String])? in
            guard let identifier = declaration["UTTypeIdentifier"] as? String,
                  let tags = declaration["UTTypeTagSpecification"] as? [String: Any],
                  let extensions = tags["public.filename-extension"] as? [String] else { return nil }
            return (identifier, extensions)
        })
        XCTAssertEqual(extensionsByType["com.goodnotesapp.goodnotes.v5"], [NotebookFileFormat.goodnotes.fileExtension])
        XCTAssertEqual(extensionsByType["com.gingerlabs.notability.notearchive"], [NotebookFileFormat.notability.fileExtension])
        XCTAssertEqual(extensionsByType["net.daringfireball.markdown"], ["md", "markdown"])
        XCTAssertEqual(Set(extensionsByType.keys).count, try importedTypes().count, "Each imported type has an extension.")
    }

    /// As Goodnotes declares it: a `.goodnotes` notebook is a ZIP archive, which is why the opened-file import tells
    /// notebooks from archives by their extension, not by their type.
    func testTheImportedTypesConformAsTheirAppsDeclareThem() throws {
        let conformances = Dictionary(uniqueKeysWithValues: try importedTypes().compactMap { declaration -> (String, [String])? in
            guard let identifier = declaration["UTTypeIdentifier"] as? String, let conformsTo = declaration["UTTypeConformsTo"] as? [String] else { return nil }
            return (identifier, conformsTo)
        })
        XCTAssertEqual(conformances["com.goodnotesapp.goodnotes.v5"], ["public.zip-archive", "public.composite-content"])
        XCTAssertEqual(conformances["com.gingerlabs.notability.notearchive"], ["public.data", "public.content"])
        XCTAssertEqual(conformances["net.daringfireball.markdown"], ["public.plain-text"])
    }

    /// Kept on: with `UIFileSharingEnabled`, it is what shows Graphite's own folder in Files as On My iPad › Graphite,
    /// where vaults live (invariant EX-02). An original opened in place is only read and copied at once.
    func testDocumentsAreStillOpenedInPlaceSoGraphitesFolderStaysInFiles() throws {
        XCTAssertEqual(try infoPropertyList()["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
        XCTAssertEqual(try infoPropertyList()["UIFileSharingEnabled"] as? Bool, true)
    }

    func testTheDeclaredSystemTypesAreKnownToTheSystem() throws {
        for identifier in ["public.zip-archive", "com.adobe.pdf", "public.image", "public.plain-text"] {
            XCTAssertEqual(UTType(identifier)?.isDeclared, true, identifier)
        }
    }
}
