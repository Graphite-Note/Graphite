# Zoom into images and open them in a new tab: implementation TODO

Created: 2026-10-22.

Status: section 1 built 2026-11-09 and completed 2026-11-11, section 2 built 2026-11-11 (see their items); hover, menus by hand and device checks open. Issues: [#76](https://github.com/Graphite-Note/Graphite/issues/76) (section 1), [#77](https://github.com/Graphite-Note/Graphite/issues/77) (section 2).

## Request

The owner, 2026-10-22: "Faut implementé le zoom in et le open in a new tab pour les images … specially in tables if you want to open a image to see it clearer by just zooming in (same window) or opening the image in a new tab, its really annoying right now." The screenshot shows the reference: a small magnifier button over an image with the tooltip "Zoom in".

So every image shown in a note offers two things, wherever it sits (its own line, inside a table cell, inline in a sentence, in a callout or an embedded note):

- **Zoom in**: look at the image larger without leaving the note.
- **Open in new tab**: open the image file as its own workspace tab, next to the note.

## What exists today (2026-10-22)

- An image on its own line in Reading view or Live Preview (`ReadingImageBlock` in `Sources/GraphiteUI/MarkdownPreview.swift`, the image widget in `Sources/GraphiteUI/LivePreviewWidgets.swift`) has a View action: on iPad and iPhone it sets `workspace.viewedImage`, which shows `ImageViewer` full screen (pinch and double-tap zoom, `ZoomableImageView` in `Sources/GraphiteUI/FilePreviewPane.swift`); on the Mac it opens Quick Look (`GraphiteRootView.swift`). Both cover the whole window instead of zooming in place, and neither offers a new tab.
- An image inside a table cell or inline in text is a text attachment (`VaultImageLoader` / `VaultImageAttachment` in `MarkdownPreview.swift`). It has no tap, hover or context-menu action at all: it can't be enlarged or opened. This is the case the owner hits most.
- Opening a file in a new tab already exists for vault entries (`VaultEntryAction.openInNewTab`, `workspace.open(_:placement: .newTab)`), and an image file opened that way shows in `FilePreviewPane`.

## 1. Zoom into an image in place

- [ ] A zoom control on every rendered image, block and inline alike, including images in table cells: a magnifier button that appears on pointer hover (Mac, iPad trackpad) and Pencil hover, and a long-press / context-menu "Zoom In" item on touch. Built 2026-11-09 for a picture on its own line (`EmbeddedImageView`: a tap, the magnifier while hovered, "Zoom In" in its menu). A picture inside text or a table zooms on a tap or click (the parser gives its run a `graphite://open?zoom=` link, and Live Preview's table cell editor leaves a tap on a picture to it), with no magnifier or menu item. The magnifier was not seen (hover cannot be driven in the background).
  Built 2026-11-11, not checked by hand: every picture now has the commands (`PictureCommand`: Zoom In, Open in New Tab, the other side). A picture inside text has them in VoiceOver's actions (`InlinePictureView`), in the text's own menu on a long press or secondary click (Textual patch 24, the iPad's edit menu, first in the Mac's text menu), in hover buttons in the reading view (`ReadingPictureHover`, from the link hover the text already reports, no tracking per picture), first in a Live Preview table's or callout's block menu (`RenderedBlockPictureMenu`), and in a Live Preview table's hover buttons (its one existing hover). Tested: `PictureActionsTests` (Mac), and the hosted test below for VoiceOver's actions; the hover, the menus and the long press were not driven.
- [x] Zoom happens in the same window over the note, as in the owner's reference screenshot of 2026-10-24 (Obsidian's image zoom): a "Zoom" magnifier button with its tooltip at the image's top-right corner, then the image fitted to the whole window over a black backdrop with the app dimmed behind it, the file name centered at the top and a close button at the top-right. Not a separate full-screen cover or Quick Look window. Pinch, double-tap and scroll-wheel/trackpad zoom, drag to pan, Escape, a tap outside or the close button returns to the note at the same scroll position. Done 2026-11-09: `ImageZoomOverlay` over the root view replaces the iPad's full-screen cover and the Mac's Quick Look window. Seen in a Debug copy of the Mac app (a block picture and a table picture in Live Preview; Escape and the close button close it, the note keeps its place) and the iPad simulator (a picture in a sentence and in a table in the reading view; a tap on the fitted picture closes it). Pinch, double-tap and trackpad zoom use the existing `ZoomingImageScrollView` and the new `MagnifyingImageScrollView` (`ImageZoomOverlayMacTests`); not tried by hand.
- [x] The zoomed image is decoded at a resolution fit for the zoom level (the table cell thumbnail is too small to enlarge), with the existing `ImageFileService.displayImage(at:maximumPixelDimension:)` bound so huge images don't spike memory. Done 2026-11-09: the zoom decodes the file itself, up to 4,096 pixels on its longer side (`ImageZoomOverlay.maximumPixelDimension`).
- [ ] Works in Reading view and Live Preview, in tables, callouts, embedded notes and canvas cards; Draw on Image stays reachable from the zoomed view where it is today.
  2026-11-11: the same `ReadingImageActions` reach the reading view (callouts and embedded notes are drawn in it), Live Preview's rendered blocks and canvas cards, and the zoom still offers Draw on Image (`ImageZoomOverlay`, unchanged). Tested in the reading view only (hosted); Live Preview's hosted test (`testATablePictureInLivePreviewHasItsCommandsInTheTablesMenuAndOpensInANewTab`) was not seen passing; callouts, embedded notes and canvas cards not tried.
- [x] Tests: hosted tests that an image in a table cell and an inline image expose the zoom action and present the zoomed view; a check that the note's scroll position survives zooming in and out.
  Done 2026-11-11: `PictureZoomAndTabHostedTests.testATableCellPictureAndAnInlinePictureZoomOverTheNoteWhichKeepsItsPlace` (iPad simulator): both pictures offer Zoom In, Open in New Tab and the other side; Zoom In shows the zoom (its title and close button); closing it leaves the scrolled note at the same offset. A simulator screenshot during the run showed the table's picture zoomed over the note.
- [ ] Checked on the iPad (finger, Pencil hover, trackpad) and on the Mac (pointer, trackpad pinch, Escape).

## 2. Open an image in a new tab

- [ ] "Open in New Tab" on every rendered image (same places as section 1): in the hover controls next to the magnifier, and in the long-press / context menu, alongside "Open on Other Side" where split panes exist.
  Built 2026-11-11 with section 1's commands (`PictureCommand`, `PictureHoverButtons`): in every place listed there, with the other side under the file tree's wording. Tested through VoiceOver's actions (hosted) and `PictureActionsTests`; the hover buttons and the menus were not driven.
- [x] The tab shows the image file through the existing image tab (`FilePreviewPane`), zoomable, with the image's file name as the tab title; the note's tab stays open and unchanged.
  Done 2026-11-11: the commands call `workspace.open(_:placement: .newTab)` (`WorkspaceModel.pictureTabOpening`), so the tab is the image tab (`ImagePane`). `testOpenInNewTabOnATableCellPictureAndABlockPictureOpensTheirFilesBesideTheNote` checks the tab's title ("Scan.png"), the picture shown in it and the note's tab kept; its screenshot shows the picture in its tab beside "Lecture.md".
- [ ] Command-click (Mac, iPad keyboard) on an image opens it in a new tab directly, as for links.
  Built 2026-11-11, not tried: a picture inside text opens on ⌘-click on both platforms (Textual patch 24 passes the click's modifier keys; ⌥⌘ other side and ⇧⌥⌘ new window, as `TabPlacement.forLink`); a picture on its own line and one in a Live Preview table only on the Mac, since SwiftUI gives the iPad's taps no modifier keys. `PictureActionsTests` covers the placements; no click was made.
- [x] Images outside the vault (web URLs) either open in a tab that shows them or offer only Zoom In; never a broken tab.
  Done 2026-11-11: a web picture is not drawn from the vault and gets no zoom link, so it offers no command and never opens a tab. `PictureActionsTests.testThePictureLinkOfATextHasThePicturesMenuAndOtherLinksHaveNone` and `PictureZoomAndTabHostedTests.testAWebPictureInATableOffersNoTab`.
- [x] Tests: hosted tests that the action on a table-cell image and a block image calls `workspace.open(_:placement: .newTab)` with the image's vault path, and that a web image doesn't.
  Done 2026-11-11: `PictureZoomAndTabHostedTests` (iPad simulator, 3 passing): the table's picture and the picture on its own line each open their vault path in a new tab; the web picture offers none and no tab opens.
- [ ] Checked on the iPad and the Mac with the owner's table-heavy notes.
