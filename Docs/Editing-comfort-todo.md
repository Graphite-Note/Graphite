# Editing comfort: typing helpers and papercuts, implementation TODO

Created: 2026-11-16.

Status: started 2026-11-16; sections 1 to 4 built and tested 2026-11-16, sections 5 and 6 open. The reference is Obsidian's own editor, read from Obsidian 1.15.1's code on this Mac (`obsidian-1.15.1.asar`, the CodeMirror setup of its Markdown view), plus Apple Notes and Goodnotes where Obsidian has no answer. The typing helpers live in `MarkdownEditing` (Core) and reach the iPad's and the Mac's editors through `EditingBehavior.typingEdit` (`EditingBehaviorTyping.swift`), so one change serves Live Preview and Source mode on iPad, iPhone and Mac.

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

- [ ] The keyboard bar's buttons, the caret after a block renders, selection handles next to embeds, and pasting rich text and web addresses, tried by hand on the iPad and iPhone simulators and in a re-signed Mac copy, with what was seen.
  Open: the owner declined computer use and the simulator panel on 2026-11-16, so this run checked the typing helpers through the editors' own text views (package tests on the Mac's `MarkdownMacTextView` with real key events, hosted tests with screenshots on the iPad and iPhone simulators) and not by hand. These four need a person's taps, a pasteboard from another app, or a picture beside the cursor.

## 6. Live Preview while the cursor is in a callout's code block

Issue: [#201](https://github.com/Graphite-Note/Graphite/issues/201)

- [ ] With the cursor in a code block inside a callout, Live Preview draws the code lines' grey box from the left edge, outside the callout's bar, with the `>` markers in front of it; the callout's other lines stay inside the bar. Seen 2026-11-16 in the hosted screenshot of `testReturnInACalloutsCodeKeepsItsMarkersAndIndentation` (iPad simulator). Obsidian shows a callout's whole source as text while the cursor is in it. Not fixed yet: it is the code block styling's layout inside quotes (`MarkdownTextStyler+CodeBlocks.swift`), not a typing helper.
