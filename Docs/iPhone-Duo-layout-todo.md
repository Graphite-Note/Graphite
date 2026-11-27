# iPhone Duo layout

Request (decided 2026-10-21): get the app ready, layout-wise, for iPhone Duo, which Xcode 27.1 supports (iOS 27.1 SDK and a simulator for its poses and orientations). Apple's guidance is "Designing for iPhone Duo" in the Human Interface Guidelines.

Decisions:

- Graphite keeps one layout per size class. The outer display is a compact width (the phone layout) and the inner display a regular one. The system stands toolbars and the bottom bar on the side, and Graphite does not override where it puts them.
- On iOS a document's More commands go into the system's overflow menu, so the bar never shows two "•••" buttons. The Mac keeps its More menu.
- Graphite's own views follow a partly folded display through the system's division regions (iOS 27.1). The deployment target is iOS 27.0 ([OS-26-support-todo.md](OS-26-support-todo.md)), and the fold code does nothing before 27.1.

## 1. Layout on the Duo's displays and around the fold

Issue: [#56](https://github.com/Graphite-Note/Graphite/issues/56)

- [x] Done 2026-10-21: the Tabs button is a numbered-square symbol titled "Tabs" (`TabCountLabel`), so the system moves it with the bar to the side instead of keeping it at the bottom of the outer display. Checked on the Duo simulator's outer display.
- [x] Done 2026-10-21: the phone's bottom bar is separate toolbar items and groups with flexible spacers. Finding a file, a new note and the tabs have a high visibility priority. Checked on the Duo simulator's outer display and on iPhone 17 Pro, where the bar looks as before.
- [x] Done 2026-10-21: on iOS, the note's, PDF's, canvas's and window's More commands are in the system's overflow menu (`ToolbarOverflowMenu`). Checked on the Duo simulator's outer display (one "•••" holding the Command Palette and the note's commands) and on iPad Pro 11-inch (the window's menu).
- [x] Done 2026-10-21: the policy for placing content around a fold (`DisplayFoldLayout` in Core: the largest region beside it, the split fraction on it, even columns over it), pinned by `DisplayFoldLayoutTests`.
- [x] Done 2026-10-21: in code, the two-sided workspace's divider is held on a fold, and the palettes, the notice banner and the Read Aloud floating player are placed beside it. Library mode's grid takes an even number of columns over a fold. Built for the Duo simulator; the folded behaviour is checked in section 2.
- [x] Done 2026-10-21: a phone's keyboard toolbar shows Undo and Redo only in a compact width, so the inner display, whose note toolbar has them, does not show two pairs. Built; checked in section 2.

## 2. Checks on the inner display and folded poses

Issue: [#63](https://github.com/Graphite-Note/Graphite/issues/63)

- [ ] The inner display, open flat, in portrait and landscape: the sidebar and documents split, the tab bar and document controls, a note, a PDF with the Pencil palette, the library. Device Hub's pose buttons did not change the simulator's pose while section 1 was built.
  Checked 2026-11-19 in the iPhone Duo simulator (iOS 27.2, the Duo's own runtime, Debug of main 325d5437 plus the release-vault-checks changes) with the release vault; the simulator tool's posture actions did change the pose this time (flat gave a 951 by 669 point screen, rotated 669 by 951). Flat, landscape: the sidebar and the note side by side, the tab bar with its document controls, the note's toolbar as a column at the right edge (back and forward, dictation, drawing, reading panel, more), a PDF with the Pencil palette over its lower edge, and the Library with five even columns of folder tiles. Flat, portrait: the Library with four even columns and a PDF with its toolbar in the title row. Nothing was cut off at the fold's side of the screen. Left: a note with the sidebar beside it in portrait (the deep link to open one timed out in that run) and the Pencil palette in portrait; the item stays open.
- [ ] Partly folded like a book: the workspace's divider on the fold with two sides, the quick switcher, the command palette, a notice banner and the Read Aloud player beside the fold, and the library grid's even columns.
  Checked 2026-11-19 in the iPhone Duo simulator (iOS 27.2, the Duo's own runtime, Debug of main 325d5437 plus the release-vault-checks changes) with the release vault; the simulator tool's posture actions did change the pose this time (flat gave a 951 by 669 point screen, rotated 669 by 951). Half open at 120 degrees with a PDF: the lit screen stays 669 by 951 points and the picture is the same as flat, with no divider drawn, so one document does not show a fold; this is the open decision below. Left: a split of two documents to see the divider on the fold, the quick switcher, the command palette, a notice banner, the Read Aloud player (not started: nothing may play sound) and the grid at that pose; the item stays open.
- [x] The keyboard toolbar on the inner display: Undo and Redo only in the note's toolbar. Done 2026-11-19: seen in the Duo simulator, flat in landscape (below).
  Checked 2026-11-19 in the iPhone Duo simulator (iOS 27.2, the Duo's own runtime, Debug of main 325d5437 plus the release-vault-checks changes) with the release vault; the simulator tool's posture actions did change the pose this time (flat gave a 951 by 669 point screen, rotated 669 by 951). Flat, landscape, a note in edit mode with the software keyboard up: the toolbar above the keyboard shows text size, bold, italic, link, tag, lists, task, strikethrough, highlight, code, formula, indent, move, attach, drawing, find and hide keyboard, with no Undo or Redo; the note's own toolbar at the tab bar has them. Not tried in portrait.
- [ ] Decide what a single document does across the fold with the sidebar hidden (a note's reading column and a PDF page run across it today).
