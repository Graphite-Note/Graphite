import SwiftUI
import GraphiteCore

// Several plugin-drawn bases in one note.
//
// The runtime has one web view, which can be in one place at a time, so a live view cannot serve
// a note with several `![[Plan.base#View]]` embeds. Each embed is shown as a copy instead, as
// plugins' code blocks are: it has its own leaf in the plugins' page, where the plugin draws it
// at the note's width; a small web view in the note, which runs no script, shows a copy of what
// was drawn, kept current as it changes, and gives taps and typing back to the real elements.
// Rejected: a picture per embed, which goes stale, cannot be scrolled or read aloud and needs the
// web view moved to take it; and a web view with a runtime per embed, which loads every plugin
// again each time and has no sensible memory limit. A copy costs one script-free web view while
// on screen (WebKit shares their process), and a leaf, which outlives scrolling away so a week
// the person chose stays chosen: `CommunityPluginEmbeddedBasesLeaves` bounds those.

/// The leaves of embedded base views, kept while their embeds are scrolled away. Those on
/// screen are never given up; of the others, the longest unseen go past the limit.
struct CommunityPluginEmbeddedBasesLeaves {
    /// Leaves kept without an embed on screen. Each holds a plugin view's elements in the page.
    static let maximumHiddenLeaves = 12

    private struct Entry {
        let request: CommunityPluginReadingBlockRequest
        let leafIdentifier: String
        var isShown: Bool
        /// The results last given to the leaf, so showing it again redraws it only if they changed.
        var lastUpdateKey: Data
    }

    /// Longest unseen first.
    private var entries: [Entry] = []

    /// A leaf for this embed that no other embed is showing now (a note may embed one view twice).
    func hiddenLeaf(for request: CommunityPluginReadingBlockRequest) -> (leafIdentifier: String, lastUpdateKey: Data)? {
        entries.last { entry in entry.request == request && !entry.isShown }.map { entry in (entry.leafIdentifier, entry.lastUpdateKey) }
    }

    mutating func show(_ leafIdentifier: String, for request: CommunityPluginReadingBlockRequest, updateKey: Data) {
        entries.removeAll { entry in entry.leafIdentifier == leafIdentifier }
        entries.append(Entry(request: request, leafIdentifier: leafIdentifier, isShown: true, lastUpdateKey: updateKey))
    }

    mutating func noteUpdate(of leafIdentifier: String, updateKey: Data) {
        guard let position = entries.firstIndex(where: { entry in entry.leafIdentifier == leafIdentifier }) else { return }
        entries[position].lastUpdateKey = updateKey
    }

    /// The embed left the screen. Returns the leaves to close.
    mutating func hide(_ leafIdentifier: String) -> [String] {
        guard let position = entries.firstIndex(where: { entry in entry.leafIdentifier == leafIdentifier }) else { return [] }
        entries[position].isShown = false
        var closed: [String] = []
        while entries.filter({ entry in !entry.isShown }).count > Self.maximumHiddenLeaves, let oldest = entries.firstIndex(where: { entry in !entry.isShown }) {
            closed.append(entries.remove(at: oldest).leafIdentifier)
        }
        return closed
    }

    mutating func forget(_ leafIdentifier: String) {
        entries.removeAll { entry in entry.leafIdentifier == leafIdentifier }
    }

    /// Everything goes: the runtime stopped, or a plugin's view types changed. Returns the
    /// leaves no embed is showing, to close.
    mutating func removeAll() -> [String] {
        defer { entries = [] }
        return entries.filter { entry in !entry.isShown }.map(\.leafIdentifier)
    }
}

extension CommunityPluginShownCodeBlock {
    /// Shows a copy of an embedded base view's leaf, at the width of the note: the last copy at
    /// once, at its height, while the leaf is attached in the plugins' page.
    func attachEmbeddedView(_ leafIdentifier: String, request: CommunityPluginReadingBlockRequest, width: CGFloat) async {
        guard let host = begin(request) else { return }
        let message: [String: Any] = ["operation": "view.attach", "blockIdentifier": blockIdentifier, "leafIdentifier": leafIdentifier,
                                      "isEmbedded": true, "width": Double(width)]
        do {
            let answer = try await host.send(message, timeout: Self.drawingTimeout)
            finishDrawing(answer, failureMessage: "The plugin did not show this view.")
        } catch {
            fail(with: error.localizedDescription)
        }
    }

