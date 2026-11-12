# The release test vault

An Obsidian vault with a note or a file for every feature Graphite has, to try them all before a release (Docs/Release-test-vault-todo.md). Everything in it is made up for the purpose: no person's notes, no photos of people, and no audio or video file, so nothing in it can play a sound. It stays under 10 MB.

Its web frames and links name real pages (example.com, example.org and pages of Wikipedia), for a person browsing the vault; none of them plays anything by itself. The release pass never loads them: in its copy of the vault every frame, whatever its address, shows a page of the pass's own server on the loopback address, so a test reaches no other host.

Open it in Graphite (or Obsidian) as a vault. The release pass (`ReleaseVaultPassTests` on the Mac, `ReleaseVaultPassHostedTests` on the iPad and iPhone simulators, both run by `scripts/release-check.sh`) opens every note below in Live Preview, the reading view and source mode, and every other file in its own view, with a screenshot of every page; it turns on the vault's community plugin first. `ReleaseVaultContentsTests` checks on every run that the vault stays small and silent, names only known https pages, and that this file lists every file, its settings included.

**Adding a feature: add its note here, a line to the table of its folder, and a row to the feature index**, naming the todo file it covers. A note that shows a failure on purpose (a link to a note not written yet) is listed in `ReleaseVaultFinding.intended` too.

## Made, not written

`scripts/make-release-vault.py` (Python, standard library only) makes these again the same way: the PNG pictures, `Logo.svg` and `Checkers.webp` in `Attachments/`; `Lecture slides.pdf`, `Scanned page.pdf`, `Annotated handout.pdf` and `Odd pages.pdf` in `PDFs/`; the daily notes in `Daily/`; `Lectures/Long lecture.md`; `Edge cases/Windows line endings.md`; and in `.obsidian/` the snippet, the theme, `appearance.json`, `hotkeys.json`, `graph.json`, `workspace.json`, `graphite-calendar.json`, `community-plugins.json` and the test plugin. It copies the bases and their notes (`Books`, `Places`, `Tasks`) from `Tests/BaseSampleVault` and two notebooks from `Tests/SyntheticNotebooks`.

