/**
 * File: NoteColorLegibility.swift
 * -------------------------------
 * Layer: UI
 * Description: The colours a note gives its text and its backgrounds, drawn so they read on a light page and on a dark
 *              one: text darkened or lightened just enough, a background made a dark tint of its hue on a dark page. The note is unchanged.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 28/11/2026
 */

import SwiftUI
import GraphiteCore
import Synchronization
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension PlatformColor {
    /// The lightness a note's background colour is drawn at on a dark page, where Notion's pale backgrounds would
    /// otherwise put light text on a light patch: Notion's own dark backgrounds are 19 to 25%.
    static let darkPageBackgroundLightness = 0.22
    /// The share of its saturation a background keeps on a dark page, so a dark tint is not a loud one.
    static let darkPageBackgroundSaturationShare = 0.6

    /// A note's text colour (`#rrggbb`), darkened on a light page and lightened on a dark one by the least amount that
    /// reads (`AccentLegibility`), resolved for the appearance the text is drawn in.
    static func legibleNoteText(hex: String) -> PlatformColor? {
        let key = "text" + hex
        if let cached = NoteColorCache.color(forKey: key) { return cached }
        guard let written = PlatformColor(graphiteHex: hex), let components = sRGBComponents(of: written) else { return nil }
        let onLight = AccentLegibility.darkenedForLightBackground(red: components.red, green: components.green, blue: components.blue)
        let onDark = AccentLegibility.lightenedForDarkBackground(red: components.red, green: components.green, blue: components.blue)
        let legible = dynamic(light: color(onLight, alpha: components.alpha), dark: color(onDark, alpha: components.alpha))
        NoteColorCache.store(legible, forKey: key)
        return legible
    }

    /// A note's background colour: as written on a light page, and on a dark one a dark tint of the same hue
    /// (`darkPageBackgroundLightness`), as Notion draws its yellow `#fbf3db` as about `#564328` there.
    static func noteBackground(hex: String) -> PlatformColor? {
        let key = "background" + hex
        if let cached = NoteColorCache.color(forKey: key) { return cached }
        guard let written = PlatformColor(graphiteHex: hex), let components = sRGBComponents(of: written) else { return nil }
        let hsl = hueSaturationLightness(red: components.red, green: components.green, blue: components.blue)
        let darkTint = rgb(hue: hsl.hue, saturation: hsl.saturation * darkPageBackgroundSaturationShare, lightness: darkPageBackgroundLightness)
        let background = dynamic(light: written, dark: color(darkTint, alpha: components.alpha))
        NoteColorCache.store(background, forKey: key)
        return background
    }

    private static func color(_ components: (red: Double, green: Double, blue: Double), alpha: Double) -> PlatformColor {
        #if canImport(UIKit)
        PlatformColor(red: components.red, green: components.green, blue: components.blue, alpha: alpha)
        #else
        PlatformColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: alpha)
        #endif
    }

    /// Hue (0 to 1), saturation and lightness of an sRGB colour.
    static func hueSaturationLightness(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let spread = maximum - minimum
        guard spread > 0 else { return (0, 0, lightness) }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        let hue: Double
        switch maximum {
        case red: hue = ((green - blue) / spread).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / spread + 2
        default: hue = (red - green) / spread + 4
        }
        return ((hue / 6 + 1).truncatingRemainder(dividingBy: 1), min(saturation, 1), lightness)
    }

    /// The sRGB colour of a hue (0 to 1), saturation and lightness.
    static func rgb(hue: Double, saturation: Double, lightness: Double) -> (red: Double, green: Double, blue: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue * 6
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (red, green, blue) = (chroma, second, 0)
        case 1: (red, green, blue) = (second, chroma, 0)
        case 2: (red, green, blue) = (0, chroma, second)
        case 3: (red, green, blue) = (0, second, chroma)
        case 4: (red, green, blue) = (second, 0, chroma)
        default: (red, green, blue) = (chroma, 0, second)
        }
        let lift = lightness - chroma / 2
        return (red + lift, green + lift, blue + lift)
    }

    private static func sRGBComponents(of color: PlatformColor) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(UIKit)
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #else
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        return (Double(red), Double(green), Double(blue), Double(alpha))
    }

    private static func dynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(UIKit)
        PlatformColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
        #else
        PlatformColor(name: nil) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
        #endif
    }
}

/// The colours made for a note's hexes, kept so each restyle gives the same colour object: an edited line then compares
/// equal to the whole note's styling, and no colour is worked out twice. A note uses a handful of colours; past
/// `maximumCount` the cache starts again.
private enum NoteColorCache {
    static let maximumCount = 256
    private static let colorsByKey = Mutex<[String: PlatformColor]>([:])

    static func color(forKey key: String) -> PlatformColor? {
        colorsByKey.withLock { colors in colors[key] }
    }

    static func store(_ color: PlatformColor, forKey key: String) {
        colorsByKey.withLock { colors in
            if colors.count >= maximumCount { colors.removeAll() }
            colors[key] = color
        }
    }
}
