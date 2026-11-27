# Downloadable core plugins: TODO

Created: 2026-11-27.

Status: planned, nothing built. Issues: [#263](https://github.com/Graphite-Note/Graphite/issues/263) to [#267](https://github.com/Graphite-Note/Graphite/issues/267), one per section, linked under each heading.

## Request

Requested 2026-11-27, after a review of which built-in features could leave the app: "these things should not come with the app, as they slow things down and a lot of people might not need them. PostgreSQL Mirror and Goodnotes and Notability Import should remain easily downloadable from the core plugins but one can delete them and whatever but lets think more".

The features named in that review were the PostgreSQL Mirror, Goodnotes and Notability Import, and Read Aloud. The result must be that a person who never uses them does not download, install or run their code, and a person who wants one gets it from Settings, Core Plugins, with one Download, and can delete it again.

## What exists today (2026-11-27)

- **Core plugins.** `CorePlugin` (`Sources/GraphiteUI/GraphitePreferences.swift`) lists 22 built-in features. Settings, Core Plugins shows a switch for each, kept per device (`CorePluginSwitches`, `GraphiteDisabledCorePlugins`, `GraphiteEnabledCorePlugins`). Read Aloud and the PostgreSQL Mirror are off by default, every other plugin is on. Every one of them is compiled into the app.
- **What the three cost in the app.**
  - PostgreSQL Mirror: `Sources/GraphitePostgreSQLMirror` (about 1,600 lines) and its client, PostgresNIO with SwiftNIO, NIOSSL, BoringSSL and AsyncAlgorithms. At least 5.6 MB of the iOS binary (symbol sizes of the dSYM, a lower bound, `Docs/App-size-todo.md`), linked whether the mirror is on or off, on the iPad as well, although the mirror feeds desktop applications such as QGIS.
  - Goodnotes and Notability Import: `Packages/NotebookImport` (reading and planning, about 9,000 lines, imports only Foundation, CoreGraphics and zlib), `Sources/GraphiteApple/NotebookImport` (writing the pages with PencilKit and PDFKit, 15 files) and six files in `GraphiteUI`. It runs when a `.goodnotes` or `.note` file is dropped or opened. Most people use it once, when they move from Goodnotes or Notability. What it writes are ordinary PDFs and drawings in the vault, which open without it.
  - Read Aloud: about 10,000 lines in 49 files, `Sources/GraphiteVoices`, the vendored `Vendor/mlx-audio-swift` and MLX (its resource bundle 2.4 MB), and the math speech JavaScript (MathJax and Speech Rule Engine, 1.2 MB in `Sources/GraphiteApple/Resources/MathSpeech`). Referenced from 54 files of `GraphiteUI`. Off by default, and with it off nothing of it is created (`Docs/Read-aloud-core-plugin.md`). The neural voices are already downloads (236 MB for Pocket TTS alba).
- **Downloads.** `AddOnPackStore` (`Sources/GraphiteApple/AddOnPackStore.swift`) installs packs into `Application Support/Graphite/Add-ons/<id>`: a staging folder first, every file's size and SHA-256 checked, then moved into place with a marker naming the revision. The welcome tour's pictures use it.
- **WebAssembly plugins.** The Notion importer in `Graphite-Note/Importer` builds with Embedded Swift to a WebAssembly module of 890 KB and imports in Graphite's plugin web view as the linked package does, 10,051 pages in 156 s on the iPad simulator with the web content process under 352 MB (`Docs/Notion-import-todo.md` section 7). Its core uses the standard library only. WebKit runs no WebAssembly in Lockdown Mode, which is why the Notion importer's linked copy was kept.

## The limit that shapes the plan

App Store guideline 2.5.2 forbids an app to download native code that adds features. This holds for the iPad and iPhone app and for the Mac app, which is distributed through App Store Connect as well. Code run by WebKit or JavaScriptCore is the exception that Graphite's community plugins already use. So a feature can leave the app in one of three ways only:

1. **A downloaded plugin** of JavaScript, or of Swift compiled to WebAssembly, run in a web view. It fits work that is mostly reading files, converting and writing files.
2. **A separate program** outside Graphite, which reads the vault's ordinary files (OBJECTIVE.md).
3. **Its own repository, still linked into the app.** The code leaves the repository but not the app, so this gives separation, not a smaller app.

Swift user interface code cannot be downloaded. A downloaded plugin's settings and progress are drawn by Graphite's own Swift, from a description the plugin gives, or in the plugin's web view.

## Decisions

Proposed 2026-11-27, to be confirmed. The open choices are marked as such.

1. **A downloaded core plugin is per device and lives outside the vault**, in `Application Support/Graphite/Add-ons/<id>` through `AddOnPackStore`, as the core plugin switches are per device (`Docs/Read-aloud-core-plugin.md`). It is never written into `.obsidian/plugins`, so Obsidian never sees it and no vault carries it to a device that does not want it.
2. **Graphite runs only what it knows.** The app ships a manifest of the downloadable core plugins: identifier, version, address of the release file in a `Graphite-Note` repository, size and SHA-256. A download that does not match is refused. A newer plugin reaches a device with the next app update that names it. A manifest fetched from the network, signed, is left for later.
3. **A host of its own, not the community plugin runtime.** Downloaded core plugins run in one web view that Graphite makes when a plugin starts work and releases when it ends. They get a small, versioned Graphite interface: read the source the person picked by range, write vault files through `VaultStore` (never replacing a file), report progress, write a report. They do not get the `obsidian` module and do not need the community plugins switch, since their code is Graphite's own and checked by its SHA-256. The scheme handler, the WebAssembly loading and the call bridge are shared with the community plugin runtime and the Notion importer plugin.
4. **Lockdown Mode.** Where the web view runs no WebAssembly, the plugin's row in Core Plugins says so and names the way out (excluding Graphite in Lockdown Mode's web browsing settings, or importing on another device). Accepting this means a person in Lockdown Mode cannot import Goodnotes notebooks on that device, unlike the Notion import, whose linked copy stays. **Open:** accept this, or keep a linked copy of the notebook import as well.
5. **Nothing already imported or mirrored depends on the plugin.** Deleting the notebook import leaves every imported notebook as it is. Deleting the mirror leaves the database as it is.
6. **Every other core plugin stays in the app.** Bases, Canvas, Graph View, Map View, Templates, Daily Notes, Backlinks, Outline, Properties, Tags, Bookmarks and the rest are core plugins in Obsidian as well, are built on Apple's frameworks (MapKit, PencilKit, PDFKit) that cost the app nothing, and are already off with their switch. Moving them out would cost a boundary for no measurable saving.
7. **Open: where the PostgreSQL Mirror goes** (section 3). Proposed: a separate Mac program in its own repository.
8. **Open: Read Aloud** (section 4). Its neural voice engine runs MLX, native GPU code, which cannot be downloaded. Proposed: measure first, try the engine in a web view, then decide.
9. **Open: the Notion importer.** Decided 2026-11-27 that its linked copy stays for Lockdown Mode. Under the rule of this request it would become a downloadable core plugin too, with decision 4's message.

