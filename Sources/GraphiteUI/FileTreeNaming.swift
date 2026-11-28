/**
 * File: FileTreeNaming.swift
 * --------------------------
 * Layer: UI
 * Description: Naming an item in the file tree's own row, as VSCodium's explorer does: what the field starts with,
 *              why a typed name cannot be used, and what Return, Escape and clicking elsewhere do.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import GraphiteCore

/// What the file tree can name in a row of its own: a new note, base, canvas or folder. A notebook keeps its sheet,
/// where its paper is chosen, and a course its sheet, which makes the course's page from its starter.
enum FileTreeCreatableKind: Equatable {
    case note, base, canvas, folder

    init?(_ kind: CreationKind) {
        switch kind {
        case .note: self = .note
        case .base: self = .base
        case .canvas: self = .canvas
        case .notebook, .course: return nil
        }
    }

    /// The extension the new file gets; a folder has none.
    var fileExtension: String {
        switch self {
        case .note: "md"
        case .base: "base"
        case .canvas: "canvas"
        case .folder: ""
        }
    }

    /// A note's name is what links name, so it cannot hold the characters that would break them.
    var isNote: Bool { self == .note }
}

/// A rename or a new item, which the workspace asks the file tree to name in its row.
enum FileTreeNamingRequest: Equatable {
    case rename(VaultPath)
    case create(FileTreeCreatableKind, in: VaultPath)
}

/// The file tree's side of naming in a row: it starts the field where the item is, or answers false when it cannot
/// (no tree on screen, or the item's row not listed), and the workspace shows its sheet instead.
@MainActor
protocol FileTreeNaming: AnyObject {
    func beginNaming(_ request: FileTreeNamingRequest) -> Bool
}

/// What a finished name field asks for.
enum FileTreeNamingOutcome: Equatable {
    case cancel
    case create(FileTreeCreatableKind, name: String, in: VaultPath)
    case rename(VaultPath, to: String)
}

/// How the person left the name field.
enum FileTreeNamingEnd: Equatable {
    case returnKey
    case escapeKey
    /// A click elsewhere, or another field or row taking the keyboard: as in VSCodium, a usable name is kept.
    case focusLeft
}

/// What is named in the field.
enum FileTreeNamingSubject: Equatable {
    case newItem(FileTreeCreatableKind, in: VaultPath)
    case existingItem(VaultPath, isFolder: Bool)
}

/// The decisions of one name field in the file tree, from what it names and the names already in its folder.
struct FileTreeNameDraft: Equatable {
    let subject: FileTreeNamingSubject
    /// The names of the folder's items, compared without case as the Mac's and the iPad's file systems compare them.
    let takenNames: Set<String>
    /// What a new item is called when nothing is typed, as Obsidian's new note is.
    static let untitledName = "Untitled"

    init(subject: FileTreeNamingSubject, namesInFolder: [String]) {
        self.subject = subject
        takenNames = Set(namesInFolder.map { name in name.lowercased() })
    }

    /// The text the field starts with, all of it selected: a file's name without its extension, a folder's whole name,
    /// nothing for a new item.
    var initialText: String {
        switch subject {
        case .newItem: ""
        case .existingItem(let path, let isFolder): isFolder ? path.name : path.stem
        }
    }

    /// Shown in the empty field of a new item: the name it gets when nothing is typed.
    var placeholder: String {
        switch subject {
        case .newItem: Self.untitledName
        case .existingItem: ""
        }
    }

    /// The extension drawn muted after a renamed file's field, which the rename keeps. A note's is left out, as its row
    /// leaves it out.
    var keptExtensionSuffix: String? {
        guard case .existingItem(let path, let isFolder) = subject, !isFolder else { return nil }
        let fileExtension = (path.name as NSString).pathExtension
        guard !fileExtension.isEmpty, DocumentKind(path: path) != .markdown else { return nil }
        return "." + fileExtension
    }

    /// Why the typed name cannot be used, shown under the field as it is typed; nil when it can. An empty field of a new
    /// item is fine: the item is then called "Untitled".
    func problem(typed: String) -> String? {
        switch subject {
        case .newItem(let kind, _):
            let name = trimmed(typed)
            if name.isEmpty { return nil }
            if let problem = FileNameRules.problem(with: name, isNote: kind.isNote) { return problem }
            return takenProblem(fileName: Self.fileName(name, fileExtension: kind.fileExtension), shownName: name)
        case .existingItem(let path, let isFolder):
            let name = renamedName(typed, path: path, isFolder: isFolder)
            if let problem = FileNameRules.problem(with: name, isNote: !isFolder && DocumentKind(path: path) == .markdown) { return problem }
            let fileName = Self.fileName(name, fileExtension: isFolder ? "" : (path.name as NSString).pathExtension)
            // The item's own name, in another case, is a rename too.
            guard fileName.lowercased() != path.name.lowercased() else { return nil }
            return takenProblem(fileName: fileName, shownName: name)
        }
    }

    /// What leaving the field asks for, or nil to keep editing: Return on a name that cannot be used leaves the field
    /// open with its problem shown.
    func outcome(typed: String, endedBy end: FileTreeNamingEnd) -> FileTreeNamingOutcome? {
        if end == .escapeKey { return .cancel }
        let problem = problem(typed: typed)
        switch subject {
        case .newItem(let kind, let directory):
            let name = trimmed(typed)
            if end == .focusLeft && (name.isEmpty || problem != nil) { return .cancel }
            if problem != nil { return nil }
            return .create(kind, name: name.isEmpty ? untitledName(for: kind) : name, in: directory)
        case .existingItem(let path, let isFolder):
            if problem != nil { return end == .focusLeft ? .cancel : nil }
            let name = renamedName(typed, path: path, isFolder: isFolder)
            return name == initialText ? .cancel : .rename(path, to: name)
        }
    }

    /// A file's "Untitled" is made different by the store ("Untitled 1"); a folder's is made different here, as the store
    /// refuses a folder that exists.
    private func untitledName(for kind: FileTreeCreatableKind) -> String {
        guard kind == .folder else { return Self.untitledName }
        var name = Self.untitledName, number = 0
        while takenNames.contains(name.lowercased()) {
            number += 1
            name = Self.untitledName + " \(number)"
        }
        return name
    }

    private func takenProblem(fileName: String, shownName: String) -> String? {
        takenNames.contains(fileName.lowercased()) ? "“\(shownName)” is already in this folder. Choose a different name." : nil
    }

    /// A renamed file keeps its extension, so a typed copy of it is dropped rather than doubled.
    private func renamedName(_ typed: String, path: VaultPath, isFolder: Bool) -> String {
        RenamedFileName.withoutTypedExtension(trimmed(typed), fileExtension: isFolder ? "" : (path.name as NSString).pathExtension)
    }

    private func trimmed(_ typed: String) -> String { typed.trimmingCharacters(in: .whitespaces) }

    private static func fileName(_ name: String, fileExtension: String) -> String {
        fileExtension.isEmpty ? name : name + "." + fileExtension
    }
}
