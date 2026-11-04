import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Wording, counts and menus that differed from Obsidian or between screens (the consistency
/// section of the bug hunt, HUNT-291 to HUNT-305).
@MainActor
final class ConsistencyBugHuntTests: XCTestCase {
    // MARK: HUNT-291: an unsupported view with no menu to choose another from

    func testAnUnsupportedOnlyViewOffersTheStepsThatExist() throws {
        let basePath = try VaultPath("Plan.base")
        XCTAssertNil(BaseUnsupportedViewWay.available(canChooseAnotherView: true, canEditView: true, baseFile: basePath), "The menu above leads on")
        XCTAssertEqual(BaseUnsupportedViewWay.available(canChooseAnotherView: false, canEditView: true, baseFile: basePath), .editView,
                       "Its layout can be changed in the view editor")
        XCTAssertEqual(BaseUnsupportedViewWay.available(canChooseAnotherView: false, canEditView: false, baseFile: basePath), .openBase(basePath),
                       "An embed that names its view opens the base")
        XCTAssertNil(BaseUnsupportedViewWay.available(canChooseAnotherView: false, canEditView: false, baseFile: nil), "A base block has no file to open")
    }

    // MARK: HUNT-292: the sidebar search while the vault is read

    func testSearchSaysItIsSearchingBeforeItSaysNoMatches() {
        XCTAssertEqual(SidebarSearchEmptyState.state(queryProblem: nil, isSearching: true, isIndexUsable: true), .searching)
        XCTAssertEqual(SidebarSearchEmptyState.state(queryProblem: nil, isSearching: false, isIndexUsable: true), .noMatches)
    }

    func testSearchDoesNotSayNoMatchesWhileTheVaultIsStillBeingRead() {
        let state = SidebarSearchEmptyState.state(queryProblem: nil, isSearching: false, isIndexUsable: false)
        XCTAssertEqual(state, .stillReadingVault)
        XCTAssertEqual(state.message, "Still reading the vault; results may be incomplete.")
    }

    func testAQueryThatCannotRunKeepsSayingWhy() {
        let state = SidebarSearchEmptyState.state(queryProblem: "/(/ is not a valid regular expression.", isSearching: true, isIndexUsable: false)
        XCTAssertEqual(state.message, "/(/ is not a valid regular expression.")
    }

    // MARK: HUNT-294: opening the file of a card that cannot show it

    func testACardNoticeOffersOpenInReadAndPointsToReadWhileWriting() {
        var openedCount = 0
        let reading = CanvasCardOpening(isWriting: false) { openedCount += 1 }
        reading.action?()
        XCTAssertEqual(openedCount, 1)
        XCTAssertEqual(reading.message("This PDF can't be shown on a card."), "This PDF can't be shown on a card.")
        let writing = CanvasCardOpening(isWriting: true) { openedCount += 1 }
        XCTAssertNil(writing.action, "A touch on a card moves it while writing; there is nothing to press")
        XCTAssertEqual(writing.message("This PDF can't be shown on a card."), "This PDF can't be shown on a card. Turn off Write to open it.")
        XCTAssertFalse(writing.message("x").contains("Tap"), "The Mac has no tap")
    }

    // MARK: HUNT-296: a new file without a typed name

    func testAFileWithoutATypedNameIsCalledUntitled() {
        XCTAssertEqual(CreationKind.note.untitledName, "Untitled")
        XCTAssertEqual(CreationKind.base.untitledName, "Untitled")
        XCTAssertEqual(CreationKind.canvas.untitledName, "Untitled")
        XCTAssertEqual(CreationKind.notebook.untitledName, "Untitled Notebook")
        for kind in [CreationKind.note, .base, .canvas, .notebook] {
            XCTAssertNil(FileNameRules.problem(with: kind.untitledName, isNote: kind == .note), "\(kind) can be created with no name typed")
        }
    }

    // MARK: HUNT-298: a PDF's page count

    func testThePageCountHasASingularAndGroupsThousands() {
        XCTAssertEqual(PDFPagesSidebar.pageCountText(1), "1 page")
        XCTAssertEqual(PDFPagesSidebar.pageCountText(12), "12 pages")
        XCTAssertEqual(PDFPagesSidebar.pageCountText(1_200), "\(1_200.formatted()) pages")
        XCTAssertNotEqual(PDFPagesSidebar.pageCountText(1_200), "1200 pages")
    }

    // MARK: HUNT-299: one wording for bookmarks

    func testBookmarkingIsWordedAlikeInEveryMenu() {
        XCTAssertEqual(VaultEntryAction.bookmarkTitle(isBookmarked: false), VaultEntryAction.bookmark.title(otherSideTitle: ""))
        XCTAssertEqual(VaultEntryAction.bookmarkTitle(isBookmarked: true), VaultEntryAction.removeBookmark.title(otherSideTitle: ""))
        XCTAssertEqual(VaultEntryAction.bookmarkTitle(isBookmarked: false), "Bookmark")
    }

    // MARK: HUNT-300: reaching the menu of a switcher result

    func testTheSwitcherNamesTheRightGestureForItsPlatform() {
        #if os(macOS)
        XCTAssertEqual(QuickPalette.moreMenuHint, "right-click")
        #else
        XCTAssertEqual(QuickPalette.moreMenuHint, "touch and hold")
        #endif
        XCTAssertFalse(QuickPalette.moreMenuHint.contains("long press"))
    }

    // MARK: HUNT-302: shortcuts shown on the empty tab

    func testAShownShortcutFollowsTheVaultsKeyboardShortcuts() throws {
        let shortcuts = VaultKeyboardShortcuts(platform: .macOS)
        XCTAssertEqual(shortcuts.shownShortcut(for: .newNote), "⌘N")
        XCTAssertEqual(shortcuts.shownShortcut(for: .closeTab), "⌘W")
        let rebound = try HotkeyFile(configurationData: Data(#"{"file-explorer:new-file":[{"modifiers":["Mod","Shift"],"key":"J"}],"switcher:open":[]}"#.utf8))
        shortcuts.show(.read(rebound))
        XCTAssertEqual(shortcuts.shownShortcut(for: .newNote), "⇧⌘J", "The vault's own shortcut")
        XCTAssertNil(shortcuts.shownShortcut(for: .quickSwitcher), "A command whose shortcuts were removed shows none")
    }

    // MARK: HUNT-304: words as Obsidian counts them

    /// The expected counts come from Obsidian's own pattern, run in Node on the same text.
    func testWordsAreCountedAsObsidianCountsThem() {
        let expectedCounts: [(text: String, words: Int)] = [
            ("", 0),
            ("one", 1),
            ("Hello  world\n\n  with 😀 emoji\tand tabs\n", 6),
            ("and/or x-ray word,word", 5),
            ("- bullet one\n- bullet two\n---\n", 7),
            ("3.14 1,000 2x 10.5.3 a1b2", 5),
            ("don't stop; it’s fine — ok", 5),
            ("日本語のテキスト、これは文です。", 14),
            ("한국어 문장입니다 hello", 3),
            ("naïve café Ünïcödé Ελληνικά Привет мир", 6),
            ("## Heading\n\n> [!note] Callout\n> text here\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n", 11),
            ("$x^2 + y_1 = z$ and $$\\frac{a}{b}$$", 9),
            ("[[Link|alias]] and [text](https://example.com/a-b_c?d=e)", 11),
            ("สวัสดีครับ", 4),
            ("你好 world 世界", 5),
            ("ｆｕｌｌｗｉｄｔｈ ＡＢＣ", 2),
        ]
        for expected in expectedCounts {
            XCTAssertEqual(NoteTextCounts(countingBodyOf: expected.text).wordCount, expected.words, expected.text)
        }
    }

    func testTheFrontmatterIsNotCountedAndCharactersAreAsAPersonSeesThem() {
        let counts = NoteTextCounts(countingBodyOf: "---\ntitle: Test\ntags: [a, b]\n---\nHello  world 😀")
        XCTAssertEqual(counts.wordCount, 2)
        XCTAssertEqual(counts.characterCount, "Hello  world 😀".count)
    }

    // MARK: HUNT-305: Format and Insert from one list

    private func menuActions(colors: [PaletteColor]?, template: (() -> Void)? = nil) -> EditorContextMenuActions {
        EditorContextMenuActions(run: { _ in }, noteState: { ("" as NSString, NSRange()) }, apply: { _ in }, insertBlock: { _ in }, colors: colors,
                                 insertColor: { _, _ in }, linkToNote: {}, template: template)
    }

    private func titles(of entries: [EditorContextMenuEntry]) -> [String] {
        entries.flatMap { entry -> [String] in
            switch entry.content {
            case .action: [entry.title]
            case .submenu(let submenuEntries): [entry.title + " ›"] + titles(of: submenuEntries).map { "  " + $0 }
            case .group(let groupEntries): titles(of: groupEntries)
            }
        }
    }

    /// The entries inside the submenu of this name, looking through groups; empty when there is none.
    private func submenuEntries(named name: String, in entries: [EditorContextMenuEntry]) -> [EditorContextMenuEntry] {
        for entry in entries {
            switch entry.content {
            case .submenu(let children) where entry.title == name: return children
            case .group(let children):
                let found = submenuEntries(named: name, in: children)
                if !found.isEmpty { return found }
            default: continue
            }
        }
        return []
    }

    func testTheFormatMenuHasTheContextMenusFormatItemsThenItsColorAndParagraphSubmenus() {
        let actions = menuActions(colors: PaletteColor.defaultPalette)
        let formatMenu = EditorContextMenuContent.formatMenuEntries(actions: actions)
        let contextEntries = EditorContextMenuContent.entries(actions: actions, editorActions: EditorActions())
        let contextFormat = submenuEntries(named: "Format", in: contextEntries)
        XCTAssertEqual(titles(of: Array(formatMenu.prefix(contextFormat.count))), titles(of: contextFormat))
        XCTAssertFalse(contextFormat.isEmpty)
        XCTAssertEqual(titles(of: contextFormat), ["Bold", "Italic", "Strikethrough", "Highlight", "Code", "Inline Math", "Comment"])
        let submenuTitles = titles(of: formatMenu).filter { title in title.hasSuffix("›") }
        XCTAssertEqual(submenuTitles, ["Color ›", "Paragraph ›"])
        XCTAssertEqual(titles(of: submenuEntries(named: "Paragraph", in: formatMenu)), titles(of: submenuEntries(named: "Paragraph", in: contextEntries)))
        let headings = titles(of: submenuEntries(named: "Paragraph", in: formatMenu)).filter { title in title.hasPrefix("Heading") }
        XCTAssertEqual(headings, (1...6).map { level in "Heading \(level)" })
    }

    func testTheFormatMenuNeverReadsTheNote() throws {
        var readCount = 0
        let actions = EditorContextMenuActions(run: { _ in }, noteState: { readCount += 1; return ("" as NSString, NSRange()) }, apply: { _ in },
                                               insertBlock: { _ in }, colors: PaletteColor.defaultPalette, insertColor: { _, _ in }, linkToNote: {}, template: nil)
        _ = EditorContextMenuContent.formatMenuEntries(actions: actions)
        XCTAssertEqual(readCount, 0, "A toolbar menu that read the note would be made again at every keystroke")
        _ = EditorContextMenuContent.entries(actions: actions, editorActions: EditorActions())
        XCTAssertGreaterThan(readCount, 0, "The context menu, made when it opens, still dims Remove when no color is selected")
    }

    func testWithoutColorsThereIsNoColorMenuInTheFormatMenu() {
        let formatMenu = EditorContextMenuContent.formatMenuEntries(actions: menuActions(colors: nil))
        XCTAssertFalse(titles(of: formatMenu).contains("Color ›"))
    }

    func testTheInsertMenuHasTheContextMenusInsertItemsAndTheToolbarsNewNotebook() {
        var paneActions = EditorActions()
        paneActions.attach = {}
        paneActions.newNotebook = {}
        let actions = menuActions(colors: nil, template: {})
        let insertMenu = EditorContextMenuContent.insertMenuEntries(actions: actions, editorActions: paneActions)
        let contextInsert = submenuEntries(named: "Insert", in: EditorContextMenuContent.entries(actions: actions, editorActions: paneActions))
        XCTAssertEqual(titles(of: insertMenu), titles(of: contextInsert))
        XCTAssertFalse(contextInsert.isEmpty)
        let insertTitles = titles(of: insertMenu)
        for title in ["Table", "Callout", "Math Block", "Link to Note…", "Attachment…", "New Notebook…", "Template…"] {
            XCTAssertTrue(insertTitles.contains(title), title)
        }
        XCTAssertFalse(insertTitles.contains("Photo Library…"), "The pane offers no photo library here")
    }

    func testTheMenuBarFollowsTheFocusedNoteAndLetsGoWithIt() {
        let registry = EditorMenuRegistry()
        let firstTab = UUID(), secondTab = UUID()
        XCTAssertNil(registry.entries)
        registry.register(tabID: firstTab) { EditorMenuEntries(format: [.action("Bold") {}], insert: []) }
        XCTAssertEqual(registry.entries?.format.map(\.title), ["Bold"])
        // Focus moved to the other side before the first side let go: its let-go must not take the menus away.
        registry.register(tabID: secondTab) { EditorMenuEntries(format: [.action("Italic") {}], insert: []) }
        registry.unregister(tabID: firstTab)
        XCTAssertEqual(registry.entries?.format.map(\.title), ["Italic"])
        registry.unregister(tabID: secondTab)
        XCTAssertNil(registry.entries)
    }
}
