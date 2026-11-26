# Calendar view for Bases and a copy into Apple Calendar: TODO

Created: 2026-11-26.

Status: built and tested 2026-11-26: the calendar view, rescheduling, the view editor and Calendar Copy, checked in iPad and iPhone simulators, with real EventKit in a simulator, and in a Debug copy of the Mac app by sight. Open: dragging and the context menu on the Mac. Issues: #241 to #245, one per section, linked under each heading.

## Request

Feature 3 of `Docs/Notion-features-for-Graphite.md`: a calendar view for Bases (month and week grids, notes placed by a date property with an optional end, drag to reschedule, tap to open, layouts for the iPad and the iPhone), and a one-way copy of a base's dated notes into Apple Calendar through EventKit, as a core plugin that is off until it is turned on, rebuilt from the vault on demand and never written back.

## Why a file of its own

`Docs/Calendar-and-reminders-todo.md` (issue #47, closed) planned reading Apple's Calendar and Reminders into notes: the daily-note calendar in the sidebar, the day's events, event notes, tasks sent to Reminders. Every item there is ticked. This feature goes the other way (notes into Calendar) and lives in Bases, so it gets its own record, which reuses #47's EventKit store, its access rules and its storage rules.

## What Obsidian and its plugins read (checked 2026-11-26)

- Obsidian 1.15.1 (`obsidian-1.15.1.asar` on the development Mac) has no calendar view for Bases: its Bases plugin registers table, cards, list and Kanban views (`plugins.bases.kanban` and the others), plugins add views through `registerBasesView`, and no string of the app names a calendar layout. Obsidian's roadmap lists "Calendar view for Bases" as planned, with no published keys.
- Calendar Bases (`calendar-bases` 0.2.8 by Edrick Leong, MIT, about 135,000 downloads, source read at github.com/edrickleong/obsidian-calendar-bases) registers the view type `calendar` with three keys: `startDate` and `endDate` (property IDs such as `note.date`, the end optional) and `weekStartDay` (`sunday` to `saturday`, `monday` when absent). It draws a month grid only (FullCalendar's `dayGridMonth`), every entry as an all-day entry from its start day to its end day inclusive, titled by the first property of the view's `order` that has a value (the file's base name otherwise), with the other properties below. It takes only date values (`DateValue`). An entry can be dragged only when both properties are note properties. A drop writes the start as `YYYY-MM-DD`, and the end shifted by the same number of days, through `processFrontMatter`.
- Of the other calendar views in the community list, none comes near that count. `bases-calendar` (lesk-org) and NosyCalendar are new and unreviewed.

## Decisions

Decided 2026-11-26, for the defaults that have one clear answer:

- **The view's keys are Calendar Bases' own**: `type: calendar`, `startDate`, `endDate`, `weekStartDay`. A `.base` file with a calendar view then draws in Obsidian with that plugin and in Graphite without it, and a view made in Graphite draws there. Graphite writes no key of its own. When Obsidian publishes its own calendar view, its keys are read as well, and the view editor writes them, keeping the plugin's.
- **Graphite draws `calendar` itself**, as it draws `map` for the Maps plugin: a running community plugin that registers `calendar` (Calendar Bases installed in the vault) does not replace the native view.
- **Month or week is a choice of the window, not of the file**: Calendar Bases has no key for it, and a key of Graphite's would be a format of its own. The choice is remembered per base view in the window's restored state (scene storage, at most 100 views), and the calendar opens on today.
- **The week grid has no hours**: seven day columns, each listing its entries in order, a timed entry with its time. Calendar Bases draws every entry as all-day, and an hour axis would leave most of a student's due dates (dates without a time) in a strip at the top.
- **A drag keeps the form the note wrote**: a date stays a date (`2026-12-03`), a date with a time keeps its time of day (`2026-12-03T14:00:00`). The end moves by the same number of days. Calendar Bases writes a date in both cases, which drops a time. Both properties are written in one revision-checked save of the note, the edit Kanban's moves use.
- **What can be dragged** follows Calendar Bases: a note whose start (and end, when the view has one) are note properties. An entry whose date is a formula or a file property (`file.ctime`) is shown and opens, and is not moved.
- **Only date values are placed**, as Calendar Bases places them. Graphite's records read frontmatter such as `2026-12-03` or `2026-12-03T14:00` as a date, as Obsidian does, unless the property is declared text, so the same notes show in both. An end before its start is drawn on the start day only. A span is drawn over at most 366 days, which keeps a month's layout bounded.
- **The iPhone gets its own layouts**: a month whose days show a mark per entry, with the chosen day's entries listed under the grid, and a week as a list of seven days. The iPad and the Mac draw titles in the month's cells. The calendar's month and its arrows sit in one row with the Month and Week switch, the only row the view adds above its grid.
- **The copy is a core plugin of its own, Calendar Copy**, off until it is turned on, beside the Calendar core plugin that reads Calendar into notes. It needs full access to calendars, which it asks for when it is turned on and a base is chosen, never before.
- **What is copied**: the notes of one calendar view of one base, chosen in Settings › Calendar Copy, with the view's own filters and dates. Each note becomes one event in a calendar named "Graphite": all-day for a date, timed for a date with a time (until the end's time, or one hour), titled as the calendar view titles it, with the note's `graphite://open` link as the event's URL and a line saying Calendar edits are replaced at the next copy. Notes dated from one year before today to three years after it are copied, the four years EventKit reads in one request.
- **Which calendar**: the calendar named "Graphite" in the source of the calendar new events go to (iCloud on most devices), else in the device's local source, made when missing. The local source comes second because Calendar hides its calendars on a device with iCloud Calendars on (corrected 2026-11-26, while building). A device that finds one already, made by Graphite on another device of the same iCloud account, uses it.
- **Never written back, and never touching anything else**: Graphite changes or removes only the events of that calendar whose URL is Graphite's link into the same vault. An event edited in Calendar is put back at the next copy, one deleted there is added again, and none of it reaches the vault. Two devices that copy the same vault into one iCloud calendar converge on the same events, as each copy compares every event with the vault and removes repeats.
- **When it copies**: when it is turned on, on Copy Now, when the vault opens, and a few seconds after the vault index takes in changes. One copy runs at a time.
- **The choice of base is the vault's**, in `.obsidian/graphite-calendar.json` under `copiedBase` (its file and view), beside the Calendar plugin's settings, so every device copies the same base. Whether a device copies is that device's switch.
- **Turning it off** stops the copies and leaves the calendar as it is. Remove Copied Events removes Graphite's events of this vault and, once it is empty, the calendar.

## Storage rules

- The vault stays the only representation of the notes and their dates. The "Graphite" calendar is derived data, like the search index: it can be emptied and rebuilt from the vault at any time, and a lost calendar costs no content.
- Graphite never changes or deletes an event it did not make, and the copy never writes a note.
- A calendar view adds no key to a `.base` file beyond those Calendar Bases reads.

## 1. The calendar view

Issue: [#241](https://github.com/Graphite-Note/Graphite/issues/241)

- [x] `type: calendar` read as a native view (`BaseViewType.calendar`) with `startDate`, `endDate` and `weekStartDay`, and written back by the editor without other changes, keys Graphite does not know kept.
  Done 2026-11-26: `BaseViewType.calendar` and `BaseCalendarOptions` (Core) read the three keys, a day name the plugin does not know reads as Monday, and the editor writes them with `setOption`, leaving the rest of the file as written. Tests: `BaseCalendarTests` (the plugin's own `Events.base` sample, the week start, which properties can be written, the editor's round trip with a cleared `endDate` removed).
- [x] Each result placed by its start day, and over the days to its end, from date values, in the device's time zone. An end before its start, a missing start and spans over 366 days handled as decided.
  Done 2026-11-26: `BaseRowPresentation.calendarStart` and `calendarEnd` hold date values only, `BaseCalendarEntry` counts days in the device's time zone, caps a span at 366 days and draws an end before its start on the start day. Tests: `BaseCalendarTests` (spans, a backwards end, a mistyped year, text that is no date left out), `UiBasesCalendarTests` (a vault's notes placed from start to end).
- [x] The month grid: weeks from the view's first weekday, today marked, days of the neighbouring months dimmed, multi-day entries as bars across the days in lanes that keep each entry on one lane through its week, and "+N more" when a day has more entries than fit.
  Done 2026-11-26: `BaseCalendarMonthGrid` over `BaseCalendarLayout.weeks`, three lanes of titled bars a week and "+N more", which opens that week. Tests: `BaseCalendarTests` (April 2026 from Monday the 30th, lanes kept through a week, a lane reused, hidden counts), `BaseCalendarViewMacTests` (a row per week, pictures light and dark looked at). Seen in the iPad simulator (`BasesViewsTests.testACalendarPlacesThisMonthsNotesAndAMovedNoteChangesDay`, screenshots) and in a separate Debug copy of the Mac app with the demo vault.
- [x] The week grid: seven day columns from the view's first weekday, entries in order with the time of timed ones.
  Done 2026-11-26: `BaseCalendarWeekColumns`. Pictures of the Mac test looked at, and seen in the iPad simulator by a UI test tapping Week in the real app (the demo vault's week of 23 November: the 14:00 quiz with its time, the problem set on Friday).
- [x] The row above the grid: the month or week shown, previous, Today and next, and the Month and Week switch, remembered per base view on the device.
  Done 2026-11-26: the month or the week's dates, Month and Week, previous, Today and next in one row. The choice is kept per base view in the window's scene storage (`BaseCalendarScopeMemory`, at most 100 views), not on the device, as the decision above now says. A phone shows "Nov 2026" with smaller controls, after the iPhone simulator showed "Novem…". Tests: `UiBasesCalendarTests.testEachViewRemembersItsOwnScopeAndTheOldestAreForgotten`. Not checked: the choice kept across a relaunch.
- [x] The iPhone's layouts: a month with marks and the chosen day's list under it, a week as a list of days. A base inside a note grows with its grid.
  Done 2026-11-26: `BaseCalendarCompactMonth` and `BaseCalendarWeekList` below 600 points wide. Seen in an iPhone 17 Pro simulator (iOS 27.2) in the hosted test and the real app, and pictures of the Mac test at 390 points. A base inside a note (`![[Deadlines.base#Calendar]]`) grows with its grid, seen in the iPad simulator, and a calendar draws every row with no "Show More".
- [x] VoiceOver: each day reads its date and its entries, each entry its title and dates.
  Done 2026-11-26: each day reads its date and its count of notes, each entry its title and dates (a bar once, not once per day), with Open and the moves as actions. Checked through the accessibility tree a UI test reads in the iPad simulator ("Wednesday, 2 December", "Algorithms problem set 9, 2 Dec"). Not checked with VoiceOver speaking.

## 2. Rescheduling and opening

Issue: [#242](https://github.com/Graphite-Note/Graphite/issues/242)

- [x] Tap or click an entry to open its note, from a `.base` file and from a base inside a note.
  Done 2026-11-26: a tap opened `History reading.md` from `Deadlines.base` and `Physics lab.md` from the base inside `Course dashboard.md`, in the iPad simulator, by a UI test with real touches. Not clicked on the Mac.
- [x] Drag an entry to another day of the month or week grid to move it: start and end shifted by the same number of days in one checked save, the form of each value kept, the index refreshed and the view run again.
  Done 2026-11-26: a drag carries the day it was picked up on (`BaseCalendarDragPayload`), a drop moves by the days between (`BaseCalendarDrop`), and `BaseDocumentModel.reschedule` writes both dates in one revision-checked save (`setProperties`). With real touches in the simulators: on the iPad a long-press drag moved "Algorithms problem set 9" from 27 November to 2 December (`due: 2026-12-02` in the note), on the iPhone a card of the chosen day's list dropped on 1 December moved there. Tests: `UiBasesCalendarTests` (both dates in one save with a comment kept, a time of day kept, a drop from a long entry's last day, other text dropped), `BaseCalendarTests` (across daylight saving time). Not dragged by hand: the week grid's columns (the same drop target) and the Mac.
- [x] An entry's context menu with Open and Move to the Previous or Next Day (and week), the same moves as VoiceOver actions, for the people and devices that do not drag.
  Done 2026-11-26: Open, Move to Previous or Next Day and Week, and the same moves as VoiceOver actions. Seen working once in the iPhone simulator: a hold past the menu's delay followed by a slide released on Move to Next Week moved the note seven days (iOS's press, slide and release in menus). Not opened on the Mac.
- [x] Entries that cannot move (a date from a formula or a file property, the note embedding the base, a file that is not a note) open and do not drag, as Calendar Bases.
  Done 2026-11-26: `BaseCalendarOptions.writesNoteProperties` and `BaseDocumentModel.canReschedule`. Tests: `UiBasesCalendarTests.testNotesWhoseDatesAreNotTheirOwnPropertiesDoNotMove` (a formula's date placed and not moved, the embedding note not written).

## 3. Choosing a calendar view and compatibility with Obsidian

Issue: [#243](https://github.com/Graphite-Note/Graphite/issues/243)

- [x] Calendar among the layouts of Add View and Edit View, with its section: Start Date, End Date (optional) and Week Starts On, written as `startDate`, `endDate` and `weekStartDay`.
  Done 2026-11-26: Calendar in New View and Edit View's Layout, and `BaseCalendarOptionsSection` with Start Date, End Date and Week Starts On, written by `applyCalendarOptions`. Tests: `BaseCalendarTests.testTheEditorWritesThePluginsKeysAndLeavesTheRestAsWritten`, `BaseCalendarViewMacTests` (the sheet laid out, picture looked at).
- [x] A view with no start date says how to choose one (Edit View), as Calendar Bases says to configure a start date property.
  Done 2026-11-26: "Choose the Calendar's Dates" with Edit View where the base can be edited. Picture of `BaseCalendarViewMacTests` looked at.
- [x] Bases' messages that list the views Graphite draws name calendar views, and printing a base to PDF draws a calendar view's results as a list.
  Done 2026-11-26: the unsupported-view and plugins-off messages name calendar views, and `NotePDFBases` prints a calendar view's notes as a list (`printedViewTypes`). The printed list was not looked at.
- [x] Calendar Bases' own sample (`test-vault/Events.base` of the plugin, with its notes) parsed and laid out in a test, and a base made and moved in Graphite read back as the plugin reads it.
  Done 2026-11-26: the sample's `Events.base` parsed with its options (`BaseCalendarTests`), its notes' shape placed and moved over a vault (`UiBasesCalendarTests`), and the moved notes written as the plugin writes dates (`2026-12-03`), keeping a time where the note had one. Not opened in Obsidian itself.

## 4. Calendar Copy: the notes of a base in Apple Calendar

Issue: [#244](https://github.com/Graphite-Note/Graphite/issues/244)

- [x] The Calendar Copy core plugin, off by default, in Settings › Core Plugins, with its own page: the base and calendar view to copy, Copy Now, the last copy's result, Remove Copied Events.
  Done 2026-11-26: `CorePlugin.calendarCopy`, off by default, and Settings › Calendar Copy (`CalendarCopySettingsPage`): base, calendar view, Copy Now with the last copy's result, Remove Copied Events with a confirmation. Tests: `CorePluginSwitchesTests`, `GraphitePreferencesPersistedKeysTests`, `BaseCalendarViewMacTests` (the page laid out, picture looked at). Not opened in the app's Settings by hand.
- [x] Full calendar access asked only when the plugin is turned on and a base chosen, or at Copy Now. Refused or restricted, the page says where to allow it and nothing is copied.
  Done 2026-11-26: automatic copies never ask, turning the plugin on and Copy Now ask once, and a refusal copies nothing and says where to allow it. Tests: `UiBasesCalendarTests.testAnAutomaticCopyNeverAsksForAccessAndARefusalCopiesNothing`, `testTurningCalendarCopyOnCopiesTheVaultsChosenBaseAfterAskingOnceAndTurningItOffStops`. The system's own question was not shown: the live test grants access beforehand.
- [x] The plan of a copy as a pure value: the vault's notes against the calendar's events of the window, giving the events to add, change and remove, with repeats removed, only Graphite's events of this vault considered.
  Done 2026-11-26: `CalendarCopyPlan` and `CalendarCopyEvents` (Core). Tests: `CalendarCopyPlanTests` (all-day and timed events in the window, links, adds, changes, removals, the person's event and another vault's left alone, repeats removed).
- [x] Events written through EventKit in the "Graphite" calendar, found or made as decided, all-day or timed, titled, with the note's link as URL.
  Done 2026-11-26: `LiveCalendarCopyStore`, an actor with its own `EKEventStore`, the calendar found by its kept identifier, then its title, else made in the default calendar's source, then the local one (the order corrected while building). Checked with real EventKit in its own simulator (`CalendarCopyLiveStoreHostedTests`).
- [x] Copies run when turned on, on Copy Now, when the vault opens, and after index changes, one at a time, off the main thread where EventKit allows, and stop when the plugin is turned off or the vault closes.
  Done 2026-11-26: `CalendarCopyController` runs one copy at a time, 5 seconds after `indexVersion` changes, when a scan ends, on Copy Now and when turned on, and `stop()` when the plugin is turned off or the vault changes. Tests: `UiBasesCalendarTests` (the settle delay on a manual clock, the workspace turning it on and off).
- [x] Remove Copied Events, which removes Graphite's events of this vault and then the calendar once it is empty.
  Done 2026-11-26: searches every year from 1970 in four-year spans, removes this vault's events and then the calendar once it is empty, and forgets its identifier. Tests: `UiBasesCalendarTests.testRemovingCopiedEventsLeavesThePersonsEventsAndKeepsACalendarThatIsNotEmpty`, `CalendarCopyLiveStoreHostedTests`.
- [x] Tests over a fake calendar store (no test touches the calendars of the machine it runs on), and the real EventKit in a dedicated simulator with access granted (`simctl privacy grant calendar`), never the person's own calendars.
  Done 2026-11-26: `FakeCalendarCopyStore` (test support), which every workspace made by `IsolatedWorkspaceDevice` now uses, and `CalendarCopyLiveStoreHostedTests`, which runs only with `TEST_RUNNER_GRAPHITE_LIVE_CALENDAR=1` in a simulator of its own after `simctl privacy grant calendar`.

## 5. Checks and documentation

Issue: [#245](https://github.com/Graphite-Note/Graphite/issues/245)

- [x] Checked in a dedicated iPad simulator with a small demo vault: month and week grids, drag to reschedule, the phone layout in an iPhone simulator.
  Done 2026-11-26: an iPad Pro 11-inch (M5) and an iPhone 17 Pro simulator of their own (iOS 27.2), with a demo vault of ten made-up course deadlines: `BasesViewsTests` hosted in the app on both, and a throwaway UI test (kept outside the repository) driving the installed app with real touches for the month, the week, drags on both, a tap from the base and from a note.
- [ ] Checked in a separate Debug copy of the Mac app with the demo vault: the grids, dragging with the mouse, the context menu.
  Seen 2026-11-26: a Debug build re-signed with a bundle ID of its own, the demo vault in its container: `Deadlines.base` drew the month in the real window (today marked, the lab report across 1 to 3 December, the 14:00 quiz with its time, "+1 more"). Open: dragging with the mouse and the context menu, which need a person's clicks or computer use (posted mouse events hang AppKit's drag loop, as seen in an earlier check).
- [x] Calendar Copy checked with real EventKit in its own simulator: events made, changed after an edit in the vault, put back after an edit in Calendar, removed.
  Done 2026-11-26: `CalendarCopyLiveStoreHostedTests` in an iPad simulator of its own with calendar access granted: two notes copied (an all-day span of 10 to 12 March 2031 and a 09:00 hour), a title edited in Calendar put back, the exam moved in the vault moved in Calendar, the person's "Dentist" event left alone through Remove Copied Events, no note written.
- [x] `Docs/Architecture.md`, `Docs/Coverage.md` and `Docs/Notion-features-for-Graphite.md` updated for what is built and checked.
  Done 2026-11-26: Architecture's Bases entries (the calendar view, Calendar Copy), Coverage's entry of 2026-11-26, the Notion note's section 3, and the invariants (`ST-32`) and the registry of stored keys.
