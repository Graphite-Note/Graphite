/**
 * File: NoteLinksInspector.swift
 * ------------------------------
 * Layer: UI
 * Description: The right sidebar of a note: outline, backlinks, outgoing links, tags, footnotes and the local graph
 *              and map.
 *
 * Authors: felixchvl
 * Version: 0.5
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// Obsidian's right sidebar: outline, backlinks, outgoing links, tags.
struct NoteLinksInspector: View {
    /// The device setting that keeps the panel shown, which commands set to open one.
    static let panelSettingKey = "GraphiteInspectorPanel"

    /// Makes `panel` the one the sidebar shows when it opens.
    static func choose(_ panel: InspectorPanel, deviceDefaults: UserDefaults) {
        deviceDefaults.set(panel.rawValue, forKey: panelSettingKey)
    }

    let session: MarkdownSession
    @Bindable var workspace: WorkspaceModel
    @AppStorage(NoteLinksInspector.panelSettingKey) private var selectedPanel: InspectorPanel = .outline
    @State private var outgoing: [OutgoingLink] = []
    @State private var linkedMentions: [MentionGroup] = []
    @State private var unlinkedMentions: [MentionGroup] = []
    /// Whether there are more notes that mention this one than are listed.
    @State private var unlinkedMentionsAreCut = false
    @AppStorage("GraphiteShowsUnlinkedMentions") private var showsUnlinkedMentions = false
    @State private var isLoadingUnlinkedMentions = false
    @State private var tags: [String] = []
    @State private var footnotes: [(note: Footnotes.Note, location: Int)] = []
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var outline: [OutlineHeading] = []

    struct OutlineHeading: Identifiable {
        let id: Int
        let level: Int
        let text: String
        let anchor: String
        /// Which of the headings with `anchor` this is, from zero, for notes where several headings read the same.
        let occurrence: Int
    }

    /// Reads the note's links, tags, footnotes and outline away from the main thread, a
    /// moment after typing pauses. The outline too: a long note's took 25 to 38 ms on the
    /// main thread at every switch to it, while the inspector was hidden as well.
    private func readNoteParts() async {
        do {
            try await Task.sleep(for: .milliseconds(250))
            let text = session.text
            let path = session.path
            let semantics = try await Task.detached { try MarkdownSemantics.parse(text) }.value
            // A detached task goes on after this one is cancelled, and its result is for the note it was started on.
            guard !Task.isCancelled, session.path == path else { return }
            let body = semantics.body
            let (listedFootnotes, headings) = await Task.detached { (Footnotes.listed(in: text), Self.outlineHeadings(in: body)) }.value
            guard !Task.isCancelled, session.path == path else { return }
            outgoing = Self.outgoingLinks(in: semantics.links); tags = semantics.tags
            footnotes = listedFootnotes
            outline = headings
        } catch is CancellationError {
        } catch { workspace.errorMessage = error.localizedDescription }
    }

    /// The outline of a note's body, each heading numbered among those that read the same,
    /// so a jump reaches that heading rather than the first of them.
    nonisolated static func outlineHeadings(in body: String) -> [OutlineHeading] {
        var occurrencesByAnchor: [String: Int] = [:]
        return NotePreviewDocument.outline(of: body).enumerated().map { headingIndex, heading in
            let occurrence = occurrencesByAnchor[heading.anchor, default: 0]
            occurrencesByAnchor[heading.anchor] = occurrence + 1
            return OutlineHeading(id: headingIndex, level: heading.level, text: heading.text, anchor: heading.anchor, occurrence: occurrence)
        }
    }

    /// A link this note makes, kept with its syntax: a Markdown link's target is a
    /// percent-encoded path relative to the note, which Wikilink rules would misread.
    struct OutgoingLink: Hashable {
        let target: String
        let isWiki: Bool

        /// Where a web or app address opens; nil for a link to a file of the vault.
        var externalLocation: URL? { WikiLinkResolver.externalLocation(of: target, isWiki: isWiki) }
    }

    /// Each distinct link once, in target order.
    nonisolated static func outgoingLinks(in links: [NoteLink]) -> [OutgoingLink] {
        Set(links.map { link in OutgoingLink(target: link.target, isWiki: link.isWiki) }).sorted { leftLink, rightLink in
            leftLink.target != rightLink.target ? leftLink.target < rightLink.target : leftLink.isWiki && !rightLink.isWiki
        }
    }

    enum InspectorPanel: String, CaseIterable, Identifiable {
        case outline, backlinks, outgoingLinks, tags, footnotes, graph, map
        var id: String { rawValue }
        var plugin: CorePlugin {
            switch self {
            case .outline: .outline
            case .backlinks: .backlinks
            case .outgoingLinks: .outgoingLinks
            case .tags: .tags
            case .footnotes: .footnotes
            case .graph: .graph
            case .map: .map
            }
        }
    }

    private var availablePanels: [InspectorPanel] { InspectorPanel.allCases.filter { panel in workspace.preferences.isEnabled(panel.plugin) } }

    var body: some View {
        VStack(spacing: 0) {
            if availablePanels.isEmpty {
                ContentUnavailableView("No Panels", systemImage: "sidebar.right", description: Text("Turn on Outline, Backlinks, Outgoing Links, or Tags View in Settings › Core Plugins."))
            } else {
                HStack(spacing: 10) {
                    Picker("Panel", selection: $selectedPanel) {
                        ForEach(availablePanels) { panel in Image(systemName: panel.plugin.systemImage).tag(panel).accessibilityLabel(panel.plugin.title) }
                    }
                    // The Mac otherwise writes the picker's own name, "Panel", before it.
                    .pickerStyle(.segmented).labelsHidden()
                    // On a phone this is a sheet, and the graph tab pans under a drag, so a swipe down
                    // does not close it: the way out is a button, in the picker's row.
                    if horizontalSizeClass == .compact { Button("Done") { dismiss() } }
                }
                .padding(10)
                if selectedPanel == .graph {
                    LocalGraphPanel(session: session, workspace: workspace)
                } else if selectedPanel == .map {
                    LocalMapPanel(session: session, workspace: workspace)
                } else {
                    List { panelContent }
                }
            }
        }
        .onAppear { selectAvailablePanel() }
        // Settings can turn off the shown panel's plugin while the sidebar stays open.
        .onChange(of: availablePanels) { selectAvailablePanel() }
        .task(id: session.text) { await readNoteParts() }
        // Mentions are in other notes: they change when the index takes in new contents of
        // another note, or this note's name or aliases change, not as this note is typed.
        .task(id: "\(selectedPanel)-\(workspace.indexChangeLog.newestVersionAffectingBacklinks(of: session.path))-\(session.path.rawValue)") {
            guard selectedPanel == .backlinks else { return }
            await loadLinkedMentions()
            if showsUnlinkedMentions { await loadUnlinkedMentions() }
        }
        .onChange(of: showsUnlinkedMentions) { _, showsMentions in
            if showsMentions { Task { await loadUnlinkedMentions() } }
        }
        // Another note's outline, links and mentions are not shown under this one while
        // its own are read.
        .onChange(of: session.path) {
            outline = []; outgoing = []; tags = []; footnotes = []
            linkedMentions = []; unlinkedMentions = []; unlinkedMentionsAreCut = false
        }
    }

    private func selectAvailablePanel() {
        if !availablePanels.contains(selectedPanel), let firstPanel = availablePanels.first { selectedPanel = firstPanel }
    }

    /// The mentions found are shown only while the note they were found for is: another
    /// note opened during a slow search kept the old note's list, and Link on one of its
    /// lines wrote a link to the wrong note.
    private func loadLinkedMentions() async {
        let path = session.path
        let names = workspace.mentionNames(of: path, text: session.text)
        let groups = await workspace.linkedMentions(of: path, names: names)
        guard !Task.isCancelled, session.path == path else { return }
        linkedMentions = groups
    }

    private func loadUnlinkedMentions() async {
        isLoadingUnlinkedMentions = true
        defer { isLoadingUnlinkedMentions = false }
        let path = session.path
        let names = workspace.mentionNames(of: path, text: session.text)
        let result = await workspace.unlinkedMentions(of: path, names: names)
        guard !Task.isCancelled, session.path == path else { return }
        unlinkedMentions = result.groups
        unlinkedMentionsAreCut = result.isCut
    }

    private func linkMention(_ match: SearchMatch, in source: VaultPath) {
        Task {
            // A mention that was not linked stays listed; the alert says why.
            guard await workspace.linkMention(match, in: source, to: session.path) else { return }
            // The linked note leaves this list, and its link joins the linked mentions.
            unlinkedMentions = unlinkedMentions.compactMap { group in
                guard group.path == source else { return group }
                let remaining = group.matches.filter { remainingMatch in remainingMatch != match }
                return remaining.isEmpty ? nil : MentionGroup(path: group.path, matches: remaining)
            }
        }
    }

    /// A note that mentions this one, with its lines; each line opens the note there.
    @ViewBuilder private func mentionGroup(_ group: MentionGroup, linksMentions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { Task { await workspace.open(group.path) } } label: {
                HStack {
                    Text(workspace.preferences.displayName(for: group.path)).lineLimit(1).interfaceFont(.body)
                    Spacer(minLength: 4)
                    if group.matches.count > 1 {
                        Text(group.matches.count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            ForEach(group.matches, id: \.self) { match in
                HStack(alignment: .top, spacing: 6) {
                    Button { Task { await workspace.open(group.path, at: match) } } label: {
                        Text(match.highlightedExcerpt(accent: accent))
                            .interfaceFont(.caption).foregroundStyle(Color.secondary).lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Opens the note at this line")
                    if linksMentions {
                        Button("Link") { linkMention(match, in: group.path) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityHint("Turns these words into a link to this note")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Obsidian's "Bookmark heading" from the outline.
    @ViewBuilder private func headingBookmarkButton(_ heading: OutlineHeading) -> some View {
        let subpath = "#" + heading.text
        if !workspace.preferences.isEnabled(.bookmarks) {
            EmptyView()
        } else if let bookmark = workspace.bookmarks.fileBookmark(for: session.path, subpath: subpath) {
            Button("Remove Bookmark", systemImage: "bookmark.slash") { Task { await workspace.removeBookmark(bookmark) } }
        } else {
            Button("Bookmark Heading", systemImage: "bookmark") {
                let bookmark = Bookmark.file(session.path, subpath: subpath)
                Task { await workspace.updateBookmarks { bookmarks in bookmarks.add(bookmark) } }
            }
        }
    }

    @ViewBuilder private var panelContent: some View {
        switch selectedPanel {
        case .outline:
            Section("Outline") {
                if outline.isEmpty { Text("No headings").foregroundStyle(.secondary) }
                ForEach(outline) { heading in
                    // Headings read as text, as in Obsidian's outline, not as tinted links.
                    Button { workspace.headingScrollRequest = HeadingScrollRequest(anchor: heading.anchor, occurrence: heading.occurrence) } label: {
                        Text(heading.text).lineLimit(2)
                            .interfaceFont(.callout, weight: heading.level == 1 ? .semibold : nil)
                            .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                            .padding(.leading, CGFloat(heading.level - 1) * 14)
                    }
                    .contextMenu { headingBookmarkButton(heading) }
                }
            }
        case .backlinks:
            Section("Linked Mentions") {
                if linkedMentions.isEmpty { Text("No other notes link here").foregroundStyle(.secondary) }
                ForEach(linkedMentions) { group in mentionGroup(group, linksMentions: false) }
            }
            Section {
                DisclosureGroup(isExpanded: $showsUnlinkedMentions) {
                    if isLoadingUnlinkedMentions && unlinkedMentions.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if unlinkedMentions.isEmpty {
                        Text("No other notes name this one without linking it").foregroundStyle(.secondary)
                    }
                    ForEach(unlinkedMentions) { group in mentionGroup(group, linksMentions: true) }
                    if unlinkedMentionsAreCut {
                        Text("Showing the first \(unlinkedMentions.count.formatted()) notes. More notes mention this one.")
                            .foregroundStyle(.secondary).interfaceFont(.caption)
                    }
                } label: {
                    Text("Unlinked mentions")
                }
            } footer: {
                if showsUnlinkedMentions {
                    Text("Places where this note's name or an alias is written as text. Link turns the words into a link to this note.")
                }
            }
        case .outgoingLinks:
            Section("Outgoing Links") {
                if outgoing.isEmpty { Text("This note has no links").foregroundStyle(.secondary) }
                ForEach(outgoing, id: \.self) { link in
                    if let location = link.externalLocation {
                        // A web address opens in the browser; it names no file of the vault.
                        Link(link.target, destination: location)
                    } else {
                        Button(link.target) { Task { await workspace.follow(link.target, from: session.path, isWiki: link.isWiki) } }
                    }
                }
            }
        case .footnotes:
            Section("Footnotes") {
                if footnotes.isEmpty { Text("No footnotes").foregroundStyle(.secondary) }
                ForEach(footnotes, id: \.note.number) { entry in
                    Button {
                        // Shows the footnote's reference in the note, marked.
                        workspace.headingScrollRequest = HeadingScrollRequest(anchor: "", textRange: NSRange(location: entry.location, length: 0))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(entry.note.number)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(accent)
                            // Emphasis, code and links read as in the note; blocks are not expected in a footnote.
                            Text((try? AttributedString(markdown: entry.note.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(entry.note.text))
                                .font(.callout).foregroundStyle(Color.primary).lineLimit(4).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .tags:
            Section("Tags") {
                if tags.isEmpty { Text("No tags").foregroundStyle(.secondary) }
                ForEach(tags, id: \.self) { tag in
                    Button("#" + tag) {
                        // The results are in the sidebar, which this tap brings forward; on a phone the sheet gives way to it.
                        workspace.searchForTagAndShowResults(tag)
                        if horizontalSizeClass == .compact { dismiss() }
                    }
                }
            }
        case .graph, .map:
            // Drawn in place of the list; see `body`.
            EmptyView()
        }
    }
}
