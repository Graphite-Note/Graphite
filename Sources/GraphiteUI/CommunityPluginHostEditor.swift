/**
 * File: CommunityPluginHostEditor.swift
 * -------------------------------------
 * Layer: UI
 * Description: The focused note's editor for plugins: the snapshots the runtime works on, and a plugin's change
 *              applied through the note's session.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GraphiteCore

/// The focused note's editor, for plugins: what the runtime's `Editor` works on, and a change it
/// sends back, applied through the note's session.
extension CommunityPluginHost {
    /// The note's text and selection for the runtime's `Editor`, remembered under an
    /// identifier so the change that comes back can be checked against it.
    /// - Parameter sendsOnlyChange: The note is sent as the change from the snapshot sent last,
    ///   as a keystroke is, when that snapshot was of this note: one letter does not carry the
    ///   whole note across. The runtime asks for the note when its copy is another.
    func editorSnapshot(of session: MarkdownSession, sendsOnlyChange: Bool = false) -> [String: Any] {
        let baseIdentifier = editorSnapshotOrder.last
        let baseSnapshot = baseIdentifier.flatMap { identifier in editorSnapshots[identifier] }
        let snapshotIdentifier = UUID().uuidString
        editorSnapshots[snapshotIdentifier] = (session.path, session.text)
        editorSnapshotOrder.append(snapshotIdentifier)
        // A few recent snapshots are enough: an asynchronous command's edit arrives soon.
        while editorSnapshotOrder.count > 8 { editorSnapshots[editorSnapshotOrder.removeFirst()] = nil }
        var snapshot: [String: Any] = [
            "path": session.path.rawValue,
            "snapshotIdentifier": snapshotIdentifier,
            "selectionAnchor": session.selection.location,
            "selectionHead": session.selection.location + session.selection.length,
            "isReadOnly": session.viewMode == .reading,
        ]
        if sendsOnlyChange, let baseIdentifier, let baseSnapshot, baseSnapshot.path == session.path {
            let change = CommunityPluginTextChange.between(baseSnapshot.text, session.text)
            snapshot["textChange"] = ["baseSnapshotIdentifier": baseIdentifier, "originalLength": change.originalLength, "location": change.location,
                                      "removedLength": change.removedLength, "insertedText": change.insertedText] as [String: Any]
        } else {
            snapshot["text"] = session.text
        }
        return snapshot
    }

    /// A plugin changed the note in its editor: the change is applied through the note's
    /// session as one undoable edit, but only while the note still has the text the
    /// plugin saw. The answer carries the note as it is now, for the plugin's next change.
    func applyEditorChange(_ message: [String: Any]) async -> [String: Any] {
        guard let workspace, let pathText = message["path"] as? String, let path = try? VaultPath(pathText),
              let snapshotIdentifier = message["snapshotIdentifier"] as? String, let changedText = message["text"] as? String else {
            return Self.failure("invalidData", "The plugin's change named no note.")
        }
        guard let session = workspace.openMarkdownSession(at: path) else {
            return Self.failure("conflict", "“\(path.name)” is no longer open, so the plugin's change was not applied.")
        }
        // Insertions the editor has not applied yet are waited for, so the comparison sees the
        // note as the person sees it.
        for _ in 0..<20 where session.pendingInsertion != nil { try? await Task.sleep(for: .milliseconds(10)) }
        guard let snapshot = editorSnapshots[snapshotIdentifier], snapshot.path == path, session.text == snapshot.text else {
            let pluginName = (message["pluginIdentifier"] as? String).flatMap(pluginName(of:)) ?? "A plugin"
            showNotice("\(pluginName) did not change “\(path.stem)”: the note changed while it was working.", pluginIdentifier: message["pluginIdentifier"] as? String)
            var failure = Self.failure("conflict", "The note changed while the plugin was working.")
            failure["snapshot"] = editorSnapshot(of: session)
            return failure
        }
        guard session.viewMode != .reading else { return Self.failure("readOnly", "The note is shown in reading view.") }
        let anchor = message["selectionAnchor"] as? Int ?? 0
        let head = message["selectionHead"] as? Int ?? anchor
        if let edit = CommunityPluginEditorChange.edit(from: snapshot.text, to: changedText, selectionAnchor: anchor, selectionHead: head) {
            let previousProblem = session.errorMessage
            session.apply(edit)
            // The session refuses an edit that a queued insertion overlaps, and says so.
            if let problem = session.errorMessage, problem != previousProblem {
                var failure = Self.failure("conflict", problem)
                failure["snapshot"] = editorSnapshot(of: session)
                return failure
            }
        } else {
            // Only the cursor or the selection moved (`setCursor`, `setSelection`).
            let selection = CommunityPluginEditorChange.selection(anchor: anchor, head: head, inTextOfLength: (changedText as NSString).length)
            if selection != session.selection { session.requestSelection(selection) }
        }
        editorSnapshots[snapshotIdentifier] = (path, changedText)
        return ["snapshot": [
            "path": path.rawValue, "snapshotIdentifier": snapshotIdentifier, "text": changedText,
            "selectionAnchor": anchor, "selectionHead": head, "isReadOnly": false,
        ] as [String: Any]]
    }
}
