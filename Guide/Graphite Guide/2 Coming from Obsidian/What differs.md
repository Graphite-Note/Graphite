---
tags:
  - guide/obsidian
---
# What differs

Graphite aims to read every vault exactly as Obsidian does. Where it does not yet, it says so here rather than surprise you.

## Things that work differently

- **Settings live in two places.** The vault's own settings (attachments, templates, daily notes, shortcuts, theme) are shared with Obsidian through `.obsidian`. Graphite's own preferences, such as the Pencil tools and which core plugins are on, belong to the app on each device and apply to every vault.
- **Code is coloured in the reading view.** While you write, code blocks are plain; they get their colours when you read.
- **Embeds go one level deep.** A note embedded inside an embedded note shows as a link.
- **Community plugins run in a web view** that starts only when you turn them on. Many work; plugins that need Obsidian's desktop app do not.

## Not there yet

Slash commands, the note composer, random note, the Slides core plugin, workspaces (saved layouts), the format converter, Templater syntax, and search embedded in a note (`query` blocks). Obsidian Sync and Publish are Obsidian's own paid services: keep the vault in iCloud Drive or another drive instead (see [[Where a vault can live]]).

> [!info] The full list
> The repository keeps the full, dated list of what is and is not built: `Docs/Obsidian-mobile-gaps.md` and `Docs/Coverage.md` on [github.com/Graphite-Note/Graphite](https://github.com/Graphite-Note/Graphite).

Next: [[Using both apps]].