    /// The note's width changed; the plugin lays its view out again and the copy follows.
    func resizeEmbeddedView(toWidth width: CGFloat) {
        guard let host, width > 0 else { return }
        let blockIdentifier = blockIdentifier
        Task { _ = try? await host.send(["operation": "view.resize", "blockIdentifier": blockIdentifier, "width": Double(width)], timeout: .seconds(5)) }
    }
}

/// A base's view of a plugin's type inside a note: a copy, as tall as what the plugin drew.
struct CommunityPluginBasesEmbedContent: View {
    let host: CommunityPluginHost
    let viewType: String
    let view: BaseView
    let source: BaseSource
    let embeddingNote: VaultPath
    let result: BaseQueryResult?
    @State private var shownBlock: CommunityPluginShownCodeBlock?
    @State private var leafIdentifier: String?
    @State private var availableWidth: CGFloat = 0
    /// Raised by Try Again, which opens the view anew.
    @State private var openingAttempt = 0
    @State private var didFailToOpen = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent
    @ScaledMetric(relativeTo: .body) private var scaledTextSize: Double = 15

    /// Below this a view's copy is not made smaller: a plugin that drew nothing still shows as
    /// a place in the note, and its base's toolbar stays with it.
    private static let minimumHeight: CGFloat = 44

    private var request: CommunityPluginReadingBlockRequest {
        let sourceText: String
        switch source {
        case .file(let path): sourceText = path.rawValue
        case .inline(let yaml): sourceText = yaml
        }
        return CommunityPluginReadingBlockRequest(kind: .embeddedBasesView(viewType: viewType, viewName: view.name), source: sourceText, note: embeddingNote, firstLine: nil, lineCount: 0)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.width } action: { width in availableWidth = width }
            .task(id: OpeningKey(viewType: viewType, viewPosition: view.id, hasResult: result != nil, hasWidth: availableWidth > 0, attempt: openingAttempt)) { await show() }
            .onChange(of: CommunityPluginBasesViewContent.updateKey(for: result)) { _, updateKey in send(updateKey: updateKey, viewOptionsChanged: false) }
            .onChange(of: view) { _, _ in send(updateKey: CommunityPluginBasesViewContent.updateKey(for: result), viewOptionsChanged: true) }
            .onChange(of: availableWidth) { _, width in shownBlock?.resizeEmbeddedView(toWidth: width) }
            .onDisappear(perform: hide)
    }

    @ViewBuilder private var content: some View {
        if didFailToOpen {
            CommunityPluginBasesFailure(viewName: host.pluginBasesViews[viewType]?.name ?? viewType) { tryAgain() }
                .frame(minHeight: EmbeddedBaseView.defaultHeight)
        } else {
            switch shownBlock?.appearance ?? .drawing {
            case .drawn(let html):
                if let shownBlock {
                    CommunityPluginCodeBlockDisplay(block: shownBlock, html: html, styleSheets: host.pluginStyleSheets, isDark: colorScheme == .dark, textSize: scaledTextSize,
                                                    accentHex: accent.sRGBHex, isEmbeddedView: true, bodyClasses: host.pluginBodyClasses, bodyStyle: host.pluginBodyStyle,
                                                    hasTheme: !host.activeThemeName.isEmpty)
                        .frame(height: Self.shownHeight(measured: shownBlock.height))
                }
            case .failed:
                CommunityPluginBasesFailure(viewName: host.pluginBasesViews[viewType]?.name ?? viewType) { tryAgain() }
                    .frame(minHeight: EmbeddedBaseView.defaultHeight)
            case .drawing, .unchanged:
                CommunityPluginBasesWaiting(text: "\(host.pluginBasesViews[viewType]?.name ?? viewType) is drawing this view…")
            }
        }
    }

    /// The height of the copy: what its page measured, the embed's usual height until then.
    static func shownHeight(measured: CGFloat) -> CGFloat {
        measured > 0 ? max(measured, minimumHeight) : EmbeddedBaseView.defaultHeight
    }

    private func show() async {
        guard let result, availableWidth > 0, leafIdentifier == nil else { return }
        let block = shownBlock ?? CommunityPluginShownCodeBlock(host: host)
        shownBlock = block
        let request = request
        let updateKey = CommunityPluginBasesViewContent.updateKey(for: result)
        var isReused = false
        var leaf: String?
        if let kept = host.embeddedBasesLeaves.hiddenLeaf(for: request) {
            leaf = kept.leafIdentifier
            isReused = true
            if kept.lastUpdateKey != updateKey { host.updateBasesView(kept.leafIdentifier, result: result) }
        } else {
            leaf = await host.openBasesView(type: viewType, viewName: view.name, viewIndex: view.id, source: source, result: result, embedWidth: availableWidth)
        }
        guard let leaf else {
            didFailToOpen = true
            return
        }
        // The embed left the screen while the plugin opened its view.
        if Task.isCancelled {
            host.embeddedBasesLeaves.show(leaf, for: request, updateKey: updateKey)
            hide(leaf)
            return
        }
        leafIdentifier = leaf
        host.embeddedBasesLeaves.show(leaf, for: request, updateKey: updateKey)
        await block.attachEmbeddedView(leaf, request: request, width: availableWidth)
        // A kept leaf that was closed meanwhile (its plugin reloaded): a new one is opened.
        if isReused, case .failed = block.appearance {
            host.embeddedBasesLeaves.forget(leaf)
            leafIdentifier = nil
            openingAttempt += 1
        }
    }

    private func send(updateKey: Data, viewOptionsChanged: Bool) {
        guard let leafIdentifier, let result else { return }
        host.updateBasesView(leafIdentifier, result: result, viewOptionsChanged: viewOptionsChanged)
        host.embeddedBasesLeaves.noteUpdate(of: leafIdentifier, updateKey: updateKey)
    }

    private func tryAgain() {
        if let leafIdentifier {
            host.embeddedBasesLeaves.forget(leafIdentifier)
            host.closeView(leafIdentifier)
        }
        leafIdentifier = nil
        didFailToOpen = false
        openingAttempt += 1
    }

    private func hide() {
        shownBlock?.release()
        shownBlock = nil
        if let leafIdentifier { hide(leafIdentifier) }
        leafIdentifier = nil
    }

    private func hide(_ leaf: String) {
        for closedLeaf in host.embeddedBasesLeaves.hide(leaf) { host.closeView(closedLeaf) }
    }

    private struct OpeningKey: Equatable {
        let viewType: String
        let viewPosition: Int
        let hasResult: Bool
        let hasWidth: Bool
        let attempt: Int
    }
}

