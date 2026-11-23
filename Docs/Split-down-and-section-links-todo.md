# Split down and section links on PDFs: TODO

Created: 2026-11-21.

Status: planned 2026-11-21. Section 1 (Split Down) built 2026-11-21 and checked in Mac package tests and on an iPad simulator; its View menu, landscape, Stage Manager, the Mac app and a real iPad are left. Section 2 (section links on PDF pages) built 2026-11-21 and checked in Mac package tests and on an iPad simulator; the reading view's drags, renames, the lasso, the Mac app, Preview and Obsidian are left. Request: [#220](https://github.com/Graphite-Note/Graphite/issues/220). Issues: [#221](https://github.com/Graphite-Note/Graphite/issues/221) (section 1), [#222](https://github.com/Graphite-Note/Graphite/issues/222) (section 2).

## Request

From [#220](https://github.com/Graphite-Note/Graphite/issues/220) (shantni, iPad, 2026-11-21), who studies and makes notes from their Obsidian notes:

- "Right now, the split is horizontal, left and right, but I want to do it vertical, top and bottom."
- Link sections of a note by dragging and dropping them onto a PDF: instead of duplicating the whole picture or section on the page, the page gets a shortcut that shows a preview of what was added.

## What exists today (2026-11-21)

- **Split view is side by side only.** `TabLayout` (`Sources/GraphiteCore/TabLayout.swift`) holds at most two groups and one `splitFraction`, "the left group's share of the width" (0.25 to 0.75). It has no direction. `WorkspacePanes` (`Sources/GraphiteUI/WorkspacePanes.swift`) lays the sides out across the width with a vertical divider (`SplitDivider`, dragged through `SplitDividerDrag`), puts the divider on a display's fold (`DisplayFoldLayout.splitFraction`), and focuses the side a touch lands on (`groupFrames`). On a compact width only the focused side shows. The only command is Split Right (`WorkspaceModel.splitRight`, `GraphiteCommand.splitRight`, the tab menu, the palette); the Guide and the Welcome tour name it. The layout is saved per vault as `SavedTabLayout` in the user defaults, not in `.obsidian/workspace.json`.
- **Notes and PDFs are linked one way.** A note's page links (`[[file.pdf#page=5]]`) move a PDF on the other side. Nothing on a PDF page links to a note.
- **A PDF page holds copies, not links.** Pictures are placed from the More menu, the fixed bar, or pasted with the lasso (`LassoPasteboard`): a copy of the image. Text boxes are `/FreeText` annotations whose text can hold `/Link` annotations (`Docs/PDF-text-boxes-todo.md`). A PDF page accepts no drops; only the pages sidebar (`PDFPagesSidebar`) does.
- **Links that open a note from outside Graphite exist.** `VaultURI` (Core) reads `graphite://` and `obsidian://open` links with Obsidian's parameters.
- **The note editor has no block drag of its own.** iPadOS's text view drags selected text; there is no handle for dragging a heading's section or a block.

## What the result must be

- **Ordinary files** (OBJECTIVE.md). The split's direction lives with the rest of the layout on the device, not in the vault. A section link on a PDF page is a standard PDF annotation with its own appearance, so Preview, Files, Acrobat and Obsidian show the preview and can follow the link; no sidecar file or app database.
- **Off costs nothing.** A layout that is not split down does no extra work; a PDF with no section links reads no notes.
- **The same on the iPad and the Mac**, with the iPhone showing one side as today.

## 1. Split down

Issue: [#221](https://github.com/Graphite-Note/Graphite/issues/221)

- [x] `TabLayout` and `SavedTabLayout` keep the split's direction (side by side or one above the other); a saved layout without one reads as side by side. The fraction is the first group's share of the width or the height.
  Done 2026-11-21: `SplitDirection` and `TabLayout.split(_:)` (Core); `SavedTabLayout.splitDirection` is written only for a split one above the other and a name a newer build saves reads as side by side. A side opened again by Open to the Right or by moving a tab goes where the last split put it. Tests: `TabLayoutTests.testSplitDownPutsTheNewSideBelowAndTurningKeepsBothSides`, `testTheSplitDirectionIsSavedOnlyWhenOneAboveTheOther`, `SplitDownTests.testTheDirectionIsKeptBetweenLaunches`.
- [ ] Split Down, as Obsidian names it: in the palette, the menu bar's View menu, the tab menu and Settings › Keyboard Shortcuts, beside Split Right. Choosing the other one on a split layout turns the split, keeping both sides' tabs.
  Built 2026-11-21: `GraphiteCommand.splitDown` (Obsidian's `workspace:split-horizontal`), the palette's `split-down` (`WorkspaceCommandIdentifiersTests`, `LayoutFitsNarrowWindowsTests`), the View menu's second item (Split Down, or Split Right on a split one above the other), and the menu of the tab bar's Split Right and Close This Side buttons and of Show All Tabs. Checked on an iPad simulator: holding Split Right offers Split Right and Split Down; holding Close This Side on a split one above the other offers Split Right, which turned it. Left: the View menu opened by hand, on the Mac and the iPad.
- [x] `WorkspacePanes` lays the sides out top and bottom with a horizontal divider that is dragged up and down (`SplitDividerDrag` in height), within the same 0.25 to 0.75.
  Done 2026-11-21: one `AnyLayout` (a horizontal or vertical stack), so turning the split keeps both sides' editors; `SplitDivider` runs across; `SplitDividerDrag` takes the length along the split. Tests: `SplitDownTests.testSplitDownShowsTheSidesOneAboveTheOtherAndTurningKeepsTheirEditors` (the same text views before and after turning), `SplitDividerDragTests`. Checked on an iPad simulator: the divider dragged up and the sides followed.
- [x] Each side's toolbar and tab bar are decided by its own size; a document's controls never sit under the other side (the thresholds of invariant U-02 read width, which both sides now share).
  Done 2026-11-21: nothing changed; each side's tab bar reads its own width, which is the window's when one is above the other. Checked in the pictures of `SplitDownTests` and on an iPad simulator in portrait: both tab bars with Write, Undo and Redo, and the PDF's fixed Pencil bar on the lower side.
- [x] A touch focuses the side it lands on; the focused side is marked as it is side by side.
  Done 2026-11-21: unchanged (`groupFrames`). Checked on an iPad simulator: a tap on the upper note moved the window's title and the tab's underline to it from the PDF below.
- [x] The divider snaps to a display's fold only where the fold runs across the window, so a side-by-side fold keeps the split side by side.
  Done 2026-11-21: `DisplayFoldLayout.splitFraction(direction:)` takes a fold down the middle for sides side by side and one across for sides one above the other. Tests: `DisplayFoldLayoutTests.testASplitAboveAndBelowPutsItsDividerOnAFoldAcross`. Not tried on a folding display.
- [x] In a compact window only the focused side shows, as today.
  Done 2026-11-21: unchanged (`showsBothGroups` needs a regular width either way), and a phone's palette offers neither split (`LayoutFitsNarrowWindowsTests.testThePaletteOffersNoSplitOnAPhone`).
- [x] The Guide and the Welcome tour name Split Down.
  Done 2026-11-21: `GuideCopyOrganizing` (touch: hold Split Right for Split Down) and `WelcomeTourCopy`.
- [x] Tests: the layout's direction, its saving and reading, turning a split; the panes' layout top and bottom; the divider drag in height.
  Done 2026-11-21: the tests above; the full Mac package suite (5,077 tests, 30 skipped) failed only `ReadingGanttChartTests.testAChartWithAStatementNotDrawnOrADateNotReadShowsTheSourceAndWhy`, which expects MermaidDiagrams to refuse Gantt statements that 0.4.0 on main now draws.
- [ ] Checked on the iPad in portrait (a PDF above a note, writing in both), in landscape and with Stage Manager windows, and on the Mac.
  2026-11-21, iPad simulator (iPad Pro 11-inch (M5), iOS 27.2, portrait, a demo vault of the test vault's files): a note above a PDF, the divider dragged, the keyboard shrinking both sides with the PDF still shown, turned side by side and back. Left: writing with Apple Pencil in the lower PDF, landscape, Stage Manager, the Mac app, a real iPad.

## 2. Section links on PDF pages

Issue: [#222](https://github.com/Graphite-Note/Graphite/issues/222)

- [ ] A note's heading (its whole section) or block (a paragraph, list item, picture or embed) can be dragged out of the editor (Source and Live Preview) and the reading view, carrying its link (`[[Note#Heading]]`, or `[[Note#^block]]` with a block ID added as Obsidian's Copy Link to Block adds one) and its text. Dragged selected text links the block it starts in; a note dragged from the file tree links the whole note.
  Built 2026-11-21: a drag of text in the editor carries the section it starts in beside the text (`SectionLinkTransfer`, `MarkdownEditorSectionDrag`: the iPad's `UITextDragDelegate`, the Mac's `dragSelection`); a block gets its identifier only when a PDF page takes the drop, the cursor left where it was; a note dragged from the iPad sidebar or the Mac file tree links the whole note. Tests: `SectionLinkTests`, `SectionLinksOnPDFTests.testADraggedBlockGetsItsIdentifierOnlyWhenAPageTakesItAndTheCursorStays`. Checked on an iPad simulator: the heading Entropy selected and dragged onto a PDF page. Built 2026-11-23: the reading view's headings can be dragged too (`ReadingSectionDrags`, from the place of each of the note's own blocks, `ReadingBlockLocation`), carrying the section and `[[Note#Heading]]` as text, so a note it is dropped into gets a link; its paragraphs are not dragged, so their text can still be selected. Test: `SectionLinksOnPDFTests.testAHeadingDraggedFromTheReadingViewCarriesItsSectionAndALinkAsText`. Left: the reading view's drag tried on an iPad simulator and the Mac by hand.
- [x] A PDF page accepts the drop where it lands, and places a section link there: a `/Link` annotation to the section (an `obsidian://open` link with the vault, the file and the heading, read back by `VaultURI`) whose appearance is a picture of the section as the reading view draws it, at most 60% of the page, selected after it is placed.
  Done 2026-11-21: the section's picture is a stamp (`PDFPicture.sectionLinkAddress`, drawn by `SectionPictureRendering` through the note's PDF renderer on an A5 page, cut to its text, with a thin frame) with one `/Link` over it to `obsidian://open?vault=…&file=Note%23Heading`, kept in step by `PDFPageManager.synchronizeSectionLinks`; placed and selected by `PDFSession.placeDroppedSectionLink` (iPad `PDFPictureDropInteraction`, Mac `MacPDFPictureDropTarget`), one step Add Section Link. Tests: `PDFSectionLinkTests` (the stamp and the link written, read back with Core Graphics), `SectionLinksOnPDFTests.testADroppedSectionIsPlacedWhereItLandedAndTheFileLinksToIt`. Checked on an iPad simulator: placed where it was dropped, selected, saved with its link.
- [ ] A section link is moved, resized and deleted like a picture, taken by the lasso with ink, pictures and text boxes, and every step is in the PDF's undo history.
  Built 2026-11-21: it is a picture, so the picture's handles, bar and history apply; its link follows a move, a turn, a replacement and a removal (`PDFSectionLinkTests.testTheLinkFollowsThePictureAndGoesWithIt`). Left: the lasso, and moving and resizing it by hand.
- [ ] Tapping a section link opens the section on the other side, or in the PDF's side when there is none.
  Built 2026-11-21: the picture's floating bar on the iPad starts with Open “Note › Heading”; a click or tap on the link of a PDF view (`PDFLinkClicks`, the view's delegate on both platforms) opens a section of this vault beside the PDF and another vault's as a link from another app. Tests: `SectionLinksOnPDFTests.testALinkClickedOnThePageOpensTheSectionAndOtherAddressesAreLeftToTheSystem`. Checked on an iPad simulator: Open showed the note at its heading on the other side, in place of another note. Left: the Mac by hand.
- [x] The preview is drawn again whenever the section changes, the next time the PDF shows that page, and saved into the annotation's appearance so other readers see the new version. A renamed note or heading keeps its links, as Obsidian updates links on rename; a deleted section says so on the link instead of a stale picture.
  Built 2026-11-21: each picture keeps a digest of the section's text (`PDFPicture.sectionTextDigest`, `SectionLink.textDigest`); `PDFSectionPictureRefresh`, behind every PDF pane, draws again the changed sections of the pages in view when the pages in view or the index change, keeping the picture's width and top edge, not as a step of the history. A missing section shows “Unable to find section `#…` in Note”. Tests: `SectionLinksOnPDFTests.testTheSectionIsDrawnAgainWhenTheNoteChangesAndNotOtherwise`, `testASectionIsDrawnAsThePageShowsItAndItsDigestFollowsTheNote`. Checked on an iPad simulator: typing in the note redrew the picture on the PDF beside it within a few seconds, and the saved file had the new picture. Done 2026-11-23: a note moved or renamed with its links updated takes the PDFs that link to it along: the index records a PDF's section pictures as links of the PDF (`PDFTypedAnnotationText.indexedText`, read again for every PDF by the index's migration `pdf-section-links-13`; backlinks list the PDF), and the move rewrites their addresses, through the session of an open PDF or in a closed PDF's file replaced atomically (`WorkspaceSectionLinkMoves`, `PDFPageManager.sectionLinkEdits`); a signed or locked PDF keeps its links and the move says so. A renamed heading is not followed, as Obsidian does not rewrite links to it either: the picture then says the section is missing. Tests: `SectionLinkTests.testAnAddressFollowsItsNoteToItsNewPlaceAndKeepsItsVaultAndHeading`, `PDFSectionLinkTests.testTheIndexReadsTheSectionsAPDFLinksTo`, `testOnlyTheSectionLinksARewriteNamesChange`, `SectionLinksOnPDFTests.testRenamingANoteRelinksAClosedPDFThatShowsItsSection`, `testRenamingANoteRelinksAnOpenPDFInPlace`, `VaultIndexMigrationsTests`.
