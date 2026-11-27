/**
 * File: CommunityPluginVaultBridgeAnswers.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: What the vault bridge's answers carry to the plugin runtime: a file's stat and revision as the runtime
 *              reads them, and every failure as one of the kinds the runtime understands.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation

/// The values of `CommunityPluginVaultBridge`'s answers. The Node tests' vault host
/// (`Tests/CommunityPluginRuntimeTests/support/test-vault-host.js`) answers with the same shapes and failure kinds.
extension CommunityPluginVaultBridge {
    /// A stat as Obsidian's `Stat` has it: a folder's size is 0, times are in milliseconds since 1970.
    static func statDictionary(isFolder: Bool, size: Int, modified: Date, created: Date) -> [String: Any] {
        [
            "isFolder": isFolder,
            "size": isFolder ? 0 : size,
            "modified": (modified.timeIntervalSince1970 * 1000).rounded(),
            "created": (created.timeIntervalSince1970 * 1000).rounded(),
        ]
    }

    /// The revision a plugin read, which it sends back with its next write so that a file changed meanwhile is not
    /// overwritten.
    static func revisionDictionary(_ revision: FileRevision) -> [String: Any] {
        ["digest": revision.digest, "size": revision.size]
    }

    /// A failure with a kind the runtime understands (`conflict`, `missing`, `exists`…).
    public struct BridgeFailure: Error, LocalizedError {
        public let kind: String
        public let message: String
        public init(kind: String, message: String) { self.kind = kind; self.message = message }
        public var errorDescription: String? { message }
    }

    /// The answer for a failed operation: `{"failure": {"kind", "message"}}`, the kind read from the error.
    public static func failureData(for error: Error) -> Data {
        let kind: String
        switch error {
        case let failure as BridgeFailure: kind = failure.kind
        case GraphiteError.conflict: kind = "conflict"
        case GraphiteError.outsideVault: kind = "outsideVault"
        case GraphiteError.invalidPath: kind = "invalidPath"
        case GraphiteError.oversized: kind = "tooLarge"
        case GraphiteError.unavailable(let reason) where reason.hasSuffix("already exists."): kind = "exists"
        case GraphiteError.unavailable(let reason) where reason.hasSuffix("is no longer in the vault."): kind = "missing"
        case is DecodingError: kind = "invalidData"
        default: kind = "failed"
        }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let answer: [String: Any] = ["failure": ["kind": kind, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(#"{"failure":{"kind":"failed","message":"Graphite could not answer."}}"#.utf8)
    }
}