/// While a plugin's base view is on its way, at an embed's usual height so the note around it
/// does not shrink and grow again. The note's editor does not take this as the block's height.
struct CommunityPluginBasesWaiting: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: EmbeddedBaseView.defaultHeight)
        .accessibilityElement(children: .combine)
        .preference(key: LivePreviewEmbedLoadingKey.self, value: true)
    }
}

/// A plugin's base view that could not be drawn, with a way to try again.
struct CommunityPluginBasesFailure: View {
    let viewName: String
    let tryAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("\u{201C}\(viewName)\u{201D} Could Not Be Shown", systemImage: "puzzlepiece.extension")
        } description: {
            Text("Its plugin did not draw the view in time. Settings › Community Plugins lists what went wrong.")
        } actions: {
            Button("Try Again", action: tryAgain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A view type a plugin registered (`registerBasesView`), as Graphite offers it.
struct CommunityPluginBasesViewRegistration: Decodable, Equatable {
    struct Option: Decodable, Equatable, Identifiable {
        enum Kind: Equatable {
            case text, toggle, dropdown, slider
            /// A kind Graphite has no row for (a list of texts, a formula): edited in the base file.
            case other(String)

            init(rawValue: String) {
                switch rawValue {
                case "text", "file", "folder", "property": self = .text
                case "toggle": self = .toggle
                case "dropdown": self = .dropdown
                case "slider": self = .slider
                default: self = .other(rawValue)
                }
            }
        }

        struct Choice: Decodable, Equatable {
            let value: String
            let title: String
        }

        var id: String { key }
        let key: String
        let kind: Kind
        let displayName: String
        let defaultValue: BaseViewOptionValue?
        let choices: [Choice]
        let minimum: Double?
        let maximum: Double?
        let step: Double?

        private enum CodingKeys: String, CodingKey { case key, type, displayName, defaultValue, choices, min, max, step }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            kind = Kind(rawValue: try container.decodeIfPresent(String.self, forKey: .type) ?? "text")
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? key
            choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
            minimum = try container.decodeIfPresent(Double.self, forKey: .min)
            maximum = try container.decodeIfPresent(Double.self, forKey: .max)
            step = try container.decodeIfPresent(Double.self, forKey: .step)
            if let isOn = try? container.decode(Bool.self, forKey: .defaultValue) { defaultValue = .boolean(isOn) }
            else if let number = try? container.decode(Double.self, forKey: .defaultValue) { defaultValue = .number(number) }
            else if let text = try? container.decode(String.self, forKey: .defaultValue) { defaultValue = .text(text) }
            else { defaultValue = nil }
        }
    }

    let viewType: String
    let name: String
    /// A Lucide name, as Obsidian gives it.
    let icon: String
    let options: [Option]

    private enum CodingKeys: String, CodingKey { case viewType, name, icon, options }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewType = try container.decode(String.self, forKey: .viewType)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? viewType
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        options = try container.decodeIfPresent([Option].self, forKey: .options) ?? []
    }

    var systemImage: String { CommunityPluginViewSymbol.systemImage(forIcon: icon) }
}

