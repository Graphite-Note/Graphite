/**
 * File: PDFSignatureStore.swift
 * -----------------------------
 * Layer: UI
 * Description: The signatures drawn on this device for signing PDFs, kept in Application Support outside every
 *              vault, one PencilKit drawing per file, in the order they were made.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 13/11/2026
 */

import Foundation
import Observation
import PencilKit
import SwiftUI
import GraphiteCore

/// Why a signature was not kept.
enum PDFSignatureError: Error, LocalizedError, Equatable {
    /// Done was chosen with no stroke on the canvas.
    case nothingDrawn

    var errorDescription: String? {
        switch self {
        case .nothingDrawn: "Draw a signature first."
        }
    }
}

/// One signature kept on the device: its strokes from its top-left corner, in points.
struct PDFSavedSignature: Identifiable, Equatable {
    /// The file's name, which also orders the signatures by when they were made.
    let id: String
    let drawing: PKDrawing

    static func == (first: PDFSavedSignature, second: PDFSavedSignature) -> Bool { first.id == second.id }
}

/// The signatures of this device, for every window and PDF. They are personal and stay out
/// of the vault: a vault is shared and synced, and a signature in it would travel with it.
/// Nothing is read until the Sign menu is first shown (`loadIfNeeded`).
@MainActor @Observable
final class PDFSignatureStore {
    private(set) var signatures: [PDFSavedSignature] = []
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored let directory: URL
    private static let fileExtension = "signature"

    init(directory: URL) {
        self.directory = directory
    }

    /// The signatures folder in `applicationFolders`' Application Support.
    static func directory(in applicationFolders: ApplicationFolders) -> URL {
        (applicationFolders.applicationSupportFolder ?? URL.applicationSupportDirectory).appendingPathComponent("Signatures", isDirectory: true)
    }

    /// Reads the folder once; a file that is not a drawing is left out.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] // None kept yet.
        signatures = files.filter { file in file.pathExtension == Self.fileExtension }
            .sorted { first, second in first.lastPathComponent < second.lastPathComponent }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file) else { return nil } // Unreadable: left out of the menu, kept in the folder.
                guard let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { return nil } // No drawing: left out.
                return PDFSavedSignature(id: file.lastPathComponent, drawing: drawing)
            }
    }

    /// Keeps a new signature after the others; its strokes are moved to start at the top-left corner.
    @discardableResult
    func save(_ drawing: PKDrawing, madeAt date: Date) throws -> PDFSavedSignature {
        loadIfNeeded()
        guard let normalized = PDFSignatureInk.normalized(drawing) else { throw PDFSignatureError.nothingDrawn }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Milliseconds with leading zeros sort as text in the order the signatures were made.
        let milliseconds = String(format: "%015.0f", (date.timeIntervalSince1970 * 1000).rounded())
        let name = "\(milliseconds)-\(UUID().uuidString.prefix(8)).\(Self.fileExtension)"
        try normalized.dataRepresentation().write(to: directory.appendingPathComponent(name), options: .atomic)
        let saved = PDFSavedSignature(id: name, drawing: normalized)
        signatures.append(saved)
        return saved
    }

    func delete(_ signature: PDFSavedSignature) throws {
        let file = directory.appendingPathComponent(signature.id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        signatures.removeAll { kept in kept.id == signature.id }
    }
}

extension EnvironmentValues {
    /// The device's signatures, for the Sign menu of a PDF's markup row; nil where none can be kept.
    @Entry var pdfSignatureStore: PDFSignatureStore? = nil
}
