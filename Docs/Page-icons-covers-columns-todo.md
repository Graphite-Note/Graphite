# Page icons, covers and columns: TODO

Created: 2026-11-26.

Status: 2026-11-26, planned. Nothing is built yet. Issues: [#256](https://github.com/Graphite-Note/Graphite/issues/256) to [#259](https://github.com/Graphite-Note/Graphite/issues/259), one per section.

## Request

Feature 9 of [Notion-features-for-Graphite.md](Notion-features-for-Graphite.md): many students choose Notion for how a course page looks, with an icon on every page, a cover picture and blocks side by side. Graphite keeps that look with properties and callouts that Obsidian already reads, without a format of its own:

- An `icon` property (an emoji or an SF Symbol name) shown in tabs, the file list, the quick switcher, links and Library mode, set from the note's menu.
- A `banner` property drawn as a short cover in reading view only, collapsible, and off on the iPhone by default, so it does not cost the screen space the editor needs.
- `> [!multi-column]` callouts drawn as columns where the note is wide enough and stacked when it is narrow. The file stays a callout that every Markdown reader shows.

Every extra must cost nothing for notes without these properties.

## What the result must be

- **The same file in Obsidian.** The properties and the callout are the ones the most used plugins and snippets write, so a note looks alike in Obsidian with those plugins (decisions 1 to 3). Graphite writes nothing else.
- **Nothing extra for notes without them.** A vault without an `icon` property costs one indexed query that returns no rows after each index change. A note without `banner` and without these callouts builds and draws as before. Measured in section 4.
- **No chrome above the page.** The cover is drawn inside the reading view's scrolling content, above the title, never as a fixed row, and never in Live Preview or source mode.
- **No inert controls.** An icon Graphite cannot draw (an Iconize pack other than Lucide, a Lucide icon without an SF Symbol here) draws nothing, and the property stays as written.

## Decisions

1. **`icon` is Iconize's frontmatter field.** Iconize reads the `icon` property when its "Use frontmatter" option is on (off by default, `iconInFrontmatterEnabled`, `iconInFrontmatterFieldName: 'icon'` in its `src/settings/data.ts`); Pixel Banner also draws `icon` on its banner (`customBannerIconField: ['icon']` in its `src/settings/settings.js`). Iconize accepts an emoji or an icon pack name with its prefix (`IbBell`, `LiBookOpen`). Graphite reads an emoji (the first one of the text, as Iconize does), a Lucide name of Iconize's built-in pack (`Li` and the Lucide name in upper camel case, drawn from Obsidian's own Lucide set without a download), and an SF Symbol name. Other packs (Font Awesome, Remix and so on) are downloads of Iconize that Graphite does not have: they draw nothing.
2. **A symbol chosen in Graphite is written as its Lucide name.** The picker offers 64 symbols, each an SF Symbol paired with the Lucide icon that shows the same thing (`NoteIconSymbols`), and writes the Lucide name (`LiBookOpen`), so Obsidian with Iconize shows the same icon. All 64 Lucide names were checked against the icon table in Obsidian 1.15.1. An SF Symbol name typed by hand is read too, and Obsidian shows nothing for it.
3. **`banner` is the field Banners and Pixel Banner share.** Banners (noatpad/obsidian-banners README) writes `banner` with `banner_x` and `banner_y` from 0 to 1. Pixel Banner (jparkerweb/pixel-banner README and settings) writes `banner` with `banner-y` as a percentage, and reads a wikilink, an embed, a Markdown link or embed, a plain path, a web address or search words. Graphite reads every form except Pixel Banner's search words (its online service) and `file://` paths outside the vault, and takes the vertical position from `banner_y` or `banner-y`. The horizontal position, height, fade and the other options of both plugins are not read: Graphite's cover has one short height for every note.
4. **Columns follow Modular CSS Layout.** The `[!multi-column]` callout is the snippet `MCL Multi Column.css` of efemkay/obsidian-modular-css-layout: the callout's title and box are hidden, each block of its body (a nested callout, a paragraph, a list, a quote) is a column at least 200 px wide that grows to share the width (`flex: 1 1 200px`, gap 1em), and columns wrap onto a new row when the width runs out. Graphite draws the same rule at 200 points (`CalloutColumnArrangement`), so a phone shows one column per row. `[!blank]` and `[!blank-container]` from the same snippet draw their content without title or box.
5. **Callout metadata is read.** Obsidian reads `> [!type|metadata]`, which the snippet uses for column widths (`[!note|wide-2]`). Graphite did not recognise such a line as a callout at all. The header now takes the metadata in the reading view, Live Preview, Read Aloud's folds and the plugin HTML (`data-callout-metadata`).
6. **One switch.** Icons, covers and columns are one core plugin, "Icons, Covers and Columns", on by default. Off, nothing is queried or drawn and the callouts show as ordinary callouts, as Obsidian shows them without the snippet.
7. **A cover is collapsed per note for the session**, as a callout's folding is (`CalloutFoldStore`). The note's file is never changed by collapsing it.
8. **Covers on the iPhone are a setting, off by default.** The phone's reading view starts with the title.

## 1. Note icons from the `icon` property

Issue: [#256](https://github.com/Graphite-Note/Graphite/issues/256)

- [ ] `NoteIcon` and `NoteIconSymbols` read an `icon` text as decisions 1 and 2 say and give the text written for a choice.
- [ ] One query reads every note's `icon` from the index (`VaultIndex.noteIcons`), and one catalog per window keeps them by path, reloaded when the index's properties change and emptied on a vault switch.
- [ ] The file list shows a note's icon in place of its name's leading space: the iPad and iPhone tree rows and the Mac outline.
- [ ] Tabs show it before the title: the tab bar, the stacked tabs' spine and the phone's tab overview.
- [ ] The quick switcher shows it on a note's row.
- [ ] Links in the reading view to a note with an icon show it before the link's text.
- [ ] Library mode shows it in a note tile's caption.
- [ ] The note's More menu has Icon…: a picker with an emoji field, the 64 symbols and Remove Icon, which writes or removes the property through the note's own session (one undo step, saved like any edit).

## 2. Covers from the `banner` property

Issue: [#257](https://github.com/Graphite-Note/Graphite/issues/257)

- [ ] `NoteBanner` reads the forms of decision 3, with the vertical position.
- [ ] The reading view draws the cover above the title: 140 points high on the iPad and the Mac, cropped to the note's width around its vertical position, a vault picture or a picture on the web. A cover whose picture is missing or cannot be read is not drawn.
- [ ] The cover collapses to a thin strip and opens again from a button on it (decision 7), with VoiceOver labels.
- [ ] The iPhone draws covers only when Settings › Appearance › Covers on iPhone is on (decision 8).

## 3. Multi-column callouts

Issue: [#258](https://github.com/Graphite-Note/Graphite/issues/258)

- [ ] Callout headers take `|metadata` (decision 5) everywhere a header is read.
- [ ] The reading view draws a `[!multi-column]` callout's blocks as columns by `CalloutColumnArrangement`: side by side where the note is wide enough, stacked when narrow, without title or box.
- [ ] `[!blank]` and `[!blank-container]` draw their content without title or box.
- [ ] Live Preview draws them the same way.

## 4. Switch, cost and checks

Issue: [#259](https://github.com/Graphite-Note/Graphite/issues/259)

- [ ] The core plugin switch of decision 6, in Settings › Core Plugins.
- [ ] File list scrolling and note opening measured before and after on a generated vault of 3,000 notes without these properties, and with icons on a part of them.
- [ ] Rendered checks of each surface in light and dark: tabs, file list, quick switcher, a link, Library mode, the cover open and collapsed, columns wide and stacked.
- [ ] Checked in an iPad simulator in portrait and landscape, an iPhone simulator and a Debug copy of the Mac app, with a small demo vault.
- [ ] `Docs/Architecture.md`, `Docs/Coverage.md` and the Iconize row of `Docs/Community-plugins.md` describe what is built.

## Later

- Iconize's own store of icons (`.obsidian/plugins/obsidian-icon-folder/data.json`), which keeps the icons set without frontmatter, and its `iconColor` property.
- Column widths from `wide-2` to `wide-5` and the snippet's other options (`col3`, `fw` and `pw` widths), which need the metadata of each nested callout carried into the reading view's blocks.
- Icons on links in Live Preview, where they would be drawn over the concealed `[[`.
