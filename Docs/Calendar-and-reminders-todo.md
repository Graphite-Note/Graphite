# Apple Calendar and Reminders integration: TODO

Created: 2026-10-18.

Status: built 2026-11-12 except the recording's name from the current event; checked with tests over a fake Calendar and Reminders, in the iPad simulator, never yet with real calendars. The Calendar core plugin (on by default) holds every part; `App/Info.plist` has the calendars and reminders full-access reasons and the Mac's sandbox the Calendars entitlement.

## Request

Native integration with Apple Calendar and Reminders through EventKit, on iPadOS, iOS and macOS. The vault stays authoritative: events and reminders are read from and written to the system stores, and what ends up in a note is ordinary Markdown that Obsidian reads unchanged.

## Scope

Issue: [#47](https://github.com/Graphite-Note/Graphite/issues/47)

- [ ] Permissions: ask only when the user first uses a calendar or reminders feature, never at launch. Full access for reading (`NSCalendarsFullAccessUsageDescription`, `NSRemindersFullAccessUsageDescription`); consider write-only calendar access where Graphite only adds events. Every feature explains itself and stays usable when access is denied.
  Built 2026-11-12: `CalendarStore` (Apple) with `LiveCalendarStore` over EventKit, which makes no `EKEventStore` until a feature needs one and asks (`requestFullAccessToEvents`, `requestFullAccessToReminders`) only through `requestAccess`, called at a feature's first use: Show Events from Calendar, inserting events, `{{events}}`, a note for the current event, sending a task, inserting reminders, Settings › Calendar's Allow. Showing the panel, listing commands, opening a vault and coming to the front ask nothing. Refused or restricted, each feature says where to allow it (Settings › Privacy & Security › Calendars or Reminders) and the rest goes on: the daily note is still made, `{{events}}` is left empty with a notice. Write-only calendar access is not asked: Graphite adds no events; a write-only answer counts as refused for reading. Both usage descriptions in `App/Info.plist`; `com.apple.security.personal-information.calendars` in `App/Graphite.entitlements` (EventKit has no Reminders entitlement: Calendars covers both). Tests: `WorkspaceCalendarTests` (what asks when, refusals), `CalendarPanelHostedTests` (no question until Show Events or Allow), `GraphiteEntitlementsTests`, `InfoPropertyListDeclarationsTests`. Open: the system's question and a refusal on a device and on the Mac, against real Calendar and Reminders.
- [x] Calendar view for daily notes, the gap noted in `Obsidian-mobile-gaps.md` ("no Calendar view"): a month view that opens or creates the daily note for a day and marks the days that have one.
  Done 2026-11-12: a Calendar segment in the sidebar's panel row (no new row; the Mac's sidebar the same), `CalendarPanel` over `CalendarPanelModel`: the month from the device's first weekday with today and the chosen day marked, a dot under each day with a daily note (the daily notes folder's paths read against the format, off the main actor, read again when files are added, moved or removed), previous and next month and Today; choosing a day opens its daily note, made from the vault's folder, format and template when missing; with Daily notes off the panel says so. Needs no calendar access. Tests: `CalendarMarkdownTests` (days, months, weekdays), `WorkspaceCalendarTests` (marks, a day's note made from the template), `CalendarPanelHostedTests` (landscape and portrait iPad windows, all five segments with room for a finger; screenshots looked at). Not checked by hand on a device or in the Mac app.
- [ ] Today's events in the daily note: a command that inserts the day's events as a Markdown list (time, title, optional link to a meeting note), and a template variable for daily-note templates.
  Built 2026-11-12: "Calendar: Insert the day's events" (`graphite:calendar-insert-events`) writes the daily note's own day (today in another note) at the cursor, on lines of their own after the properties: `- **10:15–12:00** Computer Architecture (ETZ E 6) [[2026-11-12 Computer Architecture]]`, all-day events first as `**All day**`, times in the Templates time format, the link only when the event's note exists. `{{events}}` in a daily-note template (and in Insert template) is filled with the note's day's list; with the plugin off it stays as written, as Obsidian leaves it. Tests: `CalendarMarkdownTests`, `WorkspaceCalendarTests`, `WorkspaceCommandIdentifiersTests`, `GraphiteCommandTests`. Open: real events from Calendar (repeating events, time zones, travel) on a device and the Mac.
