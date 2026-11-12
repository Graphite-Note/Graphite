# The release test vault

An Obsidian vault with a note or a file for every feature Graphite has, to try them all before a release (Docs/Release-test-vault-todo.md). Everything in it is made up for the purpose: no person's notes, no photos of people, and no audio or video file, so nothing in it can play a sound. It stays under 5 MB. Every web address in it is the placeholder `http://127.0.0.1:9/` on the loopback address, where nothing answers; the release pass points it at a server of its own, so nothing reaches the internet.

Open it in Graphite (or Obsidian) as a vault. The release pass (`ReleaseVaultPassTests` on the Mac, `ReleaseVaultPassHostedTests` on the iPad and iPhone simulators, both run by `scripts/release-check.sh`) opens every note below in Live Preview, the reading view and source mode, and every other file in its own view, with a screenshot of every page. `ReleaseVaultContentsTests` checks on every run that the vault stays small, silent and offline, and that this file lists every file.

**Adding a feature: add its note here and a line to the table of its folder**, naming the todo file it covers. A note that shows a failure on purpose (a link to a note not written yet) is listed in `ReleaseVaultFinding.intended` too.

## Made, not written

`scripts/make-release-vault.py` makes these again the same way: the pictures in `Attachments/`, the three PDFs in `PDFs/`, the daily notes in `Daily/`, `Lectures/Long lecture.md`, `Edge cases/Windows line endings.md`, and copies the bases and their notes (`Books`, `Places`, `Tasks`) from `Tests/BaseSampleVault` and the two notebooks from `Tests/SyntheticNotebooks`. With `--graphite-files <build folder>` it also has Graphite's own writers make `Drawings/Circuit drawing.png` and `Notebooks/Lab notebook.pdf` (`ReleaseVaultGraphiteFilesTests`). Every other note is written by hand.

## Settings (`.obsidian/`)

| File | What it sets | Feature |
| --- | --- | --- |
| `app.json` | attachments go to `Attachments`, shortest wikilinks, inline title, readable line length | Obsidian settings, attachment policy |
| `daily-notes.json` | daily notes in `Daily`, named `YYYY-MM-DD`, from `Templates/Daily note` | Daily notes core plugin |
| `templates.json` | templates in `Templates`, date and time formats | Templates core plugin |
| `types.json` | the property types: number, checkbox, date, date and time, list | Properties core plugin, Bases |
| `bookmarks.json` | a note, a group of a note and a PDF, and a search | Bookmarks core plugin |

## Notes and files

