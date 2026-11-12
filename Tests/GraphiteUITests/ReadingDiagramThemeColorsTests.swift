/**
 * File: ReadingDiagramThemeColorsTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The colors diagrams are painted in from a vault theme: its page, text, accent and muted text, and over
 *              them Pele's variables (`--pele-bg` …) in the appearance shown.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import XCTest
import SwiftUI
import GraphiteCore
import MermaidDiagrams
@testable import GraphiteUI

@MainActor
final class ReadingDiagramThemeColorsTests: XCTestCase {
    private func resolved(_ color: Color) -> [Float] {
        let components = color.resolve(in: EnvironmentValues())
        return [components.red, components.green, components.blue, components.opacity].map { component in (component * 1000).rounded() / 1000 }
    }

    private func theme(light: [String: ThemeColor], dark: [String: ThemeColor]) -> NoteThemeStyle {
        var lightTokens = ThemeModeTokens(), darkTokens = ThemeModeTokens()
        lightTokens.diagramColors = light
        darkTokens.diagramColors = dark
        return NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "pele-test", themeName: "Pele", light: lightTokens, dark: darkTokens))
    }

    func testPeleVariablesReplaceTheRolesTheySetInTheAppearanceShown() {
        let red = ThemeColor(red: 1, green: 0, blue: 0), navy = ThemeColor(red: 0, green: 0, blue: 0.5), green = ThemeColor(red: 0, green: 1, blue: 0)
        let style = theme(light: ["bg": navy, "series-1": red, "line": green, "surface-alt": red, "critical": green],
                          dark: ["accent": green])
        let light = ReadingDiagramColors(theme: style, colorScheme: .light)
        XCTAssertEqual(resolved(light.background), [0, 0, 0.5, 1])
        XCTAssertEqual(resolved(light.seriesColor(0)), [1, 0, 0, 1])
        XCTAssertEqual(resolved(light.seriesColor(8)), [1, 0, 0, 1], "The first series again after the eighth.")
        XCTAssertEqual(resolved(light.seriesColor(1)), resolved(Color(cgColor: DiagramPalette.peleSeries[1])), "Unset series keep Pele's.")
        XCTAssertEqual(resolved(light.line), [0, 1, 0, 1])
        XCTAssertEqual(resolved(light.alternateSurface), [1, 0, 0, 1])
        XCTAssertEqual(resolved(light.critical), [0, 1, 0, 1])
        let dark = ReadingDiagramColors(theme: style, colorScheme: .dark)
        XCTAssertEqual(resolved(dark.accent), [0, 1, 0, 1])
        XCTAssertEqual(resolved(dark.seriesColor(0)), resolved(Color(cgColor: DiagramPalette.peleSeries[0])), "The light appearance's variables stay there.")
        XCTAssertEqual(resolved(dark.line), resolved(dark.foreground), "Without --pele-line, lines are the text's color.")
    }

    func testWithoutAThemeTheColorsAreTheSystemsAndPeles() {
        let colors = ReadingDiagramColors(theme: nil, colorScheme: .light)
        XCTAssertEqual(colors.series.count, 8)
        XCTAssertEqual(resolved(colors.seriesColor(3)), resolved(Color(cgColor: DiagramPalette.peleSeries[3])))
        XCTAssertEqual(resolved(colors.critical), resolved(Color(cgColor: DiagramPalette.peleCritical)))
        XCTAssertEqual(resolved(colors.line), resolved(colors.foreground))
    }
}