- [ ] Meeting and lecture notes from an event: create a note named from the event, with date, time, location and attendees as properties, in a folder the user chooses per calendar.
  Built 2026-11-12: choosing an event in the calendar panel, or "Calendar: Open note for current event" (the event under way, else today's next), opens the event's note, made once as `2026-11-12 Title.md` with `date`, `start`, `end` (not for all-day events), `location`, `attendees` and `calendar` properties and the title as heading, in the calendar's folder from Settings › Calendar (`.obsidian/graphite-calendar.json`, by calendar title), else the plugin's default folder, else the vault's location for new notes. Tests: `CalendarMarkdownTests`, `WorkspaceCalendarTests`, `CalendarPanelHostedTests` (an event chosen in the panel opens its new note; screenshot looked at). Open: attendees and places of real invitations on a device.
- [ ] Lecture recording context: when a recording starts during a calendar event, offer the event's title and course as the recording's name and destination (OBJECTIVE.md asks for meaningful names and course context).
  Not built 2026-11-12: left for the next pass. `WorkspaceModel.openNoteForCurrentEvent` already finds the event under way; the offer needs a place in the recording controls that adds no row of chrome.
- [ ] Tasks to Reminders: a task with a due date (`- [ ] … 📅 2026-10-20`, the Tasks plugin syntax Obsidian users already write) can be sent to a Reminders list; completing it on either side completes it on the other. Which tasks sync is the user's choice, never all tasks by default.
  Built 2026-11-12: "Reminders: Send task to Reminders" (`graphite:reminders-send-task`) sends the task at the cursor, its words without the Tasks fields as the title and its 📅 day as the due date, to the list of Settings › Calendar (else Reminders' default list), and adds `^reminder-k3j9x2ab` at the end of the line (a block ID the task has already is used); a task is sent once. Completing either side completes the other, and unticking unticks, with ` ✅ 2026-11-12` written and removed as the Tasks plugin does. Only tasks the person sent are linked. Tests: `TaskRemindersTests`, `WorkspaceCalendarTests` (send, both directions, a refusal, forgetting a vault). Open: real Reminders on a device and the Mac, and two devices of one person.
- [ ] Reminders into notes: show or import a Reminders list as Markdown tasks.
  Built 2026-11-12: "Reminders: Insert open reminders" (`graphite:reminders-insert`) inserts the open reminders of the list chosen in Settings › Calendar (or of every list, each under its name in bold) as `- [ ] Milk 📅 2026-11-14`, at the cursor. They are not linked: linking is for tasks the person sends. Tests: `TaskRemindersTests`, `WorkspaceCalendarTests`. Open: real Reminders lists.
- [ ] Changes made in Calendar or Reminders while Graphite is closed are picked up on the next launch (`EKEventStoreChanged`, and a check on activation).
  Built 2026-11-12: linked tasks and reminders are brought into agreement when a vault opens, when the window comes to the front and when it leaves it, and at each `EKEventStoreChanged` (one listener for the process, `CalendarServices`, started once a vault has linked tasks), only on a device where the person used Reminders through Graphite; the panel reads a day's events again when it shows. Tests: `WorkspaceCalendarTests` (a change announced by the store ticks the note's task; nothing read before Reminders was used). Open: a change made while Graphite is closed, on a device.
- [ ] `Architecture.md`, `Coverage.md` and the gaps list updated once each part is built and tested.
  2026-11-12: updated for what is built (Architecture's storage contracts, Coverage's entry of 2026-11-12, the Daily notes row of the gaps list); to be updated again with the recording's name and the checks on devices.

## Storage rules

- Markdown stays the only representation of the user's tasks and notes. The link between a task and its reminder must survive without a Graphite database: either a visible, Obsidian-compatible marker in the task line, or a lookup that can be rebuilt from the vault and the Reminders store. An index that is lost may only cost the link, never content.
- Graphite never deletes an event or reminder it did not create, and never deletes one without the user asking.
- Events are not copied into the vault unless the user inserts them.

## Decisions

Chosen 2026-11-12, for the owner to confirm (the owner said "just do it"):

- **The link between a task and its reminder is a block ID on the task's line**, `^reminder-` and eight letters or digits, written at the end of the line as Obsidian writes block IDs (a task that has one already keeps it and is linked by it). The reminder carries the note's `graphite://open` link with `&block=<ID>`, which also opens the note from Reminders. Why: it is visible, it is ordinary Obsidian syntax (links to `#^reminder-…` work), and it survives without a Graphite database; matching on text and date breaks as soon as either is edited. The one piece kept outside the vault, whether each pair was done when they last agreed (`GraphiteLinkedTasks.<vault>`, per device), only tells which side changed; when it is lost, being done wins, so no completion is undone.
- **The Tasks plugin's emoji fields are the convention**: 📅 for the due day (📆 and 🗓 read too), ✅ for the day done; Dataview's inline fields are not read. Why: the request already writes them, the Tasks plugin is the most used task plugin, and its fields stay plain text everywhere.
- **The calendar view is a segment of the sidebar's existing panel row** (Files, Tags, Properties, Bookmarks, Calendar), on the iPad, the iPhone and the Mac alike, and not a tab. Why: no new row of chrome; a fifth symbol still leaves each segment room for a finger in an upright iPad's sidebar (checked in the simulator); Obsidian's Calendar plugin is a sidebar view too.
- **The Mac gets the same features**: the panel, the commands, Settings › Calendar and the Reminders link; EventKit and the sandbox's Calendars entitlement serve both platforms.
- **The Calendar core plugin is on by default** and costs nothing until used: no event store, no listener and no question exist until a calendar or reminders feature is used. Turned off, its panel, commands and Settings page go away and `{{events}}` stays as written.
- **Settings are the vault's**: `.obsidian/graphite-calendar.json` (Obsidian ignores it) keeps each calendar's event-note folder and the Reminders lists by title, which is the same on every device, where EventKit's identifiers are not.
- **Write-only calendar access is not used**: Graphite reads events and adds none.

## Open questions

The four questions below were answered under Decisions on 2026-11-12, for the owner to confirm.


- How should a task remember its reminder: an inline marker (for example a Tasks-style field or a block ID), or matching on text and date? A marker is reliable but adds text to the note.
- Which Obsidian plugin conventions to follow: the Tasks plugin's emoji fields, Dataview inline fields, or both?
- Should the calendar view live in the sidebar, a tab, or both, given the screen-space rule of keeping chrome to a minimum?
- macOS: same features, or Calendar only?
