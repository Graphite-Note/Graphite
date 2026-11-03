/**
 * File: CalloutFoldStore.swift
 * ----------------------------
 * Layer: UI
 * Description: Which callouts are expanded in each note, for this run of the app.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 02/11/2026
 */

import SwiftUI
import Observation
import GraphiteCore

/// Which callouts the person has expanded or collapsed, per note, shared by the reading view
/// and Live Preview, so Read Aloud reads what is open and skips what is folded. Kept for the
/// session and the open vault only; the note's own `-` and `+` markers remain the starting point.
@MainActor @Observable
final class CalloutFoldStore {
    private var expansionByNote: [String: [String: Bool]] = [:]

    func expansion(for notePath: String) -> [String: Bool] { expansionByNote[notePath] ?? [:] }

    func isExpanded(notePath: String, key: String, initially: Bool) -> Bool {
        expansionByNote[notePath]?[key] ?? initially
    }

    func setExpanded(_ isExpanded: Bool, notePath: String, key: String) {
        expansionByNote[notePath, default: [:]][key] = isExpanded
    }

    /// A note that was renamed or moved keeps how its callouts are shown.
    func followMove(from oldPath: VaultPath, to newPath: VaultPath) {
        for (notePath, expansion) in expansionByNote {
            guard let path = try? VaultPath(notePath), path.isInside(oldPath), // A key is a note's path: one that does not parse is not inside.
                  let movedPath = try? path.replacingPrefix(oldPath, with: newPath) else { continue } // Cannot be named there: left as it was.
            expansionByNote[notePath] = nil
            expansionByNote[movedPath.rawValue] = expansion
        }
    }

    /// Forgets the entries of every note, when another vault opens: a note there at the same
    /// path is another note.
    func forgetEveryNote() {
        expansionByNote = [:]
    }
}

/// A callout's place in that store: the note it is in and its key.
struct CalloutFoldScope {
    let store: CalloutFoldStore
    let notePath: String
}

extension EnvironmentValues {
    @Entry var calloutFoldNote: (store: CalloutFoldStore, notePath: String)? = nil
}
