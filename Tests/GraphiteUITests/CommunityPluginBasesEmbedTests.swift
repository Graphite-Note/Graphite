import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// Plugin-drawn bases embedded in a note, through the view a note really shows them with and
/// the plugins' real page in WebKit. The fixture plugin is small and made here: it draws a week
/// table from properties of the base's rows, the way a timetable plugin does.
@MainActor
final class CommunityPluginBasesEmbedTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    private static let weekTablePlugin = """
    'use strict';
    const { Plugin, BasesView, NullValue } = require('obsidian');
    class WeekTable extends BasesView {
        constructor(controller, parent) {
            super(controller);
            this.week = 1;
            this.containerEl = parent.createDiv('week-table');
        }
        onDataUpdated() {
            this.containerEl.empty();
            this.containerEl.createEl('h4', { text: String(this.config.get('title')) + ' week ' + this.week });
            this.containerEl.createEl('button', { cls: 'next-week', text: 'Next' }).addEventListener('click', () => { this.week += 1; this.onDataUpdated(); });
            for (const entry of this.data.data) {
                const day = entry.getValue('note.day');
                const row = this.containerEl.createDiv({ cls: 'row', text: entry.file.basename + ': ' + (day instanceof NullValue ? 'Missing' : day.toString()) });
                row.style.height = '100px';
            }
        }
    }
    module.exports = class extends Plugin {
        onload() {
            this.registerBasesView('week-table', { name: 'Week table', icon: 'calendar-days', factory: (controller, parent) => new WeekTable(controller, parent),
                options: () => [{ type: 'text', displayName: 'Heading', key: 'title', default: 'A week' }] });
        }
    };
    """

    private static let files = [
        "Plan.base": "views:\n  - type: week-table\n    name: First\n    title: First year\n  - type: week-table\n    name: Second\n    title: Second year\n",
        "Algebra.md": "---\nday: Monday\n---\n",
        "Physics.md": "---\nday: Tuesday\n---\n",
        "Masters.md": "![[Plan.base#First]]\n\n![[Plan.base#Second]]\n",
    ]

    private func runningWorkspace(files: [String: String] = CommunityPluginBasesEmbedTests.files) async throws -> WorkspaceModel {
        let workspace = try await testBed.workspaceWithRunningPlugins([("week-table", Self.weekTablePlugin)], files: files)
        try await waitUntil("the view type is known", timeoutSeconds: 10) { workspace.communityPlugins.pluginBasesViews["week-table"] != nil }
        return workspace
    }

    private func embedContext(in workspace: WorkspaceModel) throws -> BaseEmbedContext {
        try XCTUnwrap(workspace.baseEmbedContext(for: VaultPath("Masters.md")))
    }

    /// The copies now shown, in no order, as their HTML.
    private func shownCopies(in host: CommunityPluginHost) -> [String] {
        host.shownCodeBlocks.values.compactMap { block in
            if case .drawn(let html) = block.appearance { return html }
            return nil
        }
    }

    #if canImport(AppKit)
    /// Hosts `view` in a window nobody sees, as a note's hosted block is.
    private func host<Content: View>(_ view: Content, width: CGFloat = 640) -> NSWindow {
        let hosting = NSHostingView(rootView: view.frame(width: width))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 1400), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.showInvisibly()
        addTeardownBlock { @MainActor in window.contentView = nil; window.orderOut(nil) }
        return window
    }

    func testTwoEmbedsInALivePreviewNoteBothDrawAtTheirOwnHeightAndTheWebViewStaysFree() async throws {
        let workspace = try await runningWorkspace()
        let plugins = workspace.communityPlugins
        let context = try embedContext(in: workspace)
        let environment = LivePreviewEnvironment(root: try XCTUnwrap(workspace.folderAccess?.root), textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                 resolve: { _, _ in try? VaultPath("Plan.base") }, open: { _ in }, follow: { _, _ in }, updateProperties: nil, baseContext: context, pluginCodeBlocks: plugins.hostWhilePluginsAreOn)
        // The environment a note's hosted block gets from `LivePreviewRenderedBlocks`, which is where the host used to go missing.
        let first = LivePreviewRenderedBlocks.rootView(for: Self.embedEntry("![[Plan.base#First]]"), environment: environment, accentHex: "#000000", colorScheme: .light,
                                                       revealSource: {}, reportHeight: { _ in })
        let second = LivePreviewRenderedBlocks.rootView(for: Self.embedEntry("![[Plan.base#Second]]"), environment: environment, accentHex: "#000000", colorScheme: .light,
                                                        revealSource: {}, reportHeight: { _ in })
        _ = host(VStack { first.view; second.view })

        try await waitUntil("both embeds show what the plugin drew", timeoutSeconds: 25) { self.shownCopies(in: plugins).count == 2 }
        let copies = shownCopies(in: plugins).joined()
        XCTAssertTrue(copies.contains("First year week 1"), copies)
        XCTAssertTrue(copies.contains("Second year week 1"), copies)
        XCTAssertNil(plugins.liveViewIdentifier, "An embed does not take the one web view from a base open in a tab.")
        try await waitUntil("each copy measured its height", timeoutSeconds: 15) { plugins.shownCodeBlocks.values.allSatisfy { block in block.height > 0 } }
    }

    func testAnEmbedShowsTheWeekChosenInItAfterScrollingAwayAndBack() async throws {
        let workspace = try await runningWorkspace()
        let plugins = workspace.communityPlugins
        let context = try embedContext(in: workspace)
        let window = host(BaseFileEmbedView(path: try VaultPath("Plan.base"), viewName: "First", context: context).environment(\.communityPluginCodeBlocks, plugins))
        try await waitUntil("the embed shows", timeoutSeconds: 25) { self.shownCopies(in: plugins).count == 1 }
        let block = try XCTUnwrap(plugins.shownCodeBlocks.values.first)
        block.tap(elementPath: [0, 1])
        try await waitUntil("the plugin's button worked", timeoutSeconds: 10) { self.shownCopies(in: plugins).joined().contains("week 2") }

        window.contentView = nil
        try await waitUntil("the embed left the screen") { plugins.shownCodeBlocks.isEmpty }
        window.contentView = NSHostingView(rootView: BaseFileEmbedView(path: try VaultPath("Plan.base"), viewName: "First", context: context)
            .environment(\.communityPluginCodeBlocks, plugins).frame(width: 640))

        try await waitUntil("it shows again, as it was", timeoutSeconds: 25) { self.shownCopies(in: plugins).joined().contains("week 2") }
    }

    func testAPropertyChangeRedrawsTheEmbedByItself() async throws {
        let workspace = try await runningWorkspace()
        let plugins = workspace.communityPlugins
        let root = try XCTUnwrap(workspace.folderAccess?.root)
        let context = try embedContext(in: workspace)
        _ = host(BaseFileEmbedView(path: try VaultPath("Plan.base"), viewName: "First", context: context).environment(\.communityPluginCodeBlocks, plugins))
        try await waitUntil("the row shows Monday", timeoutSeconds: 25) { self.shownCopies(in: plugins).joined().contains("Algebra: Monday") }

        try Data("---\nday: Friday\n---\n".utf8).write(to: root.appendingPathComponent("Algebra.md"))

        try await waitUntil("the row shows Friday", timeoutSeconds: 20) { self.shownCopies(in: plugins).joined().contains("Algebra: Friday") }
    }
    #endif

    private static func embedEntry(_ markdown: String) -> LivePreviewBlockEntry {
        let block = LivePreviewBlockScanner.blocks(in: (markdown + "\n") as NSString)[0]
        return LivePreviewBlockEntry(block: block, range: block.range, key: LivePreviewBlockKey.keys(for: [block])[0])
    }

    // MARK: Waiting, and what a base says about a view it cannot show

    func testAViewTypeNoPluginRegisteredYetWaitsWhilePluginsStartAndIsUnsupportedOnlyAfter() async throws {
        let workspace = try await testBed.workspaceWithPlugins([("week-table", Self.weekTablePlugin)], files: Self.files)
        let plugins = workspace.communityPlugins
        XCTAssertNil(plugins.hostWhilePluginsAreOn, "Plugins are off: no host.")
        XCTAssertFalse(plugins.viewTypeMayStillArrive("week-table"))

        let turningOn = Task { await plugins.setTurnedOnForVault(true) }
        await Task.yield()
        XCTAssertNotNil(plugins.hostWhilePluginsAreOn, "An embed gets the host before the runtime runs.")
        XCTAssertTrue(plugins.viewTypeMayStillArrive("week-table"), "It waits instead of saying the type is unsupported.")
        await turningOn.value

        XCTAssertFalse(plugins.isStartingPlugins)
        try await waitUntil("the plugin's view type is known") { plugins.pluginBasesViews["week-table"] != nil }
        XCTAssertFalse(plugins.viewTypeMayStillArrive("week-table"))
        XCTAssertFalse(plugins.viewTypeMayStillArrive("a-type-nothing-registered"), "When plugins have started, an unknown type is unsupported at once.")
    }

    func testTheMessageForAnUnsupportedViewPointsAtAMenuOnlyWhenThereIsOne() {
        XCTAssertFalse(BaseUnsupportedViewMessage.text(canChooseAnotherView: false).contains("menu"))
        XCTAssertTrue(BaseUnsupportedViewMessage.text(canChooseAnotherView: true).contains("Choose another view from the menu above."))
        XCTAssertTrue(BaseUnsupportedViewMessage.text(canChooseAnotherView: false).contains("community plugins"), "It says plugins can draw views, so it does not read as a dead end.")
    }

    // MARK: Height

    func testAnEmbedHasItsUsualHeightUntilMeasuredAndIsAsTallAsWhatWasDrawnAfter() {
        XCTAssertEqual(CommunityPluginBasesEmbedContent.shownHeight(measured: 0), EmbeddedBaseView.defaultHeight)
        XCTAssertEqual(CommunityPluginBasesEmbedContent.shownHeight(measured: 873), 873)
        XCTAssertEqual(CommunityPluginBasesEmbedContent.shownHeight(measured: 3), 44, "Never collapses to a few points.")
    }

    // MARK: Leaves kept for embeds

    private func request(_ viewName: String) -> CommunityPluginReadingBlockRequest {
        CommunityPluginReadingBlockRequest(kind: .embeddedBasesView(viewType: "week-table", viewName: viewName), source: "Plan.base", note: .root, firstLine: nil, lineCount: 0)
    }

    func testAKeptLeafServesOneEmbedAtATimeSoANoteMayEmbedAViewTwice() {
        var leaves = CommunityPluginEmbeddedBasesLeaves()
        let firstRequest = request("First")
        XCTAssertNil(leaves.hiddenLeaf(for: firstRequest))
        leaves.show("leaf-1", for: firstRequest, updateKey: Data())
        XCTAssertNil(leaves.hiddenLeaf(for: firstRequest), "On screen: a second embed of this view opens its own.")
        XCTAssertEqual(leaves.hide("leaf-1"), [])
        XCTAssertEqual(leaves.hiddenLeaf(for: firstRequest)?.leafIdentifier, "leaf-1")
    }

    func testHiddenLeavesAreBoundedTheOldestGoingFirstAndThoseOnScreenNeverGo() {
        var leaves = CommunityPluginEmbeddedBasesLeaves()
        leaves.show("on-screen", for: request("Shown"), updateKey: Data())
        var closed: [String] = []
        for position in 0...CommunityPluginEmbeddedBasesLeaves.maximumHiddenLeaves {
            leaves.show("leaf-\(position)", for: request("View \(position)"), updateKey: Data())
            closed += leaves.hide("leaf-\(position)")
        }
        XCTAssertEqual(closed, ["leaf-0"])
        XCTAssertEqual(leaves.removeAll().count, CommunityPluginEmbeddedBasesLeaves.maximumHiddenLeaves, "The one on screen is its embed's to close.")
    }

    // MARK: Options

    func testAPluginsOptionIsWrittenIntoTheBaseWithTheRestOfTheFileUntouched() async throws {
        let vault = try TemporaryVault.make(prefix: "PluginOptionVault", for: self).root
        let original = "# my base\nviews:\n  - type: week-table   # the plugin's\n    name: First\n    title: Old heading\n\n  - type: table\n    name: Other\n"
        try Data(original.utf8).write(to: vault.appendingPathComponent("Plan.base"))
        let store = VaultStore(root: vault)
        let path = try VaultPath("Plan.base")

        let didChange = try await CommunityPluginHost.writeBasesViewOption("title", value: .text("New heading"), viewName: "First", viewPosition: 0, to: path, in: store)
        XCTAssertTrue(didChange)
        let saved = String(decoding: try Data(contentsOf: vault.appendingPathComponent("Plan.base")), as: UTF8.self)
        XCTAssertEqual(saved, original.replacingOccurrences(of: "Old heading", with: "New heading"))

        let didChangeAgain = try await CommunityPluginHost.writeBasesViewOption("title", value: .text("New heading"), viewName: "First", viewPosition: 0, to: path, in: store)
        XCTAssertFalse(didChangeAgain, "The same value leaves the file alone, so no reload follows.")
        do {
            _ = try await CommunityPluginHost.writeBasesViewOption("title", value: .text("x"), viewName: "Renamed", viewPosition: 0, to: path, in: store)
            XCTFail("The view is no longer there under that name.")
        } catch {}
    }

    func testAViewOfAPluginsTypeKeepsItsOptionsAndTheEditorChangesOnlyTheOneEdited() throws {
        let yaml = "views:\n  - type: week-table\n    name: First\n    title: A heading\n    firstHour: 8\n    showsRooms: true\n    order:\n      - file.name\n"
        let view = try XCTUnwrap(BaseDefinition.parse(yaml).views.first)
        XCTAssertEqual(view.pluginOptions, ["title": .text("A heading"), "firstHour": .number(8), "showsRooms": .boolean(true)])

        var draft = BaseViewDraft(view: view)
        draft.pluginOptions["title"] = .text("Another")
        draft.pluginOptions["showsRooms"] = nil
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try draft.apply(to: &editor, original: BaseViewDraft(view: view), viewPosition: view.id)
        XCTAssertEqual(try BaseDefinition.parse(editor.yaml()).views.first?.pluginOptions, ["title": .text("Another"), "firstHour": .number(8)])
    }

    // MARK: Autosave

    func testSavingTheNoteAroundAnEmbedDoesNotRunTheBaseUnlessItsRowsOrFiltersAreTouched() async throws {
        let vault = try TemporaryVault.make(prefix: "BaseChangeVault", for: self).root
        for (relativePath, text) in [
            "Tasks/First.md": "---\nstatus: open\n---\nBody\n",
            "Elsewhere/Masters.md": "---\ntopic: study\n---\n![[Plan.base]]\n",
            "Elsewhere/Other.md": "Nothing here\n",
            "Plan.base": "filters: file.inFolder(\"Tasks\")\nviews:\n  - type: table\n    name: Table\n",
        ] {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: location)
        }
        let indexFolder = try TemporaryVault.make(prefix: "BaseChangeIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let notePath = try VaultPath("Elsewhere/Masters.md")
        let model = BaseDocumentModel(source: .file(try VaultPath("Plan.base")), contextPath: notePath, store: VaultStore(root: vault), index: index)
        await model.reload()

        func save(_ relativePath: String, _ text: String) async throws -> Bool {
            try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
            let path = try VaultPath(relativePath)
            try await index.refresh(paths: [path], root: vault)
            return await model.showsTheSame(after: [path])
        }

        let typing = try await save("Elsewhere/Masters.md", "---\ntopic: study\n---\n![[Plan.base]]\nMore words typed.\n")
        XCTAssertTrue(typing, "Words typed around the embed: no query runs. Before this fix each autosave ran every base in the note.")
        let elsewhere = try await save("Elsewhere/Other.md", "Something else\n")
        XCTAssertTrue(elsewhere, "A note the filters leave out.")
        let thisChanged = try await save("Elsewhere/Masters.md", "---\ntopic: rest\n---\n![[Plan.base]]\n")
        XCTAssertFalse(thisChanged, "`this` changed, which formulas and filters can read.")
        await model.reload()
        let rowBody = try await save("Tasks/First.md", "---\nstatus: open\n---\nBody, longer now\n")
        XCTAssertTrue(rowBody, "A row's words, when the base shows no size or date of it.")
        let rowProperty = try await save("Tasks/First.md", "---\nstatus: done\n---\nBody\n")
        XCTAssertFalse(rowProperty, "A row's property.")
        await model.reload()
        let newRow = try await save("Tasks/New.md", "---\nstatus: open\n---\n")
        XCTAssertFalse(newRow, "A new note the filters let in.")
        await model.reload()
        let definition = try await save("Plan.base", "filters: file.inFolder(\"Tasks\")\nviews:\n  - type: cards\n    name: Cards\n")
        XCTAssertFalse(definition, "The base itself.")
    }

    func testABaseShowingFileDatesRunsAfterEverySave() async throws {
        let vault = try TemporaryVault.make(prefix: "BaseDateVault", for: self).root
        try Data("Body\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
        try Data("views:\n  - type: table\n    name: Table\n    order:\n      - file.mtime\n".utf8).write(to: vault.appendingPathComponent("Plan.base"))
        let indexFolder = try TemporaryVault.make(prefix: "BaseDateIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let model = BaseDocumentModel(source: .file(try VaultPath("Plan.base")), contextPath: try VaultPath("Plan.base"), store: VaultStore(root: vault), index: index)
        await model.reload()
        let isSame = await model.showsTheSame(after: [try VaultPath("Note.md")])
        XCTAssertFalse(isSame)
    }

    // MARK: A base's own tab keeps what the person chose

    func testATabsBaseKeepsTheChosenViewAndSortWhenItsViewIsGoneAndBack() async throws {
        let vault = try TemporaryVault.make(prefix: "BaseTabVault", for: self).root
        try Data("views:\n  - type: table\n    name: First\n  - type: table\n    name: Second\n".utf8).write(to: vault.appendingPathComponent("Plan.base"))
        let indexFolder = try TemporaryVault.make(prefix: "BaseTabIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let path = try VaultPath("Plan.base")
        let store = VaultStore(root: vault)
        let cache = EmbeddedBaseModelCache(capacity: 1)
        let identity = EmbeddedBaseView.EmbedIdentity(source: .file(path), embeddingNote: path, viewName: nil)
        let model = cache.model(for: identity) { BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index, preferredViewName: "First") }
        await model.reload()
        await model.selectView(named: "Second")

        let modelAfterReturning = cache.model(for: identity) { BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index) }

        XCTAssertTrue(model === modelAfterReturning)
        XCTAssertEqual(modelAfterReturning.selectedView?.name, "Second", "Before this fix a tab switch went back to First.")
    }

    // MARK: Notes a plugin may take over

    func testOnlyANoteWithAPluginsFrontmatterKeyIsOfferedToAPluginThatTakesOverNotes() {
        XCTAssertTrue(CommunityPluginNoteTakeover.mayBeTakenOver(noteBeginning: "---\ntags: [a]\nexcalidraw-plugin: parsed\n---\n"))
        XCTAssertTrue(CommunityPluginNoteTakeover.mayBeTakenOver(noteBeginning: "---\n\"kanban-plugin\": board\n---\n"))
        XCTAssertFalse(CommunityPluginNoteTakeover.mayBeTakenOver(noteBeginning: "---\ntags: [a]\n---\nexcalidraw-plugin: not in the frontmatter\n"))
        XCTAssertFalse(CommunityPluginNoteTakeover.mayBeTakenOver(noteBeginning: "# A plain note\n"))
        XCTAssertFalse(CommunityPluginNoteTakeover.mayBeTakenOver(noteBeginning: ""))
        XCTAssertTrue(CommunityPluginNoteTakeover.mayBeTakenOver(noteBeginning: "---\r\nkanban-plugin: board\r\n---\r\n"))
    }

    // MARK: Words and widths

    func testABlockIsDrawnAgainWhenTheNotesWidthChangesByAStep() {
        XCTAssertEqual(CommunityPluginDrawingWidth.step(of: 0), 0)
        XCTAssertEqual(CommunityPluginDrawingWidth.step(of: 1000), CommunityPluginDrawingWidth.step(of: 1010))
        XCTAssertNotEqual(CommunityPluginDrawingWidth.step(of: 1000), CommunityPluginDrawingWidth.step(of: 700))
    }

    func testAnUpdateOfARunningPluginSaysItNeedsAReload() throws {
        let manifest = try CommunityPluginManifest(manifestData: Data("{\"id\": \"week-table\", \"name\": \"Week Table\", \"version\": \"1.0.0\", \"minAppVersion\": \"1.0.0\"}".utf8))
        let compatibility = CommunityPluginCompatibility.assess(manifest: manifest, hasMainScript: true)
        XCTAssertTrue(CommunityPluginTurningOn.installationOutcome("Installed.", compatibility: compatibility, isTurnedOn: true, isRunning: true).contains("Reload Plugins"))
        XCTAssertTrue(CommunityPluginTurningOn.installationOutcome("Installed.", compatibility: compatibility, isTurnedOn: false, isRunning: false).contains("Turn it on"))
        XCTAssertFalse(CommunityPluginTurningOn.installationOutcome("Installed.", compatibility: compatibility, isTurnedOn: true, isRunning: false).contains("Turn it on"))
    }

    func testTurningPluginsOnNamesThoseThatWouldRun() async throws {
        let workspace = try await testBed.workspaceWithPlugins([("week-table", Self.weekTablePlugin)], files: Self.files)
        XCTAssertEqual(workspace.communityPlugins.pluginsEnabledToRun.map(\.id), ["week-table"])
        XCTAssertTrue(CommunityPluginTurningOn.question(naming: ["Week Table", "Other"]).contains("Week Table, Other"))
    }
}
