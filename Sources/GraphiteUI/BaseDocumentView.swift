/**
 * File: BaseDocumentView.swift
 * ----------------------------
 * Layer: UI
 * Description: A base in its tab or inside a note: the toolbar, the banners and the selected view.
 *
 * Authors: Bahey Shalash
 * Version: 0.20
 * Date: 05/11/2026
 */

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import GraphiteCore
import GraphiteIndex

/// Opens a `.base` file: a view switcher, the result count, and the selected view.
/// `this` is the base file itself.
///
/// - Parameters:
///   - viewName: The view to show, as in a `[[Books.base#Gallery]]` link. A new name
///     selects that view in the base already shown.
///   - contentVersion: Change it after vault files or the index change; the base
///     re-reads its definition and runs the view again.
///   - contentChange: Which files changed for `contentVersion`, when known.
///   - isIndexComplete: False while the first index scan runs, to say results may be partial.
///   - open: Opens a vault file (a row, card, marker or link).
///   - filesChanged: Called after the base saved a note (inline property edits).
///   - modelCache: Keeps the view chosen and a column's sort while the tab shows something else.
///   - viewRequestApplied: Called once the view named by `viewName` is shown, so a later link
///     to the same view shows it again, and returning to the tab does not undo the person's choice.
public struct BaseDocumentView: View {
    private let path: VaultPath
    private let viewName: String?
    private let store: VaultStore
    private let index: VaultIndex
    private let contentVersion: Int
    private let contentChange: BaseContentChange?
    private let isIndexComplete: Bool
    private let open: (VaultPath) -> Void
    private let filesChanged: ([VaultPath]) -> Void
    private let modelCache: EmbeddedBaseModelCache?
    private let viewRequestApplied: () -> Void

    public init(path: VaultPath, viewName: String? = nil, store: VaultStore, index: VaultIndex, contentVersion: Int = 0,
        contentChange: BaseContentChange? = nil, isIndexComplete: Bool = true,
                open: @escaping (VaultPath) -> Void, filesChanged: @escaping ([VaultPath]) -> Void = { _ in }, modelCache: EmbeddedBaseModelCache? = nil,
                viewRequestApplied: @escaping () -> Void = {}) {
        self.path = path
        self.contentChange = contentChange
        self.modelCache = modelCache
        self.viewRequestApplied = viewRequestApplied
        self.viewName = viewName
        self.store = store
        self.index = index
        self.contentVersion = contentVersion
        self.isIndexComplete = isIndexComplete
        self.open = open
        self.filesChanged = filesChanged
    }

    public var body: some View {
        let open = open
        BaseContainerView(source: .file(path), contextPath: path, preferredViewName: viewName, store: store, index: index, contentVersion: contentVersion,
                          contentChange: contentChange, isIndexComplete: isIndexComplete, presentation: .document, open: open, openBase: { basePath,
                              _ in open(basePath) },
                          filesChanged: filesChanged, modelCache: modelCache, viewRequestApplied: viewRequestApplied)
            .id(path)
    }
}

/// A base inside a Markdown note: a ```` ```base ```` block, or an embed such as
/// `![[Books.base#Reading]]`. `this` is the embedding note. It has a fixed height and
/// scrolls on its own.
public struct EmbeddedBaseView: View {
    public nonisolated static let defaultHeight: CGFloat = 420
    private let source: BaseSource
    private let embeddingNote: VaultPath
    private let preferredViewName: String?
    private let store: VaultStore
    private let index: VaultIndex
    private let contentVersion: Int
    private let contentChange: BaseContentChange?
    private let isIndexComplete: Bool
    private let height: CGFloat
    private let open: (VaultPath) -> Void
    private let openBase: ((VaultPath, String?) -> Void)?
    private let filesChanged: ([VaultPath]) -> Void
    private let modelCache: EmbeddedBaseModelCache?