With `--graphite-files <build folder>` it then has Graphite's own writers make the rest (`ReleaseVaultGraphiteFilesTests`, which reads the script's pictures and slides): the drawings in `Drawings/` (PNG, SVG and PDF carrying their strokes), the notebooks in `Notebooks/` and the paper in `.obsidian/graphite-templates/` (the New Notebook sheet's and My Templates' writers), the PDFs written on in `PDFs/` (`Written in Graphite.pdf`, `Dense formula sheet.pdf`, `Protected slides.pdf`, `Form.pdf`), the imports in `Imports/` (the notebook import's own conversion), `Rings.jpg`, `Rings.gif`, `Rings.tiff` and `Rings.heic` in `Attachments/` (the system's image writer), and `.obsidian/graphite-folder-styles.json` (the library's folder styles). The script's files are the same on every run; PDFKit's are the same apart from their identifiers and dates. Every other note is written by hand.

## Settings (`.obsidian/`)

| File | What it sets | Feature |
| --- | --- | --- |
| `.obsidian/app.json` | attachments go to `Attachments`, shortest wikilinks, inline title, readable line length | Obsidian settings, attachment policy |
| `.obsidian/daily-notes.json` | daily notes in `Daily`, named `YYYY-MM-DD`, from `Templates/Daily note` | Daily notes core plugin |
| `.obsidian/templates.json` | templates in `Templates`, date and time formats | Templates core plugin |
| `.obsidian/types.json` | the property types: number, checkbox, date, date and time, list | Properties core plugin, Bases |
| `.obsidian/bookmarks.json` | a note, a group of a note and a PDF, and a search | Bookmarks core plugin |
| `.obsidian/appearance.json` | the theme `Release Paper`, the snippet `Ruled headings`, an accent colour, the base font size, the system's light or dark | Appearance: themes, snippets, fonts, accent |
| `.obsidian/snippets/Ruled headings.css` | a CSS snippet: ruled second-level headings and square bullets; its opening comment is its description in Settings | CSS snippets |
| `.obsidian/themes/Release Paper/theme.css`, `.obsidian/themes/Release Paper/manifest.json` | a small theme: warm headings, a teal accent, tag and quote colours, light and dark | Obsidian themes |
| `.obsidian/hotkeys.json` | Highlight on ⇧⌘H, Insert Drawing on ⌥⌘D, Export to PDF without a shortcut, and the test plugin's command on ⇧⌘L | Keyboard shortcuts (Keyboard-shortcuts-settings-todo.md) |
| `.obsidian/graph.json` | Obsidian's graph settings with two colour groups; Graphite keeps its own and leaves this file as it is | Graph view, Obsidian's files left alone |
| `.obsidian/workspace.json` | Obsidian's open tabs and recent files; Graphite does not read it and leaves it as it is | Obsidian's files left alone |
| `.obsidian/graphite-calendar.json` | the Calendar's settings: event notes of the "Lectures" calendar in `Lectures`, others in `Daily`, tasks sent to the list "Release vault" | Calendar core plugin (Calendar-and-reminders-todo.md) |
| `.obsidian/graphite-templates/Lab sheet.pdf` | a paper of one's own in My Templates, made from the scanned lab sheet's page | My Templates (Notebook-library-and-new-file-todo.md) |
| `.obsidian/graphite-folder-styles.json` | colours and marks of the folders `PDFs`, `Notebooks`, `Drawings`, `Daily` and `Embeds`, as Customize Folder writes them | Folder customisation (Notebook-library-and-new-file-todo.md) |
| `.obsidian/community-plugins.json` | turns on the test plugin `release-vault-test` | Community plugins |
| `.obsidian/plugins/release-vault-test/manifest.json`, `.obsidian/plugins/release-vault-test/main.js` | a community plugin with two commands and a `release-vault-count` code block, no network, nothing that plays | Community plugins |

## Notes and files

| File | What it shows | Feature, todo file |
| --- | --- | --- |
| `Start here.md` | links to every area, aliases and a tag: the graph's centre and backlinks | Links, graph (Graph-view-todo.md) |
| `README.md` | this list | |
| `Markdown/Headings and text.md` | six heading levels, setext headings, bold, italic, strikethrough, code, highlight, hard line break, escapes, thematic breaks, emoji, a heading with a link | Markdown (Obsidian-mobile-gaps.md) |
| `Markdown/Lists and tasks.md` | bullets nested three deep, numbered lists starting at seven, tasks of every status (`[ ]`, `[x]`, `[/]`, `[-]`, `[>]`), nested and numbered tasks, loose lists, folding | Lists, tasks, folding |
| `Markdown/Quotes and code.md` | nested quotes, a quote with a list, fenced code in Swift and Python, a block with no language, a tilde fence, indented code, a fence inside a longer fence | Quotes, code blocks |
| `Markdown/Code in every language.md` | a fenced block in each of the 26 languages Graphite highlights, with the aliases CUDA and SystemVerilog, and one without a language | Code highlighting, code themes |
| `Markdown/Colours, links and line breaks.md` | the Colors palette by name, a highlight across a formula, `#ccc` in HTML that is not a tag, `[[#heading]]` and GitHub heading links, a folder note embedded, an unlinked mention, single line breaks | Colors, links, strict line breaks |
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
| `Embeds/Pictures in every form.md` | PNG pictures alone, with a width, a width and a height, in Markdown syntax, side by side, in a table, a callout and a folded callout inside it, a quote, bullets, numbered items and a task, in an embedded note and a heading's section, and a base's cards embedded | Pictures, embeds (Inline-images-todo.md) |
| `Embeds/SVG in every form.md` | Graphite's SVG drawing alone, with a width, a width and a height, in Markdown syntax, beside its PNG, in a table, a callout, a list item and an embedded note; another app's SVG | SVG drawings and pictures |
| `Embeds/PDFs in every form.md` | PDFs whole, from a page, at a height, from a page at a height, in a callout, a list item, a table (a link), side by side, in an embedded note, and links to each page | PDF embeds (PDFEmbedOptions) |
| `Embeds/Drawings in every form.md` | Graphite drawings at their size and smaller, with a width and a height, saved as PDF, without paper, side by side, in a table, a callout, a task and an embedded note | Drawings core plugin |
| `Embeds/Every picture format.md` | a picture of each format Graphite opens: PNG, JPEG, an animated GIF, TIFF, HEIC, WebP and SVG, in a table and alone | Pictures |
| `Embeds/Embedded note with pictures.md` | a note other notes embed: a PNG and a drawing side by side, a PDF page, an SVG drawing | Embeds of notes with pictures |
| `Diagrams/Flowcharts and sequences.md` | a flowchart with every edge kind, a top-down graph with subgraphs, a sequence diagram with activation, a note, a loop and alternatives | Mermaid drawn natively (Native-diagrams-todo.md) |
| `Diagrams/Classes, states and entities.md` | a class diagram, a state diagram, an entity relationship diagram | Mermaid (Native-diagrams-todo.md) |
| `Diagrams/Charts.md` | a pie chart, an XY chart, a quadrant chart, a Sankey diagram | Mermaid (Native-diagrams-todo.md) |
| `Diagrams/Plans and maps.md` | a Gantt chart, a mind map, a timeline, a git graph, a user journey | Mermaid (Native-diagrams-todo.md) |
| `Diagrams/Diagram options.md` | a compact Gantt chart, a pie chart with its labels outside, a hole and a legend, a git graph with its branch names hidden, and an empty diagram shown as its source | Mermaid options and safety (Native-diagrams-todo.md) |
| `Embedded base.md` | a base written in the note with a table and a kanban board, and embedded views of the bases' gallery, map and list | Bases core plugin |
| `Books.base` | table, grouped table, cards with covers and a numbered list of the books, formulas and summaries | Bases core plugin |
| `Books/Dune.md`, `Books/Frank Herbert.md`, `Books/Gödel, Escher, Bach.md`, `Books/Middlemarch.md`, `Books/Reading notes.md`, `Books/The Left Hand of Darkness.md`, `Books/The Structure of Scientific Revolutions.md` | the books the base shows, with their properties | Bases core plugin |
| `Books/covers/dune.png`, `Books/covers/geb.png`, `Books/covers/kuhn.png`, `Books/covers/lefthand.png`, `Books/covers/middlemarch.png` | the cards' covers | Bases cards |
| `Gallery.base` | cards whose covers are a PNG, a JPEG, a GIF, a Graphite drawing, its SVG and none, and a table with an `html()` formula | Bases cards, pictures |
| `Gallery/Gallery.md` | the folder note of `Gallery/`, which an embed of the folder shows | Folder notes |
| `Gallery/PNG cover.md`, `Gallery/JPEG cover.md`, `Gallery/GIF cover.md`, `Gallery/Drawing cover.md`, `Gallery/SVG drawing cover.md`, `Gallery/No cover.md` | the cards of `Gallery.base`, each with a `cover` of another kind | Bases cards |
| `Places.base` | the places on a map, a map of one type, and a table | Map core plugin (Map-view-todo.md), Bases |
| `Places.md` | only a heading, as in `Tests/BaseSampleVault`: the note of the same name as the folder `Places/`, so a link to Places opens it | Folder notes |
| `Places/Centre Pompidou.md`, `Places/Eiffel Tower.md`, `Places/Jardin des Plantes.md`, `Places/Landmarks.md`, `Places/Louvre.md`, `Places/Museums.md`, `Places/Musée d'Orsay.md`, `Places/Nowhere yet.md`, `Places/Parks.md`, `Places/Sacré-Cœur.md` | places with `coordinates`, their types, and one without coordinates | Map core plugin (Map-view-todo.md) |
| `Tasks.base` | active tasks grouped by status, and done tasks, with formulas of dates | Bases core plugin |
| `Tasks/Email the TA.md`, `Tasks/Fix testbench.md`, `Tasks/Plan study group.md`, `Tasks/Review lecture 5.md`, `Tasks/Write lab report.md` | the tasks the bases show | Bases core plugin |
| `Canvas/Course map.canvas` | a group, text cards with Markdown and math, cards of a note, a note's section, a picture and a PDF, edges with labels, colours and arrows | Canvas core plugin |
| `Canvas/Pictures and drawings.canvas` | two groups of cards: a PNG, a JPEG, a GIF, a WebP, Graphite's SVG drawing, another app's SVG, a text card with a picture, the drawings as PNG and PDF, a PDF from its third page, a notebook, a note with pictures; edges with labels | Canvas with pictures and drawings |
| `PDFs/PDF embeds.md` | the PDFs embedded whole, at a page and at a height, and links to a page | PDF embeds |
| `PDFs/Written in Graphite.md` | what each page of the PDF written in Graphite shows, the PDF embedded, and the other made PDFs | PDF ink, text boxes, pictures, markup |
| `PDFs/Lecture slides.pdf` | four slides of text with an outline, and a link from the last slide to the first | PDF reading, outline, page links, Mac markup (Mac-PDF-markup-todo.md) |
| `PDFs/Written in Graphite.pdf` | the slides written on by Graphite's PDF writer: ink of every tool and colour, the highlighter multiplied over text, a line cut by the eraser, text boxes in five fonts (one turned, one framed, one with a link), two pictures (one turned), a highlight, an underline and a strikeout, shapes, lasso-moved strokes, and bookmarks "Page 2" and "Page 4" after the outline | PDF annotation (PDF-text-boxes-todo.md, Mac-PDF-markup-todo.md) |
| `PDFs/Dense formula sheet.pdf` | an A5 page across (a quarter of A3) with 1,500 small handwritten strokes: the density of the formula sheet imported from Goodnotes, as Graphite saves a page's ink | Dense ink (made with `DenseHandwritingNotebook`) |
| `PDFs/Protected slides.pdf` | the slides with an owner password and only printing allowed, which Graphite opens read-only | Password-protected PDFs |
| `PDFs/Form.pdf` | a form with a text field, two check boxes and a choice | PDF forms shown read-only |
| `PDFs/Odd pages.pdf` | an A4 page, one turned by `/Rotate 90`, Letter across, a small card, and a page with a crop box | Rotated, mixed-size and cropped pages |
| `PDFs/Scanned page.pdf` | a scanned sheet: one picture, no text layer | Scanned PDFs, text recognition |
| `PDFs/Annotated handout.pdf` | ink, a highlight, an underline, a strikeout and text boxes, as another app saves them | PDF annotations of other apps (PDF-text-boxes-todo.md, Mac-PDF-markup-todo.md) |
| `Drawings/Drawing note.md` | the drawing embedded at its size and smaller, and a picture that is not a drawing | Drawings core plugin |
| `Drawings/Every tool.md` | what each row of the every-tool drawing shows, and the drawing | Drawings core plugin |
| `Drawings/Circuit drawing.png` | a Pencil drawing: a PNG that carries its strokes | Drawings core plugin |
| `Drawings/Every tool.png`, `Drawings/Every tool.svg`, `Drawings/Every tool.pdf` | one drawing saved in each format Graphite saves: a wave of each ink (pen, monoline, fountain pen, reed pen, pencil, crayon, watercolor, highlighter), a line and a band cut by the pixel eraser, strokes moved and turned by the lasso, the shape tool's line, arrow, arc, curved arrow, circle, ellipse, triangle and rectangle, and a picture placed on it | Drawings core plugin, Pencil tools |
| `Drawings/Without paper.png` | the same strokes on a clear background | Drawings without paper |
| `Notebooks/Notebooks.md` | the notebook embedded, and what the other apps' notebooks are | Notebooks (Notebook-library-and-new-file-todo.md) |
| `Notebooks/Every paper and size.md` | links to each paper and size, and some embedded | Notebooks (Notebook-library-and-new-file-todo.md) |
| `Notebooks/Lab notebook.pdf` | a notebook from the New Notebook sheet: a cover and three ruled pages | Notebooks (Notebook-library-and-new-file-todo.md) |
| `Notebooks/On my template.pdf` | two pages on the paper of My Templates | My Templates |
| `Notebooks/Papers/Blank.pdf`, `Notebooks/Papers/Dotted Paper.pdf`, `Notebooks/Papers/Squared Paper.pdf`, `Notebooks/Papers/Ruled Narrow.pdf`, `Notebooks/Papers/Ruled Wide.pdf`, `Notebooks/Papers/Cornell.pdf`, `Notebooks/Papers/Engineering.pdf`, `Notebooks/Papers/Isometric.pdf`, `Notebooks/Papers/Music Paper.pdf` | a notebook on each paper of the sheet, on A5, with a cover of each of the eight colours (Music Paper has none), lines of each colour and strength, paper of each colour | New Notebook sheet |
| `Notebooks/Sizes/A3 portrait.pdf`, `Notebooks/Sizes/A4 landscape.pdf`, `Notebooks/Sizes/A5 portrait.pdf`, `Notebooks/Sizes/A6 landscape.pdf`, `Notebooks/Sizes/A7 portrait.pdf`, `Notebooks/Sizes/Letter landscape.pdf`, `Notebooks/Sizes/Tabloid portrait.pdf`, `Notebooks/Sizes/Custom 5 by 5 inches.pdf` | a dotted page of each size of the sheet, every second one across, and a size of one's own | New Notebook sheet |
| `Notebooks/Synthetic text boxes.goodnotes`, `Notebooks/Synthetic typed note.note` | a Goodnotes notebook of text boxes and a Notability note of typed text, without recordings; the pass imports them | Notebook import core plugin (Goodnotes-Notability-import-todo.md) |
| `Imports/Imports.md` | what each imported PDF shows | Notebook import |
| `Imports/Synthetic lecture.pdf`, `Imports/Synthetic note.pdf`, `Imports/Synthetic text boxes.pdf`, `Imports/Synthetic typed note.pdf` | the PDFs the import writes for the four synthetic notebooks: ink, pictures, text boxes, outline and bookmarks, pages cut from a long Notability page; their recordings left out | Notebook import (Goodnotes-Notability-import-todo.md) |
| `Daily/2026-09-03.md`, `Daily/2026-09-07.md`, `Daily/2026-09-10.md`, `Daily/2026-09-14.md`, `Daily/2026-09-17.md`, `Daily/2026-09-21.md`, `Daily/2026-09-24.md`, `Daily/2026-09-28.md`, `Daily/2026-10-01.md`, `Daily/2026-10-05.md`, `Daily/2026-10-08.md`, `Daily/2026-10-12.md`, `Daily/2026-10-15.md`, `Daily/2026-10-19.md`, `Daily/2026-10-22.md`, `Daily/2026-10-26.md`, `Daily/2026-10-29.md` | daily notes on Mondays and Thursdays over two months, with properties, tasks, due dates and monthly tags | Daily notes and calendar (Calendar-and-reminders-todo.md) |
| `Templates/Daily note.md`, `Templates/Lecture.md`, `Templates/Meeting with events.md` | templates with `{{title}}`, `{{date}}`, `{{time}}`, formatted dates, `{{yesterday}}`, `{{tomorrow}}` and the calendar's `{{events}}` | Templates core plugin, calendar |
| `Web/Web pages.md` | a frame of example.com on lines of its own, a frame of a Wikipedia page with a size in a list item, a frame inside a sentence that stays text, a web link | Web frames (Iframe-embeds-todo.md) |
| `Lectures/Long lecture.md` | twelve sections of text, lists, tasks, callouts, code, tables, formulas and pictures, for scrolling | Scrolling (Editor-scrolling-todo.md) |
| `Plugins/Colors.md` | coloured text, alone and with bold and a highlight | Colors core plugin |
| `Plugins/Reminders and dates.md` | tasks with due, scheduled and done dates and a reminder's block identifier | Calendar and reminders (Calendar-and-reminders-todo.md) |
| `Plugins/Test community plugin.md` | the test plugin's commands and its `release-vault-count` block | Community plugins |
| `Edge cases/Unicode – naïve café 日本語.md` | a name and text in many scripts, right-to-left text, emoji with joiners, combining marks | Names and text |
| `Edge cases/Only properties.md` | a note that is only properties | Properties |
| `Edge cases/Empty note.md` | an empty file | Notes |
| `Edge cases/Windows line endings.md` | every line ending in `\r\n`, with a table, math and a callout | Line endings |
| `Attachments/Bar chart.png`, `Attachments/Café menu – été.png`, `Attachments/Circuit sketch.png`, `Attachments/Pasted image 20261001093000.png`, `Attachments/Portrait tile.png`, `Attachments/Square badge.png`, `Attachments/Sunset over hills.png`, `Attachments/Wide banner.png` | small generated PNGs: landscape, portrait, square, wide, an accented name, a pasted name | Pictures |
| `Attachments/Rings.jpg`, `Attachments/Rings.gif`, `Attachments/Rings.tiff`, `Attachments/Rings.heic`, `Attachments/Checkers.webp` | a picture in each other format Graphite opens; the GIF has three frames | Pictures |
| `Attachments/Logo.svg` | an SVG picture another app made | Pictures |

## Feature index

Every feature Graphite has, from `Docs/Architecture.md`, `Docs/Coverage.md`, `Docs/Obsidian-mobile-gaps.md`, the built items of every `Docs/*-todo.md`, the core plugins (`CorePlugin`), the commands (`GraphiteCommand`) and the Settings pages, with the file that shows it. A feature of the interface that works on any note names a note to try it on. A feature that cannot be in a vault says why and where it is tested instead.

### Editor and Markdown

| Feature | Where in the vault |
| --- | --- |
| Live Preview, reading view and source mode, and their switch (⌘E, Toggle Reading View, Toggle Source Mode) | every note; the pass opens each in all three |
| Live Preview reveals one element's source at a time | `Markdown/Headings and text.md`, `Math.md` |
| Headings 1 to 6, setext headings, Format › Heading (⌃⌘1 to ⌃⌘6) | `Markdown/Headings and text.md` |
| Bold, italic, strikethrough, highlight, inline code and comments, and their commands (⌘B, ⌘I, ⇧⌘X, ⇧⌘H, ⌘/) | `Markdown/Headings and text.md`, `Markdown/Footnotes and comments.md` |
| A highlight running unbroken behind a formula | `Markdown/Colours, links and line breaks.md` |
| Lists, numbered lists, smart lists, indent and unindent, move lines up and down | `Markdown/Lists and tasks.md` |
| Tasks of every status, ticking in the reading view and in embedded notes, Insert Task, Toggle Checklist | `Markdown/Lists and tasks.md`, `Embeds/Pictures in every form.md` |
| Folding headings and list items, Fold All, Unfold All | `Markdown/Lists and tasks.md`, `Lectures/Long lecture.md` |
| Quotes, nested quotes | `Markdown/Quotes and code.md` |
| Code blocks and their highlighting in 26 languages, the code themes, Format Code Blocks | `Markdown/Code in every language.md`, `Markdown/Quotes and code.md` |
| Footnotes (numbered, named, inline) and the Footnotes view | `Markdown/Footnotes and comments.md` |
| `%%` and HTML comments hidden | `Markdown/Footnotes and comments.md` |
| Inline HTML tags and `<details>` | `Markdown/HTML and highlights.md` |
| A colour in HTML that is not a tag | `Markdown/Colours, links and line breaks.md` |
| Callouts of every type, folded, nested, with tables, math and code; Insert Callout | `Callouts.md` |
| Inline and display math, `aligned`, `\tag` numbers, long formulas wrapping; Insert Math Block | `Math.md`, `Lectures/Long lecture.md` |
| Tables edited in place, the cell menu, the Table commands (rows, columns, alignment, sort), wide tables scrolling, pictures in cells | `Tables.md`, `Embeds/Pictures in every form.md` |
| Properties of every type, the Properties view and `types.json` | `Markdown/Properties and tags.md`, `.obsidian/types.json` |
| Tags in properties and text, nested tags, the Tags view | `Markdown/Properties and tags.md`, `Daily/2026-10-29.md` |
| The Colors syntax, by hex and by palette name; Settings › Colors | `Plugins/Colors.md`, `Markdown/Colours, links and line breaks.md` |
| Strict line breaks (Settings › Editor) | `Markdown/Colours, links and line breaks.md` |
| Inline title, readable line length (`app.json`) | every note, `.obsidian/app.json` |
| Word and character count | `Lectures/Long lecture.md` |
| Unicode names and text, right-to-left text, emoji | `Edge cases/Unicode – naïve café 日本語.md` |
| Windows line endings kept, an empty note, a note of only properties | `Edge cases/Windows line endings.md`, `Edge cases/Empty note.md`, `Edge cases/Only properties.md` |
| Find and Find and Replace in a note, font size bigger, smaller and reset, focus mode | any note, such as `Lectures/Long lecture.md` |
| Link, tag and heading suggestions while typing `[[` and `#` | any note, such as `Links/Links and aliases.md` |
| Paste HTML as Markdown, pasted and dropped pictures saved as "Pasted image" | `Attachments/Pasted image 20261001093000.png` shows the name; pasting needs the interface (MacEditorPastedHTMLTests) |

### Links and embeds

| Feature | Where in the vault |
| --- | --- |
| Wikilinks to notes, aliases, headings, blocks, paths, pictures, PDF pages, bases and canvases; Markdown, reference and autolinks | `Links/Links and aliases.md`, `Links/Link target.md` |
| Unresolved links, which create the note when followed | `Links/Links and aliases.md` |
| Table-of-contents links and GitHub heading links | `Markdown/Colours, links and line breaks.md`, `Links/Links and aliases.md` |
| Embeds of a note, a heading's section, a block and a list item; missing embeds shown as such | `Links/Embeds.md` |
| An embedded note with pictures, a drawing and a PDF page in it | `Embeds/Embedded note with pictures.md`, embedded by each note of `Embeds/` |
| Folder notes: an embed of a folder shows its note | `Markdown/Colours, links and line breaks.md`, `Gallery/Gallery.md` |
| Backlinks with their lines, unlinked mentions, outgoing links, the outline | `Start here.md`, `Lectures/Long lecture.md` (mentioned in `Markdown/Colours, links and line breaks.md`) |
| Page Preview: a note shown beside a link to it | any link, such as in `Start here.md` |
| Follow link, open link in a new tab or on the other side | any link, such as in `Start here.md` |
| Rename and move rewriting links | any note linked from others, such as `Links/Link target.md` |
| Web links opening in the browser | `Web/Web pages.md`, `Links/Links and aliases.md` |
| `graphite://` and `obsidian://` links, Copy Graphite URL | none in a note: a link names a vault by its name on a device (WorkspaceDeepLinksTests, WorkspaceDeepLinkVaultNamesTests) |

### Pictures

| Feature | Where in the vault |
| --- | --- |
| A picture alone, with a width, a width and a height, a caption, in Markdown syntax | `Pictures.md`, `Embeds/Pictures in every form.md` |
| Pictures side by side, in a sentence, in lists, tables, callouts and quotes | `Embeds/Pictures in every form.md`, `Pictures.md` |
| PNG, JPEG, GIF (animated), TIFF, HEIC, WebP and SVG pictures, in notes and in their own tab | `Embeds/Every picture format.md`, `Attachments/` |
| Graphite's SVG drawings drawn in notes; another app's SVG opening with the system's preview | `Embeds/SVG in every form.md`, `Attachments/Logo.svg` |
| Zoom a picture, Open in New Tab, on the other side | any picture, such as in `Pictures.md` |
| Names with spaces, accents and a pasted name | `Pictures.md` |
| Pictures in bases' cards | `Gallery.base`, `Books.base` |
| Pictures in canvas cards | `Canvas/Pictures and drawings.canvas` |

### Drawings and Pencil

| Feature | Where in the vault |
| --- | --- |
| Drawings saved as PNG, SVG and PDF carrying their strokes, opening for editing (Settings › Pencil Drawings › Save Drawings As) | `Drawings/Every tool.png`, `Drawings/Every tool.svg`, `Drawings/Every tool.pdf`, `Drawings/Circuit drawing.png` |
| Every ink of the bar: pen, monoline, fountain pen, reed pen, pencil, crayon, watercolor, highlighter | `Drawings/Every tool.png`, `PDFs/Written in Graphite.pdf` page 1 |
| The pixel eraser cutting strokes | `Drawings/Every tool.png` row 2, `PDFs/Written in Graphite.pdf` page 1 |
| The lasso moving and turning strokes | `Drawings/Every tool.png` row 2, `PDFs/Written in Graphite.pdf` page 4 |
| The shape tool and Hold to Make a Shape: line, arrow, arc, curved arrow, ellipse, polygon | `Drawings/Every tool.png` row 3, `PDFs/Written in Graphite.pdf` page 4 |
| A picture placed on a drawing | `Drawings/Every tool.png` |
| A drawing without paper, white on a dark note | `Drawings/Without paper.png` |
| Drawings embedded at several sizes, in tables, callouts, lists and canvases | `Embeds/Drawings in every form.md`, `Canvas/Pictures and drawings.canvas` |
| Draw on a picture that is not a drawing | `Drawings/Drawing note.md` (`Circuit sketch.png`) |
| Insert Drawing, the floating palette and the fixed bar, sizes, colours, double-tap and squeeze, palm rejection, Draw with Finger, the laser pointer | the interface, on any note or PDF; Apple Pencil gestures need a device (PencilModesHostedTests, PencilBarPlacementHostedTests) |

### PDFs

| Feature | Where in the vault |
| --- | --- |
| A PDF in its tab: zoom, Go to Page, page count, thumbnails, the outline | `PDFs/Lecture slides.pdf` |
| A PDF's own links between pages | `PDFs/Lecture slides.pdf` page 4 |
| Bookmark This Page and the Bookmarked filter | `PDFs/Written in Graphite.pdf` ("Page 2", "Page 4"), `Imports/Synthetic lecture.pdf` |
| Ink of every tool, the highlighter multiplied over text, eraser cuts, shapes, lasso | `PDFs/Written in Graphite.pdf` pages 1 and 4 |
| Text boxes in each font, turned, filled and framed, with a link | `PDFs/Written in Graphite.pdf` page 2, `Imports/Synthetic typed note.pdf` |
| Pictures placed on a page, upright and turned | `PDFs/Written in Graphite.pdf` page 3 |
| Highlight, underline and strikeout of text (the iPad's tools, the Mac's markup row, ⌃⌘H, ⌃⌘U) | `PDFs/Written in Graphite.pdf` page 3, `PDFs/Lecture slides.pdf` to mark |
| Annotations another app made: ink, markup, text boxes | `PDFs/Annotated handout.pdf` |
| Find in a PDF, Copy Link to Page, Copy as Quote | `PDFs/Lecture slides.pdf` |
| Pages added, duplicated, moved, turned, deleted, exported, imported from a PDF | any PDF, such as `Notebooks/Lab notebook.pdf` |
| Writing guides on a page | any PDF |
| A page written densely, scrolled and zoomed | `PDFs/Dense formula sheet.pdf` |
| Password-protected PDFs opened read-only | `PDFs/Protected slides.pdf` |
| Forms shown read-only | `PDFs/Form.pdf` |
| Turned, mixed-size and cropped pages | `PDFs/Odd pages.pdf` |
| Scanned pages with no text layer | `PDFs/Scanned page.pdf` |
| PDF embeds whole, from a page, at a height; Annotate and Open in PDF View from an embed | `Embeds/PDFs in every form.md`, `PDFs/PDF embeds.md` |
| Links to a PDF's page driving the PDF on the other side | `Embeds/PDFs in every form.md`, `PDFs/Written in Graphite.md` |
| Signed PDFs read-only until Edit and Invalidate Signature | not in the vault: no signing tool makes one without a certificate (PDFSessionProtectionTests) |
| The annotation author's name (Settings › General) | every annotation of `PDFs/Written in Graphite.pdf` names "Release vault" |

### Notebooks, import and the library

| Feature | Where in the vault |
| --- | --- |
| The New Notebook sheet: every paper (Blank, Dotted, Squared, Ruled Narrow, Ruled Wide, Cornell, Engineering, Isometric, Music) | `Notebooks/Papers/` |
| Every page size (A3 to A7, Letter, Tabloid), portrait and landscape, a size of one's own | `Notebooks/Sizes/` |
| Covers of each colour, line colours and strengths, paper colours | `Notebooks/Papers/` |
| Insert Notebook, a notebook from a note | `Notebooks/Notebooks.md` embeds one |
| My Templates: a PDF page as paper, and a notebook on it | `.obsidian/graphite-templates/Lab sheet.pdf`, `Notebooks/On my template.pdf` |
| Goodnotes and Notability import, the import's progress and report | `Notebooks/Synthetic text boxes.goodnotes`, `Notebooks/Synthetic typed note.note` (the pass imports them), `Imports/` (the import's output) |
| Library mode, its tiles, sort and filters, folder colours and marks | the vault's folders, `.obsidian/graphite-folder-styles.json` |
| Scan Documents | not in the vault: it needs the camera (DocumentScanProcessingTests) |

