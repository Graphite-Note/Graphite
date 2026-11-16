# A guide that shows what Graphite can do: implementation TODO

Created: 2026-11-16.

Status: planned. Issues: [#190](https://github.com/Graphite-Note/Graphite/issues/190), [#191](https://github.com/Graphite-Note/Graphite/issues/191), [#192](https://github.com/Graphite-Note/Graphite/issues/192), [#193](https://github.com/Graphite-Note/Graphite/issues/193), one per section.

## Request

The owner, 2026-11-16: "using the test folder vault we did a proper guide. The current guide is, you know, nothing. I want like a detailed guide, like what the app is actually capable of, for someone that does know Obsidian and for someone that doesn't know anything. Like, let's say someone is used to like good notes, and you're like want them to go into this open file system, you know, local on your computer or on a drive, or, you know, explain that to them. And then what the notes are capable of, from like, you know, the handwriting to how can you make the markdown look nice, etc. Get inspired from my vault if you want, but do not post my personal stuff. But, you know, from things like, hey, you can put your favorite restaurants or your recipes or your notes, cross-reference things. You can actually like share like single folders on using iCloud Drive or any other drive you choose. Small things of that nature. You can like make the guide visual, and, you know, how can you show the syntax and whatever."

Today the Guide is a list of short how-to topics inside the app (`GuideContent`, `GuideCopy*.swift`): steps in text, a few syntax examples, no pictures, nothing to try. `Tests/ReleaseVault` (the release test vault) has a file for every feature, written to be checked, not read.

## Decisions

- The guide is itself a vault, **Graphite Guide**: notes that show each feature working, beside the syntax that makes it, so a reader sees the result and can open the source. Graphite opens a copy of it that the reader can change freely; the original stays in the app.
- Two ways in: one path for someone coming from Goodnotes or Notability, who has never kept notes as files; one for someone who knows Obsidian, which says what Graphite adds and what differs. Both meet in the same feature notes.
- Made-up content only: example recipes, restaurants, a course, a trip, a reading list, in the spirit of the owner's vault but none of its text, names or pictures (`no-personal-notes-in-demos`). The release test vault's generators and files are reused where they fit.
- Visual: screenshots of Graphite on the iPad and the Mac, taken in simulators and a test copy of the Mac app from the guide vault itself, light and dark; small JPEGs. The whole vault stays small (a target of 5 MB).

## 1. The guide vault

Issue: [#190](https://github.com/Graphite-Note/Graphite/issues/190)

- [ ] `Guide/Graphite Guide/` in the repository, an Obsidian vault with a `Start here` note that asks "Are you coming from Goodnotes or Notability, from Obsidian, or new to both?" and links each path.
- [ ] **New to files** (for Goodnotes and Notability users): what a vault is (a folder of ordinary files you own), where it can live (on the device, iCloud Drive, another drive or a sync service, a USB stick on the Mac), what each file is (Markdown notes, PDF notebooks, PNG drawings, M4A recordings), that Obsidian, Finder, Files and Preview open them all, sharing one folder with someone through iCloud Drive or another drive, moving notebooks in from Goodnotes and Notability (Import, Open in Graphite, ZIPs), and backups.
- [ ] **Coming from Obsidian**: what Graphite opens of an existing vault (settings, themes, snippets, core and community plugins), what it adds (handwriting, PDF notebooks and markup, recording, the library), what differs or is not there yet, and using both apps on one vault.
- [ ] **Handwriting and PDFs**: drawings in notes, the Pencil tools and palette, notebooks and paper, writing on slides, text boxes, the lasso, pages, bookmarks, recordings, and on the Mac highlighting, drawing, text boxes, signatures and shapes.
- [ ] **Making notes look good**: each piece of Markdown and Obsidian syntax shown rendered beside its source (headings, emphasis, lists and tasks, quotes, callouts of every type, tables, math, code with themes, diagrams, footnotes, pictures and their sizes, embeds), with a "copy this" block for each.
- [ ] **Connecting notes**: links, backlinks, embeds of notes and sections, tags, properties, Bases over the example recipes, restaurants (with a map) and reading list, the graph, canvas, daily notes, templates and the calendar.
- [ ] **Everyday examples**: a recipe collection, favourite restaurants on a map, a course with lecture notes and slides, a trip plan, a reading list, each cross-referenced, so a reader sees how the pieces fit.
- [ ] **Making it yours**: themes, snippets, the code theme, core and community plugins, keyboard shortcuts, the library and list views.
- [ ] Small: under 5 MB with its pictures; no person's notes or photos of people; no audio or video.

## 2. Pictures of the app

Issue: [#191](https://github.com/Graphite-Note/Graphite/issues/191)

- [ ] Screenshots of each feature in use, taken from the guide vault in the iPad simulator, the iPhone simulator and a test copy of the Mac app, light and dark, embedded where the guide explains it; made by a script so they can be taken again after the app changes.
- [ ] Short animated pictures (GIF or small looping images, no sound) for gestures that a still picture cannot show: drawing, the lasso, dragging pen colours, switching views.

## 3. In the app

Issue: [#192](https://github.com/Graphite-Note/Graphite/issues/192)

- [ ] The Guide opens the guide vault: a copy is made in Graphite's own folder the first time (or again, when asked), and opens beside the reader's vaults; Settings, the welcome screen and Help › Graphite Guide lead to it.
- [ ] The in-app Guide topics link to the matching guide notes, and their text is brought up to date with what the app does today.
- [ ] Tests: the guide vault opens in every view with no errors (the release pass run over it), every link in it resolves, its size stays under the target, and the copy is made once and can be made again.

## 4. Checks

Issue: [#193](https://github.com/Graphite-Note/Graphite/issues/193)

- [ ] Read through on the iPad, the iPhone and the Mac, in light and dark, by a session, with screenshots looked at; the owner reads it and says whether it is what they meant.
