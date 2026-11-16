/**
 * File: PDFPasswordPrompt.swift
 * -----------------------------
 * Layer: UI
 * Description: The screen a protected PDF's tab shows until its password is given: the lock, what Graphite does with
 *              protected PDFs, and a password field with its Unlock button at the widths a Mac password prompt has.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

import SwiftUI

/// Asks for the password of a protected PDF. The password stays in memory until Graphite quits.
struct PDFPasswordPrompt: View {
    let fileName: String
    let message: String
    let unlock: (String) -> Void
    @State private var password = ""
    @FocusState private var isFieldFocused: Bool

    #if os(macOS)
    /// The width of a Mac password prompt's field. `ContentUnavailableView` proposes its actions
    /// a narrow width on the Mac, which squeezed a field that only had a maximum to a few characters.
    static let passwordFieldWidth: CGFloat = 200
    #else
    /// At most this wide, so the field and its button fit a phone's width.
    static let maximumPasswordFieldWidth: CGFloat = 240
    #endif

    var body: some View {
        ContentUnavailableView {
            Label("“\(fileName)” Is Locked", systemImage: "lock.doc")
        } description: {
            Text(message + " Graphite shows protected PDFs without changing them.")
        } actions: {
            HStack {
                passwordField
                    .focused($isFieldFocused)
                    .onSubmit(submit)
                Button("Unlock", action: submit)
                    .buttonStyle(.borderedProminent)
                    .fixedSize()
                    .disabled(password.isEmpty)
            }
        }
        .onAppear { isFieldFocused = true }
    }

    /// A PDF's password belongs to the file, not to an account, so on the Mac the field does not
    /// ask for the Passwords app's suggestions, which otherwise open over the prompt as it appears.
    @ViewBuilder private var passwordField: some View {
        #if os(macOS)
        SecureField("Password", text: $password)
            .textFieldStyle(.roundedBorder)
            .frame(width: Self.passwordFieldWidth)
        #else
        SecureField("Password", text: $password)
            .textContentType(.password)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: Self.maximumPasswordFieldWidth)
        #endif
    }

    private func submit() {
        guard !password.isEmpty else { return }
        unlock(password)
        password = ""
    }
}
