# Web pages in notes (`<iframe>`): TODO

Created: 2026-11-12.

Status: 2026-11-12, sections 1, 2 and 5 built and tested; sections 3 and 4 built, with the checks that need a device or VoiceOver open; section 6 open. Checked on the Mac the same day, in a Debug copy of main 7c10f109 with its own bundle identifier, a demo vault written for the check and the dark appearance: frames load, scroll and take input; the note does not scroll on past a page's end, and the owner's grapher's Draw button is covered by the page's own graph (see the items). The same day a failed frame's message, invisible in the dark appearance, and YouTube's Error 153 were fixed. Issues: [#156](https://github.com/Graphite-Note/Graphite/issues/156) to [#161](https://github.com/Graphite-Note/Graphite/issues/161), one per section.

Graphite draws notes natively and has no web embeds: an `<iframe>` in a note is shown as the text it is written with, in the reading view and in Live Preview, on every device. Only a handful of inline HTML tags are translated (`ReadingInlineHTML`: `<mark>`, `<u>`, `<sub>`, `<sup>`, `<kbd>`, `<b>`, `<i>`, `<s>`, `<br>`, comments). Obsidian draws a note's HTML in its web view, so the same note shows the page there.

## Request

The owner, 2026-11-12, with screenshots of the same note in both applications (`ETH_Computer_Architecture/HW/HW3/4_Amdahl's Law in the Multicore Era`): "idk why its not working on graphite, works on obsidian", then "Plan iframe embeds". The note has, on a line of its own:

```html
<iframe src="https://research.cs.wisc.edu/multifacet/amdahl/" width="100%" height="900" style="border:1px solid #ccc; border-radius:6px"></iframe>
```

Obsidian shows the live page at the note's width, 900 points tall, with a 1-point grey border and rounded corners; the page scrolls inside its frame, and its form and its Draw button work. Graphite shows the line as text, and colours `#ccc` inside the tag as a tag.

## What the result must be

- **The note is not changed.** The `<iframe>` stays as written; Graphite reads it, as Obsidian does. Nothing is stored beside the note (OBJECTIVE.md, ordinary files).
- **The page as Obsidian shows it**: the address of `src`, the width and height the tag gives, the border and corner radius of its `style`, and the page live inside its frame (its scripts run, its forms and links work, it scrolls inside the frame).
- **Reading view and Live Preview, on the iPad, the iPhone and the Mac.** Source mode shows the text.
- **A frame costs nothing until it is seen.** No web view is made when a note opens; a frame loads its page when it comes near the screen and gives its web view up when it is far from it, so a note with many frames, or a long note scrolled past one, holds only the pages near the screen (OBJECTIVE.md, scale and responsiveness; lean core). A note without frames pays nothing.
- **The page cannot reach the vault or the app.** The web view has no access to files, no messages to Graphite and no plugin runtime; it is not the community plugins' web view.
- **No inert frame.** A page that cannot load (offline, refused address, blocked from embedding) says so in the frame, with its address and a button to open it in the browser.

## Decisions

1. **Web addresses only.** A frame is drawn for an `src` that is an `https:` or `http:` address. Any other `src` (a vault path, `file:`, `javascript:`, `data:`), and an `<iframe>` with no `src`, stay text as today, until a later section decides otherwise. Obsidian's handling of vault paths in `src` is to be checked before that.
2. **The page loads by itself when it comes near the screen**, as in Obsidian, with no tap to load. Recorded here as the default chosen while planning; the owner may choose tap-to-load instead before section 3 is built.
3. **Only `<iframe>`.** Other HTML blocks (`<div>`, `<video>`, `<details>`, tables written in HTML) stay as they are drawn today. Graphite does not become an HTML renderer (no web view for the note's text, as Export to PDF also decided).
4. **The frame's look comes from the tag**: `width` (points or a percentage of the note's width), `height` (points), and from `style` only `border`, `border-radius`, `width` and `height`. Without a `height` the frame is 150 points tall, as a browser makes it; without a `width` it is 300 points wide, capped at the note's width. Any other style is ignored.
5. **One small web view per frame, from Apple's WebKit (`WKWebView`)**, with a website data store of Graphite's own shared by every frame, so a site remembers what it remembers in a browser (cookies, settings), apart from the community plugins' store. Links the page opens in a new window (`target="_blank"`, `window.open`) open in the system browser; navigation inside the frame stays in the frame.

## 1. Tags inside HTML stay text

Issue: [#156](https://github.com/Graphite-Note/Graphite/issues/156)

- [x] `#ccc` (or any `#word`) inside an HTML tag or an HTML block is not coloured or linked as a tag in the reading view; the tag pass skips HTML runs (`inlinePresentationIntent` `.blockHTML` or `.inlineHTML`) as it skips links and code (`MarkdownPreview.swift`, where tags are coloured, `isCode`).
  Done 2026-11-12: `ObsidianMarkdownParser.styleTags` passes over runs whose `inlinePresentationIntent` is `.inlineHTML` or `.blockHTML` (Foundation gives an HTML block no `presentationIntent`, so the tag pass took it for a paragraph). Tests: `WebFrameViewTests.testAHashInsideHTMLIsNotATagAndATagBesideItStillIs` (the owner's line and a `<div>` block: no link, no colour).
- [x] The same in Live Preview's rendered blocks and in the editor's own highlighting, checked; the vault index already leaves HTML blocks out of tags (`MarkdownSemantics`), checked with a test.
  Done 2026-11-12: Live Preview's callouts and tables use the same parser (checked through `LivePreviewText.prepared` in the same test: `<span style="color:#f00">` beside `#real` links only `real`). The editor's highlighting skips a tag inside an HTML tag's text (`MarkdownStyleScanner`, `htmlTag` pattern); the index already left HTML out. Tests: `WebFrameEmbedTests.testAHashInsideAnHTMLTagIsNotATagInTheIndexOrTheEditor`; the hosted Live Preview screenshot shows `#f80` in a frame's source uncoloured. A tag's attributes continued on a later line than its `<` are still highlighted in the editor (the scanner reads one line at a time).
- [x] Tests: a reading build of the owner's line has no tag link; an ordinary `#tag` next to HTML still has one.
  Done 2026-11-12: the tests above; with section 2 the owner's line is a frame block, so the parser is tested on the line itself.

## 2. Finding a frame in a note

Issue: [#157](https://github.com/Graphite-Note/Graphite/issues/157)

- [x] A Core value for a frame (`WebFrameEmbed`: address, width, height, border, corner radius, title) read from an `<iframe …></iframe>` written on lines of its own, attributes in any order, quoted with `"` or `'` or unquoted, in any letter case, with the closing tag on the same or a later line. Its rules are decisions 1 and 4.
  Done 2026-11-12: `WebFrameEmbed` and `WebFrameSyntax.frame(startingAt:lineCount:line:)` (`Sources/GraphiteCore/WebFrameEmbed.swift`): attributes in any order, case and quoting, character references decoded, closing tag on the same or a later line (at most 24 lines, never past a blank line), a list item's marker before it (not a task), style `width`/`height`/`border`/`border-radius` winning over the attributes, a border only with a visible style as in CSS (decided here: no border without one; Obsidian's own frame border was not checked).
- [x] The reading view's block splitter (`NotePreviewDocument`) gives it a block of its own (`NotePreviewBlock.webFrame`), also inside callouts and list items, never inside fenced code, inline code or a `%%` comment.
  Done 2026-11-12: `NotePreviewBlock.webFrame`, found before headings so a frame line is never a heading's text; in callouts and list items, never in code or comments.
- [x] Live Preview's scanner (`LivePreviewBlockScanner`) finds the same lines as a rendered block (`LivePreviewBlock.Kind.webFrame`), with the same rules, so the two views agree.
  Done 2026-11-12: `LivePreviewBlock.Kind.webFrame`, found with display math in `LivePreviewBlockScanner.wholeLinesBlock`; the same frame as the reading view's for the same lines.
- [x] Tests with plain values: the owner's line; percentages and points; missing and malformed attributes; other schemes left as text; a frame in a callout, a list item, code and a comment; `<iframe>` inside a paragraph's text left as text.
  Done 2026-11-12: `WebFrameEmbedTests` (14).

## 3. The frame in the reading view

Issue: [#158](https://github.com/Graphite-Note/Graphite/issues/158)

- [x] A frame view for the iPad, the iPhone and the Mac (`UIViewRepresentable` and `NSViewRepresentable` around `WKWebView`) with the size and look of section 2, laid out in the note's column as an image is.
  Done 2026-11-12: `WebFrameBlock` (box at the tag's size, border and corners, laid out in the column; a width of 100% is the column's) and `WebFramePage`, a `UIViewRepresentable`/`NSViewRepresentable` holding a `WebFramePageContainer` that holds the `WKWebView`. Checked: hosted screenshots on the iPad simulator, `WebFrameViewTests` on the Mac (400 by 200 at the tag's size; the Mac reading view at the 730-point column). The iPhone runs the iPad's code and was not run in an iPhone simulator.
- [x] Made when the frame comes within about a screen of being visible, given up when it is a few screens away; a placeholder of the same size, with the site's address, stands in for it, so the note does not jump. At most a few live web views at once per window.
  Done 2026-11-12: `WebFrameLiveSelection` (pure, Core): loaded within one screen, kept until three screens away, at most four at once; `WebFrameLiveViews` in the reading view; the box with the site's address stands in. Tests: `WebFrameEmbedTests.testOnlyTheFewFramesNearestTheScreenHoldAPage`, `WebFrameViewTests.testTheMacReadingViewLoadsOnlyTheFramesNearTheScreen`, `WebFrameHostedTests.testFramesFarFromTheScreenHoldNoPage` (ten 600-point frames: at most three web views at once while scrolling, every frame loaded as it was reached, the first given up; found while testing: a lazy stack took a frame's view away and back on screen without a new distance, which left it without its page; the view now reports its last distance when it appears again).
- [ ] Loading shows the placeholder with a progress indicator; a failed load or a page that refuses to be embedded says so, with its address and Open in Browser.
  Done 2026-11-12: progress indicator while loading; a failed load says why (offline, site not found, not answering, too slow, not https) with the site, Open in Browser and Try Again; the page is the web view's own document, so a site's refusal to be framed (`X-Frame-Options`) does not apply and is never shown. Tests: `WebFrameViewTests.testAPageThatCannotLoadSaysSo`, `WebFrameHostedTests.testAPageThatCannotLoadSaysSoWithItsAddress` (screenshot looked at).
  Reopened 2026-11-12: on the Mac, a frame whose site does not exist (`https://graphite-frame-check.invalid/`) showed a white box with only Open in Browser and Try Again, in the reading view and in Live Preview. Its message and site are there (three text elements in the accessibility tree) but drawn white on white: the failed page's web view stays under the placeholder (`WebFrameBlock.box` keeps `WebFramePage` while `holdsPage`), and the placeholder's background is `.quaternary.opacity(0.35)`, so the web view's white shows through and the dark appearance's text is white. The hosted test's screenshot was in the light appearance.
  Fixed 2026-11-12: the web view is hidden until its page has loaded (`WebFrameBlock.box`, `.opacity`), and kept, hidden, so Try Again loads in it again; the message is drawn on the note's own background, as before a page starts loading. Test: `WebFrameViewTests.testAFramesWebViewIsHiddenUntilItsPageHasLoaded` (a failed page's web view drawn at opacity 0, a loaded one at 1; it fails without the fix). Not yet looked at in the app in the dark appearance: the test copy's window was on another Space while the owner worked in a full-screen app.
  Looked at 2026-11-12 in the iPad simulator (iPad Pro 11-inch, iOS 27.2, Debug of main 21ea6b1a with the release test vault): Web/Web pages.md's two loopback frames show "This page can't be shown here.", "The page couldn't be loaded.", the host and Open in Browser and Try Again, readable in light and dark, in the reading view and Live Preview (/private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/e12baa59-cf1b-4607-8ec4-a12bc8ee36e6/scratchpad/checks/web-light-reading.png, /private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/e12baa59-cf1b-4607-8ec4-a12bc8ee36e6/scratchpad/checks/web-dark-reading.png, /private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/e12baa59-cf1b-4607-8ec4-a12bc8ee36e6/scratchpad/checks/web-dark-lp.png). The progress indicator was not seen (the load fails at once). Left: the Mac app in the dark appearance
- [ ] The page scrolls inside its frame by touch, trackpad and mouse wheel, and the note scrolls on when the page reaches its end, as in Obsidian; media plays inline on the iPhone.
  Built: the web view scrolls its page; `allowsInlineMediaPlayback` is on (checked in the hosted test's configuration). Needs a device: scrolling by touch, trackpad and wheel, and the note scrolling on at the page's end (no code makes it so).
  Checked on the Mac 2026-11-12: the mouse wheel scrolls the page inside its frame and, beside the frame, the note. With the page at its end, 30 more wheel steps over the frame did not scroll the note, so the note does not scroll on as in Obsidian; with the owner's 900-point frame filling most of the window, the note scrolls only with the pointer beside the frame. The steps were synthesized line-by-line wheel events; a trackpad's gesture was not tried.
- [ ] Decision 5's data store, new-window links in the system browser, no file access, no message handlers. A right-click (Mac) or long press on the frame's edge offers Open in Browser and Copy Address.
  Built and tested (`WebFrameViewTests`: Graphite's own store by identifier, no message handler, no scheme handler, no user script, navigation only to web pages, a `target="_blank"` link sent to the browser, nothing plays by itself). Open in Browser and Copy Address are on the box while it shows no page and beside a page narrower than the column, and in Live Preview's block menu above Edit Source; on a live page as wide as the column only the page's own menus answer. The menus were not opened in a test or on a device.
  Checked on the Mac 2026-11-12: right-clicking the box of a page that could not load opens a menu of Open in Browser and Copy Address (neither chosen). Not tried: beside a narrower page, Live Preview's block menu, the iPad's long press.
  Looked at 2026-11-12 in the iPad simulator (iPad Pro 11-inch, iOS 27.2, Debug of main 21ea6b1a with the release test vault): a long press on the box of a frame that could not load offers Open in Browser and Copy Address (/private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/e12baa59-cf1b-4607-8ec4-a12bc8ee36e6/scratchpad/checks/web-longpress.png; neither chosen). Left: beside a narrower page, Live Preview's block menu
- [ ] VoiceOver reads the frame by its `title`, or its address when it has none, and moves into the page.
  Built: the frame is an accessibility container named by its `title`, or its address, holding the web view. Needs VoiceOver on a device.
  Checked on the Mac 2026-11-12, without VoiceOver: the page's form fields and its Draw button are in the window's accessibility tree, inside the frame's group.
- [ ] A frame alone in a list item shows that item's bullet. Found 2026-11-12 on the Mac: in `- In a list item:` followed by `- <iframe …></iframe>`, the frame was drawn at the item's indent with no bullet before it, in the reading view and Live Preview.
  Looked at 2026-11-12 in the iPad simulator (iPad Pro 11-inch, iOS 27.2, Debug of main 21ea6b1a with the release test vault): still so on the iPad: Web/Web pages.md's frame in `- <iframe …>` has no bullet in the reading view or Live Preview (/private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/e12baa59-cf1b-4607-8ec4-a12bc8ee36e6/scratchpad/checks/web-light-reading.png, /private/tmp/claude-501/-Users-baheyshalash-Desktop-Graphite/e12baa59-cf1b-4607-8ec4-a12bc8ee36e6/scratchpad/checks/web-dark-lp.png)
- [x] Tests: hosted tests that the frame appears at its size with a page served by the test, that it is not made off screen, that it is given up when scrolled far away, and that a failed load shows its message.
  Done 2026-11-12: `WebFrameHostedTests` (4, iPad simulator, pages served by `LoopbackWebServer` on the loopback address) and `WebFrameViewTests` (Mac, 9). Memory with ten frames: the app's own footprint 64 MB before, 68 MB scrolled to the end with at most three pages (WebKit's own processes not counted).

## 4. The frame in Live Preview

Issue: [#159](https://github.com/Graphite-Note/Graphite/issues/159)

- [x] Live Preview draws the frame over its lines while the cursor is elsewhere, as it draws a base or a diagram (`LivePreviewRenderedBlocks`, `LivePreviewWidgets`), with the same view, loading and releasing rules as section 3; the cursor on its lines shows the source.
  Done 2026-11-12: `LivePreviewWebFrameView`; a frame in a callout or an embedded note too (`LivePreviewBlockStack`). Test: `WebFrameHostedTests.testLivePreviewDrawsTheFrameShowsItsSourceUnderTheCursorAndRedrawsAnEditedTag` (three screenshots looked at).
- [x] Its height is known before the page loads (the tag's height), so typing and scrolling never wait for the page and the lines below do not move when it loads.
  Done 2026-11-12: the reserved height is the tag's plus the block's 8 points of padding (`LivePreviewBlockHeightEstimate`), and the view is that tall whether or not its page has loaded. Tests: `WebFrameViewTests.testLivePreviewReservesTheTagsHeightAndKeepsNoFrameOffScreen`; the hosted test's web view is 420 points tall.
- [x] A frame is never kept in the pool of off-screen rendered blocks with its web view alive; a pooled block keeps only its placeholder.
  Done 2026-11-12: a frame's view, and a callout's holding one, is never kept off screen nor made ahead (`DetachedWidgetPool.estimatedMegabytes(of:)` nil); an embedded note's frame in a kept view gives its web view up as the view leaves the window (`WebFramePageContainer`). Tests: `WebFrameViewTests.testLivePreviewReservesTheTagsHeightAndKeepsNoFrameOffScreen`, `testAFrameGivesItsPageUpWhenItsViewLeavesTheWindowAndLoadsItAgainWhenBack`.
- [ ] Clicking or tapping inside the page acts on the page; a click beside it, or the arrow keys, put the cursor on its lines, as for the other rendered blocks.
  Built: the page takes touches and clicks inside it; a tap beside a page narrower than the column shows the tag. Not tested: a synthesized tap does not reach the page, and the arrow keys were not tried.
  Checked on the Mac 2026-11-12: in Live Preview, Down from the line above puts the cursor on a frame's line and shows its tag, and the frame is drawn again once the cursor is on another line; a click inside a live page in a callout acts on the page and does not show the source. Not tried: a click beside a narrower page, the iPad.
- [x] Tests: hosted tests that the frame shows in Live Preview, that the cursor on its lines shows the source, and that editing the tag (its height, its address) redraws it.
  Done 2026-11-12: the hosted test above: shown, the cursor on the tag shows the source (no web view), the tag's height and address edited redraw it at 300 points with the other page.

## 5. Everywhere else a note is shown

Issue: [#160](https://github.com/Graphite-Note/Graphite/issues/160)

- [x] A note embedded in another (`![[note]]`) and a hover or long-press link preview show its frames by the same rules, or their placeholders where a live page does not fit (link previews).
  Done 2026-11-12: an embedded note's frames are blocks of its body and live in the reading view and Live Preview; a link's preview card shows only the box (`WebFramePresentation.placeholder`, also the default anywhere new, such as canvas cards). Test: `WebFrameEverywhereTests.testANoteEmbeddedInAnotherShowsItsFramesPageAndAPreviewCardOnlyItsBox`.
- [x] Export to PDF draws a frame as a box of its size, cut to a sensible height, with the page's title or address and the address as a link, since a live page cannot be printed (`NotePDFBlock`).
  Done 2026-11-12: `WebFramePresentation.printed`: the box cut to 120 points, the title and the whole address, linked in the finished PDF. Test: `WebFrameEverywhereTests.testExportToPDFPrintsTheFramesBoxWithItsNameAndItsAddressAsALink` (the exported page looked at).
- [x] Read Aloud keeps skipping it (HTML is skipped today); check that the frame does not change where reading starts and stops.
  Done 2026-11-12: `WebFrameEverywhereTests.testReadAloudSkipsTheFrameAndReadsTheTextAroundIt`: nothing of the tag is read and the text after it keeps its place.
- [x] Docs: `Docs/Architecture.md` (the frame's types, the web view's limits, the release rule) and `Docs/Coverage.md`.
  Done 2026-11-12: Architecture.md (Web pages in notes), Coverage.md, Obsidian-mobile-gaps.md, invariants MD-26, SEC-13, P-19.

## 6. Checked on the devices

Issue: [#161](https://github.com/Graphite-Note/Graphite/issues/161)

- [ ] The owner's note on the iPad, the iPhone and the Mac: the grapher loads, its form takes values, Draw draws, the page scrolls inside its frame and the note scrolls past it.
  Checked on the Mac 2026-11-12, with a note of the same shape (not the owner's note): the grapher loads at the column's width (about 660 points) and 900 points tall with the tag's grey border and rounded corners; its fields take values typed in them; the wheel scrolls it inside its frame and, beside the frame, scrolls the note. Draw cannot be pressed: the page draws its graph at fixed page coordinates (`D.SetFrame(60, 550, 635, 950)`), and in WebKit the form above it ends one line higher than in Obsidian's Chromium, so the graph's `250` label covers the button; clicks, an accessibility press and Option-Tab did not reach it. A copy of the page served from the Mac with the button moved above the form drew its curve and became ReDraw in the same frame, so the page's script runs in Graphite. Not tried: the iPad, the iPhone.
- [ ] A YouTube embed (`https://www.youtube.com/embed/…`) plays inline; YouTube refuses embeds that send no referrer, so this needs checking and may need the frame to send the vault's or Graphite's own address as the referrer.
  Checked on the Mac 2026-11-12: the embed shows YouTube's "Video player configuration error", Error 153, with Watch video on YouTube: the frame's request (`WebFramePageController.load`, `URLRequest(url:)`) sends no `Referer`, which YouTube requires of applications that embed its player. Nothing played and the Mac's audio output stayed closed.
  Fixed 2026-11-12: the frame's request sends `Referer: https://<bundle identifier>/` (`WebFrameWebViews.request(for:)`), as YouTube's Required Minimum Functionality asks of an application. Checked on the Mac with YouTube's own player in a frame's web view: without the referrer it says Error 153, with it the player loads and shows the video's title and Watch on YouTube; nothing was played. Test: `WebFrameViewTests.testThePageIsAskedForWithGraphitesIdentityAsItsReferrer` (the test server receives the referrer; it fails without the fix). Still to do: play a video inline on the iPad and the iPhone.
- [ ] Memory measured on the iPad with a note of ten frames scrolled from top to bottom: no more than the few web views of section 3 alive at once, and memory back near where it started after the note closes.
- [ ] Offline: every frame shows its message, and the note itself opens and scrolls as fast as without frames.
