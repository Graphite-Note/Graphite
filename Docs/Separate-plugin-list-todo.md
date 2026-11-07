# Graphite's own list of enabled community plugins: implementation TODO

Created: 2026-11-07.

Status: done 2026-11-07. Issue: [#143](https://github.com/Graphite-Note/Graphite/issues/143).

## Request

The owner, 2026-11-07, after the plugins' page measured 1.29 GB on the Mac (Omnisearch alone about 600 MB): "can we make it so that graphite and obsidian plugins (the ones loaded) can be seperate". A plugin turned on or off in Graphite should not turn it on or off in Obsidian, and the other way round, so that Graphite can run a lighter set (Course Timetable for Bases without Omnisearch, say) while Obsidian keeps its own.

## What exists today (2026-11-07)

- Graphite reads and writes Obsidian's `.obsidian/community-plugins.json` (`CommunityPluginList`, `VaultStore.communityPluginList()` and `updateCommunityPluginList` in `Sources/GraphiteCore/CommunityPluginList.swift`; `CommunityPluginHost.reloadInventory` and `setEnabled`). A switch in Graphite's Settings › Community Plugins, or a plugin's `app.plugins.enablePlugin`, changes Obsidian's list.
- Whether community plugins run at all is already Graphite's own and per device (`GraphiteCommunityPluginsTurnedOn.<vault>` in user defaults).

## Decision

- Graphite keeps its list in the vault, in `.graphite/community-plugins.json` (the folder Graphite already uses for `.graphite/pronunciations.json`), in Obsidian's format. It travels with the vault, so the Mac and the iPad share it; Obsidian never reads it. Chosen over a list per device (user defaults), which would make every device start again.
- Until Graphite has its own file, it follows Obsidian's list, so nothing changes for a vault until a plugin is switched in Graphite. The first switch writes Graphite's file, starting from Obsidian's list as it is then; from that moment the two are separate. Graphite never writes `.obsidian/community-plugins.json` again.

## 1. Graphite's own list

Issue: [#143](https://github.com/Graphite-Note/Graphite/issues/143)

- [x] `VaultStore.communityPluginList()` reads `.graphite/community-plugins.json` when it exists and Obsidian's list otherwise; `updateCommunityPluginList` writes only Graphite's file, starting from Obsidian's list when Graphite has none, and creates no file for a change that changes nothing. Done 2026-11-07: `Sources/GraphiteCore/CommunityPluginList.swift` (`graphiteConfigurationPath`, `obsidianConfigurationPath`); a plugin's own `app.plugins.enablePlugin` goes through the same `setEnabled`, so it changes Graphite's list too.
- [x] Settings › Community Plugins says which list its switches change, and that Obsidian keeps its own. Done 2026-11-07: the Installed Plugins section's footer, "These switches choose the plugins Graphite runs. Obsidian keeps its own choice, so a plugin can be on in one app and off in the other.", seen in the Mac app.
- [x] Tests: Core tests that a switch in Graphite leaves Obsidian's file byte for byte, that the first switch starts from Obsidian's list, that later changes to Obsidian's file no longer reach Graphite, and that an unreadable Graphite file is reported, not taken as empty. Done 2026-11-07: `testGraphiteFollowsObsidiansListUntilItSwitchesAPluginThenNeverWritesIt`, `testObsidiansLaterChangesDoNotReachGraphitesList` and `testAnUnreadableGraphiteListIsReportedNotTakenAsEmpty` in `Tests/GraphiteCoreTests/CommunityPluginTests.swift`; the `CommunityPlugin` Swift tests pass (192). No hosted test switches a plugin: `CommunityPluginHostTests` only checks that Obsidian's seeded list is left as written, which still holds; hosted tests were not run on this Mac.
- [x] Checked in the Mac app: Course Timetable for Bases on in Graphite and off in Obsidian, Omnisearch the other way round. Done 2026-11-07, in a Debug copy of the Mac app on a test vault whose Obsidian list held only Omnisearch: switching Course Timetable for Bases on wrote `.graphite/community-plugins.json` as `["omnisearch", "course-timetable-bases"]` and the plugin ran; switching Omnisearch off left `["course-timetable-bases"]`; Obsidian's file kept the same MD5 throughout. Not checked on the iPad, nor with the owner's vault.
- [x] `Docs/Community-plugins.md`, `Docs/Architecture.md` (if it names the file) and `Docs/Coverage.md` say where the list lives. Done 2026-11-07.
