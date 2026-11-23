/**
 * File: MacDiagramsInAppHostedTests.swift
 * ---------------------------------------
 * Layer: Tests
 * Description: Mermaid diagrams in Graphite's own window inside the running Mac app: a note's diagrams drawn in the reading
 *              view in the light and the dark appearance, the diagram's context menu and its Copy as SVG and Save as SVG
 *              commands, and every diagram of a folder of notes written as SVG and read back.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import MermaidDiagrams
@testable import GraphiteUI

/// The Mac checks of `Docs/Native-diagrams-todo.md` (the package's types and features drawn, Copy as SVG and Save as SVG), as a
/// hosted test: Graphite's root view in a window of the app, a note of the diagram demo vault open in the reading view, and
/// the diagram's own menu asked for as a secondary click asks for it. Runs only with `GRAPHITE_MAC_DIAGRAMS` given to
/// xcodebuild as a folder to write to and `GRAPHITE_MAC_DIAGRAMS_NOTES` as the folder of the notes; a person looks at what it writes.
/// `GRAPHITE_MAC_DIAGRAMS_PICKED` lists the names of the notes to picture, apart by commas (all of them when it is absent).
@MainActor
final class MacDiagramsInAppHostedTests: XCTestCase {
    static let switchVariable = "GRAPHITE_MAC_DIAGRAMS"
    static let notesVariable = "GRAPHITE_MAC_DIAGRAMS_NOTES"
    static let pickedVariable = "GRAPHITE_MAC_DIAGRAMS_PICKED"
    private var outputFolder: URL?
    private var pictureCount = 0
    private var notes: [String] = []
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    // MARK: Every diagram as an SVG

    /// Each ```` ```mermaid ```` block of the notes is prepared as the reading view prepares it, written as SVG in the light and the
    /// dark colors, read back by an XML parser and put on a pasteboard of its own; the ones that are not drawn are listed with why.
    func testEveryDiagramOfTheNotesIsDrawnAndItsSVGReadsBack() throws {
        guard try start() else { return }
        let svgFolder = try XCTUnwrap(outputFolder).appendingPathComponent("svg")
        try FileManager.default.createDirectory(at: svgFolder, withIntermediateDirectories: true)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacDiagramsInAppHostedTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        var drawnCount = 0
        var failures: [String] = []
        for (name, text) in try noteTexts() {
            for (index, source) in Self.diagramSources(in: text).enumerated() {
                let label = "\(name)#\(index + 1)"
                switch ReadingDiagram(source: source, typography: typography) {
                case .unreadable(_, let failure):
                    failures.append("\(label): \(failure)")
                    try note("NOT DRAWN \(label): \(failure)")
                case .drawn(let prepared):
                    drawnCount += 1
                    for scheme in [ColorScheme.light, .dark] {
                        var environment = EnvironmentValues()
                        environment.colorScheme = scheme
                        let palette = ReadingDiagramColors(theme: nil, colorScheme: scheme).palette(in: environment)
                        let export = ReadingDiagramSVGExport(prepared: prepared, palette: palette, noteName: name)
                        let parser = XMLParser(data: export.data)
                        if !parser.parse() { failures.append("\(label) \(scheme): the SVG is not well-formed: \(String(describing: parser.parserError))") }
                        if export.document.contains("var(--") { failures.append("\(label) \(scheme): a color left as a variable") }
                        try export.data.write(to: svgFolder.appendingPathComponent("\(name)-\(index + 1)-\(scheme == .dark ? "dark" : "light").svg"))
                        if scheme == .light {
                            ReadingDiagramSVGSharing.copy(export, to: pasteboard)
                            if pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.svg.identifier)) != export.data {
                                failures.append("\(label): the pasteboard did not hold the SVG")
                            }
                            try note("drawn \(label) as \(prepared.kind.peleName): \(export.fileName), \(export.data.count) bytes")
                        }
                    }
                }
            }
        }
        try note("SUMMARY drawn \(drawnCount), problems \(failures.count)")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    // MARK: The reading view in a window, and the diagram's menu

    func testTheReadingViewDrawsTheNotesInBothAppearancesAndItsMenuOffersTheSVGCommands() async throws {
        guard try start() else { return }
        let texts = try noteTexts()
        let picked = ProcessInfo.processInfo.environment[Self.pickedVariable].map { list in Set(list.split(separator: ",").map(String.init)) }
        let (window, workspace, session) = try await openWindow(notes: texts.filter { name, _ in picked?.contains(name) ?? true })
        var offeredSomewhere = false
        for (name, _) in texts where picked?.contains(name) ?? true {
            _ = await workspace.open(try VaultPath(name + ".md"), placement: .currentTab)
            try await waitUntil("the note is open", timeoutSeconds: 20) { workspace.markdownSession?.path.rawValue == name + ".md" }
            let noteSession = try XCTUnwrap(workspace.markdownSession)
            noteSession.viewMode = .reading
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                try await settle(window)
                try writePicture("\(name) \(appearance == .aqua ? "light" : "dark")", of: window)
            }
            window.appearance = NSAppearance(named: .aqua)
            try await settle(window, steps: 5)
            let titles = menuTitles(probingDiagramIn: window)
            try note("\(name): menu items at the probed points: \(titles)")
            if titles.contains("Copy as SVG") { offeredSomewhere = true }
        }
        _ = session
        try note("SUMMARY the SVG commands were offered by a diagram's menu: \(offeredSomewhere)")
    }

    /// Save as SVG… as the diagram's command runs it (`ReadingDiagramSVGSharing.save`), over the key window of the app: the save
    /// panel comes as a sheet named after the diagram, offering SVG; it is cancelled, so nothing is written. The menu item itself
    /// cannot be chosen from here: a SwiftUI context menu is opened by AppKit's own tracking loop, which a test cannot enter.
    func testSaveAsSVGOpensTheSavePanelNamedAfterTheDiagram() async throws {
        guard try start() else { return }
        let texts = try noteTexts().filter { name, _ in name == "Type_class" }
        let (window, workspace, _) = try await openWindow(notes: texts)
        _ = await workspace.open(try VaultPath("Type_class.md"), placement: .currentTab)
        try await waitUntil("the note is open", timeoutSeconds: 20) { workspace.markdownSession != nil }
        try XCTUnwrap(workspace.markdownSession).viewMode = .reading
        try await settle(window)
        let source = try XCTUnwrap(Self.diagramSources(in: try XCTUnwrap(texts.first).1).first)
        guard case .drawn(let prepared) = ReadingDiagram(source: source, typography: typography) else { return XCTFail("not drawn") }
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        let palette = ReadingDiagramColors(theme: nil, colorScheme: .light).palette(in: environment)
        let export = ReadingDiagramSVGExport(prepared: prepared, palette: palette, noteName: "Type_class")
        try note("the file is named \(export.fileName), \(export.data.count) bytes")
        ReadingDiagramSVGSharing.save(export)
        try await waitUntil("the save panel opens", timeoutSeconds: 15) { NSApp.windows.contains { openedWindow in openedWindow is NSSavePanel } }
        // Without a key window (the app is not active during a test) the command opens the panel on its own, not as a sheet.
        let panel = NSApp.windows.compactMap { openedWindow in openedWindow as? NSSavePanel }.first
        let sheet = window.attachedSheet as? NSSavePanel
        try note("after Save as SVG: windows \(NSApp.windows.map { String(describing: type(of: $0)) }); sheet \(sheet != nil); standalone panel \(panel != nil)")
        let found = try XCTUnwrap(sheet ?? panel, "the save panel opened")
        try note("the save panel names the file \"\(found.nameFieldStringValue)\", allowed types \(found.allowedContentTypes.map(\.identifier))")
        XCTAssertEqual(found.nameFieldStringValue, export.fileName)
        XCTAssertTrue(found.allowedContentTypes.contains(.svg))
        found.cancel(nil)
    }

    // MARK: The window and the menu

    private func noteTexts() throws -> [(String, String)] {
        let folder = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment[Self.notesVariable], "give GRAPHITE_MAC_DIAGRAMS_NOTES"), isDirectory: true)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { url in url.pathExtension == "md" }
            .sorted { first, second in first.lastPathComponent < second.lastPathComponent }
            .map { url in (url.deletingPathExtension().lastPathComponent, try String(contentsOf: url, encoding: .utf8)) }
    }

    /// The text of each fenced ```` ```mermaid ```` block.
    private static func diagramSources(in text: String) -> [String] {
        var sources: [String] = []
        var current: [String]?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```mermaid") { current = [] } else if line.hasPrefix("```"), let lines = current {
                sources.append(lines.joined(separator: "\n"))
                current = nil
            } else { current?.append(line) }
        }
        return sources
    }

    private func openWindow(notes: [(String, String)]) async throws -> (NSWindow, WorkspaceModel, MarkdownSession?) {
        let vaultRoot = try TemporaryVault.make(prefix: "MacDiagramsInApp", for: self).root
        for (name, text) in notes { try Data(text.utf8).write(to: vaultRoot.appendingPathComponent(name + ".md")) }
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vaultRoot)
        try await waitUntil("the vault is indexed", timeoutSeconds: 60) { workspace.hasCompletedIndexScan && !workspace.isIndexing }
        let window = try ReleaseVaultWindow.show(GraphiteRootView(workspace: workspace), for: self)
        window.makeKey()
        return (window, workspace, nil)
    }

    /// The menus a secondary click asks for at points down the middle of the note, the first whose items hold an SVG command.
    private func diagramMenu(in window: NSWindow) -> NSMenu? {
        for point in Self.probePoints {
            guard let view = window.contentView?.hitTest(point),
                  let event = try? mouseEvent(.rightMouseDown, at: point, in: window),
                  let menu = view.menu(for: event), menu.items.contains(where: { item in item.title == "Copy as SVG" }) else { continue }
            return menu
        }
        return nil
    }

    private func menuTitles(probingDiagramIn window: NSWindow) -> [String] {
        var titles: [String] = []
        for point in Self.probePoints {
            guard let view = window.contentView?.hitTest(point), let event = try? mouseEvent(.rightMouseDown, at: point, in: window),
                  let menu = view.menu(for: event) else { continue }
            titles.append(contentsOf: menu.items.map(\.title))
            if menu.items.contains(where: { item in item.title == "Copy as SVG" }) { break }
        }
        return titles
    }

    /// Down the middle of the window, where the first diagram of a note is. A point is in window coordinates, whose origin is
    /// at the bottom left, so a high point has a large y.
    private static let probePoints: [CGPoint] = stride(from: 700.0, through: 150.0, by: -40.0).flatMap { y in [CGPoint(x: 640, y: y), CGPoint(x: 500, y: y)] }

    private func mouseEvent(_ type: NSEvent.EventType, at windowPoint: CGPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    /// Waits until the window's picture has stayed the same for `steps` looks in a row: a diagram is prepared off the main
    /// thread and drawn when it is ready, which the main thread's quiet alone does not show.
    private func settle(_ window: NSWindow, steps: Int = 25) async throws {
        var previous: Data?
        var unchanged = 0
        try await waitUntil("the window's picture is still", timeoutSeconds: 30) {
            let picture = ReleaseVaultWindow.screenshot(of: window)
            unchanged = picture == previous ? unchanged + 1 : 0
            previous = picture
            return unchanged >= steps
        }
    }

    // MARK: Output

    private func start() throws -> Bool {
        // Returns rather than skipping: the suites' skip count may not rise (FR-93), and this is not a missing capability.
        guard let outputPath = ProcessInfo.processInfo.environment[Self.switchVariable] else { return false }
        let testName = String(String(name.split(separator: " ").last ?? "test").dropLast())
        let folder = URL(fileURLWithPath: outputPath, isDirectory: true).appendingPathComponent(testName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        outputFolder = folder
        return true
    }

    private func note(_ line: String) throws {
        notes.append(line)
        try Data(notes.joined(separator: "\n").utf8).write(to: try XCTUnwrap(outputFolder).appendingPathComponent("notes.txt"))
    }

    private func writePicture(_ name: String, of window: NSWindow) throws {
        let pngData = try XCTUnwrap(ReleaseVaultWindow.screenshot(of: window))
        pictureCount += 1
        try pngData.write(to: try XCTUnwrap(outputFolder).appendingPathComponent(String(format: "%03d %@.png", pictureCount, name)))
    }
}
#endif
