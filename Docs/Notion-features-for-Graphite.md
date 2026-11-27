# Notion's killer features, measured against Graphite

Draft, 2026-11-26, extended 2026-11-28. Pure research for now: nothing here is built, scheduled, or tracked as a todo or a GitHub issue. Turning any item into work means writing a `Docs/<Feature>-todo.md` and its issues first, as AGENTS.md describes.

## The question

Which of the features people cite as their reason to stay on Notion would fit Graphite, possibly done better, while keeping its rules: a small core whose extras are downloads that cost nothing when off, ordinary files that Obsidian also reads, no fake features, a Pencil-first iPad and a fast iPhone, and students as the main users.

## What the sources say people stay for

- **Databases first.** Comparisons and switching stories agree that databases, relations, rollups and their views are the reason people stay ([Slite](https://slite.com/learn/obsidian-vs-notion), [Yahoo Tech](https://tech.yahoo.com/apps/articles/tried-notion-obsidian-month-heres-150810614.html), [G2](https://learn.g2.com/obsidian-vs-notion)). One guide says Notion to Obsidian "is the switch that most often gets reversed" because Obsidian fixes speed, offline and lock-in but not structure ([Bright SEO Tools](https://brightseotools.com/post/Notion-Alternatives)).
- **Linked views.** A filtered view of one database inside a page is the single thing one long-time user missed most after leaving ([Medium, Mrs Productivity](https://mrsproductivity.medium.com/notion-after-3-years-why-im-finally-cancelling-and-what-replaced-it-4795fb1da9ff)).
- **Buttons and synced blocks**, then toggles, comments and collaboration ([XDA](https://www.xda-developers.com/replacing-notion-with-obsidian-as-main-note-taking-app-here-how-it-went/), [Alphonso Labs](https://www.alphonsolabs.com/notion-obsidian-migration-checklist/)).
- **The student pattern** is a handful of related databases (Courses, Lectures, Assignments, Exams, Readings), a course page template holding a linked Assignments view filtered to "this course", rollups for progress and grade weight, and a calendar of due dates ([Medium, Tomas Vemola](https://medium.com/@tomasvemola/how-i-organize-my-student-life-with-notion-and-why-you-should-too-d9f66714c469), [MindLifeUp](https://mindlifeup.com/notion-for-students-mastering-notion-for-college/), [JooJ template](https://note.com/jooj_wall/n/nb0b7df2e08c3?hl=en), [Notiease](https://notiease.com/article-best-templates)). The Reddit post named in the request (r/Notion, "How I use Notion as an engineering student") could not be fetched from this environment, so its specifics are not cited here.
- **Why people leave Notion:** speed on large workspaces and on phones, offline use (real offline mode only since August 2025, per page and per device, offline databases capped at 50 rows), price, and lock-in ([Fabric](https://fabric.so/comparison/how-to-leave-notion-without-losing-your-mind), [Notion help: offline](https://www.notion.com/help/use-pages-offline), [AlternativeTo](https://alternativeto.net/news/2025/8/notion-rolls-out-offline-mode-edit-pages-without-an-internet-connection)). Graphite already wins on every one of these. The work is to close the structure gap without losing that.

## A record, not a note

The reason is easy to miss for someone who takes notes. Most Notion users barely write: a Notion page is usually a record, not a note. They keep lists of things with attributes (assignments with a course, a due date and a status; job applications with a stage; books with a rating; workouts, expenses, habits), and the page body is often close to empty. The value is the row and the views of the rows. Notion is closer to a spreadsheet dressed as a website, or an application builder for people who do not program, than to a note-taking app.

What makes it click for them: an assignment entered once appears on the course page, on the calendar, on a "due this week" dashboard and on a board where it moves from To do to Done, with nothing copied. For a life run by deadlines, nothing in a plain note app does that.

The other reasons are friction, not features:

- **No setup.** A downloaded "University Dashboard" template works the same evening. "I know it can be done and I could learn how to do it, I just don't want to" (r/Notion, quoted in the second review below). A plugin recipe is not a feature.
- **Looks.** Covers, icons and columns. People use what they enjoy looking at.
- **Sharing.** A link to a page for a group partner, or Notion because a team or school already uses it.

Students are often both kinds of user: notes for lectures, a tracker for deadlines, and today two apps for it.

## The portability test

Graphite already stores everything a Notion database needs. A record is a Markdown note, its fields are frontmatter properties (`due: 2026-12-05`, `status: todo`), a relation is a link (`course: "[[VLSI 3]]"`), and a view is a `.base` file. Obsidian reads all of it. What is missing is the interface: today the setup above means writing YAML and filter expressions by hand, and Notion's advantage is that nobody sees that machinery.

Every candidate feature passes two checks:

1. It writes only files that Obsidian, or any text editor, already understands.
2. With Graphite deleted, the files still make sense on their own.

Under that test the work is almost entirely interface on top of existing files. The items that would matter most on a switching student's first day are relations and new entries in views (section 1), the slash menu and block handles (section 4), and ready-made starter workspaces (section 14 below).

## Ranked shortlist

The Notion importer (Docs/Notion-import-todo.md, the Swift Importer, issues #228 to #232) is the way in and is already planned. It turns Notion databases into `.base` files and relations into links, so every item below is also what an imported workspace needs in order to keep working after the import.

| Rank | Feature | Obsidian today | Graphite today | Carried by | Core or plugin | Effort |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Relations, rollups and new entries in Bases | Links in list properties, `asFile()` and `backlinks` in formulas, no picker | Formulas, summaries, `asFile`, `backlinks`, `this` all evaluate, but no relation picker, no new entry from a view | List of `[[links]]` in frontmatter, formulas in `.base` | Core | M |
| 2 | Linked views and course dashboards | Embedded bases with `this` | Embedded bases draw in notes | `![[Course.base#View]]` with `this` filters, a template | Core (mostly exists) | S |
| 3 | Calendar view and Apple Calendar mirror | Planned on the roadmap, community plugins today | Not built (#47 plans EventKit) | Date properties, `.base` view | Core | M to L |
| 4 | Slash menu and block handles | Slash commands core plugin, no handles | Neither | Nothing new: plain Markdown | Core | S (menu), M to L (handles) |
| 5 | Lecture transcript and summary | None in core | Recording only | `.md` transcript beside the `.m4a`, timestamps as links | Core, off by default | M to L |
| 6 | Presenting a note, with Pencil | Slides core plugin | Missing (laser exists on pages) | `---` separators in the note | Core | M |
| 7 | Timeline view, sub-items and dependencies | Community plugins | Native Gantt drawing exists for Mermaid | `start`, `end`, `parent`, `blockedBy` properties | Core view on existing drawing | M |
| 8 | Chart view (grades, hours, progress) | Community plugins | Native Mermaid pie and XY charts | `.base` view of groups and summaries | Plugin first, then core | M |
| 9 | Page look: icons, covers, columns | Iconize, Banners, multi-column callouts | Folder emoji and icons only | `icon`, `banner` properties, `[!multi-column]` callouts | Core, small | S |
| 10 | Web clipper | Official Web Clipper (Safari too) | No share extension | `.md` with `source` and `clipped` properties | Core extension | M |
| 11 | Editable embedded blocks (synced blocks) | Read-only block embeds | Read-only block embeds | `![[Note#^id]]` | Core | L |
| 12 | Buttons | Meta Bind plugin | Not swept | `meta-bind-button` code blocks | Downloadable plugin | S (to check) |

Effort: S is days, M is one to three weeks, L is more, for one person, before device checks.

## 1. Relations, rollups and new entries in Bases

**Notion.** A relation property links rows of two databases, optionally two-way. A rollup reads a property across the related rows (sum, count, percent checked). Formulas compute over both. Database templates give each new row its body and properties.

**Obsidian.** A relation is a list property of `[[links]]`. Bases formulas can follow a link (`link.asFile().properties.x`) and look back (`file.backlinks`, `file.hasLink(this.file)`), which covers rollups and the reverse side of a relation in formulas ([Obsidian roadmap](https://obsidian.md/roadmap/), Bases since 1.10). What Obsidian lacks is the interface: no picker that limits a relation to the notes of another base, no two-way write, no rollup builder.

**Graphite today.** `BaseEvaluator` evaluates `asFile`, `backlinks`, `linksTo`, `properties`, `this`, summaries and the list functions. Property editing in a view goes through `BaseDocumentModel.setProperty`. Property and tag suggestions are planned (Docs/Property-and-tag-completion-todo.md, #167 to #169). There is no relation picker and no new entry from a view (Coverage.md lists "a new note from a column" as missing for Kanban).

**How, as ordinary files.**
- A relation cell in a base view is a picker over the notes a chosen base returns, writing a frontmatter list of `[[links]]` (`course: ["[[VLSI 3]]"]`). Obsidian reads it as an ordinary list property.
- The reverse side is never stored twice. It is a formula column offered as a preset: "Assignments of this course" becomes `file.backlinks` filtered by folder or tag, which Obsidian computes identically. Storing both sides, as Notion does, would mean two files to keep in step and a conflict whenever iCloud delivers one before the other.
- A rollup builder writes ordinary Bases formulas (`course.asFile().properties.credits`, `list(assignments).filter(...).length`). The `.base` file is the record, and Obsidian evaluates it the same way.
- "New" in a view creates a note in the base's folder with the values the view's filters imply (`course` set to `this` on a course page) and the body of a template named in the view. Where the template name lives needs a check of what Obsidian 1.15 writes for its own new-note button before inventing a key.

**Core, M.** It reuses the Bases engine, the property editor and the completion popup, and costs nothing at rest.

**Why it matters.** This is the structure gap itself. A student's Courses, Assignments and Exams with grade weights and "percent done" are the template every Notion student guide builds.

## 2. Linked views and course dashboards

**Notion.** A linked view shows a filtered view of a database on another page. The 2026 dashboard view arranges up to 12 widgets on one page, on Business and Enterprise plans only ([Notion help: charts](https://www.notion.com/help/charts), [DEV](https://dev.to/benarikutai/three-ways-to-get-a-notion-dashboard-in-2026-20g7)).

**Obsidian and Graphite.** Both embed a base in a note (`![[Assignments.base#Due soon]]`), and a filter on `this` makes it the linked view of the page it sits on. Graphite draws embedded tables, cards and lists at their natural height (Architecture.md, "Bases inside notes").

**How.** Little new code. A "Course" starter template (a course note with `![[Assignments.base#This course]]`, `![[Lectures.base#This course]]` and a progress summary), a command "Embed a View of This Base Here…" that writes the embed line, and a check that `this` inside an embed resolves to the embedding note in every view type. A dashboard is a note with several embeds, which Notion charges a Business plan for.

**Core, S.**

**Why it matters.** It is the most missed Notion feature in the sources, and Graphite already has the engine.

## 3. Calendar view and an Apple Calendar mirror

**Notion.** A calendar view lays a database's date property on a month grid with drag to reschedule ([Notion help: calendars](https://www.notion.com/help/calendars)). Notion Calendar shows connected databases beside Google calendars, but not in iCloud or Google Calendar themselves ([Notion help: Notion Calendar](https://www.notion.com/help/use-notion-calendar-with-notion)). Date mentions and `@remind` set reminders.

**Obsidian.** "Calendar view for Bases" is on the official roadmap as planned ([Obsidian roadmap](https://obsidian.md/roadmap/)). Community views fill the gap meanwhile: Calendar Bases (`calendar-bases`, start and optional end date, about 135,000 downloads) and others ([obsidianstats](https://www.obsidianstats.com/plugins/calendar-bases), [mtellin/obsidian-bases-calendar](https://github.com/mtellin/obsidian-bases-calendar)).

**Graphite today.** No calendar view and no EventKit (Docs/Calendar-and-reminders-todo.md, #47, not started). The Calendar community plugin draws its month in the sidebar.

**Built 2026-11-26** (`Docs/Bases-calendar-todo.md`, issues #241 to #245): the `calendar` view of Bases with Calendar Bases' keys, month and week grids for the iPad, the Mac and the iPhone, rescheduling by drag, and Calendar Copy, the one-way copy into a "Graphite" calendar. #47's EventKit reading had been built on 2026-11-12.

**How.**
- A native `calendar` view for Bases: month and week grids, a note per date property value, drag to change the date through the same checked frontmatter edit as Kanban. The precedent is the Map view, which reads the keys of Obsidian's Maps plugin. Until Obsidian ships its own calendar view, read the keys of the most used community view (Calendar Bases) so the same `.base` draws in Obsidian with that plugin, then follow Obsidian's keys once they are published. Building it under a key Obsidian later uses differently would split the format.
- An Apple Calendar mirror as a core plugin, off until turned on, like the PostgreSQL Mirror: the notes a chosen base returns are copied one way into a "Graphite" calendar on the device through EventKit, and rebuilt from the vault at any time. Due dates then show in Calendar, on the Lock Screen, in widgets and on a watch, with no server and no account. This is the part Notion Calendar cannot do with iCloud.
- Reminders stay as #47 plans them: Tasks-plugin dates (`📅 2026-12-01`) sent to Reminders only for the tasks the user chooses.

**Core, M for the view, M for the mirror.** EventKit and the drawing are system frameworks, nothing at rest.

**Why it matters.** Deadlines are the daily reason a student opens a planner. A due date that appears in the system calendar without a subscription is better than what Notion offers.

## 4. Slash menu and block handles

**Notion.** `/` opens a menu of every block type. A `⋮⋮` handle beside each block drags it, turns it into another type, duplicates or colours it.

**Obsidian.** The Slash commands core plugin opens the command palette at `/`. There are no block handles in core (make.md adds them).

**Graphite today.** "Slash commands: Missing" (Docs/Obsidian-mobile-gaps.md). Move lines up and down exists, folding exists, tables have their own menu.

**How.** Nothing reaches the file but the Markdown it inserts. The slash menu reuses the `[[` completion popup with Insert's entries (heading, callout, table, math, Mermaid, drawing, notebook, embed of a base, template), filtered as typed, and Obsidian's own setting for it. Block handles in Live Preview: a handle in the left margin of the block under the pointer (on the iPad, under a long press) that drags the block (heading sections move with their content, as folding already knows), and a menu to turn a paragraph into a heading, quote, callout or task. Handles appear only on hover or touch, to respect the rule that every row above the page is waste.

**Core. S for the menu, M to L for handles** (TextKit 2 hit testing, touch versus Pencil versus text selection).

**Why it matters.** It is how Notion feels on the first day. A switching student who types `/` and gets nothing assumes the app cannot do what it can.

## 5. Lecture transcript and summary

**Notion.** AI Meeting Notes record, transcribe with speaker labels since 3.6, and summarise. In November 2026 they can be created and linked to calendar events through the API ([Notion 3.6](https://www.notion.com/releases/2026-07-01), [releases index](https://releasebot.io/updates/notion)).

**Obsidian.** Nothing in core. Plugins send audio to cloud services with the user's key.

**Graphite today.** Session-level recording to M4A and MP4 with crash recovery. Siri answers from the vault are planned with the Foundation Models framework and Spotlight (Docs/Siri-vault-answers-todo.md).

**How.** After Stop, the system's on-device speech recognition writes a transcript note beside the recording (`Lecture 2026-11-26.md` next to `Lecture 2026-11-26.m4a`), each paragraph starting with a timestamp link that seeks the recording, the slot OBJECTIVE.md left for note-to-recording timestamps. An optional summary at the top comes from Apple's on-device model, clearly marked as generated. If the recording ran during a calendar event (section 3), the note takes the event's course. Everything is ordinary Markdown that Obsidian shows, with the links degrading to plain text there.

**Core plugin, off by default, M to L.** The frameworks ship with the OS, so the binary grows only by the glue code. A cloud model would mean accounts and keys, and stays with downloadable plugins such as Copilot.

**Why it matters.** Lectures are the student's meetings. Graphite already records them. A private, offline transcript linked to the slides annotated during the lecture is something neither Notion nor Obsidian does.

## 6. Presenting a note, with Pencil

**Notion.** Presentation mode (3.4, beta) shows the sections between dividers of a page as full-screen slides ([Notion 3.4](https://www.notion.com/releases/2026-03-26), [Eazy](https://eazyhq.com/blog/notion-slides)).

**Obsidian.** The Slides core plugin does the same with `---` separators.

**Graphite today.** "Slides: Missing". The laser pointer and the lasso exist on pages and drawings.

**How.** The note's reading view split at `---` (Obsidian's rule), drawn full screen, on an external display through AirPlay or a cable with the iPad as presenter. The Pencil writes on a slide with the laser or with ink that fades, and nothing is saved unless asked, so the note is never changed by presenting. Saving the ink would go through the existing drawing embed.

**Core, M.** It reuses the reading view, Export to PDF's page splitting, and the laser.

**Why it matters.** Students present labs and group projects. Presenting the note itself with Pencil annotation is better than Notion's version and plays to the iPad goal.

## 7. Timeline view, sub-items and dependencies

**Notion.** A timeline (Gantt) view over start and end dates, sub-items through a self-relation, and dependency arrows with optional date shifting ([Notion help: sub-tasks and dependencies](https://www.notion.com/help/guides/tasks-manageable-steps-sub-tasks-dependencies), [timeline](https://www.notion.com/help/guides/intro-to-timeline-view)).

**Obsidian.** Community Bases views (Bases Timeline View, Chronos Timeline) ([obsidianstats weekly](https://www.obsidianstats.com/posts/2026-10-10-weekly-updates), [Chronos](https://github.com/clairefro/obsidian-plugin-chronos/blob/main/main.ts)).

**Graphite today.** A native Mermaid Gantt renderer (`ReadingGanttChart*`) already draws bars, sections and dates.

**How.** A `timeline` base view that feeds the base's rows to the Gantt drawing: bars from a start and an end property, grouped by `groupBy`, sub-items as indented rows under the note named in a `parent` link property, and arrows from a `blockedBy` list of links. Dragging a bar edits the dates. Keys follow the most used community view, as in section 3.

**Core, M.** The drawing exists, so the view is cheap at rest.

**Why it matters.** Semester projects, theses and lab series. Lower than the calendar for most students, higher for engineering projects.

## 8. Chart view

**Notion.** Bar, line, donut and number charts as a database view, one chart on the Free plan ([Notion help: charts](https://www.notion.com/help/charts)).

**Obsidian.** Community plugins only (Power Bases and others).

**Graphite today.** Native Mermaid pie and XY charts in reading view.

**How.** A `chart` base view: group by a property, plot a summary (count, sum, average) per group, drawn with the existing chart drawing or Swift Charts. Obsidian shows a view type it does not know as unsupported, while keeping the file and its other views intact. To keep "Obsidian also reads it" true, ship it first as a small JS Bases view plugin that runs in both apps, and move it into the core only if it proves popular and the plugin's web view memory (67 MB for one Bases view plugin, Docs/Community-plugins.md) is the cost to remove.

**Plugin first, M.**

**Why it matters.** Grade tracking and study hours. Useful but not a switching reason on its own.

## 9. Page look: icons, covers and columns

**Notion.** Every page has an icon and an optional cover. Columns sit blocks side by side. Toggles and toggle headings fold.

**Obsidian.** Icons through Iconize, covers through Banners or Pixel Banner (a `banner` property), columns through the multi-column callouts of popular CSS snippets. Headings and callouts fold in core.

**Graphite today.** Folding headings, lists and callouts (`> [!note]-`) is done, which covers toggles and toggle headings. Folders take emoji and pictures as in Finder. Iconize loads but its icons are not shown.

**How.**
- An `icon` property (an emoji or an SF Symbol name) shown in tabs, the file list, the quick switcher, links and Library mode.
- A `banner` property drawn as a short cover in reading view only, collapsible, and never on the iPhone by default, so it does not cost the screen space the editor needs.
- `> [!multi-column]` callouts drawn as columns where the note is wide enough and stacked on the iPhone. The file stays a callout that every Markdown reader shows.

**Core, S.** Properties and callouts already exist.

**Why it matters.** Many students choose Notion for how a course page looks. These keep that without a format of Graphite's own.

## 10. Web clipper

**Notion.** The Notion Web Clipper saves pages into a database.

**Obsidian.** The official Web Clipper runs in Safari on macOS, iOS and iPadOS, with templates and triggers, and writes through the `obsidian://` URI and the clipboard ([Obsidian help](https://obsidian.md/help/web-clipper), [obsidian-clipper](https://github.com/obsidianmd/obsidian-clipper)). It cannot target Graphite, because only Obsidian receives `obsidian://`.

**Graphite today.** No share extension (Docs/Obsidian-mobile-gaps.md). `graphite://new` takes Obsidian's parameters.

**How.** A share extension (it is also what the Goodnotes import waits for) that receives a page from Safari, turns it into Markdown with Defuddle (MIT, the extractor the Web Clipper uses) run in JavaScriptCore inside the extension, and saves a note with `source`, `author`, `published` and `clipped` properties into a chosen folder. Reading Web Clipper's exported template JSON would let a student reuse templates already made for Obsidian.

**Core extension, M.** The extension runs only when invoked. Its size goes in the size budget.

**Why it matters.** Students clip papers, documentation and articles for reports. Today that path leads into Obsidian, not Graphite.

## 11. Editable embedded blocks (synced blocks)

**Notion.** A synced block is one block shown in several places, edited anywhere ([Notion help](https://www.notion.com/help/synced-blocks)).

**Obsidian and Graphite.** `![[Note#^id]]` and heading embeds show the source's current text everywhere, but read only. Graphite already ticks tasks inside an embedded note.

**How.** Tapping an embedded block in Live Preview edits it in place, writing to the source note through its own session (with its undo history and conflict checks) and reflowing every other embed. No new syntax: the embed line is already the synced copy.

**Core, L.** Two sessions editing at once inside one text view is the hard part.

**Why it matters.** Shared definitions, a formula sheet reused across course notes, a weekly checklist. Lower than the items above because read-only embeds already cover most of the reading side.

## 12. Buttons

**Notion.** Button blocks and button properties run actions: insert blocks, add pages, edit properties ([Notion help: database buttons](https://www.notion.com/help/database-buttons)).

**Obsidian.** Meta Bind's buttons (successor of the Buttons plugin) run commands, create notes from templates and set properties, on desktop and mobile ([Meta Bind](https://community.obsidian.md/plugins/obsidian-meta-bind-plugin), [docs](https://www.moritzjung.dev/obsidian-meta-bind-plugin-docs/)).

**Graphite today.** Not in the community plugin sweep. Templater and QuickAdd load.

**How.** Run Meta Bind unmodified in the plugin runtime: its buttons are code blocks the runtime's post-processors already draw, and its actions are commands and template runs. Sweep it, fix runtime gaps, and add it to Docs/Community-plugins.md. A native button syntax would be read by nothing else.

**Downloadable plugin, S to check, more if the runtime lacks an API.**

**Why it matters.** "New Assignment" and "Start Lecture" buttons on a course page are a staple of Notion student templates.

## Further ideas from a second review (2026-11-28)

A ChatGPT conversation ("Compare Notion Obsidian Use", 2026-11-26 and 2026-11-27, not available as a link) reached mostly the same list as sections 1 to 12: relations, formulas and rollups over frontmatter, a block editor that saves Markdown, dashboards, columns, calendar, Kanban and chart views, buttons, and the same caution about bloat (someone who only writes notes never meets a schema or an automation). It also says that the SQLite index should be a disposable cache that can always be rebuilt from the files, which Graphite's `GraphiteIndex` already is. Four of its ideas are not in the sections above and pass the portability test. They are not ranked into the shortlist.

### 13. Export a folder as a static website

**Idea.** Publishing a note or a folder as a site, without Notion Sites' hosting.

**How, as ordinary files.** A local export of a folder to plain HTML, CSS and images, drawn from the reading view (wikilinks become relative links, embeds become images or inline content), written to a folder the user uploads anywhere (GitHub Pages, their own server). No account and no hosting by Graphite, which is why it is separate from the publishing rejected below. The Webpage HTML Export community plugin does this for Obsidian on desktop; whether it runs in Graphite's plugin runtime, or a native export built on Export to PDF's rendering is lighter, is to check.

**Core or plugin, M.**

### 14. Starter workspaces

**Idea.** Notion's template gallery installs a whole working system, not one page. That answers the strongest complaint in the sources, not wanting to build the system first.

**How, as ordinary files.** A starter workspace is a folder copied into the vault: for students, `Courses.base`, `Assignments.base` and `Exams.base`, a course note template, a dashboard note embedding their views (section 2), and two example entries to delete. Installing it is a copy; removing it is deleting the folder. Anyone could share one as a zip or a GitHub repository, with no marketplace required. It is the natural place for the Notion importer (Docs/Notion-import-todo.md) to land an imported workspace too.

**Core, S** once sections 1 and 2 work: the folder itself is content, and it is downloaded only when chosen, which keeps the app small.

### 15. Local automations without a new format

**Idea.** "When a new assignment is created for VLSI 3, put its deadline in the calendar, set a reminder and create revision tasks."

**How, as ordinary files.** The review proposed a YAML automation engine of Graphite's own, which Obsidian would not read. The portable route reuses what exists: Templater's folder templates (a template applied to every new note in a folder, which can set properties and add task lines) and Calendar Copy (section 3, built 2026-11-26) for the deadline. Reminders stay with #47. Whether Templater's "trigger on new file creation" fires in Graphite's plugin runtime is to check. Automations that run while the app is closed need a background service and stay rejected.

**Plugin, S to check.**

### 16. Sharing a vault through a shared iCloud Drive folder

**Idea.** A small group (a lab group, a project team) sharing notes without a collaboration server.

**How, as ordinary files.** iCloud Drive lets a folder be shared with other Apple accounts. A vault, or a folder inside one, shared that way is still ordinary files, with no server or account beyond iCloud. It gives shared files, not live co-editing: two people editing the same note at once get iCloud's conflict copies ("Note 2.md"), which Graphite would need to detect and offer to merge. How Graphite behaves on a shared folder is untested.

**Core, S to check, M if conflict handling needs work.**

### Where the second review breaks portability

- **A `.workspace/` folder of Graphite's own** (`schemas/`, `views/`, `layouts/`, `automations/` as YAML). Its own rule says not to invent formats where open ones exist, and they do: views are `.base` files, property types are `.obsidian/types.json`, layouts are callouts. The one thing with no Obsidian file is a schema of required fields per kind of note; a new-entry sheet built from a base's columns (section 1) covers most of it.
- **Real-time collaboration with CRDTs**, ranked high there. It needs a relay server, accounts and reconciling CRDT state with Markdown edited elsewhere. It stays rejected below.
- **A third "visual" editing mode** next to Live Preview and Source. A third mode is another round trip that can lose Markdown formatting; block handles inside Live Preview (section 4) give the same feel.

## Smaller items worth noting

- **Page history.** Notion keeps 7 days on the Free plan ([Notion help](https://www.notion.com/help/duplicate-delete-and-restore-content)). Graphite's File recovery keeps device copies with no limit by plan, but shows no differences. A side-by-side diff in the recovery sheet would make it plainly better than Notion's. Core, S to M.
- **Mentions of dates and reminders.** Natural Language Dates and Aloha already work in the runtime (`@tom` becomes a date link). Reminders belong to #47.
- **Offline and speed.** Already better than Notion by construction. Worth saying in the Notion importer's welcome text, with numbers measured on a device rather than claimed.
- **Tabs block** (Notion 3.4). No Obsidian syntax exists. Headings with folding cover it. Not worth a format of its own.

## Rejected

- **Collaboration, comments, mentions of people, guests, teamspaces, permissions:** need accounts and a server, and Obsidian's files carry none of it.
- **Publishing and sharing (Notion Sites, public links):** need hosting. Export to PDF and the share sheet already cover handing a note to someone, and a static site the user hosts themselves is section 13.
- **Forms:** collect answers from other people, which needs a server. The local half, a sheet that asks for a base's properties when creating an entry, is part of section 1.
- **Database automations (triggers on page added or property edited, notifications, mail):** need a process running in the background and a server for notifications. Local buttons (section 12) and the Tasks plugin's recurrence cover what a single student needs.
- **Notion AI agents, cloud Q&A, AI Autofill, image generation:** need accounts, keys and a cloud model in the core. Siri answers from the vault (planned, on device) and downloadable plugins (Copilot, Smart Connections) cover them without the core paying.
- **Synced databases with GitHub, Jira, Salesforce:** server integrations for teams, not students.
- **Two-way relations stored on both sides:** two files to keep in step under iCloud. The reverse side is a formula instead (section 1).
- **A Notion-like block format (make.md style database of blocks):** would replace Markdown with a structure Obsidian does not read.
- **Notion Mail and Notion Calendar as apps:** Mail closed on 2026-09-22 ([releases index](https://releasebot.io/updates/notion)), and Apple's Calendar is the calendar (section 3).

## Sources

- Notion help: [offline](https://www.notion.com/help/use-pages-offline), [synced blocks](https://www.notion.com/help/synced-blocks), [database buttons](https://www.notion.com/help/database-buttons), [database automations](https://www.notion.com/help/database-automations), [charts](https://www.notion.com/help/charts), [calendars](https://www.notion.com/help/calendars), [Notion Calendar with Notion](https://www.notion.com/help/use-notion-calendar-with-notion), [forms](https://www.notion.com/help/forms), [sub-tasks and dependencies](https://www.notion.com/help/guides/tasks-manageable-steps-sub-tasks-dependencies), [timeline view](https://www.notion.com/help/guides/intro-to-timeline-view), [delete and restore, version history](https://www.notion.com/help/duplicate-delete-and-restore-content)
- Notion releases: [3.2, 2026-01-20](https://www.notion.com/releases/2026-01-20), [3.4, 2026-03-26](https://www.notion.com/releases/2026-03-26), [3.4 part 2, 2026-04-14](https://www.notion.com/releases/2026-04-14), [3.6, 2026-07-01](https://www.notion.com/releases/2026-07-01), [releases index](https://releasebot.io/updates/notion)
- Obsidian: [roadmap](https://obsidian.md/roadmap/), [changelog](https://obsidian.md/changelog/), [Web Clipper help](https://obsidian.md/help/web-clipper), [Build a Bases view](https://docs.obsidian.md/plugins/guides/bases-view), [Calendar Bases](https://www.obsidianstats.com/plugins/calendar-bases), [Meta Bind](https://community.obsidian.md/plugins/obsidian-meta-bind-plugin)
- Switching and staying: [Slite](https://slite.com/learn/obsidian-vs-notion), [XDA](https://www.xda-developers.com/replacing-notion-with-obsidian-as-main-note-taking-app-here-how-it-went/), [Mrs Productivity](https://mrsproductivity.medium.com/notion-after-3-years-why-im-finally-cancelling-and-what-replaced-it-4795fb1da9ff), [Alphonso Labs](https://www.alphonsolabs.com/notion-obsidian-migration-checklist/), [Yahoo Tech](https://tech.yahoo.com/apps/articles/tried-notion-obsidian-month-heres-150810614.html), [Fabric](https://fabric.so/comparison/how-to-leave-notion-without-losing-your-mind), [Bright SEO Tools](https://brightseotools.com/post/Notion-Alternatives)
- Student setups: [Tomas Vemola](https://medium.com/@tomasvemola/how-i-organize-my-student-life-with-notion-and-why-you-should-too-d9f66714c469), [MindLifeUp](https://mindlifeup.com/notion-for-students-mastering-notion-for-college/), [JooJ](https://note.com/jooj_wall/n/nb0b7df2e08c3?hl=en), [Notiease](https://notiease.com/article-best-templates)
- Graphite: OBJECTIVE.md, Docs/Architecture.md, Docs/Coverage.md, Docs/Obsidian-mobile-gaps.md, Docs/Community-plugins.md, Docs/Calendar-and-reminders-todo.md, Docs/Notion-import-todo.md, Docs/Siri-vault-answers-todo.md, Docs/Property-and-tag-completion-todo.md, Sources/GraphiteCore/BaseEvaluator.swift
