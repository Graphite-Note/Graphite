# What's New in Graphite

## 1.0.3

### 2026-11-28 21:31

- Fixed [Mac]: Playing a video embedded in a note no longer quits Graphite.

### 2026-11-28 20:09

- Added: The Graphite Guide explains moving in from Notion.
- Fixed: The Graphite Guide brings its copy up to date when it opens, so new guide pages appear without making a fresh copy.
- Fixed [Mac]: Hiding the sidebar no longer sends New Note, Files Options and Show Sidebar into the toolbar's overflow menu.

### 2026-11-28 18:34

- Added: Import from Notion can read a workspace straight from Notion with an integration's token, as well as from an exported zip or folder.
- Changed: Imported Notion pages keep their covers, icons, columns, link lists, text colours and callouts, databases become bases with whole titles, and linked views become filtered tables.

### 2026-11-28 15:26

- Changed: What's New shows the time of each update, so several updates on one day read apart.
- Changed: The guide's Notion-style dashboards and tutorial carry only their icon and cover, without tags.

### 2026-11-28 14:10

- Added: The guide shows how to make a note look like a Notion page, with three example dashboards and a tutorial that builds one step by step.
- Changed: Callouts imported from Notion are drawn as Notion draws them, with their icon on the first line and no title row.

### 2026-11-28 12:52

- Fixed [Mac]: Pressing Command-Q while Settings waits for a keyboard shortcut no longer quits Graphite; the page explains that the system keeps it.

### 2026-11-28 12:24

- Changed: Inline code in the reading view is drawn on a rounded chip, as Obsidian and Notion draw it.
- Fixed [iPad]: A new note dropped with Escape while naming it in the file list is no longer made by the next New Note, and every letter typed into a name is kept.

### 2026-11-28 11:45

- Added: A What's New page lists every version's changes, opens once after an update, and is in Settings under About and in the Mac's Help menu.
- Added: Pages imported from Notion look as in Notion, with icons, a large icon over a cover, colored text, column widths and links that carry their pages' icons.
- Added [iPad]: The iPad edits the shapes the Mac drew, with a tap to select, handles to reshape and a drag to move.
- Changed: New notes, bases, canvases and folders are named, and items renamed, in the file list's own row instead of a sheet, on the Mac, iPad and iPhone.
- Changed: Names of new files and folders are written in composed Unicode, so a note named Café is spelled on disk as links, Obsidian and git spell it.
- Changed: Scrolling a note of code blocks in the reading view is smoother, and the library scrolls a folder of 10,000 notes on time.
- Fixed: Zooming a note with Command-plus, Command-minus or a pinch grows its pictures with its text, and Command-0 at the default size no longer beeps.
- Fixed [Mac]: A CSV dropped from the Finder onto a note's reading view is added with the other files, and files dropped onto an embedded PDF reach the note.
- Fixed [iPad]: A finger's tap on a picture inside text zooms it again, and pictures on canvas cards zoom by finger.
- Fixed: Pictures in quotes and after a task's text are drawn in Live Preview.
- Fixed: A window that changed vaults no longer shows the graph of the vault it left, and a restored graph tab no longer stays on Reading links.
- Fixed [Mac]: The pointer over a Live Preview table shows its plus strips without editing a cell, and a note no longer snaps back after a resize.
- Fixed [Mac]: VoiceOver can choose a tab, and the right sidebar opens without rebuilding the toolbar.
- Fixed: A notebook written in Graphite shows its writing on its library tile at once, and tag suggestions appear instantly while typing.

### 2026-11-27

