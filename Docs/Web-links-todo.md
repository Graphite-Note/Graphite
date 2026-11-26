# Pasted web addresses as links, titled links and video cards: TODO

Created: 2026-11-16.

Status: built 2026-11-16; sections 1 and 2 done, section 3 looked at in the running apps on 2026-11-17 (a tap on a card not made). Issues: [#187](https://github.com/Graphite-Note/Graphite/issues/187) to [#189](https://github.com/Graphite-Note/Graphite/issues/189), one per section.

## Request

Reported 2026-11-16, with two screenshots: two YouTube playlist addresses pasted into a note show as plain white text in the editor, and an address shown blue and underlined is "what it should be": "pasting links is not nice here vs what it should be (clicable at least if its only the link) and an optional preview implimentation linke a ()[] kind of vibe or a play button vibe".

## Cause

Neither editor recognizes a bare web address. `LinkLocator` (what a tap or click in Live Preview follows, and what ⌥/⌘-Return follows) and `MarkdownStyleScanner` (what gets the link colour) know `[[wikilinks]]` and `[text](address)` only. The reading view links bare addresses already: Textual parses with Foundation's `AttributedString(markdown:)`, which links `https://…`, `http://…` and `www.…` as GFM's autolink extension does.

## Decisions

1. **Paste stays as written** (chosen 2026-11-16, of three choices: always titling, a setting, or this). A pasted address is pasted as is and shows as a link. Nothing is fetched until it is asked for from the link's menu (right-click on the Mac, long press on the iPad): **Use Page Title** writes `[Page title](address)`, **Show Preview** writes `![Page title](address)`.
2. **A video card opens YouTube** (chosen 2026-11-16), not YouTube's player in a web view in the note: a thumbnail, the title and a play button; a tap or click opens the address in the YouTube app or the browser. No web view, so a note with videos stays light (lean core app).
3. **Obsidian's syntax.** `![](https://www.youtube.com/watch?v=…)` on a line of its own is Obsidian's YouTube embed, so the card is drawn for that and nothing new is written into notes. Other web pages have no preview in Obsidian (`![](page)` is an image there), so Show Preview is offered for YouTube addresses only.
4. **The same addresses as the reading view.** The editor links what Foundation links: `http://` and `https://` addresses and `www.` addresses, with GFM's rules for where one ends (trailing `.,:;!?"'*_~` and an unbalanced `)` are not part of it). Code, math and Markdown links are left alone.
5. **Titles and thumbnails come from YouTube's oEmbed** (`https://www.youtube.com/oembed?url=…&format=json`), which answers for videos and playlists alike; other pages' titles from their `<title>` or `og:title`, reading at most the first 512 KB.

## 1. Bare web addresses are links in the editor

Issue: [#187](https://github.com/Graphite-Note/Graphite/issues/187)

- [x] A bare address has the link colour in Live Preview and Source mode, on the iPad and the Mac. Done 2026-11-16: `WebAddressSyntax` finds the addresses Foundation links (GFM's ends), and `MarkdownStyleScanner` gives them the `.link` span both modes draw. `BareWebAddressTests` (the spans); drawn in the editors' Live Preview by `WebLinksHostedTests` (iPad simulator, screenshot looked at) and `UiEditorMacWebLinksTests` (the Mac editor, a rendering looked at): the address has the colour of a Markdown link's text, the full stop after it the colour of text. Source mode was not drawn in a test.
- [x] A tap (iPad) or click (Mac) on a bare address in Live Preview opens it; ⌥-Return and ⌘-Return on it follow it in both modes. Done 2026-11-16: `LinkLocator` returns a bare address as `.web`, which the tap, the click and the Return commands already open. `BareWebAddressTests` (the locator), `UiEditorMacWebLinksTests.testABareAddressIsALinkThatAClickFollows` (the Mac editor's link under a click). The opening itself (`UIApplication.open`, `NSWorkspace.open`) was not run in a test.
- [x] Tests: the locator and the scanner with addresses ending in punctuation, parentheses, inside code and inside Markdown links. Done 2026-11-16: `BareWebAddressTests` (7).

## 2. A web link's menu: Use Page Title and Show Preview

Issue: [#188](https://github.com/Graphite-Note/Graphite/issues/188)

- [x] Right-click (Mac) or long press (iPad) on a bare address offers Use Page Title, which fetches the title and writes `[Title](address)` as one undo step. Done 2026-11-16: `EditorContextMenuContent` puts the entries first in the editor's menu at a bare address; `WebLinkDetailsFetching` reads oEmbed or the page, at most 512 KB, nothing kept. `WebAddressMenuTests` (3), the menu in the iPad editor (`WebLinksHostedTests`) and in the Mac editor's right-click menu (`UiEditorMacWebLinksTests`). Run once in the iPad simulator against YouTube (not kept as a test, it needs the network): the request's first playlist became `[Livestream - P&S Understanding and Designing Modern Storage Systems (Spring 2026)](…)`, one undo step.
- [x] Show Preview on a YouTube address writes `![Title](address)` on a line of its own. Done 2026-11-16: `WebLinkEditing.preview`; `WebLinkPreviewTests` (in a list item, in a sentence). Run once in the iPad simulator against YouTube: the line became the playlist's card, one undo step.
- [x] Tests: the title read from oEmbed answers and from `<title>`/`og:title`, the edit made, nothing written when the fetch fails. Done 2026-11-16: `WebLinkPreviewTests` (7: oEmbed and HTML titles, no title, the edits, no edit when the note changed or the address is not bare); with no title `titledLink` is not called, so the note is left as it is.

## 3. Video cards for YouTube embeds

Issue: [#189](https://github.com/Graphite-Note/Graphite/issues/189)

- [x] `![…](YouTube address)` on a line of its own draws a card in Live Preview and in the reading view: thumbnail, title, play button; a tap or click opens the address. Done 2026-11-16: `WebVideoCard` (at most 560 points wide, a 16:9 picture, the play button, a Playlist badge, the written or fetched title), `EmbedReference.isBlockOfItsOwn`; the card has the link trait and opens the address with `openURL`. `WebLinksHostedTests` (Live Preview and the reading view on the iPad simulator), `UiEditorMacWebLinksTests` (the Mac editor's block); screenshots with YouTube's thumbnails and titles for both playlists looked at. The tap's opening was not run in a test.
- [x] Videos (`watch?v=`, `youtu.be/`, `shorts/`) and playlists (`playlist?list=`) are recognized. Done 2026-11-16: `WebVideo`; `WebLinkPreviewTests.testYouTubeVideosAndPlaylistsAreRecognized`.
- [x] Tests: recognizing the addresses, the block found for such a line in both renderers. Done 2026-11-16: `WebLinkPreviewTests` (7).
- [x] Checked by hand on the iPad simulator and the Mac with the request's two playlists. 2026-11-16: both playlists drawn with YouTube's thumbnails and titles in hosted iPad renderings and in a rendering of the Mac editor; not by hand in the running apps, as the simulator's taps and computer use were not granted at that time. oEmbed answers for both, with the Spring 2026 and Fall 2026 livestreams of the storage systems course.
  Done 2026-11-17: looked at in the running apps: a note of the two playlists as `![](…)` lines, in the reading view of a re-signed Mac Debug copy (dark) and in Live Preview in the iPad simulator (light): each is a card with YouTube's thumbnail, its title (Spring 2026 and Fall 2026 livestreams), the play button and the Playlist badge. Not done: a tap or click on a card, which opens YouTube through `openURL`, as the simulator's taps and computer use were not granted.
