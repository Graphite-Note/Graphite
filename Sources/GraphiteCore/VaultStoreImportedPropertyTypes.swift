/**
 * File: VaultStoreImportedPropertyTypes.swift
 * -------------------------------------------
 * Layer: Core
 * Description: The property types an import brings, added to the vault's `.obsidian/types.json` without changing a type
 *              the vault already gives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

extension VaultStore {
    /// Gives each property of `types` its type in `.obsidian/types.json` where it has none yet, as an import does, and keeps
    /// every type already assigned. Returns the properties that already had another type, which they keep.
    public func assignPropertyTypesKeepingExisting(_ types: [String: PropertyType]) throws -> [String] {
        var keptKeys: [String] = []
        try updatePropertyTypeAssignments { assignments in
            for (key, type) in types.sorted(by: { leftType, rightType in leftType.key < rightType.key }) {
                if let assignedKey = assignments.keys.first(where: { assignedKey in assignedKey.caseInsensitiveCompare(key) == .orderedSame }) {
                    if assignments[assignedKey] as? String != type.rawValue { keptKeys.append(key) }
                    continue
                }
                assignments[key] = type.rawValue
            }
        }
        return keptKeys
    }
}
