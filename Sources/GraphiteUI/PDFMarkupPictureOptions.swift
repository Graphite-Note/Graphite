/**
 * File: PDFMarkupPictureOptions.swift
 * -----------------------------------
 * Layer: UI
 * Description: The Images tool's choice in the Mac's markup row: Add Image, which places an image file chosen in the
 *              open panel on the page in view.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

/// Add Image, shown in the markup row while the Images tool is chosen. Pictures can also be
/// dropped onto a page from the Finder, Photos, Mail or Safari with any tool.
struct PDFMarkupPictureOptions: View {
    let toolbar: PDFMarkupToolbar
    @State private var isChoosingFile = false

    var body: some View {
        Button { isChoosingFile = true } label: {
            Label("Add Image…", systemImage: "photo.badge.plus").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Add an image to the page in view, or drop one onto a page")
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.image]) { chosenFile in
            guard case .success(let location) = chosenFile else { return }
            toolbar.addPicture(fromFileAt: location)
        }
    }
}
#endif
