/**
 * File: ReadingDiagramSVGExportTests.swift
 * ----------------------------------------
 * Layer: Tests
 * Description: A drawn diagram's Copy as SVG and Save as SVG: the SVG in the theme's colors, its file name, the commands offered.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import XCTest
import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
import MermaidDiagrams
@testable import GraphiteUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class ReadingDiagramSVGExportTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func prepared(_ source: String) throws -> PreparedMermaidDiagram {
        try ReadingDiagram(source: source, typography: typography).drawn(as: .flowchart)
    }

    /// A theme whose `--pele-bg`, `--pele-fg` and `--pele-line` are set for the dark appearance.
    private func darkTheme() -> NoteThemeStyle {
        var dark = ThemeModeTokens()
        dark.diagramColors = ["bg": ThemeColor(red: 0x11 / 255, green: 0x22 / 255, blue: 0x33 / 255),
                              "fg": ThemeColor(red: 0xEE / 255, green: 0xDD / 255, blue: 0xCC / 255),
                              "line": ThemeColor(red: 1, green: 0x80 / 255, blue: 0)]
        return NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "svg-test", themeName: "SVG", light: ThemeModeTokens(), dark: dark))
    }

    private func export(_ source: String, theme: NoteThemeStyle?, colorScheme: ColorScheme, noteName: String? = "Lecture 4") throws -> ReadingDiagramSVGExport {
        var environment = EnvironmentValues()
        environment.colorScheme = colorScheme
        let palette = ReadingDiagramColors(theme: theme, colorScheme: colorScheme).palette(in: environment)
        return ReadingDiagramSVGExport(prepared: try prepared(source), palette: palette, noteName: noteName)
    }

    func testTheSVGIsWrittenInTheThemesColorsOfTheAppearanceShown() throws {
        let dark = try export("flowchart LR\n  A[Start] --> B[End]", theme: darkTheme(), colorScheme: .dark)
        XCTAssertTrue(dark.document.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
        XCTAssertTrue(dark.document.contains("fill=\"#112233\""), "The page in the theme's background")
        XCTAssertTrue(dark.document.contains("#eeddcc"), "The text in the theme's text color")
        XCTAssertTrue(dark.document.contains("#ff8000"), "The edges in the theme's line color")
        XCTAssertFalse(dark.document.contains("var(--"), "Every color written out, not left to a page's style")
        let light = try export("flowchart LR\n  A[Start] --> B[End]", theme: darkTheme(), colorScheme: .light)
        XCTAssertFalse(light.document.contains("#112233"), "The dark appearance's colors stay there")
        XCTAssertTrue(light.document.contains(">Start</text>"))
    }

    func testTheSVGReadsBackAsXMLWithItsTitleAndItsTextEscaped() throws {
        let export = try export("flowchart TD\n  accTitle: Plan <draft> & more\n  accDescr: How it goes\n  A[\"x < y & z\"] --> B", theme: nil, colorScheme: .light)
        XCTAssertTrue(export.document.contains("<title id=\"graphite-diagram-title\">Plan &lt;draft&gt; &amp; more</title>"))
        XCTAssertTrue(export.document.contains("<desc id=\"graphite-diagram-desc\">How it goes</desc>"))
        let parser = XMLParser(data: export.data)
        XCTAssertTrue(parser.parse(), "\(String(describing: parser.parserError))")
    }

    func testTheFileIsNamedAfterTheDiagramsTitleElseTheNote() throws {
        XCTAssertEqual(try export("flowchart TD\n  accTitle: Release plan\n  A --> B", theme: nil, colorScheme: .light).fileName, "Release plan.svg")
        XCTAssertEqual(try export("---\ntitle: Front title\n---\nflowchart TD\n  A --> B", theme: nil, colorScheme: .light).fileName, "Front title.svg")
        XCTAssertEqual(try export("flowchart TD\n  A --> B", theme: nil, colorScheme: .light).fileName, "Lecture 4.svg")
        XCTAssertEqual(try export("flowchart TD\n  A --> B", theme: nil, colorScheme: .light, noteName: nil).fileName, "Diagram.svg")
        XCTAssertEqual(ReadingDiagramSVGExport.fileName(title: "A/B: C?", noteName: nil), "A-B- C-.svg")
        XCTAssertEqual(ReadingDiagramSVGExport.fileName(title: "  ", noteName: ".hidden"), "hidden.svg")
        XCTAssertEqual(ReadingDiagramSVGExport.fileName(title: "...", noteName: "Note"), "Diagram.svg")
        XCTAssertEqual(ReadingDiagramSVGExport.fileName(title: String(repeating: "x", count: 300), noteName: nil),
                       String(repeating: "x", count: ReadingDiagramSVGExport.longestNameLength) + ".svg")
    }

    func testOnlyADrawnDiagramOffersItsSVG() {
        XCTAssertEqual(ReadingDiagramSVGCommand.offered(for: ReadingDiagram(source: "pie\n  \"A\" : 1", typography: typography)), [.copy, .save])
        XCTAssertEqual(ReadingDiagramSVGCommand.offered(for: ReadingDiagram(source: "flowchart TD\nA[never closed", typography: typography)), [])
        XCTAssertEqual(ReadingDiagramSVGCommand.offered(for: ReadingDiagram(source: "requirementDiagram", typography: typography)), [])
        XCTAssertEqual(ReadingDiagramSVGCommand.allCases.map(\.title), ["Copy as SVG", "Save as SVG…"])
    }

    #if os(macOS)
    /// Copied as an SVG image and as its text, so an app that pastes pictures and one that pastes text both take it.
    func testCopyAsSVGPutsTheImageAndItsTextOnThePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ReadingDiagramSVGExportTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let export = try export("flowchart LR\n  A --> B", theme: nil, colorScheme: .light)
        ReadingDiagramSVGSharing.copy(export, to: pasteboard)
        XCTAssertEqual(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.svg.identifier)), export.data)
        XCTAssertEqual(pasteboard.string(forType: .string), export.document)
        XCTAssertEqual(UTType.svg.identifier, "public.svg-image")
    }
    #endif
}
