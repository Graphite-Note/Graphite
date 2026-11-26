/**
 * File: NoteIconSymbols.swift
 * ---------------------------
 * Layer: Core
 * Description: The symbols a note's icon can be chosen from, each an SF Symbol paired with the Lucide icon of
 *              Iconize's built-in pack that shows the same thing, so a note looks alike in Graphite and in Obsidian.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// The symbols offered for a note's icon. Each is written as Iconize's name of its Lucide icon (`Li` and the
/// Lucide name in upper camel case), which Iconize draws from Obsidian's own Lucide set without a download.
public enum NoteIconSymbols {
    /// One symbol: the SF Symbol Graphite draws and the Lucide icon Iconize draws.
    public struct Pairing: Hashable, Sendable {
        public let systemName: String
        public let lucideName: String

        /// The name Iconize writes and reads for the Lucide icon.
        public var iconizeName: String { Self.iconizePrefix + lucideName }

        static let iconizePrefix = "Li"
    }

    /// The symbols in the order the picker shows them: study and writing first, then subjects, then the rest.
    public static let pairings: [Pairing] = [
        ("book.closed", "Book"), ("book", "BookOpen"), ("books.vertical", "Library"), ("graduationcap", "GraduationCap"),
        ("pencil", "Pencil"), ("highlighter", "Highlighter"), ("doc.text", "FileText"), ("note.text", "StickyNote"),
        ("list.bullet", "List"), ("checklist", "ListChecks"), ("checkmark.circle", "CircleCheck"), ("calendar", "Calendar"),
        ("clock", "Clock"), ("bookmark", "Bookmark"), ("tag", "Tag"), ("folder", "Folder"),
        ("lightbulb", "Lightbulb"), ("brain", "Brain"), ("questionmark.circle", "CircleHelp"), ("exclamationmark.triangle", "TriangleAlert"),
        ("star", "Star"), ("heart", "Heart"), ("flag", "Flag"), ("pin", "Pin"),
        ("function", "Sigma"), ("x.squareroot", "Radical"), ("percent", "Percent"), ("chart.bar", "ChartColumn"),
        ("chart.line.uptrend.xyaxis", "ChartLine"), ("atom", "Atom"), ("flask", "FlaskConical"), ("testtube.2", "TestTubes"),
        ("leaf", "Leaf"), ("globe", "Globe"), ("map", "Map"), ("building.columns", "Landmark"),
        ("cpu", "Cpu"), ("memorychip", "MemoryStick"), ("bolt", "Zap"), ("waveform", "AudioWaveform"),
        ("chevron.left.forwardslash.chevron.right", "Code"), ("terminal", "Terminal"), ("server.rack", "Server"), ("network", "Network"),
        ("music.note", "Music"), ("paintpalette", "Palette"), ("camera", "Camera"), ("photo", "Image"),
        ("person", "User"), ("person.2", "Users"), ("bubble.left", "MessageCircle"), ("envelope", "Mail"),
        ("house", "House"), ("briefcase", "Briefcase"), ("cart", "ShoppingCart"), ("dollarsign.circle", "CircleDollarSign"),
        ("airplane", "Plane"), ("car", "Car"), ("fork.knife", "Utensils"), ("cup.and.saucer", "Coffee"),
        ("dumbbell", "Dumbbell"), ("trophy", "Trophy"), ("target", "Target"), ("sparkles", "Sparkles"),
    ].map { systemName, lucideName in Pairing(systemName: systemName, lucideName: lucideName) }

    private static let systemNamesByIconizeName: [String: String] = Dictionary(
        pairings.map { pairing in (pairing.iconizeName, pairing.systemName) }, uniquingKeysWith: { first, _ in first })

    private static let iconizeNamesBySystemName: [String: String] = Dictionary(
        pairings.map { pairing in (pairing.systemName, pairing.iconizeName) }, uniquingKeysWith: { first, _ in first })

    /// The SF Symbol for Iconize's name of a Lucide icon (`LiBookOpen`), or nil when the name is not one of the pairings.
    public static func systemName(forIconizeName iconizeName: String) -> String? {
        systemNamesByIconizeName[iconizeName]
    }

    /// Iconize's name of the Lucide icon paired with an SF Symbol, or nil when the symbol has no pairing.
    public static func iconizeName(forSystemName systemName: String) -> String? {
        iconizeNamesBySystemName[systemName]
    }
}
