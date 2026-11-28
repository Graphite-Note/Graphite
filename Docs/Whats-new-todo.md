# What's New: TODO

Created: 2026-11-28.

Status: planned and section 1 built 2026-11-28; section 2 built and checked in an iPad simulator, the Mac's Settings button and Help menu item not yet checked by hand. Issues: [#285](https://github.com/Graphite-Note/Graphite/issues/285) (section 1), [#286](https://github.com/Graphite-Note/Graphite/issues/286) (section 2).

## Request

Requested 2026-11-28: after every update, a page with what is new, and not only for that version. A tester may have skipped several builds during the beta, so the page shows what happened since the last update and lets them scroll back through every version with what each one added and fixed. It opens by itself once after an update.

## Decisions

- The history is one text file bundled with the app, `Sources/GraphiteUI/Resources/ReleaseNotes.md`, a few kilobytes, so it needs no network and costs nothing at launch until it is read (default, 2026-11-28). It is ordinary Markdown that also reads well on GitHub.
- Its grammar is strict, so a test can refuse a malformed file: `## <version>`, then `### <YYYY-MM-DD>` or `### <YYYY-MM-DD HH:MM>`, then lines `- Added: …`, `- Changed: …` or `- Fixed: …`, with an optional platform list `- Fixed [Mac]: …` (Mac, iPad, iPhone). A line with no platform list applies to every device, and a device shows only the lines that apply to it (default, 2026-11-28).
- What counts as new since the last update comes from the build number: the build number is the archive's date and time (`20261128.1405`), the app keeps the build number of the last What's New it showed, and a group dated after that build is new. A group with a date and no time counts as the end of that day, so a same-day group is shown as new rather than hidden (default, 2026-11-28).
- It opens once after an update, never on the first launch of a new install (the welcome tour opens then), and never in a hosted test launch. Opening it marks the build seen, so when several windows reopen at once only the first opens it, and a page left open by quitting does not come back. Settings › General › About and, on the Mac, Help › What's New in Graphite open it at any time (default, 2026-11-28).
- Each TestFlight upload adds its Fixed, Added and Changed lines to the file in a commit before the archive, the same lines as the build's What to Test note (default, 2026-11-28).

## 1. The release history

Issue: [#285](https://github.com/Graphite-Note/Graphite/issues/285)

- [x] The file's grammar, parsed in GraphiteCore into versions, dated groups and entries with kind and platforms; a malformed line is an error with its line number, not a silently dropped entry. Done 2026-11-28: `ReleaseHistory.read` in `Sources/GraphiteCore/ReleaseHistory.swift`; `ReleaseHistoryTests` (7) covers reading, moments and build numbers, narrowing to a device and every refusal with its line number.
- [x] The history back to the first TestFlight build (1.0 on 2026-10-20, then 1.0.1, 1.0.2 and 1.0.3), written from the commit history in words a tester understands. Done 2026-11-28: `Sources/GraphiteUI/Resources/ReleaseNotes.md`, 4 versions, 31 dated groups, about 240 lines; the days a version was raised carry the time of the change so each group belongs to one version. Dates and platform tags spot-checked against the commits.
- [x] A test that parses the bundled file and refuses an unknown kind or platform, dates out of order, or an empty group. Done 2026-11-28: `WhatsNewTests.testTheBundledReleaseNotesReadInFullAndListSomethingOnEveryDevice` reads the bundled file with the strict reader (it caught the same date under two versions while the history was written). `scripts/archive-for-testflight.sh` refuses to archive while the newest version in the file is not `MARKETING_VERSION`.
- [x] Docs/TestFlight.md: each upload adds its lines to the file before archiving. Done 2026-11-28: section What's New of Docs/TestFlight.md.

## 2. The What's New page

Issue: [#286](https://github.com/Graphite-Note/Graphite/issues/286)

- [x] A page grouped by version, newest first, each version's days with their Added, Changed and Fixed lines, scrolling through every version; the groups since the last update are marked as new. Done 2026-11-28: `WhatsNewPage` in `Sources/GraphiteUI/WhatsNew.swift`, version headers pinned while scrolling, each line's kind a coloured word. `WhatsNewTests.testThePageDrawsTheBundledHistoryWithGroupsMarkedNew`. Checked in an iPad simulator (iPad Pro 11-inch, iOS 27.2) in light and dark: an update from build 20261117.1236 marked 17 November and later as New and left 16 November unmarked.
- [x] It opens by itself once after an update, as the Decisions say, in one window only when several windows reopen. Done 2026-11-28: `AfterUpdateWhatsNew` with `WhatsNewAtLaunch.decide` (GraphiteCore); `WhatsNewScheduleTests` (6). Checked in the iPad simulator with a build numbered 20261128.1200: a new install showed the welcome tour and recorded the build without opening What's New, an update opened it, and the next launch opened nothing. Several windows reopening at once not checked.
- [ ] Settings › General › About › What's New, and Help › What's New in Graphite on the Mac.
- [ ] Checked on the Mac and in an iPad simulator: the first launch after an update shows it, the next launch does not, a new install shows the welcome tour instead.
