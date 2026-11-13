# Importing from Notion with a downloadable plugin: TODO

Created: 2026-11-13.

Status: planned, nothing built. Issues: [#172](https://github.com/Graphite-Note/Graphite/issues/172) to [#177](https://github.com/Graphite-Note/Graphite/issues/177), one per section.

## Request

The owner, 2026-11-13: "add as a todo, to create a plugin (that can be downloaded) to import from notion and it needs to be actually thought out properly", then: "https://github.com/obsidianmd/obsidian-importer already exists we can fork it and adapt it."

A student moving from Notion should get their workspace into a Graphite vault as ordinary files: pages as Markdown notes, databases as Obsidian Bases, attachments as files. Afterwards it should work in Graphite as if it had been written there, and in Obsidian too. The importer is a download, never part of the app (`lean-core-app`: the app stays small; JavaScript community plugins are the only code iOS lets Graphite download, App Store guideline 2.5.2).

## What exists today (2026-11-13)

- **Obsidian's Importer** (`obsidianmd/obsidian-importer`, MIT, by Obsidian, release 3.2.0 of 2026-11-12, `isDesktopOnly: false`, `minAppVersion` 1.13.0, `main.js` 5.1 MB) imports from Notion in two ways (its own help page, `obsidian.md/help/import/notion`, and `src/formats/notion.ts`, `src/formats/notion-api.ts`):
  - **Notion's HTML export** (`.zip`, `NotionImporter`): no token or network needed. Pages become notes and nested pages become folders ("Save parent pages in subfolders"). Databases are *not* kept as databases. Very large exports come as a zip of `Export-<id>-Part-N.zip` files. A Markdown export is refused because it leaves out data. Zips are read with `@zip.js/zip.js` from the picked `File` in 64 KB slices (`file.slice`, `READ_CHUNK`), so a picked export is not read into memory all at once.
  - **Notion's API** (`NotionAPIImporter`, the `@notionhq/client` library, Notion API version `2025-09-03`, which has data sources): needs an integration token (`ntn_…`), kept with `getSecret()` in Obsidian's secret storage, and the pages and databases shared with that integration. Each database becomes a folder with a `.base` file: a table view of all properties, plus a Kanban view per Notion board on API 1.14 and later. Notion formulas are converted to Bases formulas (`formula-converter.ts`); `name()`, `email()`, `style()` and `unstyle()` are not. Relations become links. Attachments are downloaded with `requestUrl`. Requests keep to Notion's rate of 3 a second after a burst of 100 (`NotionRequestScheduler`), backing off on 429 and on stalls. Not imported: views other than boards, boards' filters, sorts and sub-groups, linked data sources.
  - Both write a `notion-id` property (`NOTION_ID_PROPERTY`) and show a preview of the converted notes before importing. Importing again defaults to updating the notes an earlier import made and keeping those edited since (`DuplicateHandling.Update`, compared by modification time; also skip and copy).
- **In Graphite**, Importer 3.1.14 installs and loads (sweep of 2026-10-12, `Docs/Community-plugins.md`): "partly": its formats and steps draw in Settings and the system file picker opens, but *no import was ever run*. The runtime already gives what both Notion paths lean on: `requestUrl` made natively (https, **64 MB and 60 seconds at most per request**), `app.secretStorage` in the keychain, Node and Electron modules as stand-ins that fail only when used, `Platform` as on Obsidian mobile, API version 1.14.4, coordinated vault writes. Graphite's Bases draw table, cards, list, map and Kanban views (`BaseViewType`).
- **Installing:** Settings › Community plugins installs from Obsidian's directory or from any GitHub repository (`owner/name`) into `.obsidian/plugins/<id>/`. Graphite keeps its own list of plugins it runs (`.graphite/community-plugins.json`), apart from Obsidian's.

## Decisions (2026-11-13, owner's choice of a fork; the rest proposed in this session, to be confirmed)

1. **Fork Importer instead of writing an importer from nothing.** Notion's two formats, its block types, formula language, rate limits and export quirks are already handled and maintained by Obsidian, under MIT. A new importer would repeat that and fall behind.
2. **Fix the runtime before the fork.** Graphite's plugin goal (`OBJECTIVE.md`) is to run plugins unmodified. Anything upstream Importer needs from the `obsidian` API is fixed in Graphite's runtime, so that Obsidian's own Importer also works in Graphite. The fork changes only what is Graphite's to change (decision 4), and each change that would also help Obsidian on mobile is offered upstream as a pull request.
3. **The fork is its own plugin:** `Graphite-Note/graphite-importer`, id `graphite-importer`, name "Importer for Graphite". It must not keep the id `obsidian-importer`: Graphite installs into `.obsidian/plugins/<id>/`, so the same id would overwrite the copy of Importer that the owner's Obsidian runs, and Obsidian's updates would overwrite the fork. The name and description must not suggest that Obsidian publishes it. `LICENSE` keeps Obsidian's MIT notice and adds the fork's; the README says where it comes from and what it changes.
4. **What the fork may change:** its id, name and README; which formats it offers (decision 5); Notion views that upstream leaves out and Graphite's Bases can draw (section 4); limits that come from Graphite rather than from Notion (the 64 MB per request of `requestUrl`, say). Nothing that would make it run only in Graphite: the same build must still run in Obsidian.
5. **Formats offered: Notion only, at first** (both the HTML export and the API). Upstream also offers 14 other formats; none has been run in Graphite, and showing them untested would present features as working that are not (`OBJECTIVE.md`, "No fake features"). They stay in the source, so merging upstream stays easy, and are switched off in the fork's format list until each is checked in Graphite. *Open question for the owner:* show all of them, marked "not checked in Graphite", instead?
6. **Keeping up with upstream:** the fork tracks `obsidianmd/obsidian-importer`'s `master` and merges each upstream release within a week, its own changes kept as a few commits on top. Its version is upstream's with a suffix (`3.2.0-graphite.1`), so it is clear which upstream release it carries.
7. **Test material is made for the purpose, never the owner's own workspace** (`no-personal-notes-in-demos`): a Notion workspace on a test account, filled by a script through Notion's API from a few course notes, with every block type, property type, database view, nesting depth and attachment kind listed in section 2. Its HTML export and its API answers, recorded and scrubbed of the token and of user names, become test fixtures; the token itself is never written to the repository or to a log.

## 1. The fork

Issue: [#172](https://github.com/Graphite-Note/Graphite/issues/172)

- [ ] Fork `obsidianmd/obsidian-importer` into the organisation as `Graphite-Note/graphite-importer`; set its `manifest.json` id to `graphite-importer`, name to "Importer for Graphite", description, author and author URL; README with its origin, its changes against upstream, and how to install it in Graphite. `LICENSE` keeps Obsidian's copyright line.
- [ ] A release workflow building `main.js`, `manifest.json` and `styles.css` as release assets, as Obsidian's directory expects, with `versions.json` kept so Graphite's installer picks the newest release whose `minAppVersion` fits.
- [ ] Switch off every format but Notion (HTML) and Notion (API) in the fork's list of formats, as one small commit (decision 5), until each is checked.
- [ ] Write down how upstream is merged (decision 6) in the fork's README, with the list of the fork's own commits.

## 2. Test material

Issue: [#173](https://github.com/Graphite-Note/Graphite/issues/173)

- [ ] A Notion test account and workspace, set up by the owner (Graphite cannot create accounts for them), with an internal integration whose token goes into the Mac's keychain, never into a file.
- [ ] A script (`scripts/notion-test-workspace.py`) that fills the workspace through Notion's API from a few course notes, so the workspace can be made again: every block type (headings, lists, to-dos, toggles and toggle headings, quotes, callouts with icons, code with languages, equations inline and as blocks, dividers, tables, columns, synced blocks, link previews, bookmarks, embeds, page and database mentions, date and user mentions, child pages and child databases, breadcrumbs, table of contents); every property type (text, number with formats, select, multi-select, status, date and date ranges, person, files, checkbox, URL, email, phone, formula, relation one-way and two-way, rollup, created and edited time and by, unique ID); views of each kind (table, board, gallery, list, calendar, timeline, chart) with filters, sorts and groups; pages nested five deep; images, PDFs, audio and video uploaded to Notion and linked from outside; page icons (emoji and custom) and covers; titles with characters files cannot have (`/`, `:`, emoji, 200 characters); two pages with the same title in one folder; a linked database view of another page's database.
- [ ] A workspace large enough to measure: about 10,000 pages and a database of about 5,000 rows, with an HTML export over 1 GB (so it comes as `Part-N` zips).
- [ ] The workspace's HTML export (whole workspace, with subpages, files and images) and, from the API, the answers of each request made by an import, recorded into `Tests/Fixtures/Notion/` by a recording mode of the Node test host, with the token and user names replaced. Personal data checked out by hand before committing.

## 3. Upstream Importer run in Graphite, gaps fixed in the runtime

Issue: [#174](https://github.com/Graphite-Note/Graphite/issues/174)

Before changing the fork: Obsidian's own Importer, 3.2.0, unmodified, on the test material, so every gap found is the runtime's or the plugin's, and the runtime's are fixed for every plugin.

- [ ] Import the small HTML export in the iPad simulator and in the Mac app, and list each failure, unsupported feature reported, and wrong result (compare every note with the same import in Obsidian on the Mac, file by file, with `diff -r`).
- [ ] The same with the API on the small workspace.
- [ ] Sort each finding: a gap of Graphite's runtime (fix it here, with a runtime test in `Tests/CommunityPluginRuntimeTests`), a limit of Graphite's (the 64 MB and 60 s of a `requestUrl`, iOS's App Transport Security: decide whether to raise it, or report it in the import), or the plugin's own (goes to section 4, or upstream as an issue). Likely places, to be confirmed by the run: the file picker in the plugin panel handing a `File` of several GB to WebKit without copying it into the web content process's memory; the progress modal and Pause on the plugin panel sheet; `vault.createBinary` for large attachments through the message bridge (binary passes as base64, a third larger, and as one message); `fileManager.processFrontMatter` and `metadataTypeManager` for property types; the `.base` files Importer writes, read by Graphite's own Bases (every view and formula it writes draws, or is reported unsupported in the base).
- [ ] Graphite's index and file tree while thousands of files arrive: the vault stays usable (typing and Pencil not slowed), the index refreshes in batches, not once per file; measured on the large export.
- [ ] Every runtime fix has a runtime test and a line in `Docs/Community-plugins.md`; `Docs/Community-plugin-API-coverage.md` updated for any API added.

## 4. What the fork adds for Notion

Issue: [#175](https://github.com/Graphite-Note/Graphite/issues/175)

Each item is built in the fork, runs in Obsidian as well, and is offered upstream when it would help Obsidian too.

- [ ] Notion's table, gallery and list views as Bases table, cards and list views, with their filters, sorts and visible properties where Bases can express them, beside upstream's Kanban views of boards; calendar, timeline and chart views reported, not dropped silently. (Graphite draws all four kinds of view; Obsidian 1.14 does too.)
- [ ] Boards' filters, sorts and groups kept where Bases can express them.
- [ ] Linked database views, which upstream skips: a view of another database becomes a view in that database's `.base`, or a base embedded in the page, filtered as in Notion.
- [ ] An import report written as a note in the import's folder: per page and per database, what was converted, simplified (a column layout flattened, a synced block copied, a formula function Bases lacks) or left out, with a link to each note. Upstream shows its log only in the modal, which is gone once closed.
- [ ] Attachments bigger than one `requestUrl` can carry (64 MB in Graphite) downloaded in ranges or reported, never cut short. Notion's file links expire after about an hour, so attachments are downloaded while their page is converted, not at the end.
- [ ] Importing again into the same folder: upstream's Update mode (matched by `notion-id`, a note edited since the last import kept) checked in Graphite, where Graphite's own saves, iCloud and the file's modification time meet; an edited note is never overwritten. Changed in the fork only if the check finds a case that loses an edit.
- [ ] Notion math (`$…$`, `$$…$$` blocks) written as Obsidian math, which Graphite renders; Notion callouts with their icons as Obsidian callouts; toggles as foldable callouts; code blocks with their language.

## 5. Installing it from Graphite

Issue: [#176](https://github.com/Graphite-Note/Graphite/issues/176)

- [ ] Settings › Community plugins › Browse lists Graphite's own plugins (the fork first) above Obsidian's directory, from a list in this repository (`Plugins/graphite-plugins.json`, id, name, repository, description), so the fork is found without typing its repository.
- [ ] *Owner decision:* Import in the New menu (file list and library) offers "From Notion…": when the plugin is installed and on, it opens the plugin's Notion import; when not, it says what will be downloaded (name, size, from where) and installs it on the person's yes. Off and costing nothing until used (`lean-core-app`).
- [ ] The import runs on the plugin panel and leaves the rest of Graphite usable; leaving the vault while it runs is refused or pauses the import (the Goodnotes import refuses it).

## 6. Verification

Issue: [#177](https://github.com/Graphite-Note/Graphite/issues/177)

- [ ] The fork pinned in `Tests/CommunityPluginRuntimeTests/compatibility-plugins.json`, built from source by `npm run build-compatibility-plugins`, and checked in `real-plugins.test.js` against the recorded fixtures: the HTML export and the API answers each imported into a test vault, and the result compared file by file with an expected vault committed beside the fixtures (notes, `.base` files, attachments, property types in `types.json`).
- [ ] Every note of the import opens in Graphite in reading view, Live Preview and source mode with no error; each base draws each of its views; every link and embed resolves (Graphite's unresolved-links list empty for the import's folder).
- [ ] The same vault opened in Obsidian on the Mac: notes, bases and links identical in use.
- [ ] Malformed input: a Markdown export, a truncated zip, a `Part-N` zip alone, a revoked token, a page shared then unshared mid-import, Notion answering 429 and 5xx, the network lost and back. Each ends in a clear message and a usable partial import, never a crash or a hang.
- [ ] Measured on the large workspace, on the Mac and on the owner's iPad: time, the plugin web view's memory at its peak, and the app's responsiveness meanwhile (typing and Pencil latency), with the numbers recorded here.
- [ ] Checked by hand on the owner's iPad and on the Mac: installing from Browse, an HTML import picked from Files, an API import with the token in the keychain, Pause and Cancel, importing again.
- [ ] `Docs/Community-plugins.md` (the sweep's Importer row and a section for the fork), `Docs/Architecture.md` (if section 5 adds the New menu entry), `Docs/Coverage.md` updated with what is tested and what is not.

## Risks

- **Upstream moves fast** (3.1.14 to 3.2.0 in a month). Every merge can bring API calls the runtime lacks; the Node tests on recorded fixtures catch them before a release of the fork.
- **Notion changes its export and API.** The API's version is pinned by the client (`2025-09-03`); the HTML export is not versioned. Re-record the fixtures when an import of the test workspace stops matching.
- **Memory in the plugin's web view:** a large export and its attachments pass through WebKit's content process. A limit found in section 3 that the runtime cannot lift is stated in the plugin's description and report.
- **Notion's terms:** importing the person's own content with their own token is what Notion's API is for; the token never leaves the device's keychain and Notion's servers.

## Open questions

- Decision 5: only Notion at first, or every format, marked unchecked?
- Section 5: an "From Notion…" entry in Graphite's Import menu, or only through Settings › Community plugins?
- Should the fork be listed in Obsidian's community directory too? It would be a near copy of Obsidian's own plugin, which the directory is unlikely to accept; installing from its GitHub repository works either way.
