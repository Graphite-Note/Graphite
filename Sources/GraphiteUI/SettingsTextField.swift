/**
 * File: SettingsTextField.swift
 * -----------------------------
 * Layer: UI
 * Description: A labeled text field for a setting.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI

/// A labeled text field for a setting, saved on Return. Beside its label where the row is
/// wide, and under it on a phone, where a label beside a field is cut off.
struct SettingsTextField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let submit: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                field.multilineTextAlignment(.leading)
            }
        } else {
            LabeledContent(title) { field.multilineTextAlignment(.trailing) }
        }
    }

    private var field: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .autocorrectionDisabled()
            #if canImport(UIKit)
            .textInputAutocapitalization(.never)
            #endif
            .onSubmit(submit)
    }
}
