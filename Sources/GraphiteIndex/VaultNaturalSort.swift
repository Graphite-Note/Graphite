/**
 * File: VaultNaturalSort.swift
 * ----------------------------
 * Layer: Index
 * Description: The key file names are sorted by in search results: numbers by value, letters without regard to capitals or accents.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation
import GRDB

extension VaultIndex {
    /// The most digits of a number a sort key keeps in order; longer numbers sort after shorter ones.
    private static let sortKeyDigitWidth = 20

    /// A key that sorts file names as Obsidian lists them: `Lecture 2` before `Lecture 10`, `éclair`
    /// beside `eclair`, capitals ignored. Plain comparison of the keys gives that order, so the index
    /// can sort by an indexed column instead of calling a locale comparison for every pair of rows.
    static func naturalSortKey(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var key = ""
        var digitRun = ""
        func endDigitRun() {
            guard !digitRun.isEmpty else { return }
            let significantDigits = digitRun.drop { character in character == "0" }
            let number = significantDigits.isEmpty ? "0" : String(significantDigits)
            key += String(repeating: "0", count: max(0, sortKeyDigitWidth - number.count)) + number
            digitRun = ""
        }
        for character in folded {
            if character.isASCII, character.isNumber { digitRun.append(character) } else { endDigitRun(); key.append(character) }
        }
        endDigitRun()
        return key
    }

    /// Adds the `sort_name` column the name sort reads, filled for the files already indexed.
    static func registerNaturalFileNameOrderMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("natural-file-name-order-12") { database in
            // Results sorted by name put `Note 10` before `Note 2`, and names with accents after
            // `Z`. The key sorts as Obsidian does, and an index on it keeps the sort cheap.
            database.add(function: naturalSortKeyFunction)
            defer { database.remove(function: naturalSortKeyFunction) }
            try database.execute(sql: """
                ALTER TABLE files ADD COLUMN sort_name TEXT;
                UPDATE files SET sort_name = \(naturalSortKeyFunctionName)(basename);
                CREATE INDEX files_sort_name ON files(sort_name, path);
                """)
        }
    }

    static let naturalSortKeyFunctionName = "graphite_natural_sort_key"
    static let naturalSortKeyFunction = DatabaseFunction(naturalSortKeyFunctionName, argumentCount: 1, pure: true) { values in
        String.fromDatabaseValue(values[0]).map(naturalSortKey)
    }
}
