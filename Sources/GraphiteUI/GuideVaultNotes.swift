/**
 * File: GuideVaultNotes.swift
 * ---------------------------
 * Layer: UI
 * Description: The note of the Graphite Guide vault that shows each topic of the Guide in use.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

extension GuideTopic {
    /// The note of the Graphite Guide vault (`Guide/Graphite Guide`) that shows this topic working, as a path inside the
    /// vault without `.md`, or nil for a topic the vault has no note about. `GuideVaultContentsTests` checks each exists.
    var guideVaultNote: String? {
        switch self {
        case .vaults: "1 New to files/What a vault is"
        case .syncAndObsidian: "1 New to files/Where a vault can live"
        case .fileRecovery: "1 New to files/Backups"
        case .drawings: "3 Handwriting and PDFs/Drawings in notes"
        case .pencilTools: "3 Handwriting and PDFs/Pencil tools"
        case .annotatingPDFs:
            GuideBasicsCopy.forPlatform(touch: "3 Handwriting and PDFs/Writing on slides", mac: "3 Handwriting and PDFs/PDF markup on the Mac")
        case .notebooks: "3 Handwriting and PDFs/Notebooks and paper"
        case .recording: "3 Handwriting and PDFs/Recording a lecture"
        case .firstNote, .readAndWrite: "4 Making notes look good/Making notes look good"
        case .formatting: "4 Making notes look good/Headings and text"
        case .embeds, .imagesAndAttachments: "4 Making notes look good/Pictures and embeds"
        case .listsAndTasks: "4 Making notes look good/Lists and tasks"
        case .tables: "4 Making notes look good/Tables"
        case .calloutsMathAndCode: "4 Making notes look good/Quotes and callouts"
        case .links: "5 Connecting notes/Links and backlinks"
        case .propertiesAndTags: "5 Connecting notes/Tags and properties"
        case .search, .quickSwitcherAndCommands: "5 Connecting notes/Search"
        case .bases: "5 Connecting notes/Bases"
        case .canvas: "5 Connecting notes/Canvas"
        case .graphAndMap: "5 Connecting notes/Graph and map"
        case .templatesAndDailyNotes: "5 Connecting notes/Daily notes and templates"
        case .filesAndFolders, .tabsAndSplit, .library: "7 Making it yours/Library and list"
        case .appearance: "7 Making it yours/Themes and snippets"
        case .corePlugins, .communityPlugins: "7 Making it yours/Plugins"
        case .keyboardShortcuts: "7 Making it yours/Keyboard shortcuts"
        case .readAloud, .sourceCodeAndFeedback: nil
        }
    }
}
