import Foundation

/// One item `vault.list` lists, made off the main thread and turned into JSON there too.
struct CommunityPluginListedEntry: Sendable {
    let path: VaultPath
    let isFolder: Bool
    let size: Int
    let modified: Date
    let created: Date

    init(path: VaultPath, values: URLResourceValues) {
        self.path = path
        isFolder = values.isDirectory == true
        size = values.fileSize ?? 0
        modified = values.contentModificationDate ?? .distantPast
        created = values.creationDate ?? modified
    }

    /// One JSON text of parallel lists. The reply crosses into the web view on the main thread,
    /// where WebKit copies what it holds: one string goes across at once, and 31,748 dictionaries
    /// of five values each do not.
    static func encoded(_ entries: [CommunityPluginListedEntry]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let columns: [String: Any] = [
                "paths": entries.map(\.path.rawValue),
                "isFolder": entries.map { entry in entry.isFolder ? 1 : 0 },
                "sizes": entries.map { entry in entry.isFolder ? 0 : entry.size },
                "modified": entries.map { entry in (entry.modified.timeIntervalSince1970 * 1000).rounded() },
                "created": entries.map { entry in (entry.created.timeIntervalSince1970 * 1000).rounded() },
            ]
            return String(decoding: try JSONSerialization.data(withJSONObject: columns, options: [.withoutEscapingSlashes]), as: UTF8.self)
        }.value
    }
}
