/**
 * File: ReadingFileLookup.swift
 * -----------------------------
 * Layer: UI
 * Description: The reading view's read port into the vault: the files a link written in a note names. The index
 *              answers it, so the parts of the reading view that resolve links do not import the index.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import GraphiteCore

/// The files a link written in a note names, as the reading view's cover and link icons resolve them
/// (Docs/solid/rewrite-foundations.md section 3.3 rule 3). `VaultIndex` answers it (MarkdownPreview.swift).
protocol ReadingFileLookup: Sendable {
    /// The files `target`, written in `source`, names, the best first. A Wikilink (`isWiki`) also names a note by
    /// one of its aliases.
    func resolve(_ target: String, from source: VaultPath, isWiki: Bool) async throws -> [VaultPath]
}