    /// A ```` ```base ```` code block.
    /// - Parameter modelCache: Keeps the base's results while it is off screen; see `EmbeddedBaseModelCache`.
    public init(yaml: String, embeddingNote: VaultPath, store: VaultStore, index: VaultIndex, contentVersion: Int = 0,
        contentChange: BaseContentChange? = nil, isIndexComplete: Bool = true,
                height: CGFloat = EmbeddedBaseView.defaultHeight, open: @escaping (VaultPath) -> Void, filesChanged: @escaping ([VaultPath]) -> Void = { _ in },
                modelCache: EmbeddedBaseModelCache? = nil) {
        self.init(source: .inline(yaml), embeddingNote: embeddingNote, viewName: nil, store: store, index: index, contentVersion: contentVersion,
            contentChange: contentChange,
                  isIndexComplete: isIndexComplete, height: height, open: open, openBase: nil, filesChanged: filesChanged, modelCache: modelCache)
    }

    /// An embedded `.base` file, optionally starting on the view named after `#`.
    /// - Parameter openBase: Opens the base on its own at the named view, for the Open Base
    ///   button. Without it, the button opens the base at its first view through `open`.
    /// - Parameter modelCache: Keeps the base's results while it is off screen; see `EmbeddedBaseModelCache`.
    public init(basePath: VaultPath, viewName: String? = nil, embeddingNote: VaultPath, store: VaultStore, index: VaultIndex,
        contentVersion: Int = 0, contentChange: BaseContentChange? = nil,
                isIndexComplete: Bool = true, height: CGFloat = EmbeddedBaseView.defaultHeight,
                open: @escaping (VaultPath) -> Void, openBase: ((VaultPath, String?) -> Void)? = nil, filesChanged: @escaping ([VaultPath]) -> Void = { _ in },
                modelCache: EmbeddedBaseModelCache? = nil) {
        self.init(source: .file(basePath), embeddingNote: embeddingNote, viewName: viewName, store: store, index: index,
            contentVersion: contentVersion, contentChange: contentChange,
                  isIndexComplete: isIndexComplete, height: height, open: open, openBase: openBase, filesChanged: filesChanged, modelCache: modelCache)
    }

    private init(source: BaseSource, embeddingNote: VaultPath, viewName: String?, store: VaultStore, index: VaultIndex, contentVersion: Int,
        contentChange: BaseContentChange?,
                 isIndexComplete: Bool, height: CGFloat, open: @escaping (VaultPath) -> Void, openBase: ((VaultPath, String?) -> Void)?,
                 filesChanged: @escaping ([VaultPath]) -> Void, modelCache: EmbeddedBaseModelCache?) {
        self.source = source
        self.embeddingNote = embeddingNote
        self.preferredViewName = viewName
        self.store = store
        self.index = index
        self.contentVersion = contentVersion
        self.contentChange = contentChange
        self.isIndexComplete = isIndexComplete
        self.height = height
        self.open = open
        self.openBase = openBase
        self.filesChanged = filesChanged
        self.modelCache = modelCache
    }

    public var body: some View {
        let open = open
        BaseContainerView(source: source, contextPath: embeddingNote, preferredViewName: preferredViewName, store: store, index: index,
                          contentVersion: contentVersion, contentChange: contentChange, isIndexComplete: isIndexComplete,
                              presentation: .embedded(height: height),
                          open: open, openBase: openBase ?? { basePath, _ in open(basePath) }, filesChanged: filesChanged, modelCache: modelCache)
            .id(EmbedIdentity(source: source, embeddingNote: embeddingNote, viewName: preferredViewName))
    }

    struct EmbedIdentity: Hashable {
        let source: BaseSource
        let embeddingNote: VaultPath
        let viewName: String?
    }
}

enum BasePresentation: Equatable {
    case document
    case embedded(height: CGFloat)
}

extension EnvironmentValues {
    /// False for a base inside a note: its rows lengthen the note instead of scrolling
    /// inside a box, which would trap the finger that scrolls the note.
    @Entry var basesScrollVertically = true
    /// The most rows a view shows; nil shows every row.
    @Entry var baseRowLimit: Int? = nil
}

