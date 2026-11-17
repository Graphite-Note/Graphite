# Editing comfort: typing helpers and papercuts, implementation TODO

Created: 2026-11-16.

Status: started 2026-11-16; sections 1 to 7 built and tested by 2026-11-17. The reference is Obsidian's own editor, read from Obsidian 1.15.1's code on this Mac (`obsidian-1.15.1.asar`, the CodeMirror setup of its Markdown view), plus Apple Notes and Goodnotes where Obsidian has no answer. The typing helpers live in `MarkdownEditing` (Core) and reach the iPad's and the Mac's editors through `EditingBehavior.typingEdit` (`EditingBehaviorTyping.swift`), so one change serves Live Preview and Source mode on iPad, iPhone and Mac.

## Request

The owner, 2026-11-16: "also when i write ``` it should close it with the other ``` we need to start hunting down for bugs of that nature and things that make the app not nice to use".

What Obsidian does, from its code:

- "Auto pair brackets" pairs `(`, `[`, `{`, `'` and `"`. "Auto pair Markdown syntax" pairs `*`, `_`, `` ` `` and the fence ```` ``` ````, and makes `=`, `~`, `$` and `%` wrap a selection (they pair nothing when nothing is selected). Pairs are typed only where the character before is not a letter or digit, and a closing character typed over the one just inserted steps over it.
- Three backticks give ```` ```|``` ```` on one line. Return inside code, a table or a math block keeps the line's indentation (`newlineAndIndentOnly`); elsewhere smart lists continue lists, tasks and quotes. `~~~` and `$$` are not completed.

## 1. Code fences close themselves

