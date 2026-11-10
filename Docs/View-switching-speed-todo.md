# Fast view switching: TODO

Created: 2026-11-09.

Status: measured 2026-11-09; first fixes built (section 2); the owner's vault measured and the Tags view fixed 2026-11-10 (section 3). Issues: [#146](https://github.com/Graphite-Note/Graphite/issues/146) (section 1), [#147](https://github.com/Graphite-Note/Graphite/issues/147) (section 2), [#149](https://github.com/Graphite-Note/Graphite/issues/149) (section 3).

## Request

The owner, 2026-11-09: "switching views is also slow like really slow". Asked which switch, the owner answered "do some proper testing": measure every switch and fix the slow ones.

## 1. Measure every switch

Issue: [#146](https://github.com/Graphite-Note/Graphite/issues/146)

- [x] Time, on the iPad simulator and the Mac, with a long note full of tables and pictures and with the owner-shaped vault: Reading view to Live Preview and back, Source mode, another tab, another note in the same tab, List to Library and back, the sidebar's panels, and opening a picture. Done 2026-11-09 on main e2325549, Release builds, an in-app driver that calls what the buttons call and watches the main run loop; vault: the test vault's Digital IC Design course, 1,300 generated notes and a generated long note (3,010 lines, 40 tables, 30 images, 60 callouts, 80 display formulas). Not on a physical iPad; the Mac was loaded by other builds (load average 4 to 25), so times vary by about half.
- [x] Record each time and what the main thread spent it on (Instruments Time Profiler or `sample`), in this file. Done 2026-11-09, below.

### Times (ms until the main thread is quiet; the longest single block in brackets)

| Switch | iPad simulator, first / again | Mac, first / again |
| --- | --- | --- |
| Live Preview → Reading, long note | 99–565 / 150–480 | 383 / 265–310 |
| Reading → Live Preview, long note | 150 / 90–260 | 242 / 230–265 |
| Live Preview ↔ Source | 90 / 27–108 | 60 / 25–80 |
| Source → Reading | 437–506 | 164–274 |
| Another tab | 396 / 160–500 [210–270]; both in Reading 445–1,090 | 506 / 480–530 [190–245] |
| Another note in the same tab, short | 353 / 340–425 [120–190] | 386 / 290–365 [100] |
| Another note in the same tab, 1,300 lines | 586 / 420–435 | 430 / 420–445 |
| List → Library / Library → List | 485–1,190 / 890–2,112 [up to 570] | 260–510 / 270–365 [340] |
| Sidebar: Files, Bookmarks | 16–46 | 28–80 |
| Sidebar: Tags / Properties | 217 / 649 first, then 23–180 | 80–126 / 94–330 |
| Show / hide the right sidebar | 360–755 / 580–690 | 337–578 / 335–350 |
| Opening a picture | 183–413 first, 73–158 (before the zoom of 83bf81df) | 47–197 |

### Where the main thread went

Most of the time (70–85% of busy samples) is SwiftUI building and laying out large view trees and Core Animation committing them, not Graphite's own code. Graphite's share:

- Reading ↔ Live Preview: the pane swaps one view for the other (`MarkdownPane`), so the reading view is built in full each time (its parse is cached), and going back re-hosts the editor (`MarkdownEditorStyling.reserveMeasuredHeight`).
- Another tab or note: the editor is taken down and made again; `NoteLinksInspector` read the whole note's outline on the main thread at every switch, 25–38 ms, also with the right sidebar hidden; the keyboard toolbar was built for every editor, about 38 ms; a note with an embedded PDF makes a new `PKToolPicker`. The tab thumbnail captured afterwards (`TabThumbnails`) adds to the time until quiet but comes after the switch is shown.
- List ↔ Library: the split view folds or shows its sidebar, so the window lays out again; each library tile asked whether its item is bookmarked through `isDirectory`, which resolves the path on disk one component at a time, at every drawing of every tile.
- The right sidebar: the editor is laid out again at every step of its animation.

## 2. Fix the slow ones

Issue: [#147](https://github.com/Graphite-Note/Graphite/issues/147)

- [ ] Every switch measured over 100 ms gets a fix or a written reason; numbers before and after in this file. First fixes built 2026-11-09: whether an item is bookmarked is read from the bookmarks alone (`WorkspaceModel.isBookmarked`, no disk access per tile); the inspector's outline is read off the main thread; the iPad keyboard toolbar is built when the keyboard first asks for it. Measured before and after on 83bf81df (Release, before and after alternated, load average 3 to 5): a tab switch to the long note on the iPad simulator 313 → 182 ms (median); the library tiles' disk lookups went from about 48 ms to 2 ms of main-thread time per 8 switches, but List ↔ Library still takes about 700 ms on the iPad simulator and 300 ms on the Mac, almost all of it SwiftUI and Core Animation laying out the window again as the split view's columns change; the outline left the Mac's main thread (36 ms per 12 switches) without changing its 520 ms tab switch; the keyboard toolbar cost only about 3 ms per note, so building it later changed nothing measurable. Still open: the window laid out again when the library folds the sidebar, the reading view built in full at each switch from Live Preview, the editor rebuilt per tab, the right sidebar's animation, the window layout when the library folds the sidebar.
- [ ] A test that keeps each fixed switch from doing the slow work again.
- [ ] Checked on the iPad and the Mac.

## 3. The owner's vault: Library mode froze the window

Issue: [#149](https://github.com/Graphite-Note/Graphite/issues/149)

The owner, 2026-11-10, with a screenshot of the Mac showing spinners in the library and in the sidebar's Tags view: "switching views buffers a lottttt". Measured in the owner's running app (Mac, vault of 32,843 files, 1,372 notes, about 3,000 distinct tags) with `sample` while switching: List → Library froze the main thread for about 4.5 s and Library → List for about 1.2 s. A Mac spinner keeps turning while the main thread is blocked, so both spinners were waiting on the main thread, not on the disk (the vault's root, 60 entries, lists in 13 ms).

- [x] List → Library: Library mode takes the Files panel out of the sidebar, so the sidebar showed Tags and built a SwiftUI `List` with a disclosure group per tag with nested tags. SwiftUI's outline list on the Mac looks up each row of a disclosure group by walking the rows before it, so the layout grew with the square of the tag count: 3,074 of the 4,867 samples were in `OutlineListCoordinator` expanding rows. Done 2026-11-10: the Tags view lists one flat row per tag shown (`TagTree.visibleRows`), indented by depth with a chevron for tags with nested tags, as the file tree's folders are drawn; the nested tags are built once per load and sort order (`VaultOverviewModel.tagTree`) instead of at each update. Tests: `TagsViewLayoutMacTests` (3,000 nested tags in the sidebar's list: 10.5 s before, 0.3 s after) and `TagsAndPropertiesTests.testVisibleRowsShowNestedTagsOnlyUnderExpandedTagsOneLevelDeeper`; rows checked in a rendering of the view. Not yet checked in the owner's app after the fix (needs the next build).
- [ ] Library → List: about 1.2 s of the main thread laying out the window again (SwiftUI's render of the window 0.6 s, the toolbar 0.4 s, the note's text view 0.1 s). No single cause of Graphite's own found yet.