### Export and print

| Feature | Where in the vault |
| --- | --- |
| Export to PDF (⇧⌘E) with its options, Print | any note; a rich one is `Lectures/Long lecture.md` or `Embeds/Pictures in every form.md` (NotePDFExportTests, NotePDFExportHostedTests) |

### Canvas

| Feature | Where in the vault |
| --- | --- |
| Canvases of text, file and group cards, edges with labels, colours and arrows; Select All, Delete, Duplicate | `Canvas/Course map.canvas`, `Canvas/Pictures and drawings.canvas` |
| Cards of a note's section, a picture, a PDF from a page, a drawing | `Canvas/Pictures and drawings.canvas`, `Canvas/Course map.canvas` |

### Bases

| Feature | Where in the vault |
| --- | --- |
| Table, grouped table, cards, list and map views; formulas, summaries, sorts and filters | `Books.base`, `Tasks.base`, `Places.base` |
| Kanban board, a base written in a note, embedded views | `Embedded base.md` |
| Cards with covers of every picture kind, an `html()` cell | `Gallery.base` |
| New Base | the interface |

### Graph and map

| Feature | Where in the vault |
| --- | --- |
| The graph of the vault and of a note, tags, colour groups, filters | the whole vault from `Start here.md`; Obsidian's own settings in `.obsidian/graph.json` |
| The map of the vault and of a note, from `coordinates` | `Places.base`, `Places/` |
| My Location on a map | not in the vault: it needs the device's location (MapUserLocationHostedTests) |

