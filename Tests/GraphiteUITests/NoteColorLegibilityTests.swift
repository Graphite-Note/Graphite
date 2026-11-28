/**
 * File: NoteColorLegibilityTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A note's text colours are darkened on a light page and lightened on a dark one just enough to read, and its
 *              backgrounds are drawn as dark tints of their hue on a dark page.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 28/11/2026
 */

#if os(macOS)
import XCTest
import AppKit
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class NoteColorLegibilityTests: XCTestCase {
    private func components(of color: NSColor, in appearanceName: NSAppearance.Name) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
        var resolved = NSColor.black
        try XCTUnwrap(NSAppearance(named: appearanceName)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? .black
        }
        return (Double(resolved.redComponent), Double(resolved.greenComponent), Double(resolved.blueComponent), Double(resolved.alphaComponent))
    }

    func testAPaleTextColourIsDarkenedOnLightAndADarkOneLightenedOnDark() throws {
        let yellow = try XCTUnwrap(NSColor.legibleNoteText(hex: "#dfab01"))
        let onLight = try components(of: yellow, in: .aqua)
        XCTAssertGreaterThanOrEqual(AccentLegibility.contrastOnLightBackground(red: onLight.red, green: onLight.green, blue: onLight.blue), 4.49)
        let brown = try XCTUnwrap(NSColor.legibleNoteText(hex: "#64473a"))
        let onDark = try components(of: brown, in: .darkAqua)
        XCTAssertGreaterThanOrEqual(AccentLegibility.contrastOnDarkBackground(red: onDark.red, green: onDark.green, blue: onDark.blue), 4.49)
        let blue = try components(of: try XCTUnwrap(NSColor.legibleNoteText(hex: "#0b6e99")), in: .aqua)
        XCTAssertEqual(blue.green, 110.0 / 255, accuracy: 0.02, "A colour that already reads is drawn as written.")
    }

    func testABackgroundBecomesADarkTintOfItsHueOnADarkPage() throws {
        let background = try XCTUnwrap(NSColor.noteBackground(hex: "#fbf3db"))
        let onLight = try components(of: background, in: .aqua)
        XCTAssertEqual(onLight.blue, 219.0 / 255, accuracy: 0.01, "Drawn as written on a light page.")
        let onDark = try components(of: background, in: .darkAqua)
        let lightHue = NSColor.hueSaturationLightness(red: onLight.red, green: onLight.green, blue: onLight.blue)
        let darkHue = NSColor.hueSaturationLightness(red: onDark.red, green: onDark.green, blue: onDark.blue)
        XCTAssertEqual(darkHue.hue, lightHue.hue, accuracy: 0.01)
        XCTAssertEqual(darkHue.lightness, NSColor.darkPageBackgroundLightness, accuracy: 0.01)
        let translucent = try components(of: try XCTUnwrap(NSColor.noteBackground(hex: "#f4f0f7cc")), in: .darkAqua)
        XCTAssertEqual(translucent.alpha, 0.8, accuracy: 0.01, "A background's own transparency is kept.")
    }

    func testHueSaturationLightnessRoundTrips() {
        for (red, green, blue) in [(1.0, 0.0, 0.0), (0.2, 0.6, 0.4), (0.9, 0.95, 0.97), (0.5, 0.5, 0.5), (0.3, 0.1, 0.8)] {
            let hsl = NSColor.hueSaturationLightness(red: red, green: green, blue: blue)
            let back = NSColor.rgb(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
            XCTAssertEqual(back.red, red, accuracy: 0.001)
            XCTAssertEqual(back.green, green, accuracy: 0.001)
            XCTAssertEqual(back.blue, blue, accuracy: 0.001)
        }
    }
}
#endif
