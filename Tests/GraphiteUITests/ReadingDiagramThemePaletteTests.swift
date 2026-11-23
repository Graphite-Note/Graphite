/**
 * File: ReadingDiagramThemePaletteTests.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: A diagram's own theme palette (pie1, git0, cScale0, xyChart.plotColorPalette …) painted in the reading view and
 *              written in its SVG.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

#if os(macOS)
import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

/// The series colors a diagram's own theme variables set (MermaidDiagrams 0.6.0, `DiagramScene.seriesColors`, as Pele's
/// palette.ts reads them) are painted over the note's colors, as Pele sets them over the page's, and written in Copy and
/// Save as SVG; a diagram that sets none keeps the note's series.
@MainActor
final class ReadingDiagramThemePaletteTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let scale: CGFloat = 2
    private let red = DiagramPixel(red: 1, green: 0, blue: 0)
    private let blue = DiagramPixel(red: 0, green: 0, blue: 1)

    private func pie(firstSlice color: String?) -> String {
        let configuration = color.map { color in "---\nconfig:\n  themeVariables:\n    pie1: \"\(color)\"\n---\n" } ?? ""
        return configuration + "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85\n  \"Rats\" : 15"
    }

    private func light() -> ReadingDiagramColors {
        ReadingDiagramColors(background: Color(.sRGB, red: 1, green: 1, blue: 1), foreground: Color(.sRGB, red: 0.1, green: 0.1, blue: 0.1))
    }

    private func dark() -> ReadingDiagramColors {
        ReadingDiagramColors(background: Color(.sRGB, red: 0.08, green: 0.08, blue: 0.1), foreground: Color(.sRGB, red: 0.95, green: 0.95, blue: 0.95))
    }

    private func painted(_ source: String, colors: ReadingDiagramColors, colorScheme: ColorScheme) throws -> DiagramPicture {
        let scene = try ReadingDiagram(source: source, typography: typography).drawn(as: .pieChart).scene
        let painting = ReadingDiagramScenePainting(scene: scene, colors: colors).environment(\.colorScheme, colorScheme)
        return try XCTUnwrap(DiagramPicture(painting: painting, background: colors.background, size: scene.size, scale: scale))
    }

    func testAPieChartsOwnFirstSliceColorIsPaintedOverTheNotesSeries() throws {
        let themed = try painted(pie(firstSlice: "#ff0000"), colors: light(), colorScheme: .light)
        let plain = try painted(pie(firstSlice: nil), colors: light(), colorScheme: .light)
        XCTAssertGreaterThan(themed.share { pixel in pixel.isClose(to: red, tolerance: 8 / 255) }, 0.05, "The largest slice in pie1's red")
        XCTAssertEqual(plain.share { pixel in pixel.isClose(to: red, tolerance: 8 / 255) }, 0, "Without pie1 no slice is red")
    }

    /// The painting matches the package's own renderer, which paints the scene's series over the same palette.
    func testThePaletteIsPaintedAsThePackageDrawsIt() throws {
        let source = pie(firstSlice: "#ff0000")
        let scene = try ReadingDiagram(source: source, typography: typography).drawn(as: .pieChart).scene
        XCTAssertFalse(scene.seriesColors.isEmpty)
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        let drawn = try XCTUnwrap(DiagramPicture(scene: scene, palette: light().palette(in: environment), scale: scale))
        XCTAssertLessThan(try painted(source, colors: light(), colorScheme: .light).share(differingFrom: drawn), 0.03)
    }

    /// `light-dark()` is decided by the note's appearance, as a browser decides it over a light or a dark page.
    func testLightDarkIsResolvedInTheNotesAppearance() throws {
        let source = pie(firstSlice: "light-dark(#ff0000, #0000ff)")
        let lightPicture = try painted(source, colors: light(), colorScheme: .light)
        let darkPicture = try painted(source, colors: dark(), colorScheme: .dark)
        XCTAssertGreaterThan(lightPicture.share { pixel in pixel.isClose(to: red, tolerance: 8 / 255) }, 0.05)
        XCTAssertGreaterThan(darkPicture.share { pixel in pixel.isClose(to: blue, tolerance: 8 / 255) }, 0.05)
        XCTAssertEqual(darkPicture.share { pixel in pixel.isClose(to: red, tolerance: 8 / 255) }, 0)
    }

    /// Copy and Save as SVG write the palette's colors out, with Pele's label ink on them, and no variable left.
    func testTheSVGIsWrittenInTheDiagramsOwnPalette() throws {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        let palette = light().palette(in: environment)
        let gitGraph = "%%{init: { 'themeVariables': { 'git0': '#ff0000', 'git1': '#00ff00' } } }%%\ngitGraph\n  commit\n  branch develop\n  commit\n  checkout main\n  commit"
        for (source, kind) in [(pie(firstSlice: "#ff0000"), MermaidDiagramKind.pieChart), (gitGraph, .gitGraph)] {
            let prepared = try ReadingDiagram(source: source, typography: typography).drawn(as: kind)
            let document = ReadingDiagramSVGExport(prepared: prepared, palette: palette, noteName: "Palette").document
            XCTAssertTrue(document.contains("#ff0000"), "\(kind): the first series in its own red")
            XCTAssertFalse(document.contains("var(--"), "\(kind): every color written out")
            let plain = try ReadingDiagram(source: source.replacingOccurrences(of: "#ff0000", with: "not a color"), typography: typography).drawn(as: kind)
            XCTAssertFalse(ReadingDiagramSVGExport(prepared: plain, palette: palette, noteName: nil).document.contains("#ff0000"),
                           "\(kind): a value Pele refuses keeps the note's series")
        }
    }
}
#endif