### Days, templates, calendar and reminders

| Feature | Where in the vault |
| --- | --- |
| Daily notes: today, previous and next, the template and folder | `Daily/`, `.obsidian/daily-notes.json`, `Templates/Daily note.md` |
| Templates: Insert Template, `{{title}}`, `{{date}}`, `{{time}}`, formats and offsets | `Templates/`, `.obsidian/templates.json` |
| The Calendar panel, the day's events, `{{events}}`, event notes, Send Task to Reminders, Insert Reminders | `Daily/`, `Templates/Meeting with events.md`, `Plugins/Reminders and dates.md`, `.obsidian/graphite-calendar.json`; Apple's Calendar and Reminders need a device's own (FakeCalendarStore in the tests) |

### Search, files, tabs and windows

| Feature | Where in the vault |
| --- | --- |
| Search and its operators (`path:`, `tag:`, `task:`, `[property]`, `/regex/`), bookmarked searches | the whole vault; `.obsidian/bookmarks.json` keeps a search |
| Quick switcher, command palette, back and forward | the whole vault |
| The files panel, its filter (⌥⌘J), sort, reveal, collapse all; new note, folder, base, canvas, notebook; rename, move, duplicate, delete | the whole vault |
| Bookmarks of notes, groups and searches | `.obsidian/bookmarks.json` |
| Tabs, pinning, reopening, ⌘1 to ⌘9, stacked tabs, the tab overview, split right, multiple windows | the interface, on any notes |
| File recovery snapshots, review other versions, local history | any note edited in the vault (FileRecoveryTests, ConflictVersionsTests) |
| Sync conflicts and unreadable files | not in the vault: they need a provider's versions or a file in another encoding (FileVersionConflictTests, ConflictVersionTests) |

