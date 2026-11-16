/**
 * File: SearchFolderQuery.swift
 * -----------------------------
 * Layer: Core
 * Description: The folders a search lists as results of their own: those whose name matches the search's folder:.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import Foundation

/// Which folders a search lists above its notes. `folder:bati` lists the folders whose name contains "bati" and narrows
/// the notes to those inside one (`SearchMatcher`); the folders themselves are found from their own names, by the part
/// of the search that `folder:` names.
public enum SearchFolderQuery {
    /// What a folder's own name must match for the search to list it, nil when the search names no folder. Operands
    /// of `folder:` combine as the search combines them: both of `folder:a folder:b`, either of `folder:a OR folder:b`.
    /// Terms outside `folder:` describe notes, not folders, and a `folder:` under `-` excludes notes, so neither lists
    /// a folder.
    public static func folderNameExpression(in expression: SearchExpression) -> SearchExpression? {
        switch expression {
        case .all(let items):
            let operands = items.compactMap(folderNameExpression(in:))
            return operands.count > 1 ? .all(operands) : operands.first
        case .any(let items):
            let operands = items.compactMap(folderNameExpression(in:))
            return operands.count > 1 ? .any(operands) : operands.first
        case .scoped(let scope, let operand):
            switch scope {
            case .folder: return operand
            // A folder's name keeps the capitals `match-case:` asks for.
            case .matchCase, .ignoreCase: return folderNameExpression(in: operand).map { folderOperand in .scoped(scope, folderOperand) }
            case .file, .path, .content, .tag, .line, .block, .section, .task, .taskTodo, .taskDone: return nil
            }
        case .not, .term, .property:
            return nil
        }
    }

    /// The folders among `folders` that the search lists, nil when it names no folder.
    public static func matchingFolders(of query: String, among folders: [VaultPath]) -> [VaultPath]? {
        guard let expression = SearchQueryParser.parse(query), let folderExpression = folderNameExpression(in: expression) else { return nil }
        var matcher = SearchMatcher(expression: folderExpression)
        return folders.filter { folder in matcher.matchesFolderName(of: folder) }
    }

    /// Every folder that holds one of `filePaths`, at any depth.
    public static func folders(holding filePaths: [VaultPath]) -> [VaultPath] {
        var folders = Set<VaultPath>()
        for path in filePaths {
            var folder = path.parent
            // The walk up stops at the first folder already found: those above it are found too.
            while !folder.rawValue.isEmpty, folders.insert(folder).inserted { folder = folder.parent }
        }
        return Array(folders)
    }
}
