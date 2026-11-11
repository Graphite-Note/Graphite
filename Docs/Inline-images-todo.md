# Images side by side on one line: implementation TODO

Created: 2026-10-24.

Status: section 1 built and tested on the Mac and the iPad simulator (2026-11-05 under HUNT-323, finished 2026-11-11); the check with the owner's note on his devices is open. Issue: [#102](https://github.com/Graphite-Note/Graphite/issues/102) (section 1).

## Request

The owner, 2026-10-24, with screenshots of the note "Butter-basted steak.md": "![] are not showing properly". Its Photos section writes several image embeds on one line, as Obsidian users do to put photos side by side:

```
![[IMG_3599.jpg|300]] ![[IMG_3598.PNG|200]]

![[IMG_6652.JPG|250]] ![[IMG_6653.JPG|250]] … ![[IMG_6661.JPG|250]]
```

Graphite shows each as link-colored text, `IMG_3599.jpg|300`, the width included, wrapping in the middle of a name (`IMG_6656.JPG|` / `250`). Obsidian shows the images, each at its width, side by side and wrapping to the next row.

## What exists today (2026-10-24)

- Live Preview draws an embed as an image only when it is alone on its line: `EmbedLocator.standaloneEmbed(onLine:)` (`Sources/GraphiteCore/EmbedLocator.swift`, called from `Sources/GraphiteCore/LivePreviewBlocks.swift`). Any other embed is styled like a link (`MarkdownTextStyler`, `case .link, .embed`): its `![[` and `]]` are hidden, its target and size stay as text.
- Reading view already turns a resolved inline image embed into an inline image (`prepared` in `Sources/GraphiteUI/MarkdownPreview.swift`, drawn by `VaultImageLoader` / `VaultImageAttachment` with `EmbedDisplaySize`); an embed the index has not resolved yet is shown as a link until it does.

## 1. Draw inline image embeds as images

Issue: [#102](https://github.com/Graphite-Note/Graphite/issues/102)

- [x] Live Preview draws an image embed that shares its line with text or other embeds as an inline image at its size (`|300`, `|300x200`), images side by side and wrapping to the next row as in Obsidian; wiki (`![[a.jpg|300]]`) and Markdown (`![300](a.jpg)`) forms alike, any extension case (`.JPG`, `.PNG`).
  Done 2026-11-11: built 2026-11-05 under HUNT-323 (`LivePreviewBlock.Kind.imageLine`, `EmbedLocator.imageLinePieces(onLine:)`, `LivePreviewImageLineView` with `ImageLineFlowLayout`). `UiLivePreviewImageLineTests` (the owner's nine `.JPG|200` drawn three to a row at 700 points, `|200x150`, `![Wide|200](Wide.png)` beside a wiki embed, text and pictures in order) passed on the Mac; `InlineImagesSideBySideHostedTests.testLivePreviewDrawsEveryPictureOfTheNoteOnceTheIndexHasReadTheVault` passed on the iPad simulator (`|300` and `|200` on one row, ten `|250` two to a row, `.jpg`, `.PNG`, `.JPG`), screenshot looked at.
- [ ] The size suffix and the file name never show as text; the cursor on an embed shows that embed's source only, as today for the first one in the screenshot.
  Partly built 2026-11-11: while the cursor is elsewhere the line is one block that shows no size or name as text (`UiLivePreviewImageLineTests.testTheSourceShowsWhileTheCursorIsOnTheLineAndThePicturesOtherwise`, and no such text in the hosted test's Live Preview screenshots). Open: the cursor anywhere on the line shows the whole line's source, every embed of it, not only the embed it is in; a picture's own source alone would need the block to be cut at each embed.
- [x] Reading view checked with the same note: every image of the Photos section drawn, none left as a link once the index has read the vault.
  Done 2026-11-11: checked with a made-up note of the same shape (the owner's two lines with his widths and extensions, pictures in an `Attachments` folder only the index finds), not the owner's note. Found while checking: a Markdown image in a table cell with an escaped pipe (`![Done\|100](../Attachments/Done.png)`) stayed its alt text, since the parser's columns after the escape are one short; the reading view now finds it from where it starts (`ReadingViewBuilder.writtenImageRange`). `InlineImagesSideBySideHostedTests.testTheReadingViewDrawsEveryPictureOfThePhotosSectionOnceTheIndexHasReadTheVault` (iPad simulator: links before the index reads the pictures, then all 19 pictures drawn at their widths, none a link) and `UiReadingInlineImagesTests` (Mac) passed; screenshots looked at.
- [x] Inline images in table cells, list items and callouts drawn the same way in both views.
  Done 2026-11-11: a list item that embeds images (`- ![[a.jpg|120]] ![[b.jpg|120]]`, numbered too, nested items kept at their indentation) is an image line in Live Preview with its bullet or number before the pictures (`ImageLinePiece.listMarker`, `ImageLineListMarkerView`), the rows they wrap onto under the first picture; a task, a quoted item and indented code keep their text. Live Preview's tables and callouts, drawn by the reading view's renderer, now also turn Markdown images into vault pictures (`EmbedLocator.markdownEmbeds(in:)`; they were looked up as web addresses and not drawn), and a table with pictures looks them up again when the index changes (`LivePreviewWidgetSignature.readsIndex`): a table opened before the index had read its pictures kept one as `![[Seared.png|100]]` text. Tests: `LivePreviewImageListItemTests` (6, Core), `UiLivePreviewImageLineTests` (list item bullet and number drawn and wrapping, Markdown images in a table), `UiEditorRenderedBlockReuseTests`, both hosted tests above; screenshots of the list item, table and callout in both views looked at.
- [x] Thumbnails decoded off the main actor at their displayed size, through the existing image cache, so a row of ten 250-point photos scrolls without slow frames and without decoding the full camera images.
  Done 2026-11-11: Live Preview's pictures were already decoded for their width (`ReadingImageCache`, `.block`). A picture inside text (the reading view, Live Preview's tables and callouts) was decoded at the inline limit, 1,800 pixels, whatever its `|width`; `VaultImageLoader` now decodes one given a width for that width at the screen's scale (750 pixels for 250 points at 3x), one without a width keeping the limit, as it is laid out at its pixel size. Measured in `UiInlineImageDecodeSizeTests` (Mac): ten 3,000 by 2,250 JPEGs at `|250` in a Live Preview line are each decoded 250 points times the window's scale wide and never whole; the same in a table cell, which failed before the change; one without a width at 1,800. Slow frames while scrolling were not measured.
- [x] Tests: Core tests that a line of several embeds yields inline image ranges with their sizes; hosted tests that Live Preview and reading view draw two side-by-side embeds as image attachments, not link text.
  Done 2026-11-11: `UiLivePreviewImageLineTests` and `LivePreviewImageListItemTests` (pieces, sizes and ranges), `InlineImagesSideBySideHostedTests` (2, iPad simulator).
- [ ] Checked on the Mac and the iPad with the owner's "Butter-basted steak.md".
  Not done: needs the owner's note on his Mac and iPad.