- Added: Notion's HTML export, as a zip or a folder, is imported from a sheet in the New menu, the Mac sidebar's menu and the File menu.
- Added: Obsidian's Importer plugin can be installed from the community directory as another way to import from Notion.
- Changed [iPad, iPhone]: Version 27 is required again on the iPad and the iPhone, while the Mac keeps working on macOS 26.
- Changed: A property's values are suggested instantly while typing, even in a vault of tens of thousands of notes.
- Fixed: Scrolling a note is smoother on the iPad and the Mac, as a table, callout or display formula scrolling into Live Preview is laid out once.
- Fixed [iPhone]: Live Preview on a note of PDF embeds no longer keeps the iPhone busy with views made ahead.
- Fixed [iPhone]: The slash command suggestions no longer cover the line being typed when the keyboard is up.
- Fixed: A line of Meta Bind fields no longer comes out as Graphite's own text when its page is opened again.
- Fixed: Several files dropped at once into a note are embedded whole and in the order dropped.
- Fixed [Mac]: A heading dragged from the reading view onto a PDF page no longer freezes the app.
- Fixed: In the reading view, a long press or right-click beside a narrow web page offers Open in Browser and Copy Address.

### 2026-11-26

- Added: A note can be presented as slides split at its thematic breaks, with Start Presentation in the Mac's View menu and a presenter view on another display.
- Added: Typing a slash lists the note's blocks and every command, as in Obsidian's Slash commands.
- Added: Bases get relations between notes, rollups, and a New button that follows the view's filters.
- Added: Bases draw a calendar view of notes by their dates, and Calendar Copy copies a base's dated notes into Apple Calendar.
- Added: Page icons, covers and columns work as Obsidian's plugins write them, in a new core plugin.
- Added: Notion-style buttons run through the Meta Bind community plugin.
- Added: Live Preview has block handles that move a block and open a menu to turn it into another kind, duplicate it or delete it.

### 2026-11-25

- Changed: Diagrams of every type are prepared faster.

### 2026-11-24

- Changed: Diagrams are read, laid out and prepared faster.
- Fixed [Mac]: A file dropped or pasted into a note no longer sends the editor to the top of the note.
- Fixed [iPad, iPhone]: The reading view scrolls a note full of diagrams without dropped frames.

### 2026-11-23

- Changed: Diagrams take the colors of the vault's theme and of their own palette settings, such as a pie chart's slice colors.
- Changed: Diagrams are laid out at the real width of the column that shows them, and a diagram a little wider than the column is shrunk to fit.
- Changed: Diagram labels show bold, italic and code.
- Fixed: An SVG picture made by another app is shown in a note instead of reporting that it cannot be shown.
- Fixed: The reading view shows bold text in a color as bold when it begins or ends with inline math.

### 2026-11-21

- Added: Split Down puts the two sides of a split one above the other, for a PDF above a note on an iPad held upright.
- Added: A heading or block dragged from a note onto a PDF page becomes a picture of that section linking to it.

### 2026-11-20

- Added: Every Mermaid diagram type is drawn natively, with 19 new ones such as radar, treemap, kanban, packet, C4, block, architecture and Venn diagrams.

### 2026-11-19

- Added: A drawn Mermaid diagram offers Copy as SVG and Save as SVG.
- Changed: Live Preview no longer pauses while Mermaid diagrams are prepared.
- Fixed [iPad]: A densely written PDF or formula-sheet notebook scrolls, zooms, opens its pages and takes writing without stopping.
- Fixed [iPad]: Pausing while writing on a full PDF page no longer hitches at the autosave.
- Fixed [Mac]: A note of handwritten PDFs on screen takes about half the memory for its ink.
- Fixed [Mac]: A folder revealed near the top of the file tree is no longer scrolled half under the Filter field.
- Fixed: A customized folder no longer turns gray in the library while Finder shows it in its color.

### 2026-11-18

