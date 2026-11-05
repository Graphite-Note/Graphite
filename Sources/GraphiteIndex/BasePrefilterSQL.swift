/**
 * File: BasePrefilterSQL.swift
 * ----------------------------
 * Layer: Index
 * Description: Turns the part of a base's filters the index can answer into SQL over its tables.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

import Foundation
import GRDB
import GraphiteCore

/// SQL for a base's pre-filter (`BasePrefilterCondition`), read two ways.
///
/// The superset holds for every file the filter is true for, and nil means every file.
/// The subset holds only for files the filter is true for, and nil means no file is
/// known to; it exists only for exact conditions, which never fail to evaluate. A `not`
/// keeps out only the files its condition's subset holds, so files for which that
/// condition fails or is uncertain always reach the evaluator.
enum BasePrefilterSQL {
    struct Fragment {
        let text: String
        let arguments: StatementArguments
    }

    struct Bounds {
        let superset: Fragment?
        let subset: Fragment?
    }

    static func bounds(of condition: BasePrefilterCondition, in database: Database) throws -> Bounds {
        switch condition {
        case .anyFile:
            return Bounds(superset: nil, subset: nil)
        case .requirement(let requirement, let isExact):
            return Bounds(superset: try VaultIndex.supersetCondition(for: requirement, in: database),
                          subset: isExact ? VaultIndex.subsetCondition(for: requirement) : nil)
        case .propertyText(let requirement):
            return Bounds(superset: VaultIndex.supersetCondition(for: requirement), subset: nil)
        case .allOf(let children):
            let childBounds = try children.map { child in try bounds(of: child, in: database) }
            let subsets = childBounds.compactMap(\.subset)
            return Bounds(superset: joined(childBounds.compactMap(\.superset), by: "AND"),
                          subset: !children.isEmpty && subsets.count == children.count ? joined(subsets, by: "AND") : nil)
        case .anyOf(let children):
            let childBounds = try children.map { child in try bounds(of: child, in: database) }
            let supersets = childBounds.compactMap(\.superset)
            let subsets = childBounds.compactMap(\.subset)
            // A child the index cannot narrow lets every file through. Evaluation stops at
            // the first child that fails, so the subset needs every child exact.
            return Bounds(superset: !children.isEmpty && supersets.count == children.count ? joined(supersets, by: "OR") : nil,
                          subset: !children.isEmpty && subsets.count == children.count ? joined(subsets, by: "OR") : nil)
        case .noneOf(let children):
            let childBounds = try children.map { child in try bounds(of: child, in: database) }
            let negatedSubsets = childBounds.compactMap(\.subset).map(negated)
            // Every child exact: a file outside each child's superset fails none of them.
            let isExact = !children.isEmpty && childBounds.allSatisfy { bounds in bounds.subset != nil && bounds.superset != nil }
            return Bounds(superset: joined(negatedSubsets, by: "AND"),
                          subset: isExact ? joined(childBounds.compactMap(\.superset).map(negated), by: "AND") : nil)
        }
    }

    private static func joined(_ fragments: [Fragment], by connective: String) -> Fragment? {
        guard fragments.count > 1 else { return fragments.first }
        return Fragment(text: "(" + fragments.map(\.text).joined(separator: " \(connective) ") + ")",
                        arguments: fragments.reduce(into: StatementArguments()) { arguments, fragment in arguments += fragment.arguments })
    }

    private static func negated(_ fragment: Fragment) -> Fragment {
        Fragment(text: "NOT (\(fragment.text))", arguments: fragment.arguments)
    }
}