Issue: [#196](https://github.com/Graphite-Note/Graphite/issues/196)

- [x] Typing the third backtick of ```` ``` ```` at the start of a line (after any indentation or `>` markers) puts the closing fence on the line below, with the cursor after the opening fence so the language can be typed; Return then opens the empty line between. Live Preview and Source mode, iPad, iPhone and Mac. It follows "Auto pair Markdown syntax", as Obsidian's fence pairing does. No closing fence is added when the fence closes an open block, or when a fence below has no partner (its opening fence was deleted and is being retyped). Undo takes the backtick and the closing fence back in one step.
  Differs from Obsidian on purpose: Obsidian puts the closing fence on the same line (```` ```|``` ````), and the owner asked for it below.
  Done 2026-11-16: `MarkdownEditing.closingCodeFence` (`MarkdownCodeFenceClosing.swift`), called from `EditingBehavior.typingEdit` when "Auto pair Markdown syntax" is on, so the iPad's, iPhone's and Mac's editors in both modes share it. A fence is left alone when the line is inside code or the properties, or when the fences below, read by themselves, leave one open; a whole block below (```` ```js … ``` ````) does not stop it. The closing line repeats the fence's indentation and `>` markers and the note's line ending. Tests: `CodeFenceClosingTests` (8: placement, quotes and callouts, CRLF, closing an open block, an unmatched fence below, a whole block below, only the third backtick of a bare line start, properties); `MacEditorParityTests.testATypedFenceClosesBelowAndUndoTakesItBackInOneStep` (the Mac's text view: fence, `js`, Return gives the empty line between, one Undo gives back `` `` ``); hosted `EditingComfortHostedTests` on the iPad and iPhone simulators (Live Preview and Source mode typed key by key, Undo, an unmatched fence below); a hosted screenshot shows the finished block in Live Preview with the cursor on its code line. Not tried by hand on a device, since the owner declined computer use today.
- [x] Return inside a code block keeps the line's indentation, as Obsidian does; in a code block inside a callout or quote, the new line also keeps the `>` markers, so the block stays in its callout (before, Return wrote a bare line that ended the callout). Indented text outside code, such as an item's second paragraph or the properties' YAML, keeps its indentation too.
  Done 2026-11-16: `MarkdownEditing.newLineKeepingIndentation` (`MarkdownNewLineIndentation.swift`), used for Return when no list continues, with or without smart lists, as in Obsidian. In code it keeps the quote markers of the fence's own quote depth (`codeQuoteDepth`, the code check of `continuingList` now also giving that depth), so `>>> print(1)` in code stays code. Tests: `NewLineIndentationTests` (code, callout code, doctest, item paragraphs and YAML, cursor inside the indentation, selection and CRLF), hosted `testReturnInACalloutsCodeKeepsItsMarkersAndIndentation`; `CodeHighlightingTests` still pass.
- [x] `~~~` and `$$` are not completed, as in Obsidian.
  Done 2026-11-16: checked in Obsidian 1.15.1's code: its fence pairing lists only ```` ``` ````, and `$` and `~` only wrap a selection. `CodeFenceClosingTests.testOnlyTheThirdBacktickOfABareLineStartCompletesAFence` holds `~~~` to typing alone.

## 2. Pairs and wrapping follow Obsidian's two settings

Issue: [#197](https://github.com/Graphite-Note/Graphite/issues/197)

- [x] A backtick pairs under "Auto pair Markdown syntax", as in Obsidian, not under "Auto pair brackets", where Graphite had it.
  Done 2026-11-16: `MarkdownEditing.markdownPairs` holds the backtick; the bracket pairs are `( [ { " '`; `deletingPair` and the step-over follow the same two settings. Tests: `SmartEditingTests.testABacktickPairsWithTheMarkdownSettingAsInObsidian`, `MacEditorParityTests.testABacktickPairsUnderTheMarkdownSettingAndAQuoteUnderBrackets`.
- [x] `'` pairs under "Auto pair brackets", as in Obsidian, only where no letter or digit comes before it, so "it's" and "l'été" stay as typed; a `'` typed over the inserted one steps over it.
  Done 2026-11-16: the same rule as `"`: no pair after a letter, a digit or another `'`, nor before a word. Tests: `SmartEditingTests.testASingleQuotePairsOnlyAtTheStartOfAWordAndStepsOver`, the Mac test above.
- [x] `%` wraps a selection, so typing `%` twice over selected text makes an Obsidian comment (`%%text%%`).
  Done 2026-11-16: `%` joined `markdownWrapMarkers`; with nothing selected it is typed alone. Test: `SmartEditingTests.testPercentWrapsASelectionTwiceIntoAComment`.
- [x] ~~`*` and `_` typed with nothing selected pair as `**` and `__`, as Obsidian does.~~ Not copied: a bullet started with `* ` would carry a stray `*` at the end of the line, and an underscore in a file name or `snake_case` would get a second one. Graphite keeps wrapping a selection with them.

## 3. Return, Tab and Backspace in lists

Issue: [#198](https://github.com/Graphite-Note/Graphite/issues/198)

- [x] Shift-Return in a list item breaks the line without a new marker, with the new line indented to the item's text, as Obsidian's Shift-Enter does (Mac, and iPad with a hardware keyboard). It must never write a Unicode line separator into the note.
  Done 2026-11-16: the `lineBreakInItem` editor command runs `MarkdownEditing.breakingLineWithinItem`: in an item the new line is indented to its text (marker and spacing as spaces, a tab kept), in a quote it keeps the `>` markers, in code the indentation, elsewhere a plain line break. The Mac's text view takes Shift-Return (Return and keypad Enter) in `keyDown` and Control-Return in `insertLineBreak`, which wrote U+2028 before (AppKit's binding, checked with a probe); the iPad's text view has a Shift-Return key command, which a hardware keyboard reaches. Tests: `NewLineIndentationTests` (2), `MacEditorParityTests.testShiftReturnBreaksAnItemsLineWithoutANewItemAndControlReturnWritesNoLineSeparator` (a real Shift-Return key event, Undo, Control-Return), hosted `testShiftReturnFromAHardwareKeyboardBreaksAnItemsLineWithoutANewItem` (the key command is there and runs the edit). A real hardware keyboard on an iPad is not tried.
- [x] Return continues bullets, numbers, tasks and quotes and renumbers the items below; Return on an empty item ends the list or moves the item out one level; Tab and Shift-Tab indent and outdent list items; Backspace between an empty pair removes both halves.
  Done 2026-11-16: checked as already built and covered: `SmartEditingTests` (Core), `MacEditorParityTests` (Mac: Return, numbers, tasks, Tab, pairs, Undo), hosted `LivePreviewRevealTests.testPairingListsAndToolbarCommandsKeepWorking` (iPad). Backspace at the start of an item's text deletes the space before it, as in Obsidian, which has no handler of its own there.

## 4. The iPad and iPhone keyboard

Issue: [#199](https://github.com/Graphite-Note/Graphite/issues/199)

- [x] Autocorrect and automatic capitals stay out of code: inside a fenced code block or inline code the keyboard neither corrects nor capitalizes words, so `int` and `printf` are left as typed. Obsidian's editor turns autocorrect on everywhere; Apple's own editors for code (Swift Playgrounds) turn it off, and code is never prose.
  Done 2026-11-16: `updateKeyboardForCode` (`NativeMarkdownEditorCodeKeyboard.swift`) runs on every selection change and settled edit; `MarkdownEditorStyling.isCode` answers from the block context checkpoints and the one line's inline code spans, and the keyboard is reloaded only when the cursor crosses into or out of code. The opening fence's own line, where the language is typed, counts as prose. Test: hosted `testTheKeyboardNeitherCorrectsNorCapitalizesInCode` (prose, a code block, inline code, prose again, and a typed fence). The keyboard's look as it reloads is not checked on a device.
- [x] Smart quotes and smart dashes cannot break Markdown: they are off in the note editor (`NativeMarkdownEditor` sets `smartQuotesType` and `smartDashesType` to `.no`, the Mac's editor turns quote and dash substitution off), and edits go through `replaceCharacters(in:with:in:)`, which does not turn `---` into an em dash.
  Done 2026-11-16: checked in the code; no change needed.

## 5. Checks that need a device

Issue: [#200](https://github.com/Graphite-Note/Graphite/issues/200)

- [x] The keyboard bar's buttons, the caret after a block renders, selection handles next to embeds, and pasting rich text and web addresses, tried by hand on the iPad and iPhone simulators and in a re-signed Mac copy, with what was seen.
  Done 2026-11-17, by the editor's own controls in hosted tests on an iPad simulator, standing in for a hand (the owner declined computer use; the brief allowed hosted tests or XCUITest where they can stand in): `EditingComfortHostedTests.testEveryFormattingButtonOfTheKeyboardBarEditsTheSelectionAndUndoes` presses each formatting button of the bar (Bold, Italic, Strikethrough, Highlight, Code, Inline math, Link to note, Tag, the three lists, Indent, Move line down) through its own action over a selected word: each makes its edit and one Undo takes it back. `testPastingAnAddressOverASelectionLinksItAndRichTextBecomesMarkdown`: an address pasted over "guide" gives `[guide](https://help.obsidian.md)`, and HTML on the pasteboard is pasted as `**Bold** and [a link](https://example.org)`. `testTheCursorStaysBelowAMathBlockThatRendersAsItIsLeft`: a math block typed key by key and left with Return renders, and the cursor stays after "After", below the formula (screenshot looked at). `testASelectionAcrossARenderedTableHasItsEndsAtTheText`: the selection's ends, where the handles go, are on "table" above and "Below" below, a line high each, with the table between (screenshot looked at: both handles at the text, the table highlighted). Not covered: a pasteboard filled by another app (iOS asks before an app reads another's), the Heading and Attach menus (their actions are not reachable without a tap), and the Mac copy, which needs computer use.

## 6. Live Preview while the cursor is in a callout's code block

Issue: [#201](https://github.com/Graphite-Note/Graphite/issues/201)

- [x] With the cursor in a code block inside a callout, Live Preview draws the code lines' grey box from the left edge, outside the callout's bar, with the `>` markers in front of it; the callout's other lines stay inside the bar. Seen 2026-11-16 in the hosted screenshot of `testReturnInACalloutsCodeKeepsItsMarkersAndIndentation` (iPad simulator).
  Done 2026-11-17: a quoted code line's `>` markers were inside its code span, so they took the code's background and were never drawn as the bar. `drawCodeBlocksAsBoxes` now gives them the quote bar, as a quoted text line's markers get it (`drawQuoteBars(ofQuotedCodeLine:)`), and the background starts after them. Test: hosted `testACalloutsCodeLinesStayInsideItsBarsWhileTheCursorIsInIt` (the markers of both code lines are bars without background; the code keeps it); screenshot looked at: the bar runs down past the code lines and the code sits inside it. `CodeHighlightingTests` still pass. The Mac's editor draws no bars, as before. Found on the way: `LivePreviewCalloutTableHostedTests` failed whenever a test with a callout ran before it (its class sorts after this one): it read the callout's first height, an estimate that the heights measured earlier in the run correct (236 instead of about 200), so the new row seemed to add nothing. It now waits for the callout's height to settle first, and passes after `EditingComfortHostedTests`.

## 7. Lists after Tab, Shift-Tab, moved lines and Backspace

Issue: [#205](https://github.com/Graphite-Note/Graphite/issues/205)

Found in Obsidian 1.15.1's code: its indent and outdent move an item's nested lines with it, its smart lists count numbered items again after every change, and CodeMirror's Backspace deletes a whole level in leading spaces.

- [x] Tab and Shift-Tab carry the nested lines of the last selected item (its child items and continuation lines) along, so a parent keeps its children; Shift-Tab carries them only when the item itself moves out.
  Done 2026-11-17: `MarkdownEditing.endOfNestedLines(under:in:tabSize:onlyWhenIndented:)` widens the lines `indenting` and `outdenting` change. Tests: `SmartEditingTests.testTabAndShiftTabCarryTheItemsNestedLinesAlong` (tabs, spaces, quotes, a sibling left alone, a top-level item), `MacEditorParityTests.testTabCarriesAnItemsChildrenAndRenumbersAndBackspaceRemovesALevelOfSpaces` (Tab in the Mac's text view, one Undo).
- [x] Numbered lists are counted again after Tab, Shift-Tab and moved lines, in the same edit, so one Undo takes both back: Tab on `2.` of `1. 2. 3.` gives a nested `1.` and turns `3.` into `2.`; a line moved to a list's top takes its first number; a list numbered all alike (`1. 1. 1.`) is left as written.
  Done 2026-11-17: `MarkdownEditing.renumberingLists(after:in:tabSize:)` (`MarkdownListRenumbering.swift`), applied by `indenting`, `outdenting` and `movingLines`. Tests: `ListRenumberingTests` (5: Tab and Shift-Tab, joining a nested list, moved lines including a list from 5, lists numbered alike, bullets and quotes, a number growing a digit before the cursor), the Mac test above.
- [x] Backspace in a line's leading spaces deletes back to the previous level in a vault that indents with spaces, as CodeMirror does; one space after text, and a tab, as before.
  Done 2026-11-17: `MarkdownEditing.deletingIndentation`, called for Backspace in `EditingBehavior.typingEdit`. Tests: `NewLineIndentationTests.testBackspaceInLeadingSpacesRemovesALevel`, the Mac test above.
- [x] Numbered lists counted again after any other edit that adds or removes lines, such as a deleted item or pasted lines, as Obsidian's smart lists do after every change, in the same edit, so one Undo takes both back.
  Done 2026-11-17: `EditingBehavior.typingEdit` hands any edit that adds or removes a line break, and that no key helper took, to `MarkdownEditing.renumberingLists(replacing:with:in:tabSize:)`, which returns nil when the numbers stay as they are, so the text view makes every other edit itself, and composing is never touched. The iPad's and iPhone's paste now asks the editor first, as UIKit's own paste does (`MarkdownTextView.insertPastedText`; it inserted without asking, so a paste also skipped the opening of a folded section). Tests: `ListRenumberingTests` (deleted items, Backspace from the line above, a nested list, pasted items, edits left alone), `MacEditorParityTests.testDeletingOrPastingItemsCountsTheListAgainAndOneUndoTakesItBack` (the Mac's own delete and paste), hosted `EditingComfortHostedTests.testDeletingOrPastingItemsCountsTheListAgain` (iPad Pro 13-inch (M5) simulator, iOS 27.2: the keyboard's Backspace over an item, Undo, then UIKit's paste of two items). Not checked with real keys in a Mac copy of the app: access to drive it was declined on 2026-11-17, so the Mac rests on its own delete and paste in the package test.
- [x] Return at the end of an item that has children starts its first child, with the child's indentation, marker and checkbox, and the children count on after it, as Obsidian does; before, the new item went between the item and its children and took them.
  Done 2026-11-17: `MarkdownEditing.continuingAsFirstChild` (`MarkdownNewLineIndentation.swift`), called by `continuingList` when the cursor ends a non-empty item. Tests: `NewLineIndentationTests.testReturnAtTheEndOfAnItemWithChildrenStartsItsFirstChild` (bullets, numbers, tasks with spaces, quotes, Return inside the text, no child), hosted `EditingComfortHostedTests.testReturnAtAnItemWithChildrenStartsItsFirstChild` (screenshot looked at: the new 1. above Draft and Review, now 2. and 3.).
- [x] Return inside an item's text drops the spaces after the cursor, so `- foo| bar` gives a new item `- bar`, not `-  bar`, as Obsidian's list continuation removes them.
  Done 2026-11-17: `MarkdownEditing.continuingList` replaces the spaces and tabs after the cursor with the new item's marker. Tests: `NewLineIndentationTests.testReturnInsideAnItemDropsTheSpacesAfterTheCursor` (bullets, numbers with renumbering, tasks).
