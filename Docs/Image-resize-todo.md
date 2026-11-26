# Resize images by dragging their corner: implementation TODO

Created: 2026-11-16.

Status: sections 1 and 2 built and checked on 2026-11-16 (see their items). Issues: [#194](https://github.com/Graphite-Note/Graphite/issues/194) (section 1), [#195](https://github.com/Graphite-Note/Graphite/issues/195) (section 2).

## Request

Requested 2026-11-16, with a screenshot of a picture in a note whose bottom-right corner carries a resize handle: "cant seem to have the resize option on graphite", then "NOT THE WINDOW!!! THE IMAGES", on the Mac and the iPad. Obsidian draws such a handle on a picture in Live Preview; dragging it resizes the picture and writes its width into the embed, `![[picture.png|300]]`.

## What existed (2026-11-16)

Graphite already read Obsidian's size, `|300` or `|300x200` after the last `|` of an embed's label (`EmbedDisplaySize`), and drew the picture at it in the reading view and Live Preview. Nothing changed that size but typing it in the source.

## 1. Resize a picture on its own line in Live Preview

Issue: [#194](https://github.com/Graphite-Note/Graphite/issues/194)

- [x] A handle at the bottom-right corner of a picture on its own line, in Live Preview only (not the reading view, as in Obsidian). Done 2026-11-16: `EmbeddedImageResizeHandle` on `EmbeddedImageView`, given by `LivePreviewEmbedView` when the block can edit its source. The glyph is a corner like the system's window handle; on the Mac it shows while the pointer is over the picture and the pointer becomes the resize arrow; on the iPad it always shows, since a finger does not hover. The corner takes a drag before the hover shows it (found on the Mac: a quick press landed on the picture).
- [x] The picture follows the drag, keeps its shape, stays within the note's column and no narrower than 48 points; letting go writes the width, in whole points, into the embed as one edit that can be undone. Done 2026-11-16: `EmbedWidthEditing.settingWidth` writes `![[picture.png|W]]` or `![Caption|W](picture.png)`, keeping a caption, replacing a size already there height and all, and changing nothing else; it writes nothing when the line no longer embeds that picture. Through `RenderedBlockSourceEditing.replaceSource`, as a table's cells are written. Tests: `EmbedWidthEditingTests` (7), `EmbeddedImageResizeHandleTests` (4).
- [x] On the iPad a finger's drag on the corner resizes instead of scrolling the note. Done 2026-11-16: the handle takes touches with a UIKit view of its own (`ImageResizeTouchView`), which the editor's text view does not start its scroll for. Checked in the iPad simulator.
- [x] No progress indicator after letting go. Done 2026-11-16: the picture at its old width stands in, scaled, while it is made for the new width (`ReadingImageCache.latestThumbnail`). Test: `EmbeddedImageResizeHandleTests.testTheThumbnailAtAnotherWidthStandsInForTheNewWidth`.
- [x] Checked by hand, 2026-11-16: on the Mac, in a separate Debug copy of the app with a demo vault, a picture at `|300` dragged smaller wrote `|181` and dragged larger wrote `|486`, the text below following. On an iPad simulator (iPad Pro 11-inch, iOS 27.2), a finger drag wrote `|215` then `|345` without scrolling the note, and the toolbar's Undo and Redo went back to `|215` and to `|345`.

Not covered by this section: pictures inside a sentence's text drawn inline while the cursor is on their line, a picture in an embedded note or a callout, and VoiceOver's adjustable action on the handle beyond its declaration. ⌘Z on the Mac was not tried by hand (computer use could not make the editor the key window); the edit goes through the same text view path as a table cell's, whose undo is tested.

## 2. Resize pictures shown side by side

Issue: [#195](https://github.com/Graphite-Note/Graphite/issues/195)

Requested 2026-11-16, after section 1: "make it work for images side by side too".

- [x] Each picture of a line that shows several (`![[a.png|200]] ![[b.png|200]]`, with text between them or as a list item's) has its own corner handle, as a picture on its own line. Done 2026-11-16: `LivePreviewImageLineView` gives each picture's `LivePreviewEmbedView` a resize of its own, and `LivePreviewRenderedBlocks` gives an image line's block source editing.
- [x] The row is laid out again as a picture is dragged, the pictures beside it moving and wrapping as they would at that width; letting go writes the width into that picture's embed only. Done 2026-11-16: the dragged width goes up as a preference (`DraggedPictureWidthKey`) and the line offers the picture that width (`ImageLinePieceSizing.picture`); `EmbedWidthEditing.settingWidth(_:ofEmbedOf:at:in:)` writes the embed that starts where the picture's embed starts in the line, and nothing when another picture is there now. Tests: `EmbedWidthEditingTests` (3 more: one picture of three, a list item's picture after text, a picture no longer where it was).
- [x] Checked by hand, 2026-11-16: on the Mac, in a separate Debug copy with a demo vault, `![[a.png|150]] ![[b.png|150]] ![c|150](c.png)`: the middle picture dragged larger wrote `|261` and the third dragged smaller wrote `![c|84](c.png)`, the others unchanged and the row standing on its bottom edge. In an iPad simulator, a finger drag on the first wrote `|230` without scrolling the note, the others unchanged.

Not checked: a line whose pictures wrap onto a second row while one is dragged, a list item's line by hand, a physical iPad.
