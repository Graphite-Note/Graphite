---
tags:
  - guide/obsidian
---
# What Graphite opens

Graphite reads an Obsidian vault as it is. Choose **Open Folder as Vault** on the welcome screen (or **Manage Vaults…** later) and pick the vault's folder, for example iCloud Drive › **Obsidian** › your vault. Graphite changes nothing until you edit, and it never rewrites a note just because it opened it.

## Notes and syntax

Everything Obsidian writes is read the Obsidian way: `[[wikilinks]]` with aliases, headings and blocks, `![[embeds]]` of notes, sections, pictures and PDF pages, callouts, `$math$`, tasks, footnotes, `%%comments%%`, properties and tags, highlights and the Colors syntax. The editor has **Live Preview**, the reading view and **Source Mode**, as you know them. [[Making notes look good]] walks through all of it.

## The `.obsidian` folder

| What | Read from | What Graphite does with it |
| --- | --- | --- |
| Attachment folder, link format, inline title | `app.json` | follows them when it saves pictures and writes links |
| Theme, accent, fonts, CSS snippets | `appearance.json`, `themes/`, `snippets/` | draws notes in your theme with **Use the Vault's Obsidian Theme** (see [[Themes and snippets]]) |
| Core plugins' settings | `daily-notes.json`, `templates.json`, `bookmarks.json`, `graph.json`, `types.json` | uses the same folders, formats, bookmarks and property types |
| Keyboard shortcuts | `hotkeys.json` | the same shortcuts in both apps (see [[Keyboard shortcuts]]) |
| Community plugins | `plugins/`, `community-plugins.json` | runs many of them (see [[Plugins]]) |

## Bases, canvases and the graph

`.base` files open as tables, cards, lists, boards and maps; `.canvas` files open as boards you can arrange. The graph, the map, bookmarks, the outline, backlinks, the Tags and Properties panels, templates and daily notes are all there, each a core plugin you can turn off.

## Core plugins as switches

As in Obsidian, every feature is a core plugin: Settings › **Core Plugins** has a switch for each. Turning one off hides it in Graphite and never changes your notes.

Next: [[What Graphite adds]].
