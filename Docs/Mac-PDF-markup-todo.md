# Marking up PDFs on the Mac: TODO

Created: 2026-11-11.

Status: planned 2026-11-11; section 1 (the markup row and text markup) built and checked on the Mac 2026-11-11, except on the iPad and in Preview itself; 2026-11-13 the row lays its choices out (section 1's last item), and Draw with the eraser (section 5) and Text Box (section 2) are built and tested in the package, not yet checked by hand; sections 3, 4 and 6 not started. Issues: [#150](https://github.com/Graphite-Note/Graphite/issues/150) to [#155](https://github.com/Graphite-Note/Graphite/issues/155), one per section. The Mac's PDF viewer (`GraphitePDFView` for AppKit, `GraphiteMacPDFView`) shows a PDF and its annotations but has no tool to add or change any: no highlight, no text box, no ink.

## Request

The owner, 2026-11-11, with a screenshot of Preview's markup toolbar: "i want to be able to highlight and what not when im on mac like on mac preview". Shown three layouts, the owner asked that the Mac and iPad UI "be abit different" and that it look like a desktop app, not a touch one, then chose:

- **Layout: A, the markup row** as Preview has it: a markup button in the PDF's toolbar shows a second row of tools under the toolbar, and hides it again.
- **Tools:** highlight colours, underline, strikethrough, recolouring or removing marks, text boxes, notes, shapes, freehand drawing and signatures.

## What the result must be

- **Ordinary PDF.** Every mark is a standard PDF annotation with its own appearance, stored in the PDF the way the iPad stores its ink, pictures, text boxes and markup, so Preview, Acrobat, Files and Obsidian show it (OBJECTIVE.md). No sidecar and no app database.
- **The same file on both devices.** What the Mac adds, the iPad shows and edits with its own tools, and the other way round, wherever the iPad has a tool for it.
- **A Mac interface.** Pointer, keyboard, right-click menus, the menu bar and shortcuts; small toolbar controls; nothing sized for a finger. The iPad keeps its Pencil palette, fixed bar and touch menus unchanged.
- **One history.** Every mark is a step of the PDF's undo history (`PDFEditHistory`), undone with ⌘Z and the toolbar's Undo, as on the iPad.
- **Locked files stay locked.** A PDF that is protected by a password or digitally signed (`PDFSession.isProtected`) shows the markup button with the reason it is off, as its banner says today.
- **No inert tools.** The row shows only tools that are built; each later section adds its own.
- **Off costs nothing.** The row and its tools are made when the markup button is first turned on in a PDF, not when the PDF opens.

## Decisions

1. **Layout A** (owner, 2026-11-11), not a highlight button alone (B) or an inspector at the side (C).
2. **Highlight works like Preview's**: with the highlight tool chosen in the row, every text selection is marked with the current style when the mouse is let go; the button's arrow chooses the style (colours, underline, strikethrough). With the selection tool chosen, selected text is marked from the right-click menu or the menu bar.
3. **The markup storage the iPad already has is reused**: `PDFSession.addMarkup`, `recolorMarkup` and `removeMarkup`, the `PDFEdit` cases behind them and their undo steps. The decisions of what a click or a selection does are shared types tested with plain values (FR-05, FR-06); only the AppKit event handling is the Mac's own.
4. **Shortcuts follow Preview where it has one**: View › Show Markup Toolbar ⇧⌘A, Tools › Annotate › Highlight Text ⌃⌘H and Underline Text ⌃⌘U. Strikethrough Text has no default: Preview's ⌃⌘S is the Mac's Show Sidebar in Graphite. All four are commands of Graphite's command list (group PDF, Mac only), so Settings › Keyboard Shortcuts and a vault's `hotkeys.json` can change them.

## 1. The markup row and text markup

Issue: [#150](https://github.com/Graphite-Note/Graphite/issues/150)

- [x] A markup button in the PDF's toolbar (pen in a circle, filled with the accent while on) shows and hides the markup row under the toolbar; ⇧⌘A and a View menu item do the same. The row is per PDF pane and starts hidden. Done 2026-11-11: `PDFMarkupToolbarButton`, `PDFMarkupToolbarRow`, `PDFMarkupToolbar`; `PDFMarkupToolbarTests`; checked by hand in a copy of the Mac app.
- [x] The row's first tools: Text Selection and Highlight. Highlight is a split button: a click chooses the tool and marks the current selection; its arrow opens a menu of the highlight colours, Underline and Strikethrough, with the current one ticked. The style chosen is kept on the device. Done 2026-11-11: `PDFMarkupStyle` under `GraphitePDFMarkupStyle`; `PDFMarkupStyleTests`; checked by hand.
- [x] With Highlight chosen, letting go of the mouse after selecting text marks it with the current style; the selection is cleared and the mark is one undo step. Done 2026-11-11: `MacPDFMarkupInteraction.mouseUpFinished`, also after PDFKit's own drag loop; `MacPDFMarkupInteractionTests.testTheHighlighterMarksTheSelectionWhenTheMouseIsLetGo`; checked by hand.
- [x] Right-clicking selected text gives Copy, Highlight (colours), Underline and Strikethrough, and the link commands the iPad's selection menu has. Done 2026-11-11: the items come before PDFKit's own (Look Up, Copy, zoom); Copy is PDFKit's. `testRightClickingSelectedTextOffersTheMarksAndLinksBeforePDFKitsItems`; checked by hand (Underline from the menu).
- [x] Clicking or right-clicking a mark offers its colours and Remove; Delete removes a selected mark. Marks other applications made are recoloured and removed the same way. Done 2026-11-11: a click selects exactly the mark's text and gives the PDF the keyboard; the right-click menu ticks its colour. `testRightClickingAMarkRecoloursOrRemovesIt`, `testAClickSelectsAMarkAndDeleteRemovesIt`; click and Delete checked by hand (the right-click menu of a mark only in tests). Found on the way: Edit › Undo and ⌘Z never reached a PDF's history on the Mac, only the toolbar's Undo; the PDF view now answers them (`testEditUndoAndRedoReachThePDFsHistory`, checked by hand). They stay enabled while the PDF has the keyboard, as PDFKit's menu validation enables actions it does not know.
- [x] The menu bar has the same commands, with the shortcuts of decision 4, enabled only when they can act. Done 2026-11-11: View › Show Markup Toolbar and Tools › Annotate (`PDFMarkupMenuActions`, `GraphiteCommand` group PDF); `GraphiteCommandTests`, `KeyboardShortcutsPageContentTests`; checked by hand (View's title follows the row, ⌃⌘H marks the selection).
- [x] Protected and signed PDFs: the markup button says why it is off. Done 2026-11-11: the button is dimmed with that help text and the row is not shown; `testAProtectedPDFTakesNoMarks`. Not tried by hand with a protected PDF.
- [ ] Tests: the shared decisions with plain values; the Mac view's handling of a selection, a click on a mark and the menus; undo of each step. Checked by hand in a copy of the Mac app, and the marks opened in Preview and on the iPad. 2026-11-11: tests done (37 passing), the Mac app checked by hand, and the saved file read back (standard `/Highlight` and `/Underline` with `/QuadPoints`, drawn by Quick Look). Second pass 2026-11-11, in a Debug copy of main 145134a3 with a generated two-page lecture and a password-protected copy: ⇧⌘A, Strikethrough chosen from the arrow and drawn by dragging, a mark's right-click menu (its colour ticked, recoloured to Blue, then Remove Strikethrough), PDFKit's Zoom Out, and the protected PDF (banner, the markup button dimmed with its tooltip, View › Show Markup Toolbar dimmed, no marks in the right-click menu of selected text). On an iPad Pro 11-inch simulator (iOS 27.2) the Mac's two highlights showed where the Mac drew them, and the iPad's own menu recoloured one to Green and Undo gave it back. Found and fixed: the Underline and Strikethrough icons of the highlight button's menu were black on the dark menu (`PDFMarkupToolbarRow.styleIcon`). Seen, not changed: the right-click menus show no icons beside Graphite's items, while Apple's Look Up and Translate show theirs; on this test file, made by `cupsfilter`, PDFKit reports lines 27 points tall around 7-point letters, so a strikethrough runs under the words (ordinary fonts measured within 2 points). Still to do: open a file marked on the Mac in Preview itself (access to Preview was declined), and the iPad's selection menu by Pencil on a device (the simulator's long press did not start a selection).
- [ ] The row shows its choices instead of hiding them in menus (the owner, 2026-11-13, with a screenshot of the highlight button's menu of Yellow, Green, Blue, Pink, Purple, Underline and Strikethrough: "horrible interface, a lot of screen real estate available and we still chose to use a menu, also free hand drawing with a mouse or stickers for signatures etc could be an option but nooooo all in one place.. also text boxes etc"). The highlight colours are swatches in the row, Underline and Strikethrough are buttons of their own, and the row gives each tool of sections 2 to 6 (text box, note, shapes, draw, sign) its own button as each is built, folding into a menu only where the window is too narrow for them.
  Done 2026-11-13: the row (`PDFMarkupToolbarRow`, `PDFMarkupRowContent`) shows Text Selection; a swatch per highlight colour, ringed while in use, then Underline and Strikethrough buttons, each click choosing the mark, marking the selected text and leaving the highlighter on; Draw and Eraser; Text Box; then the chosen tool's choices (`PDFMarkupRowOptions.swift`: ink colours and three line widths, or the text controls). `ViewThatFits` takes the first of four layouts that fits (`PDFMarkupRowFolding`): the choices fold into menus first, then the highlight colours, then the tools into one menu. The shortcuts and Tools › Annotate are unchanged. Tests: `PDFMarkupToolbarRowTests` (each folding narrower, the unfolded row under 1,000 points, the most folded under 440), `PDFMarkupToolbarTests`, `MacPDFMarkupInteractionTests`. Looked at: renderings of the row in light and dark at 1,100, 760, 560 and 360 points with Highlight, Draw and Text Box chosen (`PDFMarkupToolbarRowTests.testScreenshotsOfTheRow`); found and fixed there, the folded menus' colour and width labels drawn as SwiftUI shapes did not show, now images. Not checked in the running app: the check by hand in the re-signed copy was stopped before the row was opened.

## 2. Text boxes on the Mac

Issue: [#151](https://github.com/Graphite-Note/Graphite/issues/151)

- [x] A Text Box tool in the row: a click on a page places a box with the last-used look (`PDFTextBoxDefaults`) and starts typing in it.
  Done 2026-11-13: `MacPDFTextBoxTool` over the PDF view's tool surface (`MacPDFToolSurface`, `MacPDFPageTools`), typing in `MacPDFTextBoxEditor`, an `NSTextView` in the PDF's scrolling document at the box's place and zoom; boxes change only through the session's text box model the iPad uses (`PDFSessionTextBoxes.swift`), and `PDFTextBoxTextConversion` now serves both platforms. `MacPDFPageToolsTests.testAClickPlacesABoxToTypeInAndAClickAwayCommitsItAsOneStep`.
- [ ] Select, move, resize, delete and duplicate a box with the pointer and the keyboard; double-click to type; Escape ends typing.
  Built 2026-11-13: a click selects (`PDFTextBoxPointerPress`), a drag moves, a handle at each side along the text resizes (`PDFTextBoxPointerDrag`), Delete, ⌘D, Return, Escape and the arrow keys (Shift for ten points), and a right-click menu of Edit Text, Duplicate and Delete. Tested: `testABoxIsSelectedMovedFormattedDuplicatedAndDeleted`, `testADoubleClickTypesInABoxAndEscapeLeavesItSelected`, the decisions in `PDFPointerInkTests`; resizing by a handle is tested only as the decision, not through the view, and nothing was checked by hand.
- [ ] The row's text style control (font, size, colour, faces, alignment, fill, border) acts on the selected box, as the iPad's format popover does.
  Built 2026-11-13: `PDFMarkupTextFormatControls` in the row, formatting the box through `PDFSession.applyTextBoxFormat`, or the next box's look when none is selected. Tested: Bold through `applyTextBoxFormat` on a selected box; the controls themselves only seen in renderings.
- [x] Each step is one undo step, with the same names as on the iPad.
  Done 2026-11-13: Add Text Box, Edit Text, Move Text Box, Resize Text Box, Format Text, Duplicate Text Box and Delete Text Box, the iPad's names; typing keeps its own history until it ends. `MacPDFPageToolsTests` (the names of adding, editing, moving and duplicating, and undo of each).
- [ ] Tests, and checked by hand with a box made on the Mac edited on the iPad and in Preview, and the other way round.

## 3. Notes

Issue: [#152](https://github.com/Graphite-Note/Graphite/issues/152)

Graphite has no notes today: the text boxes' decision 2 (`PDF-text-boxes-todo.md`) left them out, and notes other applications made stay in the file untouched.

- [ ] A Note tool in the row places a note (a standard `/Text` annotation with its `/Popup`) where the page is clicked and opens it to type.
- [ ] Clicking a note's icon opens it to read and edit; it can be moved, recoloured and deleted. Notes made by Preview and Acrobat open and edit the same way.
- [ ] The iPad shows notes and opens them to read (editing them on the iPad is its own item, to be decided).
- [ ] Search and the index find a note's text.
- [ ] Tests, golden fixtures for the written annotation, and checked in Preview and Acrobat Reader.

## 4. Shapes

Issue: [#153](https://github.com/Graphite-Note/Graphite/issues/153)

- [ ] A Shapes menu in the row: rectangle, oval, line and arrow, drawn by dragging on a page, stored as standard `/Square`, `/Circle` and `/Line` annotations with appearances.
- [ ] The row's border colour, fill colour and line width controls act on the selected shape and on the next one.
- [ ] Select, move, resize and delete a shape; each step is one undo step.
- [ ] The iPad shows them; whether it edits them is decided with the owner.
- [ ] Tests, and checked in Preview and on the iPad.

## 5. Freehand drawing with the mouse and trackpad

Issue: [#154](https://github.com/Graphite-Note/Graphite/issues/154)

- [x] A Draw tool in the row: dragging on a page draws ink, stored as the iPad's ink is (`PDFInkUpdate` with `PortableInkStroke`s), so the iPad edits it with PencilKit.
  Done 2026-11-13: `MacPDFPointerInkTool` turns the pointer's places into a PencilKit pen stroke in the page's drawing space (`PDFPointerInk`) and adds it to the page's editable ink group through `PDFPageInkTracker` (`PDFSessionPointerInk.swift`), writing the re-editing record at once. `MacPDFPageToolsTests.testAStrokeDrawnWithTheMouseIsTheIPadsEditableInkAndOneUndoStep` (the group restores as the iPad's canvas restores it) and `testInkDrawnOnTheMacIsSavedAsEditableInk` (saved, read back from the file). Not yet opened on an iPad.
- [x] Colour and line width from the row; an eraser that removes whole strokes.
  Done 2026-11-13: black and the favourite colours of Settings › Colors, Fine, Medium and Bold (1, 2.5 and 5 points), kept on the device (`PDFMarkupInkStyle`); the eraser removes each stroke it passes, also between two far places of a fast pointer. `PDFPointerInkTests`, `testTheEraserRemovesWholeStrokesItPassesAsOneStep`.
- [ ] Each stroke is one undo step; the ink appears at the screen's resolution at any zoom.
  One step per stroke and one per pass of the eraser, named Drawing as on the iPad, done 2026-11-13 (the history's ink steps now run on the Mac too, `PDFEditHistory`, `PencilDrawingChange`). The ink is the iPad's outlined annotation, which the Mac draws at the screen's resolution (`PDFAnnotationLayerResolution`), but that was not checked at several zooms.
- [ ] Tests, and checked on the iPad and in Preview.

## 6. Signatures

Issue: [#155](https://github.com/Graphite-Note/Graphite/issues/155)

- [ ] A Sign menu in the row lists the signatures kept on this Mac and Create Signature, which draws one with the trackpad or mouse in a sheet.
- [ ] Choosing a signature places it on the page as ink (vector, like section 5); it can then be moved and resized.
- [ ] Signatures are kept on the device, outside the vault, and can be deleted from the menu.
- [ ] Tests, and checked in Preview and on the iPad.