- Added [iPad]: A picture selected on a PDF page has a floating toolbar beside it, and two fingers turn and resize it as one undo step.
- Added [iPad]: The lasso's selection has a floating toolbar beside it instead of the system's edit menu, with colors one tap away.
- Changed: Graphite runs on iOS, iPadOS and macOS 26 as well as 27.
- Changed: The grips and the room around a Live Preview table look as in Obsidian.
- Changed [Mac]: The Settings window names the vault its pages change in its title.
- Fixed [iPad]: Ending the typing of a PDF text box no longer freezes the iPad, and the typed text is kept.
- Fixed [iPad]: A PDF page that stopped taking ink after a stroke, until the tab was switched, is reset.
- Fixed [iPad]: The text highlighter's live fill no longer flickers.
- Fixed [iPhone]: On a phone the pages scroll clear of the docked Pencil palette.
- Fixed: A PDF page duplicated in a saved PDF keeps its strokes as Graphite's ink.
- Fixed: Graphite's own saves no longer come back as outside changes that refresh the note or PDF a second later.
- Fixed: A PDF embedded in a note no longer freezes the app.
- Fixed: An edited table cell keeps its cell's look, with no white box over a header's shading or a callout's tint.
- Fixed: A long note switched to the reading view and back keeps its line.

### 2026-11-17

- Added: A property's names, values and tags are suggested while they are typed, and a link typed in a property field suggests the vault's notes.
- Added [iPad]: The lasso has a Lasso panel and a Take Screenshot button first in its bar.
- Added [Mac, iPad]: PDF pages get notes, with a Note tool in the Mac's markup row, an icon that opens each note, and Search finding their text.
- Added [iPad]: A PDF dropped on the page list of a PDF's sidebar inserts its pages where it is let go, as one undo step.
- Added: Settings shows Open and Delete on the Graphite Guide Vault row once it is downloaded.
- Added: Notion exports can be imported with Obsidian's Importer plugin, which now runs in Graphite.
- Changed [iPad, iPhone]: The note editor scrolls past the end of a note, so the last line stops at the middle of the editor.
- Changed: A Live Preview table is edited as in Obsidian, with arrow keys moving between cells, and a tap on a link in a table follows it.
- Changed [iPad]: The app switcher names each Graphite window after its document.
- Fixed [iPad]: A color held on the Pencil bar lifts and moves again, and black stays in view.
- Fixed [iPad]: A lasso loop around part of a stroke takes the whole stroke, and Color and Delete show before Ask Siri.
- Fixed [iPad]: The text highlighter shows the text it covers as the Pencil moves, and the eraser erases highlights, underlines and strikethroughs.
- Fixed [Mac]: The welcome tour's pictures can be deleted again in Settings.
- Fixed: Unticking a task in a note linked to Reminders is no longer undone, and a reminder completed while Graphite is closed is ticked at the next launch.

### 2026-11-16

- Added [Mac, iPad]: Pictures can be dropped onto PDF pages, and the Mac has an Images tool.
- Added [Mac, iPad]: Any color for highlights, underlines and strikethroughs, with colors saved on the device and a color picker.
- Added [iPad]: A text highlighter on the Pencil bar marks text dragged over with the Pencil when the touch lifts.
- Added [Mac, iPad]: Bring to Front, Bring Forward, Send Backward and Send to Back arrange a PDF page's pictures, text boxes and shapes, and the ink moves as one layer.
- Added: A Graphite Guide vault shows each feature working beside its Markdown, with screenshots and short animated pictures, and the Guide opens it.
- Added: A pasted web address becomes a link in the editor, its menu writes the page's title or a preview, and a YouTube address becomes a card.
- Added [Mac, iPad]: Pictures in Live Preview resize by dragging their corner, as in Obsidian, also when shown side by side.
- Added: A typed triple backtick closes itself, Return keeps indentation, and code gets no autocorrect.
- Changed [Mac]: The note editor scrolls past the end of a note, so the last line stops at the middle of the editor.
- Changed: Marking text that is already marked changes the mark instead of stacking another.
- Fixed [Mac]: A note embedding handwritten PDFs scrolls without stopping as each PDF comes into view.
- Fixed [iPad]: The Pencil bar's color row scrolls sideways only, also side by side with another app.
- Fixed [iPad]: The reading view no longer freezes when a note is switched to it at a table holding a picture.
- Fixed [Mac]: Pictures and PDFs in a Live Preview note are no longer left blank while editing, and typing under pictures no longer makes the note jump.