/// A result group with only the rows that fit within a row limit.
struct BaseVisibleGroup: Identifiable {
    let group: BaseResultGroup
    let rows: [BaseResultRow]
    var id: Int { group.id }
}

extension BaseQueryResult {
    func visibleGroups(rowLimit: Int?) -> [BaseVisibleGroup] {
        guard let rowLimit else { return groups.map { group in BaseVisibleGroup(group: group, rows: group.rows) } }
        var remainingRowCount = rowLimit
        var visibleGroups: [BaseVisibleGroup] = []
        for group in groups where remainingRowCount > 0 {
            let rows = Array(group.rows.prefix(remainingRowCount))
            remainingRowCount -= rows.count
            visibleGroups.append(BaseVisibleGroup(group: group, rows: rows))
        }
        return visibleGroups
    }
}

/// Shared body of the document and embedded bases. Owns the model for one source.
struct BaseContainerView: View {
    let presentation: BasePresentation
    @Environment(\.accent) private var accent
    /// The vault's plugins, while they are on: they may show views of their own types.
    @Environment(\.communityPluginCodeBlocks) private var pluginHost
    /// Set while plugins are off, so a view of a type one may draw offers to turn them on.
    @Environment(\.communityPluginsTurnOnOffer) private var pluginsTurnOnOffer
    let contentVersion: Int
    let contentChange: BaseContentChange?
    let isIndexComplete: Bool
    let preferredViewName: String?
    /// The view `preferredViewName` asked for is shown.
    let viewRequestApplied: () -> Void
    let open: (VaultPath) -> Void
    /// Opens a `.base` file on its own, at the named view.
    let openBase: (VaultPath, String?) -> Void
    let filesChanged: ([VaultPath]) -> Void
    @State private var model: BaseDocumentModel
    /// Where a base inside a note keeps its model while it is off screen.
    private let modelCache: EmbeddedBaseModelCache?
    /// Kept across reloads: each cached thumbnail is checked against its file, so an index
    /// change after every autosave does not decode every cover again.
    @State private var thumbnails = BaseThumbnailStore()
    @State private var editRequest: BaseEditRequest?
    /// The edited property as written in its note, read before the property sheet opens.
    @State private var editedWrittenNode: BaseFrontmatterNode?
    @State private var editedView: EditedView?
    @State private var viewPendingDeletion: BaseViewTarget?
    /// Rows a base inside a note shows; "Show More" raises it.
    @State private var embeddedRowLimit = Self.embeddedRowLimitStep

    init(source: BaseSource, contextPath: VaultPath, preferredViewName: String?, store: VaultStore, index: VaultIndex, contentVersion: Int,
        contentChange: BaseContentChange? = nil,
         isIndexComplete: Bool, presentation: BasePresentation, open: @escaping (VaultPath) -> Void, openBase: @escaping (VaultPath, String?) -> Void,
         filesChanged: @escaping ([VaultPath]) -> Void, modelCache: EmbeddedBaseModelCache? = nil, viewRequestApplied: @escaping () -> Void = {}) {
        self.presentation = presentation
        self.contentVersion = contentVersion
        self.contentChange = contentChange
        self.viewRequestApplied = viewRequestApplied
        self.isIndexComplete = isIndexComplete
        self.preferredViewName = preferredViewName
        self.open = open
        self.openBase = openBase
        self.filesChanged = filesChanged
        let makeModel = {
            BaseDocumentModel(source: source, contextPath: contextPath, store: store, index: index, preferredViewName: preferredViewName,
                              didSaveFile: { path in filesChanged([path]) })
        }
        // A base's own tab is one base whichever view a link asked for; each embed of a view is its own.
        let identity = EmbeddedBaseView.EmbedIdentity(source: source, embeddingNote: contextPath, viewName: presentation == .document ? nil : preferredViewName)
        _model = State(initialValue: modelCache?.model(for: identity, makeModel: makeModel) ?? makeModel())
        self.modelCache = modelCache
    }

