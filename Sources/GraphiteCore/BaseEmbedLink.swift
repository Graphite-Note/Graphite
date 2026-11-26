/**
 * File: BaseEmbedLink.swift
 * -------------------------
 * Layer: Core
 * Description: The embed that shows one view of a base inside a note, as Obsidian writes it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// `![[Courses/Assignments.base#This course]]`: a base embedded in a note at one of its views, by the base's vault path
/// so the embed reaches it from any note. In the note, `this` is the embedding note.
public enum BaseEmbedLink {
    public static func text(basePath: VaultPath, viewName: String?) -> String {
        let view = viewName.map { name in name.trimmingCharacters(in: .whitespaces) }.flatMap { name in name.isEmpty ? nil : "#" + name } ?? ""
        return "![[" + basePath.rawValue + view + "]]"
    }
}