extension CommunityPluginHost {
    /// A plugin set an option of its view (`config.set`): written into the view in the `.base`
    /// file, as Obsidian does, in turn with other such saves and with the file's revision
    /// checked. A value the file cannot hold as one scalar is reported, not written.
    func saveBasesViewOption(_ message: [String: Any]) {
        guard let store = workspace?.store, let pathText = message["baseFilePath"] as? String, let path = try? VaultPath(pathText),
              let key = message["key"] as? String, let viewName = message["viewName"] as? String, let viewPosition = message["viewIndex"] as? Int else { return }
        let value = Self.baseViewOptionValue(message["value"])
        if value == nil, !(message["value"] is NSNull) {
            showNotice("A plugin's view tried to keep a value a base file's view cannot hold, so it lasts only until it closes.", pluginIdentifier: nil)
            return
        }
        let previousSave = basesViewOptionSave
        basesViewOptionSave = Task { [weak self] in
            await previousSave?.value
            do {
                guard try await Self.writeBasesViewOption(key, value: value, viewName: viewName, viewPosition: viewPosition, to: path, in: store) else { return }
                self?.workspace?.filesSavedOutsideEditors([path])
            } catch {
                self?.showNotice("A plugin's view could not save its option in “\(path.name)”. " + error.localizedDescription, pluginIdentifier: nil)
            }
        }
    }

    /// A value from the plugins' page: WebKit gives numbers and Booleans as `NSNumber`.
    private static func baseViewOptionValue(_ value: Any?) -> BaseViewOptionValue? {
        switch value {
        case let text as String: return .text(text)
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .boolean(number.boolValue) : .number(number.doubleValue)
        default: return nil
        }
    }

    /// True when the file changed. It stays byte for byte as written outside the option.
    static func writeBasesViewOption(_ key: String, value: BaseViewOptionValue?, viewName: String, viewPosition: Int, to path: VaultPath, in store: VaultStore) async throws -> Bool {
        let snapshot = try await store.read(path, maximumBytes: BaseDefinition.maximumSourceBytes)
        guard let fileText = UTF8FileText(snapshot.data) else { throw GraphiteError.invalidFile("This base is not UTF-8 text.") }
        let definition = try BaseDefinition.parse(fileText.text)
        guard definition.views.contains(where: { view in view.id == viewPosition && view.name == viewName }) else {
            throw GraphiteError.invalidFile("The view “\(viewName)” changed in another app.")
        }
        var editor = try BaseDefinitionEditor(yaml: fileText.text)
        try editor.setOption(key, value: value, forViewAt: viewPosition)
        let updatedText = try editor.yaml()
        guard updatedText != fileText.text else { return false }
        _ = try await store.save(fileText.encoded(updatedText), at: path, expecting: .revision(snapshot.revision))
        return true
    }

    /// Whether plugins are still on their way, so a view type none has registered yet may
    /// still be one a plugin draws.
    func viewTypeMayStillArrive(_ viewType: String) -> Bool {
        pluginBasesViews[viewType] == nil && isStartingPlugins
    }
}
