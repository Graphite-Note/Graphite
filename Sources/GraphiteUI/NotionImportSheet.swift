/**
 * File: NotionImportSheet.swift
 * -----------------------------
 * Layer: UI
 * Description: Import from Notion's sheets: how to export from Notion and the choice of the export, the offer of the
 *              same importer as a plugin, the progress card while it is imported, and the summary when it ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */

import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// The sheet Import from Notion opens: how to get the HTML export from Notion, the folder it goes into, and Choose
/// Export, whose file chooser takes Notion's zip, the `Part-N` zips of a large export, or the folder a zip unzips to.
/// Below, the offer of the Notion Importer plugin (`NotionImporterPluginOffer`).
struct NotionImportSheet: View {
    let choice: NotionImportChoice
    /// The offer of the Notion Importer plugin, made once for the sheet; nil without a vault.
    let makePluginOffer: @MainActor () -> NotionImporterPluginOffer?
    let start: @MainActor ([URL], VaultPath) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsChooser = false
    @State private var pluginOffer: NotionImporterPluginOffer?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(NotionImportWording.exportSteps)
                } header: {
                    Text("In Notion")
                }
                Section {
                    LabeledContent("Into", value: NotionImportWording.destinationDescription(of: choice.directory))
                } footer: {
                    Text(NotionImportWording.whatIsImported)
                }
                Section {
                    Button("Choose Export…", systemImage: "doc.zipper") { showsChooser = true }
                        .frame(minHeight: 44)
                }
                if let pluginOffer { NotionImporterPluginOfferSection(offer: pluginOffer) }
            }
            .onAppear { if pluginOffer == nil { pluginOffer = makePluginOffer() } }
            .formStyle(.grouped)
            .navigationTitle("Import from Notion")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fileImporter(isPresented: $showsChooser, allowedContentTypes: [.zip, .folder], allowsMultipleSelection: true) { result in
                // A cancelled chooser leaves the sheet as it was.
                guard case .success(let sources) = result, !sources.isEmpty else { return }
                dismiss()
                start(sources, choice.directory)
            }
        }
        .sheetMinimumSize(width: 460, height: 420)
    }
}

/// The import's progress while the vault stays usable: a small card at the top of the document area with the pages
/// written, a bar, Pause or Resume, and Cancel.
struct NotionImportProgressCard: View {
    let progress: NotionImportProgress
    let isPaused: Bool
    let isCancelling: Bool
    let session: NotionImportSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(NotionImportWording.progressTitle(isPaused: isPaused, isCancelling: isCancelling)).font(.callout.weight(.semibold))
                if let fractionCompleted = progress.fractionCompleted {
                    ProgressView(value: fractionCompleted)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(NotionImportWording.progressDetail(progress))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(isPaused ? "Resume" : "Pause") {
                if isPaused { session.resumeImport() } else { session.pauseImport() }
            }
            .disabled(isCancelling)
            .frame(minHeight: 44)
            Button("Cancel") { session.cancelImport() }
                .disabled(isCancelling)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 520)
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}

/// The summary shown when an import ends: what it wrote, how much its report lists, and the report note to open.
struct NotionImportSummarySheet: View {
    let summary: NotionImportSummary
    let openReport: @MainActor (VaultPath) -> Void
    let done: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(NotionImportWording.headline(of: summary))
                    ForEach(NotionImportWording.details(of: summary), id: \.self) { detail in
                        Text(detail).foregroundStyle(.secondary)
                    }
                }
                if let reportPath = summary.reportPath {
                    Section {
                        Button("Open the Import Report", systemImage: "doc.text") { openReport(reportPath) }
                    }
                }
            }
            .navigationTitle(NotionImportWording.title(of: summary))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
        .sheetMinimumSize(width: 420, height: 320)
    }
}

/// The sidebar menu's import choices, as the iPad's New offers them: Import… for PDFs, pictures, notebooks and folders,
/// copied into the vault and converted where they need to be, then Import from Notion… while its core plugin is on.
struct ImportMenuButtons: View {
    let importFiles: @MainActor () -> Void
    /// Nil while the Notion Import core plugin is off (`WorkspaceModel.notionImportOpener`).
    let importFromNotion: (@MainActor () -> Void)?

    var body: some View {
        Button("Import…", systemImage: "square.and.arrow.down", action: importFiles)
        if let importFromNotion { Button("Import from Notion…", systemImage: "tray.and.arrow.down", action: importFromNotion) }
    }
}

/// Shows Import from Notion over the document area: its sheet while the export is chosen, its progress card at the top
/// while it runs, and its summary when it ends.
struct NotionImportPresentation: ViewModifier {
    /// The sheet's folder while the sheet is on screen (`WorkspaceModel.notionImportChoice`).
    @Binding var choice: NotionImportChoice?
    let session: NotionImportSession?
    let makePluginOffer: @MainActor () -> NotionImporterPluginOffer?
    let start: @MainActor ([URL], VaultPath) -> Void
    let openReport: @MainActor (VaultPath) -> Void
    /// Closes the summary; the workspace then lets the session go.
    let close: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            // At the top, below the tab bar, as the notebook import's card: the Pencil palette takes the bottom.
            .overlay(alignment: .top) {
                if let session, case .importing(let progress, let isPaused, let isCancelling) = session.state {
                    NotionImportProgressCard(progress: progress, isPaused: isPaused, isCancelling: isCancelling, session: session)
                }
            }
            .sheet(item: $choice) { choice in NotionImportSheet(choice: choice, makePluginOffer: makePluginOffer, start: start) }
            .sheet(isPresented: Binding(get: { finishedSummary != nil }, set: { isPresented in if !isPresented { close() } })) {
                if let finishedSummary {
                    NotionImportSummarySheet(summary: finishedSummary, openReport: { path in
                        close()
                        openReport(path)
                    }, done: close)
                }
            }
    }

    private var finishedSummary: NotionImportSummary? {
        if case .finished(let summary)? = session?.state { summary } else { nil }
    }
}