### 2026-11-14

- Fixed: The highlighter's stroke looks different while drawn and once it settles.

### 2026-11-13

- Added: Graphite is offered in Open In, in Files, by AirDrop and on the Mac for Goodnotes and Notability files, ZIP archives, PDFs, pictures and Markdown.
- Added: The welcome tour's pictures arrive with the app, and a ZIP chosen with Import or dropped on the library is unpacked.
- Added: A table in a callout, or in a list item inside a callout, is edited in place in Live Preview on the iPad and the Mac.
- Added [Mac]: The PDF markup row shows its choices as swatches and buttons, draws and places text boxes, draws shapes, and signs PDFs.
- Added [iPad]: The Pencil bar's colors are arranged by dragging, as in Apple's markup palette.
- Fixed [iPad]: A Live Preview table's right plus strip adds a column again, and a new empty row is drawn at once.
- Fixed [iPad]: A signature placed on the Mac and the Mac's Fine ink show on the iPad's PDF page.
- Fixed: A note switched from the reading view to source or Live Preview always shows its editor.
- Fixed: A picture on a line of its own offers Zoom In, the tabs and Copy Image on a long press.
- Fixed: Colors plugin colors are no longer shown as tags in the graph and the tags view.
- Fixed: The reading view shows two PDF embeds on one line as two viewers, as Live Preview does.

### 2026-11-12

- Added: A web page written as an iframe in a note is shown live, as in Obsidian, and a YouTube video in it loads its player.
- Added: A Calendar core plugin shows the month with a dot under each day with a daily note, opens the chosen day and can show Apple Calendar events.
- Added [Mac]: The sidebar's New menu and the File menu offer Import again.
- Changed: The graph of the whole vault is drawn and settles much sooner, on the Mac and on the iPad.
- Changed: Mermaid diagrams fit narrow columns, draw composite states, follow the theme's colors and show their source when they cannot be drawn.
- Changed: A dense Goodnotes notebook imports much faster, and its strokes are saved in a third of the room.
- Fixed [iPad]: A PDF written as densely as a formula sheet scrolls and zooms smoothly.
- Fixed: A note exported to PDF or printed shows its wide formulas, drawings, diagrams and bases as the reading view does.
- Fixed: An imported Goodnotes or Notability notebook keeps its typed text, and later pages no longer show earlier pages' writing.
- Fixed: A long formula in a paragraph wraps in Live Preview as it does in the reading view.
- Fixed: In Live Preview, the cursor on one photo of a line shows only that photo's source.
- Fixed: A long Live Preview note no longer jumps when scrolled back to its top, and its blocks take their right height at once.

### 2026-11-11

- Added [Mac]: PDFs are marked up as in Preview, with a markup row for highlight, underline and strikethrough, colors, and right-click menus.
- Added: The Files panel has a filter of its own, and the sidebar's search finds folders with folder:.
- Added: Live Preview tables get plus strips to add a column or row and a cell menu for rows and columns.
- Added: Every picture in a note can be zoomed or opened in a tab of its own from its menu, with a magnifier on hover.
- Added: The maps have a location button that centers on where the person is.
- Changed: A line of photos written side by side shows them at their widths, now also in lists, tables and callouts.
- Fixed [Mac]: Edit Undo and Command-Z reach a PDF's history, and the Underline and Strikethrough icons show in dark menus.
- Fixed [Mac]: A protected PDF's password prompt has a readable field and a full Unlock button.
- Fixed [iPhone]: A search, a tag or Reveal asked for on a phone brings the file list back over the note.
- Fixed: Scrolling a long note is smoother, as the blocks just below the screen are prepared ahead.
- Fixed: Closing a note's tab frees its note and editor from memory.

### 2026-11-10

