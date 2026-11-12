# Fast view switching: TODO

Created: 2026-11-09.

Status: measured 2026-11-09; first fixes built (section 2); the owner's vault measured and the Tags view fixed 2026-11-10 (section 3); a vault of the owner's shape reproduced in tests, every switch timed on the Mac and the iPad simulator, and the hidden sidebar's work in Library mode removed 2026-11-12 (section 3). Issues: [#146](https://github.com/Graphite-Note/Graphite/issues/146) (section 1), [#147](https://github.com/Graphite-Note/Graphite/issues/147) (section 2), [#149](https://github.com/Graphite-Note/Graphite/issues/149) (section 3).

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
  Measured again 2026-11-12 in a vault of the owner's shape (section 3, with the table), and what each switch over 100 ms spends its time on, from `sample` of the test process: Library ↔ List is section 3's last item. Live Preview → Reading of the long lecture, about 230 ms on the Mac (Release) and 140 ms on the iPad simulator: the reading view is built in full, its parse cached, and laid out; Reading → Live Preview, 160 and 74 ms: the editor is hosted again. Another tab, to the long lecture, 90 ms of the Mac's main thread and 77 ms on the iPad (on the Mac the main thread is quiet only about 310 ms after the switch, after a later burst of work that was not traced). The sidebar's Files ↔ Tags, 75 to 95 ms on the Mac and 25 to 35 ms on the iPad; Live Preview ↔ Source, under 40 ms until shown on both. Still not timed in these tests: showing and hiding the right sidebar and opening a picture. Not fixed: the reading view built at each switch and the editor hosted again per tab; these stay the open part of this item.
- [ ] A test that keeps each fixed switch from doing the slow work again. 2026-11-12: `ViewSwitchingMacTests` keeps section 3's fix (the file tree kept across Library mode with its open folders, no Tags view behind the library, each switch under 2 s; its file tree checks failed before the fix) and `ViewSwitchingHostedTests` the iPad's Library ↔ List under 3 s; the bookmark lookup has `WorkspaceBookmarkLookupTests`. Open: a test for the inspector's outline read off the main thread.
- [ ] Checked on the iPad and the Mac.

## 3. The owner's vault: Library mode froze the window

