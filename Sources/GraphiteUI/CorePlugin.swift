/**
 * File: CorePlugin.swift
 * ----------------------
 * Layer: UI
 * Description: Graphite's features that can be switched off, like Obsidian's core plugins: their names, summaries,
 *              defaults and symbols.
 *
 * Authors: Bahey Shalash, Félix Chevalier
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// Graphite features that can be switched off, like Obsidian's core plugins.
enum CorePlugin: String, CaseIterable, Identifiable, Codable {
    case backlinks, outgoingLinks, outline, properties, tags, wordCount
    case colors, drawings, audioRecorder, readAloud, bases, slashCommands
    case templates, dailyNotes, calendar, footnotes, fileRecovery, bookmarks, graph, map, canvas, notebookImport, postgreSQLMirror, pagePreview, slides

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlinks: "Backlinks"
        case .outgoingLinks: "Outgoing Links"
        case .outline: "Outline"
        case .properties: "Properties View"
        case .tags: "Tags View"
        case .wordCount: "Word Count"
        case .colors: "Colors"
        case .drawings: "Pencil Drawings"
        case .audioRecorder: "Audio Recorder"
        case .readAloud: "Read Aloud"
        case .bases: "Bases"
        case .templates: "Templates"
        case .slashCommands: "Slash Commands"
        case .dailyNotes: "Daily Notes"
        case .calendar: "Calendar"
        case .footnotes: "Footnotes View"
        case .fileRecovery: "File Recovery"
        case .bookmarks: "Bookmarks"
        case .graph: "Graph View"
        case .map: "Map View"
        case .canvas: "Canvas"
        case .notebookImport: "Goodnotes and Notability Import"
        case .postgreSQLMirror: "PostgreSQL Mirror"
        case .pagePreview: "Page Preview"
        case .slides: "Slides"
        }
    }

    /// The summary for a window with no room for the right sidebar, as on a phone, where
    /// the panels are in the Links and Outline sheet.
    func summary(hasRightSidebar: Bool) -> String {
        hasRightSidebar ? summary : summary.replacingOccurrences(of: "in the right sidebar", with: "in the Links and Outline sheet")
    }

    var summary: String {
        switch self {
        case .backlinks: "Shows the notes that link to the current note."
        case .outgoingLinks: "Shows the links in the current note."
        case .outline: "Shows the headings of the current note, and jumps to them."
        case .properties: "Shows a note's frontmatter as editable properties, and every property in the vault in the left sidebar."
        case .tags: "Lists the tags of the current note, and every tag in the vault with its count in the left sidebar."
        case .wordCount: "Shows the word and character count of the current note."
        case .colors: "Colors text with ~={#hex}text=~, compatible with the Colors plugin for Obsidian."
        case .drawings: "Draw with Apple Pencil and embed the drawing in a note."
        case .audioRecorder: "Records lectures into ordinary audio and video files in the vault."
        case .readAloud: "Reads notes and PDFs aloud with a natural voice, highlighting each word, entirely on this device."
        case .bases: "Opens .base files and base code blocks as tables, cards, lists, and maps."
        case .templates: "Inserts notes from a templates folder, filling in the title, date, and time."
        case .slashCommands: "Typing / at a line's start or after a space lists the blocks to insert, then every command to run."
        case .dailyNotes: "Opens a note for today, created from a template, and the notes of other days."
        case .calendar:
            "A month of daily notes in the left sidebar, with each day's events from Apple's Calendar, notes made from events, "
                + "and tasks sent to Reminders. Calendar and Reminders are asked for only when you first use them."
        case .footnotes: "Lists the current note's footnotes in the right sidebar."
        case .fileRecovery: "Keeps copies of notes as they are edited, outside the vault, to recover earlier versions and deleted notes."
        case .bookmarks: "Keeps notes, headings, folders, and searches at hand in the left sidebar, shared with Obsidian."
        case .graph: "Draws the vault's notes and links, and each note's neighborhood in the right sidebar."
        case .map: "Places notes with a coordinates property on Apple's map, and the open note's linked places in the right sidebar."
        case .canvas: "Opens .canvas files as boards of cards and connections, to read and to edit."
        case .postgreSQLMirror:
            "Copies the notes, their properties, tags, links and places into a PostgreSQL database, to query them in QGIS or other apps. "
                + "The notes themselves are never changed."
        case .notebookImport:
            "Turns Goodnotes and Notability notebooks into PDFs with editable handwriting when they are imported. Off, they are copied as they are."
        case .pagePreview:
            "Shows a note beside a link to it while the pointer or Apple Pencil rests on the link, or when the link is held."
        case .slides:
            "Presents a note as slides, separated by \u{201C}---\u{201D}, full screen or on an external display, "
                + "with Apple Pencil's laser and ink that fades."
        }
    }

    /// Whether the plugin is on until the person turns it off. Read Aloud is off until it is
    /// turned on (owner decision 2026-10-19): its voices, models and audio are heavy, and many
    /// people never use it. The PostgreSQL Mirror sends the vault's notes to a server, which
    /// only the person can choose to do.
    var isEnabledByDefault: Bool {
        switch self {
        case .readAloud, .postgreSQLMirror: false
        case .backlinks, .outgoingLinks, .outline, .properties, .tags, .wordCount, .colors, .drawings, .audioRecorder,
             .bases, .templates, .dailyNotes, .calendar, .footnotes, .fileRecovery, .bookmarks, .graph, .map, .canvas, .notebookImport, .pagePreview,
             .slides, .slashCommands: true
        }
    }

    var systemImage: String {
        switch self {
        case .backlinks: "arrow.uturn.left"
        case .outgoingLinks: "arrow.up.right"
        case .outline: "list.bullet.indent"
        case .properties: "list.bullet.rectangle"
        case .tags: "number"
        case .wordCount: "textformat.123"
        case .colors: "paintpalette"
        case .drawings: "pencil.tip.crop.circle"
        case .audioRecorder: "mic"
        case .readAloud: "speaker.wave.2"
        case .bases: "tablecells"
        case .templates: "doc.on.doc"
        case .slashCommands: "slash.circle"
        case .dailyNotes: "calendar"
        case .calendar: "calendar.day.timeline.left"
        case .footnotes: "textformat.superscript"
        case .fileRecovery: "clock.arrow.circlepath"
        case .bookmarks: "bookmark"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .map: "map"
        case .canvas: "rectangle.3.group"
        case .notebookImport: "square.and.arrow.down.on.square"
        case .postgreSQLMirror: "cylinder.split.1x2"
        case .pagePreview: "doc.text.magnifyingglass"
        case .slides: "play.rectangle"
        }
    }
}
