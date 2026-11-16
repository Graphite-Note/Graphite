# Resize images by dragging their corner: implementation TODO

Created: 2026-11-16.

Status: section 1 built and checked on 2026-11-16 (see its items). Issue: [#194](https://github.com/Graphite-Note/Graphite/issues/194) (section 1).

## Request

The owner, 2026-11-16, with a screenshot of a picture in a note whose bottom-right corner carries a resize handle: "cant seem to have the resize option on graphite", then "NOT THE WINDOW!!! THE IMAGES", on the Mac and the iPad. Obsidian draws such a handle on a picture in Live Preview; dragging it resizes the picture and writes its width into the embed, `![[picture.png|300]]`.

## What existed (2026-11-16)

Graphite already read Obsidian's size, `|300` or `|300x200` after the last `|` of an embed's label (`EmbedDisplaySize`), and drew the picture at it in the reading view and Live Preview. Nothing changed that size but typing it in the source.

## 1. Resize a picture on its own line in Live Preview

Issue: [#194](https://github.com/Graphite-Note/Graphite/issues/194)

- [x] A handle at the bottom-right corner of a picture on its own line, in Live Preview only (not the reading view, as in Obsidian). Done 2026-11-16: `EmbeddedImageResizeHandle` on `EmbeddedImageView`, given by `LivePreviewEmbedView` when the block can edit its source. The glyph is a corner like the system's window handle; on the Mac it shows while the pointer is over the picture and the pointer becomes the resize arrow; on the iPad it always shows, since a finger does not hover. The corner takes a drag before the hover shows it (found on the Mac: a quick press landed on the picture).
- [x] The picture follows the drag, keeps its shape, stays within the note's column and no narrower than 48 points; letting go writes the width, in whole points, into the embed as one edit that can be undone. Done 2026-11-16: `EmbedWidthEditing.settingWidth` writes `![[picture.png|W]]` or `![Caption|W](picture.png)`, keeping a caption, replacing a size already there height and all, and changing nothing else; it writes nothing when the line no longer embeds that picture. Through `RenderedBlockSourceEditing.replaceSource`, as a table's cells are written. Tests: `EmbedWidthEditingTests` (7), `EmbeddedImageResizeHandleTests` (4).
- [x] On the iPad a finger's drag on the corner resizes instead of scrolling the note. Done 2026-11-16: the handle takes touches with a UIKit view of its own (`ImageResizeTouchView`), which the editor's text view does not start its scroll for. Checked in the iPad simulator.
- [x] No progress indicator after letting go. Done 2026-11-16: the picture at its old width stands in, scaled, while it is made for the new width (`ReadingImageCache.latestThumbnail`). Test: `EmbeddedImageResizeHandleTests.testTheThumbnailAtAnotherWidthStandsInForTheNewWidth`.
- [x] Checked by hand, 2026-11-16: on the Mac, in a separate Debug copy of the app with a demo vault, a picture at `|300` dragged smaller wrote `|181` and dragged larger wrote `|486`, the text below following. On an iPad simulator (iPad Pro 11-inch, iOS 27.2), a finger drag wrote `|215` then `|345` without scrolling the note, and the toolbar's Undo and Redo went back to `|215` and to `|345`.

Not covered by this section: pictures several to a line or inside text (`LivePreviewImageLine`, inline pictures), a picture in an embedded note or a callout, and VoiceOver's adjustable action on the handle beyond its declaration. ⌘Z on the Mac was not tried by hand (computer use could not make the editor the key window); the edit goes through the same text view path as a table cell's, whose undo is tested.