Issue: [#149](https://github.com/Graphite-Note/Graphite/issues/149)

The owner, 2026-11-10, with a screenshot of the Mac showing spinners in the library and in the sidebar's Tags view: "switching views buffers a lottttt". Measured in the owner's running app (Mac, vault of 32,843 files, 1,372 notes, about 3,000 distinct tags) with `sample` while switching: List → Library froze the main thread for about 4.5 s and Library → List for about 1.2 s. A Mac spinner keeps turning while the main thread is blocked, so both spinners were waiting on the main thread, not on the disk (the vault's root, 60 entries, lists in 13 ms).

- [x] List → Library: Library mode takes the Files panel out of the sidebar, so the sidebar showed Tags and built a SwiftUI `List` with a disclosure group per tag with nested tags. SwiftUI's outline list on the Mac looks up each row of a disclosure group by walking the rows before it, so the layout grew with the square of the tag count: 3,074 of the 4,867 samples were in `OutlineListCoordinator` expanding rows. Done 2026-11-10: the Tags view lists one flat row per tag shown (`TagTree.visibleRows`), indented by depth with a chevron for tags with nested tags, as the file tree's folders are drawn; the nested tags are built once per load and sort order (`VaultOverviewModel.tagTree`) instead of at each update. Tests: `TagsViewLayoutMacTests` (3,000 nested tags in the sidebar's list: 10.5 s before, 0.3 s after) and `TagsAndPropertiesTests.testVisibleRowsShowNestedTagsOnlyUnderExpandedTagsOneLevelDeeper`; rows checked in a rendering of the view. Not yet checked in the owner's app after the fix (needs the next build).
- [ ] Library → List: the main thread is busy 1.2 to 3.7 s (two samples, the Mac under other builds' load). Sampled again 2026-11-10 in the owner's app: a quarter in SwiftUI updating the window's views when the switch is clicked; about 1 s laying out the window's toolbar again, because the note's toolbar items come back (the library home replaces the note's pane and its toolbar) and AppKit asks each item's hosting view for its contents about 20 times, each read costing about 45 ms; the rest SwiftUI's render, the file tree and the note's text view. Half of each read was SwiftUI looking up, by name, the SF Symbol of every entry of the toolbar's menus (Format, Insert, More and its File submenu, about 70 entries) in the system's asset catalog. Built 2026-11-10: those entries get their symbol as an image made when the menu is drawn (`MenuItemLabel`, `Button(_:menuSymbol:)`), on the Mac only. Measured in `MenuItemLabelTests`: four toolbar menus of 18 entries appear in about 155 ms with made images against 255 ms with named symbols (100 ms for plain buttons), so the switch should lose roughly 0.3 s of its toolbar time. Not measured in the app and the menus' look not checked by eye: driving a separate test copy of the app was declined, and the owner's installed app has not been rebuilt. Still open: the rest of the toolbar's work and SwiftUI's update of the window, which are Apple's frameworks doing what the window's views ask; making them cheaper means keeping the note's pane, and its toolbar, alive under the library instead of replacing it.

  Reproduced 2026-11-12 without the owner's vault: `OwnerShapedVault` (in `ViewSwitchingBenchmarkSupport.swift`) writes 1,400 notes in course folders with 3,174 tags, 3,000 of them nested under 1,000 subjects, a long lecture (20 sections of tables, code, callouts and formulas) and 31,400 one-pixel pictures in a folder of batches of a thousand, 32,800 files in all; `ViewSwitchingWindow` opens the window's root view over it in Library mode with six notes in tabs, the long lecture in front in Live Preview, and three folders open in the file tree (1,194 rows), its toolbar and title bridged to the window as the app's scene does (the Mac at 1,440 × 900, the iPad simulator at 1,194 × 834). `MainThreadQuietWatch` times each switch: the main thread's busy time until it has been quiet for half a second and the window shows what was asked (the file tree with its open folders), and its longest single step, which the person sees as the window frozen. It polls and suspends, so the main-actor tasks that bring a folder's listing or the tags run meanwhile; a first version turned the run loop itself, which held the main actor, and missed that work. The benchmark is `PerformanceBenchmarkTests.testSwitchingViewsInAVaultOfTheOwnersSize` (`GRAPHITE_BENCHMARKS=1`).

  Found, sampled with `sample` on the test process: Library mode takes the Files panel out of the sidebar, so the sidebar, folded out of the window, built the Tags view behind the library and loaded the 3,174 tags from the index; Library → List then built the file tree again, whose open folders listed their files from the disk again and opened about a tenth of a second after the switch had drawn. Built 2026-11-12: while Library mode keeps the sidebar folded, it keeps the file tree it had and lists nothing else (`SidebarFilesPlace.foldedByLibrary`, set by `LibraryModeSidebarVisibility` also for the update in which the switch is made, one update before the column folds, as the switch otherwise built the Tags view for that update). A search that opens the sidebar beside the library offers the other panels as before. Measured, before → after, six switches each, the medians (Mac: Release build; iPad: the simulator, Debug, the hosted tests' build; load average about 4 from other sessions):

  | Switch | Mac: busy / longest step | iPad simulator: main thread / longest step |
  | --- | --- | --- |
  | List → Library | 213 → 187 ms / 172 → 106 ms | 188 → 177 ms / 108 → 98 ms |
  | Library → List | 285 → 211 ms / 187 → 169 ms; the open folders shown at 285 → 169 ms | 215 → 196 ms / 116 → 116 ms |

  What the rest is, from the samples (Debug, which times the same as Release within a few milliseconds here): on the Mac about 30% of Library → List is AppKit laying out the window's toolbar again as the note's five toolbar items come back, the rest SwiftUI updating and laying out the window and the editor hosted again; Graphite's own code was about 5% of the busy samples. Tried and dropped: keeping the note's pane alive under the library changed nothing (187 against 190 ms, Debug) while its toolbar items still went and came; hiding those items instead (`ToolbarContent.hidden`) kept AppKit's items but took 195 ms each way, as AppKit lays the toolbar out again when an item hides; keeping them shown took 113 ms but puts the note's Format, Insert and More over the library, which Library mode's design rules out. These tests do not reach the owner's 1.2 to 3.7 s: what the owner's window holds beyond them (the community plugins, Read Aloud and the other toolbar items, more tabs, the owner's notes) is not known. Tests: `ViewSwitchingMacTests` (the same file tree before and after a Library round trip, with its open folders at once, and no other list behind the library; the three file tree checks failed before the fix), `ViewSwitchingHostedTests` (the iPad's switches under a budget). Not checked in the owner's app, which needs its next build.
