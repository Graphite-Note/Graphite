/**
 * File: NotionTokenStore.swift
 * ----------------------------
 * Layer: Apple
 * Description: The token of the Notion integration Import from Notion reads a workspace with, kept in the device's
 *              keychain: never in the vault, the preferences, a file or a log.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import Foundation
import Security

/// The Notion integration's token (`ntn_…`), in the device's keychain. It is read only when an import through Notion's
/// API starts, and handed to the transport that adds it to the requests to Notion's API alone.
public struct NotionTokenStore: Sendable {
    /// The keychain item's service: a stored value, since changing it forgets the token.
    static let service = "Graphite Notion Import"

    private let account: String

    /// The store of the device's one token. Tests give an account of their own.
    public init(account: String = "integration token") {
        self.account = account
    }

    private var item: KeychainGenericPasswordItem {
        KeychainGenericPasswordItem(service: Self.service, account: account)
    }

    /// The stored token, nil when none is stored or the keychain cannot be read.
    public func token() -> String? {
        let (status, data) = item.read()
        guard status == errSecSuccess, let data, !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Keeps `token`, its spaces and line breaks trimmed, or forgets the stored one when it is empty.
    public func setToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try forgetToken() }
        let status = item.write(Data(trimmed.utf8))
        guard status == errSecSuccess else { throw NotionTokenStoreError(status: status) }
    }

    public func forgetToken() throws {
        let status = item.delete()
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NotionTokenStoreError(status: status) }
    }
}

public struct NotionTokenStoreError: LocalizedError, Equatable {
    let status: OSStatus
    public var errorDescription: String? { "The keychain did not keep the Notion token (\(status))." }
}