### Appearance and settings

| Feature | Where in the vault |
| --- | --- |
| An Obsidian theme from the vault, Use the Vault's Obsidian Theme | `.obsidian/themes/Release Paper/`, `.obsidian/appearance.json` |
| CSS snippets and their descriptions | `.obsidian/snippets/Ruled headings.css`, `.obsidian/appearance.json` |
| Fonts, font size and accent shared with Obsidian | `.obsidian/appearance.json` |
| Settings › General, Editor, Files and Links, Appearance, Core Plugins, Colors, Pencil Drawings, Templates, Daily Notes, Calendar, File Recovery | the vault's settings files above, and the interface |
| Keyboard Shortcuts and `hotkeys.json`, a plugin's command among them | `.obsidian/hotkeys.json` |
| The app icon, the welcome tour, the Guide, add-on downloads | the interface (GuideContentTests, AddOnPackStoreTests) |

### Core plugins

| Core plugin | Where in the vault |
| --- | --- |
| Backlinks, Outgoing Links, Outline, Word Count, Page Preview | every note; `Start here.md`, `Lectures/Long lecture.md` |
| Properties View, Tags View | `Markdown/Properties and tags.md` |
| Colors | `Plugins/Colors.md` |
| Pencil Drawings | `Drawings/`, `Embeds/Drawings in every form.md` |
| Bases | `Books.base`, `Tasks.base`, `Places.base`, `Gallery.base`, `Embedded base.md` |
| Templates, Daily Notes, Calendar | `Templates/`, `Daily/`, `Plugins/Reminders and dates.md` |
| Footnotes View | `Markdown/Footnotes and comments.md` |
| File Recovery | any note edited in the vault |
| Bookmarks | `.obsidian/bookmarks.json` |
| Graph View, Map View | the whole vault, `Places/` |
| Canvas | `Canvas/` |
| Goodnotes and Notability Import | `Notebooks/`, `Imports/` |
| Audio Recorder (and video recording) | not in the vault: a recording is an audio or video file, which could play, and recording needs the microphone or camera (RecordingControllerAudioFormatTests, VideoRecordingTests, RecordingRecoveryTests) |
| Read Aloud | not in the vault: it speaks, and nothing here may make a sound (ReadAloudSessionTests, ReadAloudReadingViewTests, PDFReadAloudExtractionTests); `PDFs/Scanned page.pdf` and `Math.md` are what it would read |
| PostgreSQL Mirror | not in the vault: it needs a database server (PostgreSQLMirrorServerTests, PostgreSQLMirrorSafetyTests) |

### Community plugins

| Feature | Where in the vault |
| --- | --- |
| Community plugins turned on per vault, their commands, code blocks, hotkeys | `.obsidian/plugins/release-vault-test/`, `.obsidian/community-plugins.json`, `Plugins/Test community plugin.md` |
| Installing from the directory or GitHub, plugin settings | not in the vault: it needs the network (CommunityPluginHostTests) |

### Web frames

| Feature | Where in the vault |
| --- | --- |
| `<iframe>` pages on lines of their own and in list items, their size, border and corners; a frame in a sentence staying text | `Web/Web pages.md` |

### Not built, so not in the vault

Siri and App Intents (Siri-vault-answers-todo.md, not started), Teach Mode (Teach-mode-presenter-todo.md, a proposal) and a share extension have no file here until they are built.