- [ ] Other PDF readers show the picture and follow the link; Obsidian opens the note.
  2026-11-21: Quick Look draws the saved page with the section's picture, and Core Graphics reads the link's `/URI` (`PDFSectionLinkTests`). Left: following the link in Preview and in Obsidian.
- [x] Tests: the link's address read and written; the annotation saved and read back; a drop placing a link; a changed and a missing section.
  Done 2026-11-21: `SectionLinkTests` (5), `PDFSectionLinkTests` (3), `SectionLinksOnPDFTests` (5).
- [ ] Checked on the iPad (note and PDF in Split Right and Split Down, dragging with a finger and the Pencil) and on the Mac, and the saved PDF in Preview and Obsidian.

## Decisions

1. **The preview stays live** (owner, 2026-11-21: "obviously it would update"): editing the section redraws its preview on the PDF; it is never a snapshot frozen at the drop.
2. **Headings and blocks can be dragged** (default, 2026-11-21): a heading brings its section, any other block brings itself with a block ID; selected text links the block it starts in.
3. **Drags work from wherever a note shows** (default, 2026-11-21): the editor and reading view on either side of a split, another Graphite window, and the file tree for a whole note.
4. **Links follow renames; a deleted section says so** (default, 2026-11-21), as Obsidian treats links: a renamed or moved note is followed; a renamed heading is not, as in Obsidian (2026-11-23).
5. **A side opened again goes where the last split put it** (default, 2026-11-21): the direction is kept while there is one side, so Open to the Right or moving a tab after Split Down opens the side below. Obsidian's names for those commands are kept.
