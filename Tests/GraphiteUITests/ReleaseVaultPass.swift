/**
 * File: ReleaseVaultPass.swift
 * ----------------------------
 * Layer: Tests
 * Description: The release pass over Tests/ReleaseVault: the window's root view over a copy of the vault, every note
 *              opened in Live Preview, the reading view and source mode page by page, every other file in its own view,
 *              a screenshot of each page, and what went wrong; the Mac's and the iPad's tests run it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import SwiftUI
import XCTest
import GraphiteCore
#if canImport(GraphiteFixtures)
import GraphiteFixtures
#endif
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Docs/Release-test-vault-todo.md, section 2. The pass opens the window's root view, as the app shows it, over a copy of
/// `Tests/ReleaseVault`, imports its Goodnotes and Notability samples, and opens every file: a note in each of its three
/// views, scrolled a page at a time to its end, a PDF, canvas, base or picture in its own view. Every page is a screenshot
/// attached to the run (kept always) and, with `GRAPHITE_RELEASE_PASS_SCREENSHOTS` naming a folder, written there too.
///
/// It records as findings (`ReleaseVaultFinding`): an error the workspace reports or a tab that cannot open its file;
/// a Live Preview block on screen with no view over its source; a rendered view in source mode; a picture Live Preview
/// or the reading view did not load; an embed or section not found and a diagram not drawn, in the reading view's
/// blocks; and a stretch of main-thread work longer than the budget, at each opening, switch of view and scroll.
@MainActor
final class ReleaseVaultPass {
    /// The pass takes minutes, so the normal suites leave it out: `GRAPHITE_RELEASE_PASS=1` runs it (on the iPad as
    /// `TEST_RUNNER_GRAPHITE_RELEASE_PASS=1`, which xcodebuild hands to the tests). `scripts/release-check.sh` sets it.
    static let switchVariable = "GRAPHITE_RELEASE_PASS"
    static let skipReason = "Not run: the release pass over Tests/ReleaseVault runs before a release, with GRAPHITE_RELEASE_PASS=1."
    static let screenshotFolderVariable = "GRAPHITE_RELEASE_PASS_SCREENSHOTS"
    static let maximumPagesPerView = 60
    /// The vault's own community plugin (`.obsidian/plugins/release-vault-test`), made by `scripts/make-release-vault.py`.
    static let testPluginIdentifier = "release-vault-test"
    /// The longest the main thread may stay busy in one stretch. Measured 2026-11-12 (Debug builds): see
    /// Docs/Release-test-vault-todo.md; the budget leaves room for a machine running other work.
    #if canImport(UIKit)
    static let freezeBudget = Duration.milliseconds(2_500)
    #else
    static let freezeBudget = Duration.milliseconds(1_500)
    #endif

    let testCase: XCTestCase
    let workspace: WorkspaceModel
    let window: MainThreadQuietWatch.Window
    let vaultRoot: URL
    private let webServer: LoopbackWebServer
    private let quietWatch: MainThreadQuietWatch
    private(set) var findings: [ReleaseVaultFinding] = []
    private(set) var screenshotCount = 0
    private(set) var openedFileCount = 0
    private(set) var longestStep: (duration: Duration, place: String) = (.zero, "")
    private(set) var part: ReleaseVaultPassPart?

    private init(testCase: XCTestCase, workspace: WorkspaceModel, window: MainThreadQuietWatch.Window, vaultRoot: URL, webServer: LoopbackWebServer) {
        self.testCase = testCase
        self.workspace = workspace
        self.window = window
        self.vaultRoot = vaultRoot
        self.webServer = webServer
        // A fifth of a second without work ends each step: the pass measures several hundred.
        quietWatch = MainThreadQuietWatch(window: window, quietStepsToStop: 40)
    }

    /// The vault copied, indexed and shown in a window that closes when the test ends.
    static func open(for testCase: XCTestCase) async throws -> ReleaseVaultPass {
        let webServer = try await LoopbackWebServer(pages: try ReleaseVaultPassWebPages.pages())
        testCase.addTeardownBlock { webServer.stop() }
        let vaultRoot = try TemporaryVault.make(prefix: "ReleaseVault", for: testCase).root
        try ReleaseVaultPassWebPages.copyVault(to: vaultRoot, pointingFramesAt: webServer.address("/").absoluteString)
        let device = try IsolatedWorkspaceDevice.make(for: testCase)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the release vault is indexed", timeoutSeconds: 120) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: testCase)
        return ReleaseVaultPass(testCase: testCase, workspace: workspace, window: window, vaultRoot: vaultRoot, webServer: webServer)
    }

    /// Opens every file of the part in order of its path, after importing the notebooks of other apps when they are in
    /// it. The first part also records a file that no part opens, so a new folder of the vault is not left out unseen.
    func run(_ part: ReleaseVaultPassPart) async throws {
        self.part = part
        if part.contains("Notebooks/") { try await importNotebooks() }
        if part.contains("Plugins/") { try await turnOnCommunityPlugins() }
        let files = try filesToOpen()
        if part == ReleaseVaultPassPart.allCases.first {
            for path in files where !ReleaseVaultPassPart.allCases.contains(where: { somePart in somePart.contains(path.rawValue) }) {
                record(ReleaseVaultFinding(path: path.rawValue, shown: .wholeVault, problem: .notShown("no part of the pass opens it")))
            }
        }
        for path in files where part.contains(path.rawValue) {
            switch DocumentKind(path: path) {
            case .markdown: try await passNote(path)
            case .pdf, .image, .base, .canvas: try await passFile(path)
            case .media, .other: continue
            }
            openedFileCount += 1
        }
        if part.contains("Web/"), !webServer.requestedPaths.contains(where: ReleaseVaultPassWebPages.isFramePage) {
            record(ReleaseVaultFinding(path: "Web/Web pages.md", shown: .livePreview, problem: .notShown("the page in the frame was never asked for")))
        }
    }

    /// Findings that are not the vault's own deliberate failures.
    var unexpectedFindings: [ReleaseVaultFinding] {
        findings.filter { finding in !ReleaseVaultFinding.intended.contains(finding) && !finding.isKnownOpenDefect }
    }
    /// Deliberate failures of the part's files that the pass did not see, so Graphite stopped showing them as failures.
    var intendedFindingsNotSeen: [ReleaseVaultFinding] {
        ReleaseVaultFinding.intended.filter { finding in part?.contains(finding.path) == true && !findings.contains(finding) }
    }

    /// One `GRAPHITE-RELEASE-PASS` line for the log, then each finding on a line of its own.
    func printReport() {
        let longestMilliseconds = Int(longestStep.duration / .milliseconds(1))
        print("GRAPHITE-RELEASE-PASS part=\(part?.rawValue ?? "none") files=\(openedFileCount) screenshots=\(screenshotCount) findings=\(findings.count)"
              + " known_open=\(findings.filter(\.isKnownOpenDefect).count) unexpected=\(unexpectedFindings.count) longest_step_ms=\(longestMilliseconds) at=\"\(longestStep.place)\"")
        for finding in findings { print((finding.isKnownOpenDefect ? "GRAPHITE-RELEASE-KNOWN " : "GRAPHITE-RELEASE-FINDING ") + "\(finding)") }
    }

    // MARK: Files

    private func filesToOpen() throws -> [VaultPath] {
        let enumerator = FileManager.default.enumerator(at: vaultRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var paths: [VaultPath] = []
        while let location = enumerator?.nextObject() as? URL {
            guard (try location.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relativePath = location.standardizedFileURL.path.dropFirst(vaultRoot.standardizedFileURL.path.count + 1)
            paths.append(try VaultPath(String(relativePath)))
        }
        return paths.sorted { first, second in first.rawValue.localizedStandardCompare(second.rawValue) == .orderedAscending }
    }

    private func importNotebooks() async throws {
        let notebooksFolder = try VaultPath("Notebooks")
        let sources = try filesToOpen().filter { path in ["goodnotes", "note"].contains(path.fileExtension) }.map { path in try path.url(in: vaultRoot) }
        await workspace.importFiles(from: sources, into: notebooksFolder)
        try await waitUntil("the notebook import has ended", timeoutSeconds: 120) {
            if case .finished = self.workspace.notebookImport?.state { true } else { false }
        }
        if case .finished(let summary)? = workspace.notebookImport?.state, summary.outcomes.contains(where: { outcome in outcome.importedNotebook == nil }) {
            record(ReleaseVaultFinding(path: "Notebooks", shown: .wholeVault, problem: .error("a notebook was not imported: \(summary.outcomes)")))
        }
        workspace.endNotebookImport()
    }

    /// Community plugins stay off in a vault until the person turns them on; the pass turns them on for the part with the
    /// vault's test plugin (`Plugins/Test community plugin.md`), so its code block is drawn by the plugin.
    private func turnOnCommunityPlugins() async throws {
        let host = workspace.communityPlugins
        testCase.addTeardownBlock { @MainActor in await host.vaultWillClose() }
        await host.setTurnedOnForVault(true)
        try? await waitUntil("the vault's test plugin is loaded", timeoutSeconds: 60) { host.loadStates[Self.testPluginIdentifier] == .loaded }
        if host.loadStates[Self.testPluginIdentifier] != .loaded {
            let state = host.loadStates[Self.testPluginIdentifier].map { state in String(describing: state) } ?? "not listed"
            record(ReleaseVaultFinding(path: ".obsidian/plugins/\(Self.testPluginIdentifier)", shown: .wholeVault, problem: .notShown("the plugin is \(state)")))
        }
    }

    private func passFile(_ path: VaultPath) async throws {
        try await open(path)
        let isShown = switch DocumentKind(path: path) {
        case .pdf: (workspace.pdfSession?.pageCount ?? 0) > 0
        case .canvas: workspace.canvasSession != nil
        case .image, .base, .markdown, .media, .other: workspace.activeDocument.loadedPath == path
        }
        if !isShown { record(ReleaseVaultFinding(path: path.rawValue, shown: .ownView, problem: .notShown("its view did not open"))) }
        attachScreenshot(named: "\(path.rawValue) — \(ReleaseVaultFinding.Shown.ownView.rawValue)")
    }

    private func passNote(_ path: VaultPath) async throws {
        try await open(path)
        guard let session = workspace.markdownSession else {
            return record(ReleaseVaultFinding(path: path.rawValue, shown: .livePreview, problem: .notShown("no note was opened")))
        }
        let text = session.text as NSString
        let blocks = LivePreviewBlockScanner.blocks(in: text, pluginCodeBlockLanguages: workspace.communityPlugins.codeBlockLanguages)
        let views: [(shown: ReleaseVaultFinding.Shown, mode: NoteViewMode)] = [(.livePreview, .livePreview), (.reading, .reading), (.source, .source)]
        for view in views {
            if session.viewMode != view.mode {
                scrollToTop()
                try await measure(path.rawValue, "switching to \(view.shown.rawValue)") { session.viewMode = view.mode }
            }
            try await pageThrough(path, in: view.shown, blocks: blocks, text: text)
        }
        scrollToTop()
        try await checkReadingBlocks(of: path, text: text as String)
    }

    private func open(_ path: VaultPath) async throws {
        let opening = OpeningRequest()
        try await measure(path.rawValue, "opening it") {
            Task { [workspace] in
                _ = await workspace.open(path, placement: .currentTab)
                opening.hasEnded = true
            }
        } until: { opening.hasEnded }
        if let loadFailure = workspace.activeDocument.loadFailure {
            record(ReleaseVaultFinding(path: path.rawValue, shown: .ownView, problem: .error(String(describing: loadFailure))))
        }
    }

    // MARK: Pages

    private func pageThrough(_ path: VaultPath, in shown: ReleaseVaultFinding.Shown, blocks: [LivePreviewBlock], text: NSString) async throws {
        for page in 1...Self.maximumPagesPerView {
            try await checkPage(of: path, in: shown, blocks: blocks, text: text)
            attachScreenshot(named: "\(path.rawValue) — \(shown.rawValue) — page \(page)")
            guard let scroller = ReleaseVaultScrolling.pageScroller(in: rootView), let nextOffset = ReleaseVaultScrolling.nextPageOffset(of: scroller) else { return }
            try await measure(path.rawValue, "\(shown.rawValue), page \(page + 1)") { ReleaseVaultScrolling.scroll(scroller, to: nextOffset) }
        }
    }

    private func checkPage(of path: VaultPath, in shown: ReleaseVaultFinding.Shown, blocks: [LivePreviewBlock], text: NSString) async throws {
        guard shown != .reading else { return }
        guard let textView = ReleaseVaultViews.noteTextView(in: rootView) else {
            return record(ReleaseVaultFinding(path: path.rawValue, shown: shown, problem: .notShown("no text view on screen")))
        }
        if shown == .source {
            let renderedViews = ReleaseVaultViews.renderedBlockViews(in: textView)
            if !renderedViews.isEmpty { record(ReleaseVaultFinding(path: path.rawValue, shown: shown, problem: .renderedViewInSourceMode(count: renderedViews.count))) }
            return
        }
        // Views are placed after layout, and again a quarter of a second later when one was missing.
        try? await waitUntil("every block on screen has its view", timeoutSeconds: 3) { LivePreviewBlockCheck.blocksLeftAsSource(in: textView, blocks: blocks).isEmpty }
        for block in LivePreviewBlockCheck.blocksLeftAsSource(in: textView, blocks: blocks) {
            let problem = ReleaseVaultFinding.Problem.blockLeftAsSource(kind: LivePreviewBlockCheck.kindName(of: block), line: LivePreviewBlockCheck.lineNumber(of: block, in: text))
            record(ReleaseVaultFinding(path: path.rawValue, shown: shown, problem: problem))
        }
        try await waitForWebFrames(of: path, in: blocks)
        let pictures = LivePreviewBlockCheck.shownPictures(in: textView, blocks: blocks)
        let root = workspace.folderAccess?.root ?? vaultRoot
        try? await waitUntil("every picture on screen is decoded", timeoutSeconds: 5) {
            pictures.allSatisfy { picture in LivePreviewEmbedImageLocations.foundImage(for: picture, in: root) != nil }
        }
        for picture in pictures where LivePreviewEmbedImageLocations.foundImage(for: picture, in: root) == nil {
            record(ReleaseVaultFinding(path: path.rawValue, shown: shown, problem: .pictureNotLoaded(target: picture.target)))
        }
    }

    /// A note's first web frame loads its page from the pass's server; WebKit's first page in a simulator can take half a
    /// minute to start, as `WebFrameHostedTests` found, so the page is waited for before the screenshot.
    private func waitForWebFrames(of path: VaultPath, in blocks: [LivePreviewBlock]) async throws {
        guard blocks.contains(where: { block in if case .webFrame = block.kind { true } else { false } }) else { return }
        try? await waitUntil("the frame's page is asked for", timeoutSeconds: 40) {
            self.webServer.requestedPaths.contains(where: ReleaseVaultPassWebPages.isFramePage)
        }
        try await measure(path.rawValue, "loading its frames") {}
    }

    private func checkReadingBlocks(of path: VaultPath, text: String) async throws {
        guard let vault = ReadingVault(workspace.folderAccess?.root, workspace.index, store: workspace.store) else { return }
        let build = try await vault.build(text, note: path, configuration: ReadingConfiguration())
        for problem in await ReadingBlockCheck.problems(in: build.blocks) {
            record(ReleaseVaultFinding(path: path.rawValue, shown: .reading, problem: problem))
        }
    }

    private func scrollToTop() {
        guard let scroller = ReleaseVaultScrolling.pageScroller(in: rootView) else { return }
        ReleaseVaultScrolling.scroll(scroller, to: ReleaseVaultScrolling.topOffset(of: scroller))
    }

    // MARK: Measuring and recording

    /// Makes `change` and waits until the window shows it and the main thread is quiet, recording a freeze and an error.
    private func measure(_ path: String, _ step: String, _ change: () -> Void, until isShown: () -> Bool = { true }) async throws {
        let measurement = try await quietWatch.measure(change, until: isShown)
        if measurement.longestStep > longestStep.duration { longestStep = (measurement.longestStep, "\(path), \(step)") }
        if measurement.longestStep > Self.freezeBudget {
            record(ReleaseVaultFinding(path: path, shown: .wholeVault, problem: .freeze(milliseconds: Int(measurement.longestStep / .milliseconds(1)))))
        }
        if let message = workspace.errorMessage {
            record(ReleaseVaultFinding(path: path, shown: .wholeVault, problem: .error(message)))
            workspace.errorMessage = nil
        }
    }

    private func record(_ finding: ReleaseVaultFinding) {
        guard !findings.contains(finding) else { return }
        findings.append(finding)
    }

    private var rootView: ReleaseVaultViews.PlatformView {
        #if canImport(UIKit)
        window
        #else
        window.contentView ?? NSView()
        #endif
    }

    private func attachScreenshot(named name: String) {
        guard let pngData = ReleaseVaultWindow.screenshot(of: window) else { return }
        let attachment = XCTAttachment(data: pngData, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        screenshotCount += 1
        guard let folder = ProcessInfo.processInfo.environment[Self.screenshotFolderVariable] else { return }
        let fileName = String(format: "%04d ", screenshotCount) + name.replacingOccurrences(of: "/", with: " › ") + ".png"
        // A screenshot that cannot be written is only not looked at; the attachment has it.
        try? pngData.write(to: URL(fileURLWithPath: folder, isDirectory: true).appendingPathComponent(fileName))
    }
}

/// Whether an opening started in a task has ended, read by the measurement that waits for it.
@MainActor
private final class OpeningRequest {
    var hasEnded = false
}

/// The pass in five parts, one test each, so each stays well within the hosted tests' four minutes a test: the vault's
/// top-level folders and files, by what they hold. A file in none of them is a finding of the first part.
enum ReleaseVaultPassPart: String, CaseIterable {
    case filesAndBases = "files-and-bases"
    case textNotes = "text-notes"
    case longAndRepeatedNotes = "long-and-repeated-notes"
    case pdfsNotebooksAndDrawings = "pdfs-notebooks-and-drawings"
    case embeds = "embeds"

    var topLevelNames: Set<String> {
        switch self {
        case .filesAndBases:
            ["Attachments", "Books", "Books.base", "Canvas", "Embedded base.md", "Gallery", "Gallery.base", "Places", "Places.base", "Places.md",
             "Tasks", "Tasks.base"]
        case .textNotes:
            ["Callouts.md", "Edge cases", "Links", "Markdown", "Math.md", "Pictures.md", "Plugins", "README.md", "Start here.md", "Tables.md",
             "Templates", "Web"]
        case .longAndRepeatedNotes: ["Daily", "Diagrams", "Lectures"]
        case .pdfsNotebooksAndDrawings: ["Drawings", "Imports", "Notebooks", "PDFs"]
        case .embeds: ["Embeds"]
        }
    }

    /// Whether the vault path (a file's, or a folder's with its slash) is in this part.
    func contains(_ path: String) -> Bool {
        topLevelNames.contains(path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? path)
    }
}
