# Web pages in notes (`<iframe>`): TODO

Created: 2026-11-12.

Status: planned 2026-11-12; nothing built. Issues: [#156](https://github.com/Graphite-Note/Graphite/issues/156) to [#161](https://github.com/Graphite-Note/Graphite/issues/161), one per section.

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

- [ ] `#ccc` (or any `#word`) inside an HTML tag or an HTML block is not coloured or linked as a tag in the reading view; the tag pass skips HTML runs (`inlinePresentationIntent` `.blockHTML` or `.inlineHTML`) as it skips links and code (`MarkdownPreview.swift`, where tags are coloured, `isCode`).
- [ ] The same in Live Preview's rendered blocks and in the editor's own highlighting, checked; the vault index already leaves HTML blocks out of tags (`MarkdownSemantics`), checked with a test.
- [ ] Tests: a reading build of the owner's line has no tag link; an ordinary `#tag` next to HTML still has one.

## 2. Finding a frame in a note

Issue: [#157](https://github.com/Graphite-Note/Graphite/issues/157)

- [ ] A Core value for a frame (`WebFrameEmbed`: address, width, height, border, corner radius, title) read from an `<iframe …></iframe>` written on lines of its own, attributes in any order, quoted with `"` or `'` or unquoted, in any letter case, with the closing tag on the same or a later line. Its rules are decisions 1 and 4.
- [ ] The reading view's block splitter (`NotePreviewDocument`) gives it a block of its own (`NotePreviewBlock.webFrame`), also inside callouts and list items, never inside fenced code, inline code or a `%%` comment.
- [ ] Live Preview's scanner (`LivePreviewBlockScanner`) finds the same lines as a rendered block (`LivePreviewBlock.Kind.webFrame`), with the same rules, so the two views agree.
- [ ] Tests with plain values: the owner's line; percentages and points; missing and malformed attributes; other schemes left as text; a frame in a callout, a list item, code and a comment; `<iframe>` inside a paragraph's text left as text.

## 3. The frame in the reading view

Issue: [#158](https://github.com/Graphite-Note/Graphite/issues/158)

- [ ] A frame view for the iPad, the iPhone and the Mac (`UIViewRepresentable` and `NSViewRepresentable` around `WKWebView`) with the size and look of section 2, laid out in the note's column as an image is.
- [ ] Made when the frame comes within about a screen of being visible, given up when it is a few screens away; a placeholder of the same size, with the site's address, stands in for it, so the note does not jump. At most a few live web views at once per window.
- [ ] Loading shows the placeholder with a progress indicator; a failed load or a page that refuses to be embedded says so, with its address and Open in Browser.
- [ ] The page scrolls inside its frame by touch, trackpad and mouse wheel, and the note scrolls on when the page reaches its end, as in Obsidian; media plays inline on the iPhone.
- [ ] Decision 5's data store, new-window links in the system browser, no file access, no message handlers. A right-click (Mac) or long press on the frame's edge offers Open in Browser and Copy Address.
- [ ] VoiceOver reads the frame by its `title`, or its address when it has none, and moves into the page.
- [ ] Tests: hosted tests that the frame appears at its size with a page served by the test, that it is not made off screen, that it is given up when scrolled far away, and that a failed load shows its message.

## 4. The frame in Live Preview

Issue: [#159](https://github.com/Graphite-Note/Graphite/issues/159)

- [ ] Live Preview draws the frame over its lines while the cursor is elsewhere, as it draws a base or a diagram (`LivePreviewRenderedBlocks`, `LivePreviewWidgets`), with the same view, loading and releasing rules as section 3; the cursor on its lines shows the source.
- [ ] Its height is known before the page loads (the tag's height), so typing and scrolling never wait for the page and the lines below do not move when it loads.
- [ ] A frame is never kept in the pool of off-screen rendered blocks with its web view alive; a pooled block keeps only its placeholder.
- [ ] Clicking or tapping inside the page acts on the page; a click beside it, or the arrow keys, put the cursor on its lines, as for the other rendered blocks.
- [ ] Tests: hosted tests that the frame shows in Live Preview, that the cursor on its lines shows the source, and that editing the tag (its height, its address) redraws it.

## 5. Everywhere else a note is shown

Issue: [#160](https://github.com/Graphite-Note/Graphite/issues/160)

- [ ] A note embedded in another (`![[note]]`) and a hover or long-press link preview show its frames by the same rules, or their placeholders where a live page does not fit (link previews).
- [ ] Export to PDF draws a frame as a box of its size, cut to a sensible height, with the page's title or address and the address as a link, since a live page cannot be printed (`NotePDFBlock`).
- [ ] Read Aloud keeps skipping it (HTML is skipped today); check that the frame does not change where reading starts and stops.
- [ ] Docs: `Docs/Architecture.md` (the frame's types, the web view's limits, the release rule) and `Docs/Coverage.md`.

## 6. Checked on the devices

Issue: [#161](https://github.com/Graphite-Note/Graphite/issues/161)

- [ ] The owner's note on the iPad, the iPhone and the Mac: the grapher loads, its form takes values, Draw draws, the page scrolls inside its frame and the note scrolls past it.
- [ ] A YouTube embed (`https://www.youtube.com/embed/…`) plays inline; YouTube refuses embeds that send no referrer, so this needs checking and may need the frame to send the vault's or Graphite's own address as the referrer.
- [ ] Memory measured on the iPad with a note of ten frames scrolled from top to bottom: no more than the few web views of section 3 alive at once, and memory back near where it started after the note closes.
- [ ] Offline: every frame shows its message, and the note itself opens and scrolls as fast as without frames.
