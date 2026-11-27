/**
 * File: NotionAPIImportForm.swift
 * -------------------------------
 * Layer: UI
 * Description: Import from Notion's way through Notion's API: how to make the integration and share pages with it,
 *              its token kept in the device's keychain, a new folder or an earlier import to update, and Import.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

import SwiftUI
import GraphiteApple
import GraphiteCore

/// The sheet's sections for an import through Notion's API. A token typed here is kept in the keychain when the import
/// starts, never in the vault or a file, and the next import starts with it; Forget Token removes it.
struct NotionAPIImportForm: View {
    let directory: VaultPath
    /// The folders of `directory` holding an earlier import through the API.
    let earlierImports: [VaultPath]
    let start: @MainActor (_ token: String, _ directory: VaultPath, _ earlierImport: VaultPath?) -> Void
    var tokenStore = NotionTokenStore()
    @State private var typedToken = ""
    @State private var hasStoredToken = false
    /// The earlier import to update, nil for a new folder.
    @State private var earlierImport: VaultPath?
    @State private var keychainMessage: String?

    var body: some View {
        Section {
            Text(NotionImportWording.apiSteps)
        } header: {
            Text("In Notion")
        }
        tokenSection
        Section {
            Picker("Into", selection: $earlierImport) {
                Text(NotionImportWording.destinationDescription(of: directory)).tag(VaultPath?.none)
                ForEach(earlierImports, id: \.self) { folder in
                    Text(NotionImportWording.updateDescription(of: folder)).tag(VaultPath?.some(folder))
                }
            }
        } footer: {
            Text(earlierImport == nil ? NotionImportWording.apiWhatIsImported : NotionImportWording.updateWhatIsImported)
        }
        Section {
            Button(earlierImport == nil ? "Import from Notion" : "Update the Import", systemImage: "arrow.down.circle") { startImport() }
                .disabled(typedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasStoredToken)
                .frame(minHeight: 44)
                .accessibilityIdentifier("notion-import-api-start")
        }
        .onAppear { hasStoredToken = tokenStore.token() != nil }
    }

    /// The token typed, or the one the keychain keeps with Forget Token.
    @ViewBuilder private var tokenSection: some View {
        Section {
            SecureField(hasStoredToken ? "Saved in this device's keychain" : "Integration token (ntn_…)", text: $typedToken)
                // No content type: the system would offer to keep the token in Passwords, outside Graphite's own item.
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .accessibilityIdentifier("notion-import-token")
            if hasStoredToken {
                Button("Forget Token", systemImage: "key.slash", role: .destructive) { forgetToken() }
                    .frame(minHeight: 44)
            }
            if let keychainMessage { Text(keychainMessage).foregroundStyle(.red) }
        } header: {
            Text("Token")
        } footer: {
            Text(NotionImportWording.tokenFooter)
        }
    }

    private func startImport() {
        let typed = typedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            do {
                try tokenStore.setToken(typed)
            } catch {
                // The import still runs with the token typed: only the next one will ask for it again.
                keychainMessage = NotionImportWording.tokenNotKept
            }
        }
        guard let token = typed.isEmpty ? tokenStore.token() : typed else { return }
        start(token, directory, earlierImport)
    }

    private func forgetToken() {
        do {
            try tokenStore.forgetToken()
            hasStoredToken = false
            keychainMessage = nil
        } catch {
            keychainMessage = NotionImportWording.tokenNotForgotten
        }
    }
}
