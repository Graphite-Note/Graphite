# Split down and section links on PDFs: TODO

Created: 2026-11-21.

Status: planned 2026-11-21; nothing built. Request: [#220](https://github.com/Graphite-Note/Graphite/issues/220). Issues: [#221](https://github.com/Graphite-Note/Graphite/issues/221) (section 1), [#222](https://github.com/Graphite-Note/Graphite/issues/222) (section 2).

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

- [ ] `TabLayout` and `SavedTabLayout` keep the split's direction (side by side or one above the other); a saved layout without one reads as side by side. The fraction is the first group's share of the width or the height.
- [ ] Split Down, as Obsidian names it: in the palette, the menu bar's View menu, the tab menu and Settings › Keyboard Shortcuts, beside Split Right. Choosing the other one on a split layout turns the split, keeping both sides' tabs.
- [ ] `WorkspacePanes` lays the sides out top and bottom with a horizontal divider that is dragged up and down (`SplitDividerDrag` in height), within the same 0.25 to 0.75.
- [ ] Each side's toolbar and tab bar are decided by its own size; a document's controls never sit under the other side (the thresholds of invariant U-02 read width, which both sides now share).
- [ ] A touch focuses the side it lands on; the focused side is marked as it is side by side.
- [ ] The divider snaps to a display's fold only where the fold runs across the window, so a side-by-side fold keeps the split side by side.
- [ ] In a compact window only the focused side shows, as today.
- [ ] The Guide and the Welcome tour name Split Down.
- [ ] Tests: the layout's direction, its saving and reading, turning a split; the panes' layout top and bottom; the divider drag in height.
- [ ] Checked on the iPad in portrait (a PDF above a note, writing in both), in landscape and with Stage Manager windows, and on the Mac.

## 2. Section links on PDF pages

Issue: [#222](https://github.com/Graphite-Note/Graphite/issues/222)

Open questions, to settle with the requester and the owner before building:

- What is dragged: a heading (its whole section), a block (`^id`), selected text, or an embed already in the note?
- Is the preview drawn again when the section changes, or kept as it was when dropped?
- Does it work only with the note and the PDF side by side, or also from the sidebar, the file tree and another app's window?
- What does a link show when its section is renamed or deleted?

Items:

- [ ] Settle the questions above; record the answers under Decisions.
- [ ] A note's heading or block can be dragged out of the editor (Source and Live Preview) and the reading view, carrying its link (`[[Note#Heading]]` or `[[Note#^block]]`) and its text.
- [ ] A PDF page accepts the drop where it lands, and places a section link there: a `/Link` annotation to the section (an `obsidian://open` link with the vault, the file and the heading, read back by `VaultURI`) whose appearance is a picture of the section as the reading view draws it, at most 60% of the page, selected after it is placed.
- [ ] A section link is moved, resized and deleted like a picture, taken by the lasso with ink, pictures and text boxes, and every step is in the PDF's undo history.
- [ ] Tapping a section link opens the section on the other side, or in the PDF's side when there is none.
- [ ] The preview follows the section as decided above; a missing section says so on the link instead of a stale picture.
- [ ] Other PDF readers show the picture and follow the link; Obsidian opens the note.
- [ ] Tests: the link's address read and written; the annotation saved and read back; a drop placing a link; a changed and a missing section.
- [ ] Checked on the iPad (note and PDF in Split Right and Split Down, dragging with a finger and the Pencil) and on the Mac, and the saved PDF in Preview and Obsidian.

## Decisions

None yet.
