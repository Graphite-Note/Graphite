# Calendar view for Bases and a copy into Apple Calendar: TODO

Created: 2026-11-26.

Status: planned 2026-11-26. Nothing is built yet. Issues: #241 to #245, one per section, linked under each heading.

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
- **Month or week is a choice of the device, not of the file**: Calendar Bases has no key for it, and a key of Graphite's would be a format of its own. The choice is remembered per base view on the device, and the month opens on today.
- **The week grid has no hours**: seven day columns, each listing its entries in order, a timed entry with its time. Calendar Bases draws every entry as all-day, and an hour axis would leave most of a student's due dates (dates without a time) in a strip at the top.
- **A drag keeps the form the note wrote**: a date stays a date (`2026-12-03`), a date with a time keeps its time of day (`2026-12-03T14:00:00`). The end moves by the same number of days. Calendar Bases writes a date in both cases, which drops a time. Both properties are written in one revision-checked save of the note, the edit Kanban's moves use.
- **What can be dragged** follows Calendar Bases: a note whose start (and end, when the view has one) are note properties. An entry whose date is a formula or a file property (`file.ctime`) is shown and opens, and is not moved.
- **Only date values are placed**, as Calendar Bases places them. Graphite's records read frontmatter such as `2026-12-03` or `2026-12-03T14:00` as a date, as Obsidian does, unless the property is declared text, so the same notes show in both. An end before its start is drawn on the start day only. A span is drawn over at most 366 days, which keeps a month's layout bounded.
- **The iPhone gets its own layouts**: a month whose days show a mark per entry, with the chosen day's entries listed under the grid, and a week as a list of seven days. The iPad and the Mac draw titles in the month's cells. The calendar's month and its arrows sit in one row with the Month and Week switch, the only row the view adds above its grid.
- **The copy is a core plugin of its own, Calendar Copy**, off until it is turned on, beside the Calendar core plugin that reads Calendar into notes. It needs full access to calendars, which it asks for when it is turned on and a base is chosen, never before.
- **What is copied**: the notes of one calendar view of one base, chosen in Settings › Calendar Copy, with the view's own filters and dates. Each note becomes one event in a calendar named "Graphite": all-day for a date, timed for a date with a time (until the end's time, or one hour), titled as the calendar view titles it, with the note's `graphite://open` link as the event's URL and a line saying Calendar edits are replaced at the next copy. Notes dated from one year before today to three years after it are copied, the four years EventKit reads in one request.
- **Which calendar**: the calendar named "Graphite" in the device's local source when it has one ("On My iPad"), else in the source of the default calendar (iCloud on most devices), made when missing. A device that finds one already, made by Graphite on another device of the same iCloud account, uses it.
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

- [ ] `type: calendar` read as a native view (`BaseViewType.calendar`) with `startDate`, `endDate` and `weekStartDay`, and written back by the editor without other changes, keys Graphite does not know kept.
- [ ] Each result placed by its start day, and over the days to its end, from date values, in the device's time zone. An end before its start, a missing start and spans over 366 days handled as decided.
- [ ] The month grid: weeks from the view's first weekday, today marked, days of the neighbouring months dimmed, multi-day entries as bars across the days in lanes that keep each entry on one lane through its week, and "+N more" when a day has more entries than fit.
- [ ] The week grid: seven day columns from the view's first weekday, entries in order with the time of timed ones.
- [ ] The row above the grid: the month or week shown, previous, Today and next, and the Month and Week switch, remembered per base view on the device.
- [ ] The iPhone's layouts: a month with marks and the chosen day's list under it, a week as a list of days. A base inside a note grows with its grid.
- [ ] VoiceOver: each day reads its date and its entries, each entry its title and dates.

## 2. Rescheduling and opening

Issue: [#242](https://github.com/Graphite-Note/Graphite/issues/242)

- [ ] Tap or click an entry to open its note, from a `.base` file and from a base inside a note.
- [ ] Drag an entry to another day of the month or week grid to move it: start and end shifted by the same number of days in one checked save, the form of each value kept, the index refreshed and the view run again.
- [ ] An entry's context menu with Open and Move to the Previous or Next Day (and week), the same moves as VoiceOver actions, for the people and devices that do not drag.
- [ ] Entries that cannot move (a date from a formula or a file property, the note embedding the base, a file that is not a note) open and do not drag, as Calendar Bases.

## 3. Choosing a calendar view and compatibility with Obsidian

Issue: [#243](https://github.com/Graphite-Note/Graphite/issues/243)

- [ ] Calendar among the layouts of Add View and Edit View, with its section: Start Date, End Date (optional) and Week Starts On, written as `startDate`, `endDate` and `weekStartDay`.
- [ ] A view with no start date says how to choose one (Edit View), as Calendar Bases says to configure a start date property.
- [ ] Bases' messages that list the views Graphite draws name calendar views, and printing a base to PDF draws a calendar view's results as a list.
- [ ] Calendar Bases' own sample (`test-vault/Events.base` of the plugin, with its notes) parsed and laid out in a test, and a base made and moved in Graphite read back as the plugin reads it.

## 4. Calendar Copy: the notes of a base in Apple Calendar

Issue: [#244](https://github.com/Graphite-Note/Graphite/issues/244)

- [ ] The Calendar Copy core plugin, off by default, in Settings › Core Plugins, with its own page: the base and calendar view to copy, Copy Now, the last copy's result, Remove Copied Events.
- [ ] Full calendar access asked only when the plugin is turned on and a base chosen, or at Copy Now. Refused or restricted, the page says where to allow it and nothing is copied.
- [ ] The plan of a copy as a pure value: the vault's notes against the calendar's events of the window, giving the events to add, change and remove, with repeats removed, only Graphite's events of this vault considered.
- [ ] Events written through EventKit in the "Graphite" calendar, found or made as decided, all-day or timed, titled, with the note's link as URL.
- [ ] Copies run when turned on, on Copy Now, when the vault opens, and after index changes, one at a time, off the main thread where EventKit allows, and stop when the plugin is turned off or the vault closes.
- [ ] Remove Copied Events, which removes Graphite's events of this vault and then the calendar once it is empty.
- [ ] Tests over a fake calendar store (no test touches the calendars of the machine it runs on), and the real EventKit in a dedicated simulator with access granted (`simctl privacy grant calendar`), never the person's own calendars.

## 5. Checks and documentation

Issue: [#245](https://github.com/Graphite-Note/Graphite/issues/245)

- [ ] Checked in a dedicated iPad simulator with a small demo vault: month and week grids, drag to reschedule, the phone layout in an iPhone simulator.
- [ ] Checked in a separate Debug copy of the Mac app with the demo vault: the grids, dragging with the mouse, the context menu.
- [ ] Calendar Copy checked with real EventKit in its own simulator: events made, changed after an edit in the vault, put back after an edit in Calendar, removed.
- [ ] `Docs/Architecture.md`, `Docs/Coverage.md` and `Docs/Notion-features-for-Graphite.md` updated for what is built and checked.
