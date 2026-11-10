# Graphite's own list of enabled community plugins: implementation TODO

Created: 2026-11-07.

Status: done (section 1 2026-11-07, section 2 2026-11-10). Issues: [#143](https://github.com/Graphite-Note/Graphite/issues/143) (section 1), [#148](https://github.com/Graphite-Note/Graphite/issues/148) (section 2).

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

## 2. Graphite leaves out by default what it does itself

Issue: [#148](https://github.com/Graphite-Note/Graphite/issues/148)

The owner, 2026-11-10: "reduce again, also make it so that we can have different sets of plugins enabled from obsidian". Their vault had no Graphite list yet, so Graphite still ran all six of Obsidian's plugins. Four do nothing useful in Graphite: Omnisearch repeats Graphite's search, Maps (Obsidian's map layout for bases) repeats Graphite's own map view, Colors repeats Graphite's Colors core plugin, and LaTeX Suite works only through editor extensions (`registerEditorExtension`), which Graphite's editor does not run. Decision (taken in this session, to be confirmed by the owner): while Graphite has no list of its own, it runs Obsidian's list without these; switching one on in Graphite runs it, and Obsidian's list is untouched.

- [x] `CommunityPluginList.pluginsGraphiteDoesItself` names these plugins by identifier with the reason; `VaultStore.communityPluginList()` leaves them out of Obsidian's list while Graphite has none, and Graphite's first switch starts its list from that. Done 2026-11-10: `withoutPluginsGraphiteDoesItself` in `Sources/GraphiteCore/CommunityPluginList.swift`.
- [x] Settings › Community Plugins says, under such a plugin, what in Graphite does its work, and that it is off in Graphite unless switched on. Done 2026-11-10 (`whatGraphiteLacks` in `CommunityPluginSettings.swift`), seen in the Mac app under Colors and LaTeX Suite.
- [x] Tests: Core tests that these are left out while Graphite follows Obsidian, that the first switch starts from the shorter list, and that one switched on in Graphite runs. Done 2026-11-10: `testPluginsGraphiteDoesItselfStayOffInGraphiteUntilSwitchedOnThere`; the `CommunityPlugin` Swift tests pass (193).
- [x] Measured in a Debug copy of the Mac app with the owner's six plugins on a vault shaped like theirs: the plugins' page before and after. Done 2026-11-10, settled footprint of the plugins' page: 577 MB before (all six), 248 MB after (Graphite runs Dataview and Course Timetable for Bases), 67 MB with only Course Timetable for Bases on in Graphite.
- [x] `Docs/Community-plugins.md` and `Docs/Coverage.md` updated. Done 2026-11-10.