| File | What it shows | Feature, todo file |
| --- | --- | --- |
| `Start here.md` | links to every area, aliases and a tag: the graph's centre and backlinks | Links, graph (Graph-view-todo.md) |
| `README.md` | this list | |
| `Markdown/Headings and text.md` | six heading levels, setext headings, bold, italic, strikethrough, code, highlight, hard line break, escapes, thematic breaks, emoji, a heading with a link | Markdown (Obsidian-mobile-gaps.md) |
| `Markdown/Lists and tasks.md` | bullets nested three deep, numbered lists starting at seven, tasks of every status (`[ ]`, `[x]`, `[/]`, `[-]`, `[>]`), nested and numbered tasks, loose lists, folding | Lists, tasks, folding |
| `Markdown/Quotes and code.md` | nested quotes, a quote with a list, fenced code in Swift and Python, a block with no language, a tilde fence, indented code, a fence inside a longer fence | Quotes, code blocks |
| `Markdown/Footnotes and comments.md` | numbered, named, repeated and inline footnotes, a footnote over two lines; `%%` comments inline and over lines, an HTML comment | Footnotes core plugin, comments |
| `Markdown/HTML and highlights.md` | `==` highlights, `<mark>`, `<u>`, `<b>`, `<i>`, `<s>`, `<kbd>`, `<sub>`, `<sup>`, `<br>`, `<details>`, a styled `<div>` and `<span>` | Inline HTML (Obsidian-mobile-gaps.md) |
| `Markdown/Properties and tags.md` | properties of every type (text, list, number, checkbox, date, date and time, tags, aliases, links, empty, nested), nested tags in the text and words that are not tags | Properties core plugin, tags |
| `Links/Link target.md` | aliases, headings and block identifiers on a paragraph, a list item and a quote | Links (Rendered-links-todo.md) |
| `Links/Links and aliases.md` | wikilinks to a note, an alias, a heading, a nested heading, a block, this note's heading, a path, a picture, a PDF page, a base view and a canvas; two unresolved links; Markdown, angle-bracket, reference links and an autolink | Links (Rendered-links-todo.md) |
| `Links/Embeds.md` | embeds of a whole note, a heading's section, a block, a list item, a picture, a PDF page, a base view; an embed of a heading that does not exist and of a note that does not exist, both on purpose | Embeds, transclusion |
| `Callouts.md` | every callout type and alias, an unknown type, open and folded callouts, three nested levels, a table, display math and code inside callouts | Callouts |
| `Math.md` | inline math, display math on lines of its own and on one line, `aligned`, a numbered equation (`\tag`), matrices, cases, a long formula, math in a list | Math |
| `Tables.md` | alignment, a wide table, formulas, links, pictures and escaped pipes in cells, emoji, lines that are not a table | Tables (Table-editing-todo.md) |
| `Pictures.md` | a picture alone, with a width, with a width and a height, with a caption, side by side, side by side in a list, inside a sentence, in Markdown syntax with a size, a wide picture, names with spaces and accents and a pasted name, an SVG | Pictures (Inline-images-todo.md, Image-zoom-and-new-tab-todo.md) |
| `Diagrams/Flowcharts and sequences.md` | a flowchart with every edge kind, a top-down graph with subgraphs, a sequence diagram with activation, a note, a loop and alternatives | Mermaid drawn natively (Native-diagrams-todo.md) |
| `Diagrams/Classes, states and entities.md` | a class diagram, a state diagram, an entity relationship diagram | Mermaid (Native-diagrams-todo.md) |
| `Diagrams/Charts.md` | a pie chart, an XY chart, a quadrant chart, a Sankey diagram | Mermaid (Native-diagrams-todo.md) |
| `Diagrams/Plans and maps.md` | a Gantt chart, a mind map, a timeline, a git graph, a user journey | Mermaid (Native-diagrams-todo.md) |
| `Embedded base.md` | a base written in the note with a table and a kanban board, and embedded views of the bases' gallery, map and list | Bases core plugin |
| `Books.base` | table, grouped table, cards with covers and a numbered list of the books, formulas and summaries | Bases core plugin |
| `Books/Dune.md`, `Books/Frank Herbert.md`, `Books/Gödel, Escher, Bach.md`, `Books/Middlemarch.md`, `Books/Reading notes.md`, `Books/The Left Hand of Darkness.md`, `Books/The Structure of Scientific Revolutions.md` | the books the base shows, with their properties | Bases core plugin |
| `Books/covers/dune.png`, `Books/covers/geb.png`, `Books/covers/kuhn.png`, `Books/covers/lefthand.png`, `Books/covers/middlemarch.png` | the cards' covers | Bases cards |
| `Places.base`, `Places.md` | the places on a map, a map of one type, and a table | Map core plugin (Map-view-todo.md), Bases |
| `Places/Centre Pompidou.md`, `Places/Eiffel Tower.md`, `Places/Jardin des Plantes.md`, `Places/Landmarks.md`, `Places/Louvre.md`, `Places/Museums.md`, `Places/Musée d'Orsay.md`, `Places/Nowhere yet.md`, `Places/Parks.md`, `Places/Sacré-Cœur.md` | places with `coordinates`, their types, and one without coordinates | Map core plugin (Map-view-todo.md) |
| `Tasks.base` | active tasks grouped by status, and done tasks, with formulas of dates | Bases core plugin |
| `Tasks/Email the TA.md`, `Tasks/Fix testbench.md`, `Tasks/Plan study group.md`, `Tasks/Review lecture 5.md`, `Tasks/Write lab report.md` | the tasks the bases show | Bases core plugin |
| `Canvas/Course map.canvas` | a group, text cards with Markdown and math, cards of a note, a note's section, a picture and a PDF, edges with labels, colours and arrows | Canvas core plugin |
| `PDFs/PDF embeds.md` | the PDFs embedded whole, at a page and at a height, and links to a page | PDF embeds |
| `PDFs/Lecture slides.pdf` | four slides of text with an outline | PDF reading, outline, Mac markup (Mac-PDF-markup-todo.md) |
| `PDFs/Scanned page.pdf` | a scanned sheet: one picture, no text layer | Scanned PDFs, text recognition |
| `PDFs/Annotated handout.pdf` | ink, a highlight, an underline, a strikeout and text boxes, as another app saves them | PDF annotations (PDF-text-boxes-todo.md, Mac-PDF-markup-todo.md) |
| `Drawings/Drawing note.md` | the drawing embedded at its size and smaller, and a picture that is not a drawing | Drawings core plugin |
| `Drawings/Circuit drawing.png` | a Pencil drawing: a PNG that carries its strokes | Drawings core plugin |
| `Notebooks/Notebooks.md` | the notebook embedded, and what the other apps' notebooks are | Notebooks (Notebook-library-and-new-file-todo.md) |
| `Notebooks/Lab notebook.pdf` | a notebook from the New Notebook sheet: a cover and three ruled pages | Notebooks (Notebook-library-and-new-file-todo.md) |
| `Notebooks/Synthetic text boxes.goodnotes`, `Notebooks/Synthetic typed note.note` | a Goodnotes notebook of text boxes and a Notability note of typed text, without recordings; the pass imports them | Notebook import core plugin (Goodnotes-Notability-import-todo.md) |
| `Daily/2026-09-03.md`, `Daily/2026-09-07.md`, `Daily/2026-09-10.md`, `Daily/2026-09-14.md`, `Daily/2026-09-17.md`, `Daily/2026-09-21.md`, `Daily/2026-09-24.md`, `Daily/2026-09-28.md`, `Daily/2026-10-01.md`, `Daily/2026-10-05.md`, `Daily/2026-10-08.md`, `Daily/2026-10-12.md`, `Daily/2026-10-15.md`, `Daily/2026-10-19.md`, `Daily/2026-10-22.md`, `Daily/2026-10-26.md`, `Daily/2026-10-29.md` | daily notes on Mondays and Thursdays over two months, with properties, tasks, due dates and monthly tags | Daily notes and calendar (Calendar-and-reminders-todo.md) |
| `Templates/Daily note.md`, `Templates/Lecture.md`, `Templates/Meeting with events.md` | templates with `{{title}}`, `{{date}}`, `{{time}}`, formatted dates, `{{yesterday}}`, `{{tomorrow}}` and the calendar's `{{events}}` | Templates core plugin, calendar |
| `Web/Web pages.md` | a page in a frame, a frame of a size in a list item, and a frame inside a sentence that stays text | Web frames (Iframe-embeds-todo.md) |
| `Lectures/Long lecture.md` | twelve sections of text, lists, tasks, callouts, code, tables, formulas and pictures, for scrolling | Scrolling (Editor-scrolling-todo.md) |
| `Plugins/Colors.md` | coloured text, alone and with bold and a highlight | Colors core plugin |
| `Plugins/Reminders and dates.md` | tasks with due, scheduled and done dates and a reminder's block identifier | Calendar and reminders (Calendar-and-reminders-todo.md) |
| `Edge cases/Unicode – naïve café 日本語.md` | a name and text in many scripts, right-to-left text, emoji with joiners, combining marks | Names and text |
| `Edge cases/Only properties.md` | a note that is only properties | Properties |
| `Edge cases/Empty note.md` | an empty file | Notes |
| `Edge cases/Windows line endings.md` | every line ending in `\r\n`, with a table, math and a callout | Line endings |
| `Attachments/Bar chart.png`, `Attachments/Café menu – été.png`, `Attachments/Circuit sketch.png`, `Attachments/Pasted image 20261001093000.png`, `Attachments/Portrait tile.png`, `Attachments/Square badge.png`, `Attachments/Sunset over hills.png`, `Attachments/Wide banner.png` | small generated PNGs: landscape, portrait, square, wide, an accented name, a pasted name | Pictures |
| `Attachments/Logo.svg` | an SVG picture | Pictures |

## Core plugins

Each core plugin with its own syntax or files has a note above: Properties, Colors, Footnotes, Drawings, Bases, Templates, Daily notes, Calendar, Bookmarks, Map, Canvas and Notebook import. Backlinks, outgoing links, the outline, tags, word count, page preview, graph and file recovery have no syntax of their own and work on every note. Read Aloud is left out on purpose, since nothing here may make a sound; the PostgreSQL mirror needs a database server and has its own tests.