## 1. Download, switch and delete in Core Plugins

Issue: [#263](https://github.com/Graphite-Note/Graphite/issues/263)

- [ ] App Store guideline 4.7 (software not embedded in the binary) read in its current text, and the Core Plugins page designed within it: the index of plugins it asks for, nothing offered as a store, no native interface given to the plugins beyond what the community plugins already have.
- [ ] `CorePlugin` knows which plugins are downloads. Settings, Core Plugins shows for such a plugin: Download with its size while it is not on the device, its switch and Delete once it is, Update when the app's manifest names a newer version, and why it cannot run where it cannot (Lockdown Mode, a Mac-only program on the iPad).
- [ ] The manifest of decision 2 in the app, and the download through `AddOnPackStore` with progress, Cancel, and a failed or interrupted download leaving nothing behind.
- [ ] Delete removes the plugin's folder and its caches, turns its switch off, and asks first, saying what stays (imported files, the database).
- [ ] The places that start the feature offer the download when it is missing: a dropped or opened `.goodnotes` or `.note` file asks to download Goodnotes and Notability Import (name, size, source) and imports once it is there.
- [ ] The plugin host of decision 3: one web view made when a plugin starts work and released when it ends, the module served as `application/wasm`, the Graphite interface versioned so an app update that changes it refuses an older plugin with a message.
- [ ] A device that had a feature before the update finds it as a download, with a one-time note in Core Plugins, and its settings kept.
- [ ] Tests: the switch states and the download, update and delete steps with plain values and a test transport, a damaged download refused, the host's calls with a test module.
- [ ] Checked on the iPad simulator and the Mac: download, use, delete, download again, and with the network off.

## 2. Goodnotes and Notability Import as a download

Issue: [#264](https://github.com/Graphite-Note/Graphite/issues/264)

- [ ] `Packages/NotebookImport` moves into `Graphite-Note/Importer` as the targets `GoodnotesImport` and `NotabilityImport`, next to `NotionImport`, with its tests and fixtures. Code goes into that repository, never under `Packages/`.
- [ ] Their code uses the standard library only and builds with Embedded Swift in the Importer's CI: CoreGraphics' points, rectangles and transforms replaced by the package's own types, zlib by the Importer's `Inflater`, contents as `[UInt8]`, the zip reading shared with `ImporterCore`.
- [ ] The boundary: the plugin reads and plans, one page at a time, and hands Graphite each page's plan (`ImportedPagePlan` with its strokes, pictures and background, the outline, recordings, the report) in a versioned format. Graphite's writer (`Sources/GraphiteApple/NotebookImport`, PencilKit and PDFKit) stays in the app and writes the pages, so the files written are the ones written today.
- [ ] A plugin release in the Importer repository and its entry in the app's manifest.
- [ ] The plugin imports every fixture notebook as the linked package does, file by file, compared by a test before the linked copy leaves. Time and the web content process's memory measured on the largest Goodnotes and Notability notebooks on the iPad and the Mac, against the linked import.
- [ ] Then the linked copy leaves the app: `NotebookImport` removed from `Package.swift`, both `Package.resolved` files and the Xcode project, and the app's size before and after recorded (section 5).
- [ ] Checked on the iPad simulator and the Mac: a Goodnotes notebook and a Notability note dropped with the plugin absent, downloaded, imported, the plugin deleted, the imported notebook still opening.

## 3. PostgreSQL Mirror out of the app

Issue: [#265](https://github.com/Graphite-Note/Graphite/issues/265)

Two ways out, to be chosen:

- **A, a separate Mac program** (proposed) in its own repository, `Graphite-Note/PostgreSQLMirror`: a small Mac program, signed and notarized, that watches the chosen vault folder and mirrors it with the PostgresNIO client it has today. It links `GraphiteCore` and `GraphiteIndex` from this repository, which then offers `GraphiteIndex` as a library. The app keeps no part of it on either platform. It keeps the database current while Graphite is closed, and an iPad's edits reach it through the vault's sync. On the iPad, Core Plugins says it runs on a Mac. It does not run on the iPad itself.
- **B, a downloadable core plugin.** A PostgreSQL client in Swift compiled to WebAssembly, connected through a TCP and TLS connection the host would give it (`Network.framework`). It would run on the iPad too. Against it: the client written again without SwiftNIO, a web view running for as long as the mirror is on, Lockdown Mode, and a raw network connection given to downloaded code, which guideline 4.7 may count as a native interface given to the software.

- [ ] A or B chosen.
- [ ] For A: the repository, the program (vault folder, server, database, user, the password in the Keychain, a status in the menu bar), its tests moved from `GraphitePostgreSQLMirrorTests` and run against the PostgreSQL and PostGIS server used today.
- [ ] For A: Core Plugins on the Mac links to the program's release, and the settings a device had are carried over (a shared Keychain group if the signing allows it, else asked once).
- [ ] `GraphitePostgreSQLMirror`, PostgresNIO and its packages removed from `Package.swift`, both `Package.resolved` files and the Xcode project, and the app's size before and after recorded (section 5).
- [ ] Checked on the Mac: a vault mirrored by the program, a note edited in Graphite on the iPad simulator reaching the database, QGIS reading the places.

## 4. Read Aloud out of the app

Issue: [#266](https://github.com/Graphite-Note/Graphite/issues/266)

- [ ] Measured first: the bytes of `GraphiteVoices`, MLX, `MLXAudioTTS`, math speech and the Read Aloud interface in a link map of the iOS and Mac Release builds, and the launch time and memory at rest of a build with Read Aloud compiled out against one with it.
- [ ] Math speech (MathJax and Speech Rule Engine, 1.2 MB of JavaScript run by JavaScriptCore) becomes an add-on pack downloaded with Read Aloud's first voice, like the voices.
- [ ] A trial of a neural voice in a web view with WebGPU (a model of the size of Pocket TTS or Kokoro, through ONNX Runtime Web) on the physical iPad and the Mac: time to the first sound, speed against real time, the web content process's memory, heat over a 30-minute lecture, Lockdown Mode, all against today's MLX engine.
- [ ] Then decided, from the trial: either the engine becomes a downloadable core plugin and the app keeps only the player (audio output, Now Playing, word highlight, the system voice), MLX and `mlx-audio-swift` leaving the app, or the engine moves to its own repository, `Graphite-Note/Voices`, still linked and off by default as today.
- [ ] The chosen way built, its tests moved with it, the app's size before and after recorded (section 5), and Read Aloud checked on the physical iPad with a downloaded voice.

## 5. Measured before and after

Issue: [#267](https://github.com/Graphite-Note/Graphite/issues/267)

- [ ] Before any feature leaves: Release archives of iOS and the Mac measured (`scripts/archive-for-testflight.sh --archive-only`, `scripts/app-size-budget.py`): app, binary, resource bundles, launch to the first frame on the physical iPad and the Mac, and memory at rest with a vault open.
- [ ] The same after each section, recorded here with the commit measured.
- [ ] The size budget recorded again (`scripts/app-size-budget.py --record`) once the features are out, closing `Docs/App-size-todo.md`'s items that this work settles.
- [ ] `Docs/Architecture.md`, `Docs/Coverage.md`, `Docs/Read-aloud-core-plugin.md` and the Guide say where each feature now comes from.