- Changed: Community plugins whose work Graphite does itself, such as Omnisearch, Maps, Colors and LaTeX Suite, are left out by default until switched on.
- Fixed: A long note switched to Reading view starts at the line the editor was at.
- Fixed [Mac]: Switching to Library mode no longer freezes the window for seconds in a vault with thousands of tags.
- Fixed [Mac]: The note's toolbar comes back faster when switching from Library to List.
- Fixed [Mac]: Fold chevrons no longer redraw at every scroll step.
- Fixed [iPad]: A PDF that took no finger scroll or pinch is reset and scrolls again by itself.

### 2026-11-09

- Added: Pictures zoom over the window as in Obsidian, and photos and files from any app can be dropped on a note and the file tree.
- Changed: Switching between views does less work, so tab switches and the keyboard toolbar feel quicker.

### 2026-11-07

- Added: Graphite keeps its own list of running community plugins apart from Obsidian's, so a plugin can be on in one app and off in the other.
- Fixed: Community plugins such as Dataview and Omnisearch use far less memory in a large vault.
- Fixed: A PDF embedded in a note stays on its page when another device's version replaces the file.

### 2026-11-05

- Added: Line Width Narrow or Wide in a note's Format menu, with bases and their placeholders keeping to the text's column.
- Added [iPad]: Graphite's own pixel eraser cuts the chosen width at any zoom, hides ink live under the tip and takes one Undo step at the lift.
- Added: A base of a plugin's view type says community plugins are off and offers to turn them on.
- Changed [iPad]: The Pencil bar folds its least used controls a stage at a time, so favorite colors, the ruler and Add Image stay on it.
- Changed: Live Preview draws a line of image embeds as pictures side by side at their widths.
- Changed: Bases check every file that could match, and the 5,000-file banner is gone.
- Fixed [iPad]: The Pencil erases while a hand rests on the page.
- Fixed [iPad]: The lasso picks the right strokes at any zoom.
- Fixed [iPad]: A placed picture on a PDF page is drawn sharper.
- Fixed: Plugins in a folder macOS marks hidden are listed and run, as in Obsidian.
- Fixed [iPhone]: A phone's file list marks the open file only while the note is in front.

### 2026-11-04

- Added [iPad]: The pixel eraser offers much smaller sizes, from 1 to 100 points in finer steps.
- Changed [iPad]: The Pencil bar over a PDF is a centered row of its own, upright and sideways, with the sizes of the ink or eraser on it.
- Changed [iPad]: Colors can be moved, removed and added at the bar, and every favorite color and the ruler stay on it at every 11-inch iPad width.
- Changed [iPad]: The Floating Palette and the Fixed Bar offer the same tools, and the palette's Graphite button adds the color in use to the favorites.
- Changed [iPad]: The lasso closes its loop when the Pencil lifts and takes strokes, pictures and text boxes it only partly circles.
- Changed: The name chosen in Settings is written as the author of what Graphite adds to a PDF.
- Fixed [iPad]: Writing on a PDF no longer freezes while a page's ink is saved.
- Fixed [iPad]: A PDF shown again after another tab comes back at once with its ink, zoom and place.
- Fixed [iPad]: Turning the iPad keeps the PDF view, the sidebar as shown, the fitted page and the centered Pencil bar.
- Fixed [Mac, iPad]: Pictures and other marks on a PDF are drawn sharp at the screen's resolution.
- Fixed [iPad]: Ink on a PDF page stays sharp at any zoom.
- Fixed [iPad]: Undo on a PDF page goes back stroke by stroke.

## 1.0.2

### 2026-11-04 13:33

- Fixed [iPad]: Strokes drawn while a PDF page's ink is being decoded are kept.
- Fixed [iPhone]: The folder icon maker, New Note and Read Aloud sheets no longer ask for more room than a phone has.
- Fixed: A failed PostgreSQL copy is tried again a minute after the failure.

### 2026-11-02

