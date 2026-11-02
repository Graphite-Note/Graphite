/**
 * File: DrawingConflictSaveTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A drawing whose file changed elsewhere while it was open is never written over, and its
 *              strokes can go to a new file beside it. Hosted, since saving a drawing is iOS code.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import PencilKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class DrawingConflictSaveTests: XCTestCase {
    func testADrawingThatChangedElsewhereSavesAsANewFileBesideIt() async throws {
        let vault = try TemporaryVault.make(prefix: "DrawingConflict", for: self).root.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Sketches"), withIntermediateDirectories: true)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)

        let original = try VaultPath("Sketches/Drawing.svg")
        let location = vault.appendingPathComponent(original.rawValue)
        let content = DrawingContent(strokeData: PKDrawing().dataRepresentation(), canvasWidth: 800, background: .white)
        _ = try await DrawingFileService(writer: AtomicFileWriter()).save(content, format: .svg, to: location, expecting: .absent)
        let request = DrawingEditorRequest(target: .existingDrawing(path: original, location: location, revision: try FileRevision.read(location)),
                                           title: original.name, initialStrokeData: PKDrawing().dataRepresentation(), canvasWidth: 800, background: .white, format: .svg)
        try Data("<svg/>".utf8).write(to: location)

        do {
            try await workspace.saveDrawing(content, format: .svg, for: request)
            XCTFail("The newer file is not overwritten.")
        } catch { XCTAssertEqual(error as? GraphiteError, .conflict) }
        try await workspace.saveDrawingAsNewFile(content, format: .svg, for: request)

        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "<svg/>")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Sketches/Drawing Graphite edits.svg").path))
        XCTAssertTrue(workspace.notice?.contains("Drawing Graphite edits.svg") == true)
    }
}
