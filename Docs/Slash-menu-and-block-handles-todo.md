<!--
 File: Slash-menu-and-block-handles-todo.md
 ------------------------------------------
 Layer: Docs
 Description: The plan and record of the slash menu and the block handles of Live Preview.

 Authors: Bahey Shalash
 Version: 0.1
 Date: 26/11/2026
-->

# Slash menu and block handles: TODO

Created: 2026-11-26.

Status: 2026-11-26, section 1 (the slash menu) built and tested on the Mac, an iPad simulator and an iPhone simulator, except real taps and the Mac app by hand; sections 2 and 3 not started. Issues: [#238](https://github.com/Graphite-Note/Graphite/issues/238) to [#240](https://github.com/Graphite-Note/Graphite/issues/240), one per section.

## Request

Feature 4 of [Notion-features-for-Graphite.md](Notion-features-for-Graphite.md#4-slash-menu-and-block-handles), requested 2026-11-26: a slash menu, then block handles in Live Preview. `/` opens the editor's completion popup with the Insert menu's entries and the commands, filtered as typed. A handle in the left margin of the block under the pointer (on the iPad, under a long press) drags the block, a heading with its section, and opens a menu that turns a paragraph into a heading, a quote, a callout or a task. Handles appear only on hover or touch. The slash menu lands before block handles are started.

## What the result must be

- **Only Markdown reaches the file.** Choosing an entry writes the Markdown the Insert menu writes, and the `/` and the letters typed after it are taken out. Moving a block moves its lines and nothing else. No identifier, comment or property is added to a note.
- **Obsidian's behaviour where it has one.** Obsidian 1.15's Slash commands core plugin (read in its `obsidian-1.15.1.asar`): off until turned on in Settings › Core plugins; it opens when the text before the cursor on its line matches `(^|\s)\/([^\s\/]*)$`, so `/` at the start of a line or after a space or tab, and the letters after it up to the cursor are the query; a space or a second `/` ends the match and closes the list; the list is every command of the command palette, fuzzy-matched, with each command's hotkey on its right; choosing one removes `/query` (`replaceRange("", start, end)`) and runs the command. The list opens only on typing (`EditorSuggest.trigger` opens it only for a change made by typing, and keeps it while open). Obsidian has no block handles in core.
- **One list of entries.** The slash menu shows the Insert and Paragraph entries the toolbar's and the menu bar's menus are made from (`EditorContextMenuContent`), and the command palette's commands (`WorkspaceCommandList`), never a copy of either (FR-17).
- **Every platform.** Mac, iPad with a hardware keyboard or by touch, iPhone. Keys: Up and Down move, Return and Tab choose, Escape closes. A tap chooses.
- **No permanent chrome.** Nothing is added above or beside the page. The popup shows while `/…` is typed; a handle shows only while the pointer is over a block or a finger holds it.
- **Off costs nothing.** With Slash Commands off, typing runs no slash check. Block handles are made the first time the pointer rests on a block or a finger holds the margin, never when a note opens.
- **Typing stays as fast.** A keystroke is measured before and after each section, the numbers recorded here.

## Decisions

1. **On by default.** Decided 2026-11-26: Obsidian ships Slash commands off, but in Graphite a switching student who types `/` and gets nothing assumes the feature is missing ([Notion-features-for-Graphite.md](Notion-features-for-Graphite.md#4-slash-menu-and-block-handles)), and the trigger rule keeps `and/or`, `1/2` and links from opening it. It is a core plugin of its own, Settings › Core Plugins › Slash Commands, so it can be turned off as in Obsidian. Graphite's core plugin switches are kept per device (`CorePluginSwitches`), not in the vault's `.obsidian/core-plugins.json`, as every other one is.
2. **Blocks before commands.** With nothing typed after `/`, the menus' entries come first in the menus' order (Paragraph: lists, task, headings, body, quote; Insert: table, callout, code, math, Mermaid, rule, tag, then links, embeds, attachments, drawing, notebook and template; Format: bold to comment, without the colours, which need a selection), then the command palette's commands. A query ranks all of them by the fuzzy match the command palette uses (`FuzzyMatcher`); equal scores keep that order. Palette commands that do what a block entry does (Set as heading N, Insert task, table, math block, callout, template, notebook, drawing) are left out, so each action is listed once.
3. **Not in code, math or the frontmatter.** Typing `/` inside a code block, inline code, a math block or the frontmatter opens nothing: a path or a comment such as `/usr/bin` or `// note` is common there, and Return would run a command instead of starting a line. Obsidian opens it there too; this is the one place Graphite differs.
4. **Where the entry lands.** The entry runs at the cursor as it does from its menu, on the note as it is once the `/query` is taken out: a block (table, callout, code, math, Mermaid, rule) on lines of its own, a heading, list, task or quote mark on the cursor's line. The removal and the entry's edit are made as one edit, so one Undo gives the `/query` back (as two edits, Undo took back the block and left the note without the typed `/query`). An entry that opens a dialog (a link, a template, a photo) opens it, and a palette command runs once the `/query` is out.
5. **Mermaid and Embed join the Insert menu.** The Notion research names Mermaid diagrams and embeds of a base. Both become Insert entries, so the menu bar, the toolbar and the slash menu list them alike: Mermaid Diagram writes a ```` ```mermaid ```` block, and Embed writes `![[]]` with the cursor inside, where the link completion lists the vault's files, bases included.
6. **Handles act on Markdown blocks as folding knows them.** A block is a paragraph, a list item with its nested items, a heading with its section (`NoteFolding`'s heading region), a quote or callout, a table, a code or math block, a rule or an embed. One pure function finds the block at a line, tested with plain text, shared by the Mac and the iPad (FR-05, FR-06).

## 1. The slash menu

Issue: [#238](https://github.com/Graphite-Note/Graphite/issues/238)

- [x] Typing `/` at the start of a line or after a space or tab in a note being edited (Live Preview or Source) opens the completion popup; the letters typed after it filter the list; a space, a second `/`, moving the cursor out of the query, or Escape close it. It opens only on typing, never when the cursor is placed after an existing `/`. Not in code, math or the frontmatter (decision 3).
  Done 2026-11-26: `SlashCommandTrigger` (Core) reads Obsidian's rule; `EditorCompletionTracking` opens the list only for an update that follows typing (`followsTyping`, from `textViewDidChange` and `textDidChange`) and keeps it while the cursor stays in the same query; the block a line is in comes from the editors' styling checkpoints. Tests: `SlashCommandTriggerTests` (8), `SlashCommandListTests` (tracking), `UiEditorMacSlashCommandsTests`, `SlashCommandsHostedTests.testPlacingTheCursorAfterAWrittenSlashOpensNothing` and `testEscapeAndASpaceCloseTheListAndReturnThenStartsALine`.
- [x] The list: the Insert and Paragraph entries, then the command palette's commands (decision 2), each with its symbol, the matched letters in the accent colour, and the command's shortcut on the right.
  Done 2026-11-26: `SlashCommandList` and `SlashCommandSource` from `EditorContextMenuContent.slashMenuEntries` and the window's `WorkspaceCommandList` (through `WindowPaletteCommands`), without the palette commands a menu entry already offers; the popup shows `CompletionItem.shortcut`. Tests: `SlashCommandListTests`, `SlashCommandsHostedTests.testThePalettesCommandsFollowTheBlocks`; the popup looked at in the hosted tests' screenshots on the iPad and the iPhone (`/tab` lists Table with Tab in the accent colour).
- [x] Choosing an entry with Return, Tab, a click or a tap removes `/query` and runs it (decision 4), as one undo step.
  Done 2026-11-26: `SlashCommandEditRecorder` and `SlashCommandList.combined`. Tests: `SlashCommandListTests` (a block, a heading, a dialog, a command, a query no longer typed, the combination), `UiEditorMacSlashCommandsTests.testSlashTabThenReturnInsertsATableAndUndoGivesTheTypedQueryBack` (Mac key events), `SlashCommandsHostedTests.testSlashTabThenReturnInsertsATableAndOneUndoTakesItBack`, `testTheDownArrowAndReturnChooseTheSecondEntry` and `testAChosenRowSetsTheLineAsAHeading` (a row chosen through its accessibility action, the path a tap takes that a test can drive).
- [x] Mermaid Diagram and Embed in the Insert menu (decision 5).
  Done 2026-11-26: `EditorContextMenuContent.mermaidBlock` and `embedBlock` with their typing places, in the toolbar's, the menu bar's and the context menu's Insert menus. Tests: `SlashCommandListTests.testMermaidAndEmbedBlocksPlaceTheCursorWhereTheyAreFilledIn`, `ConsistencyBugHuntTests` (the menus' titles alike).
- [x] Settings › Core Plugins › Slash Commands turns it on and off; off, typing runs no slash check (decision 1).
  Done 2026-11-26: `CorePlugin.slashCommands`, on by default; off, the pane gives the editor no `SlashCommandSource` and the tracking skips the check. Tests: `SlashCommandListTests.testSlashCommandsIsACorePluginOnByDefault` and `testOffTheEditorsLookForNoSlashAndLinksComeFirst`, `GraphitePreferencesPersistedKeysTests`, `SlashCommandsHostedTests.testTurnedOffASlashIsJustTyped`, `UiEditorMacSlashCommandsTests.testOffTheSlashIsJustTyped`. The Settings page itself not looked at.
- [x] Unit tests: the trigger and its query from plain text (start of line, after a space, after a tab, inside a word, a second `/`, a space, code, math, frontmatter, a cursor placed without typing), the ranking and the dedup of the list, the edits of choosing an entry.
  Done 2026-11-26: `SlashCommandTriggerTests` (8) and `SlashCommandListTests` (17), passing on the Mac.
- [x] Hosted iPad tests driving real keys and touches: `/tab` then Return inserts a table; `/h2` then a tap on the row sets a heading; Escape closes; a space closes.
  Done 2026-11-26: `SlashCommandsHostedTests` (7), characters through the editor's `shouldChangeTextIn` as the keyboard sends them and the hardware keyboard's arrows and Escape as the text view's own key commands, passing on an iPad Pro 11-inch (M5) and an iPhone 17 Pro simulator (iOS 27.2) of their own.
- [ ] Checked in a dedicated iPad simulator (hardware keyboard and touch), an iPhone simulator and a Debug copy of the Mac app.
  2026-11-26: the hosted tests ran in the app on both simulators, with their screenshots looked at, and the Mac's editor was driven by key events in `UiEditorMacSlashCommandsTests`. Not done: a real finger tap on a row in the simulator (access to the simulators was not granted) and the Mac app by hand.
- [x] Typing latency measured before and after.
  Done 2026-11-26: `PerformanceBenchmarkTests.testOpeningScrollingAndTypingInALongNote` on the development Mac, Debug, a build of main without the slash commands (ec2001a6) and one with them, run in turn twice, three runs each, with a load average of 380 to 650 from other builds. Median frame of a keystroke, before and after: 12.8 and 11.1 ms in a paragraph, 16.0 and 14.0 ms in a list item, 16.8 and 14.1 ms in a callout; the main thread's time a key 15.0 and 14.6, 19.7 and 18.6, 17.4 and 15.9 ms. The differences are within the load's noise: no cost is measurable. A key typed inside a `/` query reads only its own line: `SlashCommandTriggerTests.testAQueryAtTheEndOfALongNoteReadsOnlyItsLine` keeps it under 1 ms at the end of a 5,000-line note (43 ms when the trigger read the lines before for code and math, as `LinkCompletion` does).
- [x] `Docs/Obsidian-mobile-gaps.md` (Slash commands), `Docs/Architecture.md` and `Docs/Coverage.md` updated.
  Done 2026-11-26.

## 2. Block handles on the Mac

Issue: [#239](https://github.com/Graphite-Note/Graphite/issues/239)

- [ ] The block under the pointer in Live Preview shows a handle (`⋮⋮`) in the left margin, beside the fold chevron, while the pointer is over the block or the handle; it goes when the pointer leaves. Nothing shows in Source mode or in the reading view.
- [ ] Dragging the handle moves the block, a heading with its section, to the place shown by an insertion line between blocks; dropping it moves the lines as one undo step. Escape cancels a drag.
- [ ] Clicking the handle opens a menu: Turn into Heading 1, 2, 3, Quote, Callout and Task (on a paragraph or a list item), and the heading's level or Body on a heading.
- [ ] Unit tests: the block at each kind of line, the move edit (up, down, into another section, past the end, onto itself), the turn-into edits.
- [ ] Package tests driving mouse events on the Mac editor: the handle appears on hover and goes, a drag moves a section, the menu turns a paragraph into a callout.
- [ ] Checked in a Debug copy of the Mac app; typing latency measured before and after.

## 3. Block handles on the iPad and iPhone

Issue: [#240](https://github.com/Graphite-Note/Graphite/issues/240)

- [ ] A finger's long press in the left margin beside a block in Live Preview shows the block's handle and lifts the block; moving drags it to the insertion line, lifting drops it; lifting without moving opens the same menu as on the Mac. Apple Pencil never starts it, and a long press on the text still selects text as before.
- [ ] Hosted iPad tests with synthesized touches: a long press in the margin then a move drags a heading's section; a long press on text still starts a selection; a Pencil touch in the margin does not lift the block.
- [ ] Checked in a dedicated iPad simulator and an iPhone simulator; typing latency measured before and after.
- [ ] `Docs/Architecture.md` and `Docs/Coverage.md` updated.