- Added: A note over 8 MB opens read-only, a page at a time, with Edit Anyway to trim it, instead of refusing to open.
- Added: Daily notes can be named in the language Obsidian uses, and a note named in another language is found instead of made again.
- Changed [Mac]: The note editor continues lists, indents with Tab, pairs brackets, folds and shows the note's name, as the iPad's does.
- Changed: Word count follows Obsidian's rule, and the Format and Insert menus, Find and Untitled names agree between screens.
- Changed: Diagrams show colors, scroll when wide and say what they cannot draw.
- Changed: Long PDF page lists, external reports and base columns over linked files do far less work.
- Fixed: Renaming or moving an open note keeps it open as it was, with its text, cursor, undo and unsaved work.
- Fixed: Typing during a slow move is kept in a draft, and nothing waits on a move without limit.
- Fixed: Search and the file switcher sort file names by number, list notes before pictures, make Folder and Note and open Note#Heading.
- Fixed: Footnotes, heading links, callouts, embeds, tags and raw HTML read the same in the reading view and in Live Preview.
- Fixed: Fractions, limits and side room in formulas are drawn more accurately, and a highlight runs unbroken behind a formula.
- Fixed [iPad]: Saved ink follows the nib at every angle.

### 2026-11-01

- Changed: Settings opens on its list on iPhone and on the last page used on iPad and Mac.
- Changed: Far more formulas are typeset, including named colors and fractions.
- Fixed [iPad, iPhone]: The Pencil tools stay with a visible PDF in a split, the tool bar folds instead of scrolling, and narrow windows get sheets and menus that fit.
- Fixed [iPad]: A pen lands equally wide on the page at every zoom, and a highlight is as tall as the tool is wide.
- Fixed [iPad]: Undo works during a lasso drag, and the eraser cuts the same gap at every zoom.
- Fixed: Text that cannot be saved stays safe outside the vault, and drawings, drags between vaults and moves made elsewhere lose nothing.
- Fixed: Plugin-drawn bases embedded in a note all draw, and plugins read no notes or code at start-up.
- Fixed: A picture on a PDF page keeps its pixels, and a highlight stays see-through in saved files.
- Fixed: The last note opens before the vault's root is listed, and scans of an unchanged vault write nothing.

### 2026-10-24

- Changed [iPad, iPhone]: Scrolling a long note drops fewer frames, as more off-screen block views are kept.
- Fixed: Inline math wraps as in Obsidian, so a table of formulas fits the note.
- Fixed [Mac]: The editor opens at the passage being read aloud, and arrows in formulas are typeset.
- Fixed: A formula with row breaks inside color groups no longer crashes Graphite.

### 2026-10-23

- Added: Mermaid diagrams are drawn natively in the reading view, including flowcharts with subgraphs, pie charts, mindmaps, state, class, sequence and entity relationship diagrams.
- Added: The reading view also draws Mermaid timelines, Gantt charts, user journeys, XY charts, Git graphs, quadrant charts and Sankey diagrams.
- Added: Live Preview draws a Mermaid block's diagram over its code, and a tap on a diagram shows its source.

### 2026-10-22

- Fixed: A tap on a link in the reading view follows it at once.

## 1.0.1

### 2026-10-22 21:23

- Added: The whole vault's graph opens in a tab of its own, and a note's More menu opens its local graph, with Shift-Command-G and Option-Command-G on the Mac.
- Added: The graph filter reads Obsidian's search words, groups with a search and a color are kept per vault, and a button turns tags on and off.
- Added: Tabs can be stacked side by side as sliding panes, as in Obsidian's Stack Tabs.
- Added: Show All Tabs, Shift-Command-Backslash in the View menu, shows every open tab as a card, as in Safari's tab overview.
- Added: Page Preview, a core plugin, shows a link's card when the pointer rests on it, on Apple Pencil hover or on a long press on the iPad.
- Added: PostgreSQL Mirror, a core plugin that is off until turned on, copies the vault into a PostgreSQL server as it changes.
- Added [Mac]: The note editor suggests links, tags and community plugins' entries while typing.
- Added: Mermaid flowcharts are drawn natively in the reading view.
- Added: Settings › Editor › Remember View keeps a note's view per note or per vault, and Settings explains what each CSS snippet does.
- Changed: A note is placed on the map by its coordinates property, and by location only in a vault with Map View.
- Fixed: A link to a heading below the screen scrolls to it in the reading view.
- Fixed: A printed note shows its bases as the reading view does, and printed cards fill the page.

