# Naming files in the file tree's rows: implementation TODO

Created: 2026-11-27.

Status: section 1 (the Mac) built, tested and checked by hand on 2026-11-28, except a PDF's rename and a real mouse click seen in the app (its last item); section 2 (the iPad and the iPhone) planned. Issues: [#270](https://github.com/Graphite-Note/Graphite/issues/270) (section 1), [#271](https://github.com/Graphite-Note/Graphite/issues/271) (section 2).

## Request

Requested 2026-11-27: "adding a new file, renaming etc curretly looks like it was made in the 2000s, i like it in the vscodium style the where(path) the file is created and how you rename doesnt pop up in the middle of your screen". New Note, New Folder and Rename each opened a sheet in the middle of the window (`CreateDocumentSheet`, `NewFolderSheet`, `RenameSheet` in `FileSheets.swift`), saying where the item went in a line of its footer. In VSCodium's explorer, New File and New Folder open the folder and put an empty name field in a row of it, and Rename turns the row's name into a field; Return keeps the name, Escape cancels, a bad name is explained in a box under the field.

## Decisions

- Decided 2026-11-27, as obvious defaults: an empty new item's field makes "Untitled" on Return, as the sheet and Obsidian did (a folder gets the first "Untitled", "Untitled 1"… the folder does not have); a click elsewhere keeps a typed name and drops an empty one, as VSCodium does; a name another item of the folder has, compared without case, is refused under the field instead of being numbered.
- A notebook and a course keep their sheets: the notebook's chooses its paper, the course's makes its page from the starter. So does every item while no tree is on screen (the sidebar folded or showing another panel, a filtered tree, Library mode, the library's own New menu) and the Move sheet's New Folder.
- The workspace asks the tree first (`WorkspaceModel.requestRename`, `requestNewFolder`, `creationSheet`) through a narrow `FileTreeNaming` capability the tree registers while it is shown; the sheets stand in when it answers no.

## 1. The Mac's file tree names in its rows

Issue: [#270](https://github.com/Graphite-Note/Graphite/issues/270)

- [x] New Note, New Base and New Canvas, from the sidebar's New button and its menu, a folder's menu, the menu bar, ⌘N and the palette, open the target folder and the folders above it, one level at a time as their contents are listed when they were never opened, and put an empty field, hinted "Untitled", in a row of it where its files begin; New Folder puts it first in the folder. Return creates the item there, and it opens as before.
  Done 2026-11-27: `FileTreeController.beginNaming` (`MacFileTreeNaming.swift`) adds a `FileTreeNewItemRow` to the outline's data source, after the folder's listing arrives when it was folded; `FileTreeNameEditor` owns the field, `WorkspaceModel.finishNaming` calls `createNote`, `createBase`, `createCanvas` or `createFolder`. Tests: `UiFileTreeInlineNamingMacTests.testANewNoteIsNamedInARowOfItsFolder` (a folded folder opens, the field is its first file's row and has the keyboard, Return makes `Course/Week 2.md`, no sheet), `testANewNoteInAFolderNeverOpenedOpensTheFoldersAboveIt` (`Signals/Labs` two levels down, never listed; a folder not there yet keeps the sheet).
- [x] Rename, from a row's menu, a tab's menu and the palette, turns the item's row into a field holding its name with the whole name selected; a file other than a note shows its extension muted after the field, which the rename keeps. Return renames (the vault's "Update links?" question unchanged); Escape keeps the old name.
  Done 2026-11-27: `FileTreeNameDraft` (pure: the field's text, the kept extension, the outcome of Return, Escape and a click elsewhere), `FileTreeCellView.showNameField`. Tests: `FileTreeNameDraftTests` (9), `UiFileTreeInlineNamingMacTests.testARenameIsTypedInTheItemsRow` (the field holds "Lecture" selected, Return renames the file on disk).
- [x] A name that cannot be used (forbidden characters, a dot at its start, a note's link-breaking characters, a name the folder already has) is explained in a small popover under the field as it is typed, and Return leaves the field open; a click elsewhere drops it.
  Done 2026-11-27: `FileTreeNameDraft.problem(typed:)`, the popover of `FileTreeNameEditor`. Tests: `FileTreeNameDraftTests.testANameAlreadyInTheFolderIsRefused`, `testANotesNameKeepsLinksWorking`, `testAnEmptiedRenameKeepsTheOldName`, `UiFileTreeInlineNamingMacTests.testReturnOnATakenNameKeepsTheField`. The popover's look is not covered by a test.
- [x] While a name is typed, listings that arrive (a sync, another app's change) wait, so the field keeps its row and the keyboard; they show once the field is left. A field left by a click on another row ends after the click, so the row clicked is the one that opens.
  Done 2026-11-27: `FileTreeController.update` and `show` hold the state and the folders listed while `namingPhase` is `.editing`, `applyChangesHeldWhileNaming` shows them. Test: `UiFileTreeInlineNamingMacTests.testAListingWhileTypingKeepsTheField`. The click on another row is not covered by a test.
- [x] With no tree on screen, Rename, New Folder, New Note, New Base and New Canvas open their sheets as before; a notebook and a course always do.
  Done 2026-11-27: `UiFileTreeInlineNamingMacTests.testTheSheetsStandInWithoutATree`, `testANotebookKeepsItsSheetBesideATree`, `FileTreeNameDraftTests.testANotebookAndACourseAreNotNamedInARow`.
- [x] Checked by hand in a separate Debug copy of the Mac app with a made-up vault: New Note at the root and in a folder never opened, New Folder, Rename of a note, a taken name's popover (and that it leaves the keyboard in the field), Escape, and choosing another row while a new item's field is open.
  Done 2026-11-28 in a re-signed Debug copy (`com.graphite.study.repro.naming`, its own container): File › New Note put the field after the root's folders; "index" showed "“index” is already in this folder. Choose a different name." under the field, Return left it open with the keyboard, "Week 3" made `Week 3.md` and opened it; the palette's Rename file showed `Week 3` selected in its row and Return renamed it to `Week 3 Sampling.md`; with the vault's folder for new notes at `Signals/Labs`, New Note opened Signals and Labs and put the field inside Labs; choosing Week 1 while it was empty made nothing and opened Week 1; New Folder "Results" was made in Labs. Found and fixed during the check: the popover drew above the field without its text (laid out by hand now, under the field), and the new item's reused cell kept the earlier field under the new one (`testASecondNewItemShowsOneField`).
- [ ] Seen in the app: a PDF's muted extension after its rename field (the made-up PDF did not open), and a real mouse click on a row below a new item's field (the check chose the row through accessibility, so the rows' shift within a click was not exercised).

## 2. The iPad's and the iPhone's file list name in their rows

Issue: [#271](https://github.com/Graphite-Note/Graphite/issues/271)

- [ ] The SwiftUI file list (`FileTreeRows`) names a new note, base, canvas or folder in a row of its folder and renames in the item's row, with the same `FileTreeNameDraft` decisions, as the Files app renames in place; the keyboard's Return keeps the name.
- [ ] Hosted tests on the iPad simulator, and a check in the simulator with the release test vault, portrait and landscape.