    private var isEmbedded: Bool { presentation != .document }
    /// Rows a base inside a note shows at first, and how many more each "Show More" adds.
    /// Its rows lengthen the note, so they are all laid out; the limit keeps that bounded.
    private static let embeddedRowLimitStep = 100
    /// A base inside a note grows with its rows, except a map, which keeps its height. A
    /// plugin's view is as tall as what it drew (`CommunityPluginBasesEmbedContent`).
    private var growsWithContent: Bool { isEmbedded && model.selectedView?.type != .map }
    /// A plugin draws every row of its view itself, so no row limit applies to it.
    private var isDrawnByPlugin: Bool { model.selectedView?.type.isOfAPluginsType ?? false }
    /// An embed that names its view (`![[Plan.base#First]]`) shows that view, as Obsidian does:
    /// a note about one view is not switched to another, or the shared file edited, from inside it.
    private var isLockedToNamedView: Bool {
        isEmbedded && preferredViewName != nil && model.viewSelectionErrorMessage == nil
    }

    var body: some View {
        Group {
            switch presentation {
            case .document:
                content
            case .embedded(let height):
                content
                    .modifier(BaseEmbeddedHeight(defaultHeight: growsWithContent ? nil : height,
                                                 configuredMapHeight: model.selectedView.flatMap { view in view.type == .map ? CGFloat(view.map.embeddedHeight) : nil }))
                    .environment(\.basesScrollVertically, !growsWithContent)
                    .environment(\.baseRowLimit, growsWithContent ? embeddedRowLimit : nil)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)) }
            }
        }
        .task(id: contentVersion) {
            // A kept model, or this view appearing again, may already show this version.
            guard model.loadedContentVersion != contentVersion else { return }
            await model.followVaultChange(to: contentVersion, change: contentChange)
            modelCache?.modelDidLoad()
        }
        .onAppear { model.startKeepingLoadedRecords() }
        .onDisappear { if modelCache != nil { model.releaseLoadedRecords() } }
        .onChange(of: preferredViewName) { _, viewName in
            guard let viewName else { return }
            Task { await model.selectView(named: viewName) }
            viewRequestApplied()
        }
        .onAppear {
            // A kept model shows what the person chose last, unless a link now asks for a view.
            guard presentation == .document, let preferredViewName else { return }
            if model.definition != nil { Task { await model.selectView(named: preferredViewName) } }
            viewRequestApplied()
        }
        // Both sheets wait for the save and stay open with the edit when it fails.
        .sheet(item: $editRequest) { request in
            BasePropertyEditorSheet(request: request, writtenNode: editedWrittenNode) { newValue in
                guard await model.setProperty(request.property, of: request.path, to: newValue) else {
                    return takeActionErrorMessage(otherwise: "The note was not saved.")
                }
                return nil
            }
            .tint(accent)
        }
        .sheet(item: $editedView) { editedView in
            // The sheet follows the base as it reloads: it shows when its view changed or was
            // removed, and always keeps Cancel.
            let definition = model.definition ?? editedView.definition
            BaseViewEditorSheet(definition: definition, viewIndex: editedView.viewIndex(in: definition),
                                availablePropertyKeys: model.availablePropertyKeys, pluginViews: pluginHost?.pluginBasesViews ?? [:]) { draft,
                                    original, viewPosition in
                // The view the draft was made from; saving is refused if the file no longer
                // has it there, so the draft never lands on another view.
                let target = BaseViewTarget(position: viewPosition, name: original.name)
                let newViewName = draft.name.trimmingCharacters(in: .whitespaces)
                let isSaved = await model.editDefinition(target: target, selectingViewNamed: newViewName) { editor in
                    try draft.apply(to: &editor, original: original, viewPosition: viewPosition)
                } != nil
                return isSaved ? nil : takeActionErrorMessage(otherwise: "The base was not saved.")
            }
            .tint(accent)
        }
        .confirmationDialog("Delete the view “\(viewPendingDeletion?.name ?? "")” from this base?",
                            isPresented: Binding(get: { viewPendingDeletion != nil }, set: { isPresented in if !isPresented { viewPendingDeletion = nil } }),
                            titleVisibility: .visible, presenting: viewPendingDeletion) { target in
            Button("Delete View", role: .destructive) { Task { await model.deleteView(target) } }
        } message: { _ in
            Text("The notes it shows are not changed.")
        }
    }

    /// Says how many rows are hidden and offers to show more. A `.base` file can also be
    /// opened on its own; a ```` ```base ```` block has no file to open.
    private func rowLimitFooter(displayedCount: Int) -> some View {
        HStack(spacing: 12) {
            Text("Showing the first \(embeddedRowLimit.formatted()) of \(displayedCount.formatted()) results.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Show More") { embeddedRowLimit += Self.embeddedRowLimitStep }
                .font(.caption)
            if case .file(let basePath) = model.source {
                Button("Open Base") { openBase(basePath, model.selectedView?.name) }
                    .font(.caption)
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// The file an embed shows, which Open Base opens on its own; nil for a base in its own tab or a ```` ```base ```` block.
    private var embeddedBaseFile: VaultPath? {
        guard isEmbedded, case .file(let basePath) = model.source else { return nil }
        return basePath
    }

    private func beginEditingSelectedView() {
        guard let definition = model.definition, let view = model.selectedView else { return }
        editedView = EditedView(definition: definition, target: BaseViewTarget(view))
    }

    /// The model's message for a failed save, moved into the open sheet so it is not also
    /// shown behind it.
    private func takeActionErrorMessage(otherwise fallbackMessage: String) -> String {
        let message = model.actionErrorMessage ?? fallbackMessage
        model.actionErrorMessage = nil
        return message
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            BaseToolbar(model: model, isEmbedded: isEmbedded, isLockedToNamedView: isLockedToNamedView, openBase: openBase, editView: beginEditingSelectedView,
                        deleteView: { viewPendingDeletion = model.selectedView.map(BaseViewTarget.init) })
            Divider()
            banners
            viewContent
                .frame(maxWidth: .infinity, maxHeight: growsWithContent ? nil : .infinity)
            if growsWithContent, !isDrawnByPlugin, let result = model.result, result.displayedCount > embeddedRowLimit {
                Divider()
                rowLimitFooter(displayedCount: result.displayedCount)
            }
        }
        .background(.background)
    }

    @ViewBuilder private var banners: some View {
        let messages = bannerMessages
        if !messages.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Label(message.text, systemImage: message.systemImage)
                        .font(.callout)
                        .foregroundStyle(message.isError ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
            Divider()
        }
    }

    private struct BannerMessage {
        let text: String
        let systemImage: String
        let isError: Bool
    }

    private var bannerMessages: [BannerMessage] {
        var messages: [BannerMessage] = []
        if let actionErrorMessage = model.actionErrorMessage {
            messages.append(BannerMessage(text: actionErrorMessage, systemImage: "exclamationmark.circle", isError: true))
        }
        if let viewSelectionErrorMessage = model.viewSelectionErrorMessage {
            messages.append(BannerMessage(text: viewSelectionErrorMessage, systemImage: "exclamationmark.triangle", isError: true))
        }
        if !isIndexComplete {
            messages.append(BannerMessage(text: "The vault is still being indexed, so results may be incomplete.", systemImage: "hourglass", isError: false))
        }
        for issue in model.definition?.issues ?? [] {
            messages.append(BannerMessage(text: issue, systemImage: "exclamationmark.triangle", isError: false))
        }
        for problem in model.result?.problems ?? [] {
            messages.append(BannerMessage(text: problem, systemImage: "exclamationmark.triangle", isError: true))
        }
        return messages
    }

    @ViewBuilder private var viewContent: some View {
        if let loadErrorMessage = model.loadErrorMessage {
            ContentUnavailableView {
                Label("Can't Show This Base", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadErrorMessage)
            } actions: {
                Button("Try Again") { Task { await model.reload() } }
            }
        } else if let view = model.selectedView, case .unsupported(let typeName) = view.type {
            pluginTypeContent(view: view, typeName: typeName)
        } else if let result = model.result, result.view.id == model.selectedView?.id {
            if result.rows.isEmpty && result.view.type != .map {
                ContentUnavailableView {
                    Label("No Results", systemImage: result.view.type.systemImage)
                } description: {
                    Text(result.problems.isEmpty ? "No files match this view's filters." : "Fix the problem shown above to see results.")
                }
            } else {
                resultView(result)
            }
        } else if model.isLoading || model.definition == nil {
            // Inside a note, the placeholder's height is not reported as the base's: the
            // text would shrink around it and grow again by its rows seconds later.
            ProgressView().controlSize(.large)
                .preference(key: LivePreviewEmbedLoadingKey.self, value: true)
        }
    }

    /// A view of a type Graphite does not draw: a community plugin's (TaskNotes' calendars and
    /// boards) is live in the base's own tab and a copy in a note, where several can show at once.
    @ViewBuilder private func pluginTypeContent(view: BaseView, typeName: String) -> some View {
        switch CommunityPluginBasesViewChoice.choose(viewType: typeName, host: pluginHost, turnOnOffer: pluginsTurnOnOffer) {
        case .drawnByPlugin:
            if let pluginHost {
                let result = model.result?.view.id == view.id ? model.result : nil
                if isEmbedded {
                    CommunityPluginBasesEmbedContent(host: pluginHost, viewType: typeName, view: view, source: model.source,
                        embeddingNote: model.contextPath, result: result)
                } else {
                    CommunityPluginBasesViewContent(host: pluginHost, viewType: typeName, view: view, source: model.source, result: result)
                }
            }
        case .waitingForPlugins:
            CommunityPluginBasesWaiting(text: "Waiting for community plugins…")
        case .pluginsAreOff:
            if let pluginsTurnOnOffer { CommunityPluginsOffForBaseView(viewType: typeName, offer: pluginsTurnOnOffer) }
        case .unsupported:
            unsupportedViewContent(typeName: typeName)
        }
    }

    /// A view type nothing draws: what is drawn, and the one step that leads on (`BaseUnsupportedViewWay`).
    @ViewBuilder private func unsupportedViewContent(typeName: String) -> some View {
        let canChooseAnotherView = model.views.count > 1 && !isLockedToNamedView
        let way = BaseUnsupportedViewWay.available(canChooseAnotherView: canChooseAnotherView, canEditView: model.canEditDefinition && !isLockedToNamedView,
                                                   baseFile: embeddedBaseFile)
        ContentUnavailableView {
            Label("“\(typeName)” Views Aren't Supported", systemImage: "questionmark.square.dashed")
        } description: {
            Text(BaseUnsupportedViewMessage.text(canChooseAnotherView: canChooseAnotherView))
        } actions: {
            switch way {
            case .editView: Button("Edit View…", action: beginEditingSelectedView)
            case .openBase(let basePath): Button("Open Base") { openBase(basePath, model.selectedView?.name) }
            case nil: EmptyView()
            }
        }
    }

    @ViewBuilder private func resultView(_ result: BaseQueryResult) -> some View {
        let actions = viewActions
        switch result.view.type {
        case .table:
            let model = model
            BaseTableView(result: result, sortKeys: model.effectiveSort, actions: actions, sort: { property, direction in
                Task {
                    if let direction { await model.setSort(on: property, direction: direction) } else { await model.toggleSort(on: property) }
                }
            }, resizeColumn: model.canEditDefinition ? { property, width in await model.setColumnWidth(width, of: property) } : nil)
        case .cards:
            BaseCardsView(result: result, actions: actions)
        case .list:
            BaseListView(result: result, actions: actions)
        case .map:
            BaseMapView(result: result, actions: actions)
        case .kanban:
            let model = model
            BaseKanbanView(result: result, actions: actions, moves: BaseKanbanMoves(
                canMove: { path in model.canMoveToGroup(path) },
                move: { path, groupKey in Task { await model.moveToGroup(path, groupKey: groupKey) } }))
        case .unsupported:
            EmptyView()
        }
    }

    private var viewActions: BaseViewActions {
        let model = model
        return BaseViewActions(
            openPath: open,
            openLink: { link in
                Task {
                    do {
                        if let path = try await model.resolve(link) { open(path) }
                        else { model.actionErrorMessage = "No single file matches “\(link.displayText)”." }
                    } catch {
                        model.actionErrorMessage = "Graphite couldn't follow “\(link.displayText)”. \(error.localizedDescription)"
                    }
                }
            },
            editRequest: { path, property, cell in
                let value = cell.value
                guard model.canEdit(property, of: path), BaseDocumentModel.canEditValue(value) else { return nil }
                return BaseEditRequest(path: path, property: property, displayName: model.definition?.displayName(for: property) ?? property.name,
                                       kind: model.editorKind(for: property, currentValue: value), currentValue: value)
            },
            beginEditing: { request in
                Task {
                    editedWrittenNode = await model.writtenPropertyNode(request.property, of: request.path)
                    editRequest = request
                }
            },
            toggleCheckbox: { request, shownValue in Task { await model.toggleCheckbox(request, shownValue: shownValue) } },
            requestedCheckboxValue: { request in model.requestedCheckboxValues[request.id] },
            thumbnails: thumbnails,
            vaultRoot: model.vaultRoot,
            contentVersion: contentVersion)
    }

    /// The view the view editor was opened on, with the definition it was read from.
    private struct EditedView: Identifiable {
        let definition: BaseDefinition
        let target: BaseViewTarget
        var id: BaseViewTarget { target }

        /// Where the edited view is in `definition.views`: where it was, or by its name after
        /// views were added or removed before it. Past the end when it was removed, which the
        /// sheet shows.
        func viewIndex(in definition: BaseDefinition) -> Int {
            definition.views.firstIndex(where: target.matches)
                ?? definition.views.firstIndex { view in view.name == target.name }
                ?? definition.views.endIndex
        }
    }
}

extension BaseViewType {
    /// A type Graphite does not draw itself, which a plugin may.
    var isOfAPluginsType: Bool {
        switch self {
        case .unsupported: true
        case .table, .cards, .list, .kanban, .map: false
        }
    }
}

/// What a base says about a view it cannot show. The menu it may point to is there only when
/// the base has another view and the embed does not name this one.
enum BaseUnsupportedViewMessage {
    static func text(canChooseAnotherView: Bool) -> String {
        let shown = "Graphite shows table, cards, list, Kanban and map views, and views drawn by community plugins that are on."
        return canChooseAnotherView ? shown + " Choose another view from the menu above." : shown
    }
}

/// The one step a base offers when its only way forward is not the view menu: changing this
/// view's layout in the view editor, or, in an embed that cannot edit the base, opening the base.
enum BaseUnsupportedViewWay: Equatable {
    case editView
    case openBase(VaultPath)

    /// Nil when another view can be chosen from the menu, or nothing here can change the view.
    static func available(canChooseAnotherView: Bool, canEditView: Bool, baseFile: VaultPath?) -> BaseUnsupportedViewWay? {
        guard !canChooseAnotherView else { return nil }
        if canEditView { return .editView }
        return baseFile.map(BaseUnsupportedViewWay.openBase)
    }
}

/// The row above the view: a view switcher (a menu, like Obsidian's), the result
/// count, and sorting.
struct BaseToolbar: View {
    @Bindable var model: BaseDocumentModel
    let isEmbedded: Bool
    /// The embed names its view: no menu to leave it, and nothing to edit the base from here.
    var isLockedToNamedView = false
    @Environment(\.communityPluginCodeBlocks) private var pluginHost
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let openBase: (VaultPath, String?) -> Void
    let editView: () -> Void
    let deleteView: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if model.views.count > 1 && !isLockedToNamedView {
                Menu {
                    ForEach(Array(model.views.enumerated()), id: \.element.id) { viewIndex, view in
                        Button {
                            Task { await model.selectView(viewIndex) }
                        } label: {
                            Label(view.name, systemImage: symbol(of: view.type))
                        }
                    }
                } label: {
                    viewTitle(showsChevron: true)
                }
                .menuIndicator(.hidden)
                // The name gives way before the buttons in a narrow note, which its menu still names.
                .fixedSize(horizontal: horizontalSizeClass != .compact, vertical: true)
                .layoutPriority(-1)
                .accessibilityLabel("View: \(model.selectedView?.name ?? "")")
            } else {
                viewTitle(showsChevron: false).foregroundStyle(.tint).layoutPriority(-1)
            }

            countLabel
            if model.showsProgress { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            if model.sortOverride != nil {
                resetSortButton
            }
            if model.canEditDefinition && !isLockedToNamedView { viewOptions }
            if isEmbedded, case .file(let basePath) = model.source {
                Button("Open Base", systemImage: "arrow.up.forward.square") { openBase(basePath, model.selectedView?.name) }
                    .labelStyle(.iconOnly)
                    .help("Open \(basePath.name)")
            }
            Button("Reload", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                .labelStyle(.iconOnly)
                .disabled(model.showsProgress)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, isEmbedded ? 8 : 10)
    }

    /// Its title takes room a narrow note's toolbar does not have.
    @ViewBuilder private var resetSortButton: some View {
        let button = Button("Reset Sort", systemImage: "arrow.uturn.backward") { Task { await model.resetSort() } }
            .font(.subheadline)
            .help("Return to the sort saved in the base")
        if horizontalSizeClass == .compact { button.labelStyle(.iconOnly) } else { button.labelStyle(.titleAndIcon) }
    }

    /// A plugin's view type shows the icon it registered.
    private func symbol(of type: BaseViewType) -> String {
        if case .unsupported(let typeName) = type, let registration = pluginHost?.pluginBasesViews[typeName] { return registration.systemImage }
        return type.systemImage
    }

    /// Obsidian's view menu: edit, create, duplicate and delete views, and keep a sort.
    private var viewOptions: some View {
        Menu {
            Button("Edit View…", systemImage: "slider.horizontal.3", action: editView)
            if model.sortOverride != nil {
                Button("Save Sort to View", systemImage: "arrow.up.arrow.down") { Task { await model.saveSortToView() } }
            }
            Menu("New View", systemImage: "plus") {
                ForEach([BaseViewType.table, .cards, .list, .kanban, .map], id: \.rawValue) { type in
                    Button(type.defaultViewName, systemImage: type.systemImage) { Task { await model.addView(type: type) } }
                }
                ForEach(pluginViewRegistrations, id: \.viewType) { registration in
                    Button(registration.name, systemImage: registration.systemImage) {
                        Task { await model.addView(type: BaseViewType(rawValue: registration.viewType), named: registration.name) }
                    }
                }
            }
            Button("Duplicate View", systemImage: "plus.square.on.square") { Task { await model.duplicateSelectedView() } }
            Button("Delete View…", systemImage: "trash", role: .destructive, action: deleteView)
                .disabled(model.views.count < 2)
        } label: {
            Label("View Options", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .disabled(model.showsProgress)
    }

    private var pluginViewRegistrations: [CommunityPluginBasesViewRegistration] {
        (pluginHost?.pluginBasesViews.values.map { registration in registration } ?? []).sorted { first, second in first.name < second.name }
    }

    private func viewTitle(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: model.selectedView.map { view in symbol(of: view.type) } ?? "tablecells")
            Text(model.selectedView?.name ?? "Base").fontWeight(.semibold).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
        }
    }

    /// A narrow toolbar (a base inside a note on iPhone) drops the noun rather than cut it.
    private var countLabel: some View {
        ViewThatFits(in: .horizontal) { Text(countText(showsNoun: true)); Text(countText(showsNoun: false)) }
            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            .accessibilityLabel(countText(showsNoun: true))
    }

    private func countText(showsNoun: Bool) -> String {
        guard let result = model.result else { return "" }
        let matchingCount = result.matchingCount
        let noun = showsNoun ? (matchingCount == 1 ? " result" : " results") : ""
        let shownCount = result.displayedCount < matchingCount ? "\(result.displayedCount.formatted()) of " : ""
        return shownCount + matchingCount.formatted() + noun
    }
}