### 2026-10-21

- Fixed [iPad]: New Notebook from the New menu opens its sheet.
- Fixed [iPad]: The fixed Pencil bar keeps its favorite colors with the text tool on it.
- Fixed [Mac]: The Mac app can print.

## 1.0

### 2026-10-21 22:55

- Added: A welcome tour introduces Graphite to TestFlight testers, and a Guide teaches the app step by step.
- Added: Paper documents can be scanned into a PDF.
- Added: Folders can be customized as in Finder, with colors, pictures as folder icons and Apple's folder art, and look the same in Graphite, Files and Finder.
- Added [Mac, iPad]: Several windows can be open at once, on the same or different vaults, with New Window on Option-Command-N, and each window restores its own tabs.
- Added [Mac, iPad]: Keyboard shortcuts can be changed in Settings per vault and are shared with Obsidian's hotkeys file.
- Added: Goodnotes and Notability notebooks can be imported into the vault.
- Added: A note can be exported to PDF from More, and printed with Command-P on the Mac.
- Added: Text boxes can be typed and arranged on PDF pages, taken by the lasso, found by Search and read by Read Aloud.
- Added: My Templates uses a page of a PDF or a picture as paper for new notebooks, and a new notebook can have a cover.
- Added: Image from Photos and Take Photo are in the New menu, and several tiles can be chosen and dragged in the library.
- Added [Mac]: Reveal in Finder shows a file in Finder.
- Changed: The house button works as a tab, going back to the folder shown and then to the vault root.
- Fixed [Mac]: Opening a note on the Mac no longer reserves 170 MB.
- Fixed: Display formulas break a late fraction onto a new line and support underbrace and overbrace.
- Fixed [iPad, iPhone]: Library folders are drawn blue by Graphite instead of Quick Look.

### 2026-10-20

- Added: Obsidian-compatible Markdown vaults with Live Preview, reading view and source mode, links, tags, properties, callouts, tables edited in place, math and code blocks.
- Added: Apple Pencil handwriting with pens, a highlighter, an eraser, a lasso, shape snapping, palm rejection and a laser pointer.
- Added: PDF reading and annotation, with ink, pictures, highlights and links on PDF pages, and PDFs embedded in notes.
- Added: Drawings embedded in notes, and Obsidian canvases with cards and ink.
- Added: Bases show notes as tables, lists, cards, Kanban boards and maps, including on the iPhone.
- Added: Graph view, Map View of placed notes, backlinks and an outline of each note.
- Added: Lecture recording saved with the notes.
- Added: Read Aloud reads notes and PDFs with natural downloadable voices, a floating player, pronunciations and a highlight that follows the words.
- Added: Community plugins from Obsidian's directory run inside the app, with Obsidian themes, fonts and CSS snippets.
- Added: A notebook library with page sizes, a paper gallery, covers, folder colors and a Library view of files.
- Added: Tabs, split panes, a file tree styled like Obsidian's and a command palette.
- Added [Mac]: A Mac app with a Settings window on Command-comma and a file tree that opens vaults of tens of thousands of files.
- Added [iPhone]: Phone layouts for notes, properties and bases.
- Fixed: Table of contents links find headings by their GitHub names, and formulas in the reading view keep their letters.
- Fixed: Read Aloud's Stop holds during a fold change, and switching vaults leaves the old vault's queue, folds, graph and map behind.
- Fixed: A link to a missing audio or video file creates no note, and a note created on the Mac starts editing.
