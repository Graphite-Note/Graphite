/**
 * File: AnnotationAuthorSettingsSection.swift
 * -------------------------------------------
 * Layer: UI
 * Description: The General settings' field for the name written as the author of what is added to a PDF.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 04/11/2026
 */

import GraphiteApple
import SwiftUI

/// The name Preview and other readers show beside the ink, highlights, text boxes and pictures added to a PDF. A small
/// section of one row: it takes no more room than the setting needs.
struct AnnotationAuthorSettingsSection: View {
    @Bindable var preferences: GraphitePreferences
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    static let title = "Your Name"

    #if os(macOS)
    static let footer = "Written as the author of the ink, highlights, text boxes and pictures you add to PDFs. Left empty, this Mac’s account name is used."
    #else
    static let footer = "Written as the author of the ink, highlights, text boxes and pictures you add to PDFs. Left empty, no author is written."
    #endif

    var body: some View {
        Section {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.title)
                    nameField.multilineTextAlignment(.leading)
                }
            } else {
                LabeledContent(Self.title) { nameField.multilineTextAlignment(.trailing) }
            }
        } footer: {
            Text(Self.footer)
                .formFooterAlignment()
        }
    }

    private var nameField: some View {
        TextField(Self.title, text: $preferences.annotationAuthorName, prompt: Text(PDFAnnotationAuthor.deviceOwnerName ?? "Optional"))
            .autocorrectionDisabled()
            #if canImport(UIKit)
            .textInputAutocapitalization(.words)
            .textContentType(.name)
            .submitLabel(.done)
            #endif
    }
}
