# Relations, rollups, new notes from a view and course dashboards in Bases: TODO

Created: 2026-11-26.

Status: planned 2026-11-26. Nothing is built yet. Issues: [#252](https://github.com/Graphite-Note/Graphite/issues/252) to [#255](https://github.com/Graphite-Note/Graphite/issues/255), one per section, linked under each heading.

## Request

Features 1 and 2 of `Docs/Notion-features-for-Graphite.md`: relations between the notes of two bases with a picker, the reverse side and rollups as ordinary Bases formulas, "New" in a view that fills in the values its filters imply, and linked views: a course page that embeds views of other bases filtered by `this`, made from a starter, with `this` in an embed meaning the embedding note in every view type.

## What Obsidian 1.15 does (checked 2026-11-26 in `obsidian-1.15.1.asar`)

- **No relation type.** A relation is a list property of `[[links]]`. A base's `properties` section keeps only `displayName` as a known key and carries any other key through a save (`unrecognizedData`), but nothing reads one as a relation.
- **New in a view.** The toolbar's New button (`bases:add-item` in the command list) reads two top-level keys of the `.base` file, `newItemFolder` and `newItemTemplate` (a template file's path), both optional strings, written back as they were read. Without a template, the new note's properties come from the base's filters joined with the view's (all rules inside `and`, `or` and `not`, those under an odd number of `not` left out):
  - `property == value`, `>=` and `<=` set the property to the value, evaluated with the new note as the row, so `this` is the note the base is embedded in, written as a link from the new note.
  - `property.contains(x)`, `containsAll`, `startsWith` and `endsWith` set the property to `x`, as a one-item list when the vault takes the property as a list. `containsAny(a, b)` sets the first value. `property.isEmpty()` sets an empty value. `list(property)` counts as `property`.
  - `file.hasTag("t")` adds `t` to `tags`, `file.tags.contains…` sets `tags`, `file.hasProperty("p")` adds an empty `p`, and `file.inFolder("F")` or `file.folder == "F"` chooses the folder.
  - Each note property of the view's `order` that is not set yet is added empty.
  - With a template, the template's frontmatter is used instead of all of that, and the body stays empty. The folder is `newItemFolder`, else the template's own folder, else the folder the filters name, else the vault's location for new notes.
- **Kanban.** New in a column sets the grouped property to the column's value (`createNoteInGroup`), and a board grouped by folder makes the note in that folder.
- **Formulas.** `file.backlinks` is a list of links, `asFile()` turns a link into its file, and `list.contains` compares loosely: a link equals the file it resolves to. Lists have `length`, `sum()`, `mean()`, `min()`, `max()`, `median()`, `filter()`, `map()`. Formulas can read each other (`formula.assignments`).
- **Embeds.** In `![[Assignments.base#This course]]`, `this` is the embedding note (the query's `sourcePath`).

## Decisions

Decided 2026-11-26, for the defaults that have one clear answer:

- **No new `.base` key for relations.** Obsidian has none, and a key of Graphite's would mean nothing there. The relation picker finds its notes from the vault: first the notes the property already links to in any note, then the other notes of those notes' folders, then every note the typed text finds, as the quick switcher finds them. A `course` property that names one course already offers the folder of courses.
- **A property is a relation** when its value in the row holds a link to a note, or when the values the vault gives it most often are links. Any text or list property can become one: its editor offers Link Notes, which opens the picker.
- **One link or several.** A property the vault declares as text (`.obsidian/types.json`) takes one note. A list property, a value that is already a list, and an empty property the vault does not declare take a list, as Obsidian writes `course: ["[[VLSI 3]]"]` for a list property. A single link that is not declared becomes a list when a second note is chosen.
- **Links are written as Obsidian writes them**: `"[[Target]]"`, the target named by the vault's link format from the row's note, through the checked property write every base edit uses.
- **The reverse side is a formula, never stored.** "Notes linking here through `course`" is the formula `file.backlinks.filter(list(value.asFile().properties.course).contains(file))`. Graphite's `file.backlinks` gives files where Obsidian's gives links, so Graphite's `asFile()` also takes a file and returns it, and the same formula evaluates the same in both apps.
- **Rollups are formulas of the base** written into its `formulas` and added as a column of the view: count, sum, average, minimum, maximum and percent checked of a property of the related notes, or the related notes themselves, through list functions both apps have. A rollup over the reverse side reads the reverse formula (`formula.assignments.length`), so the relation is written once.
- **New follows Obsidian's rules** for the filters' values, the template and `newItemFolder`, with three choices of Graphite's: the template's body is copied with `{{title}}`, `{{date}}` and `{{time}}` filled in as Insert Template fills them (Obsidian copies only its frontmatter), the filters' values are set over the template's properties (Obsidian drops them when a template is set, so its new note leaves the view), and the folder named by the filters comes before the template's own folder (Obsidian's order puts new notes in the Templates folder).
- **New asks for the note's name** in a small sheet, as New Note does, prefilled with "Untitled", then opens the note in a new tab, so the course page that made it stays open.
- **New sits in the base's toolbar row**, as an icon button beside View Options: no new row. A Kanban column's own New sits in its header. Both are shown only where the base can make a note (Bases on, a vault open).
- **New Note settings** (`newItemFolder`, `newItemTemplate`) are edited from View Options › New Note Settings… of a `.base` file. Obsidian 1.15 has labels for them but no control, so this writes the keys it reads.
- **The course starter** is a set of ordinary files made once in a chosen folder (`Courses` at the vault's root by default): `Courses.base` (courses, with rollups of their assignments: count, done, percent done), `Assignments.base` and `Lectures.base` (a "This course" view filtered by `list(course).contains(this)`, and an "All" view grouped by course), the folders `Assignments` and `Lectures`, and the template `Course.md` in the Templates folder (the vault's, or `Templates`) holding the embeds `![[Courses/Assignments.base#This course]]` and `![[Courses/Lectures.base#This course]]`. `Courses.base` names that template and its folder in `newItemTemplate` and `newItemFolder`, so its New makes a course page in Obsidian as well. Existing files are never overwritten. The files' text lives in resource files.
- **New Course…** in the sidebar's New menus and the command list (`graphite:new-course`) makes the starter where it is missing, then a course through `Courses.base`'s New.
- **Embed Base View…** in the editor's Insert menu and the command list (`graphite:insert-base-view`) chooses a `.base` file and one of its views and writes `![[Path.base#View]]` on a line of its own at the cursor.
- **Off costs nothing.** All of it lives in Bases: the picker, the builder and the sheets are made when opened, and with Bases off none of the buttons, menus or commands exist.

## Storage rules

- A relation is the frontmatter list of links Obsidian reads. Nothing is stored twice: the reverse side and every rollup are formulas in the `.base` file, evaluated on demand.
- Graphite adds no `.base` key beyond those Obsidian 1.15 reads (`newItemFolder`, `newItemTemplate`, `formulas`, `order`).
- A new note is an ordinary Markdown note whose frontmatter Obsidian reads as written.

## 1. Relations: a picker in base views

Issue: [#252](https://github.com/Graphite-Note/Graphite/issues/252)

- [ ] A Core decision of what a relation is and what choosing notes writes (`BaseRelation`): whether a property is one, one link or a list, the written link text, and the value after a note is added or removed. Tests with plain values.
- [ ] The picker's notes: the property's linked notes across the vault with their counts, then the other notes of their folders, then the typed text's matches, each named by its title with its folder, the chosen ones checked. Bounded queries of the index only.
- [ ] The base's property sheet shows the picker for a relation, and Link Notes for any text or list property. Choosing and removing notes writes the frontmatter once on Save, through the checked write, and the row shows the links.
- [ ] Tests: the Core decision, the candidates query, and a hosted test that choosing a note in the sheet writes `"[[Note]]"` into the row's note.
- [ ] Checked on an iPad simulator and in a Mac Debug copy with a demo vault.

## 2. Reverse relations and rollups

Issue: [#253](https://github.com/Graphite-Note/Graphite/issues/253)

- [ ] `asFile()` on a file returns the file, so formulas written for Obsidian's `file.backlinks` links evaluate the same. Test.
- [ ] A Core builder of rollup formulas (`BaseRollupFormula`): through a link property of the rows, or through the notes linking here by a property, of the related notes themselves or one of their properties, with count, sum, average, minimum, maximum or percent checked. Each formula evaluated over records in tests.
- [ ] `BaseDefinitionEditor` sets a formula and adds a column to a view, keeping the rest of the file as written. Tests.
- [ ] Add Rollup… in View Options: the relation, the property, the calculation and the column's name, a preview of the formula, and Save writing the formula and the column.
- [ ] A hosted or rendered check that a saved rollup shows its values in the table.
- [ ] Checked on an iPad simulator and in a Mac Debug copy with a demo vault.

## 3. New notes from a view

Issue: [#254](https://github.com/Graphite-Note/Graphite/issues/254)

- [ ] `newItemFolder` and `newItemTemplate` read into `BaseDefinition` and kept by the editor, with tests.
- [ ] A Core planner (`BaseNewItemPlan`) of the folder and the properties a new note gets from the base's and the view's filters, `this`, the view's columns, the template and `newItemFolder`, by the rules above. Tests per rule.
- [ ] Making the note: a unique name in the folder, the template's body filled in, the frontmatter written once, saved as a new file, the index told, the note opened in a new tab. Failure-injection test of the save.
- [ ] The New button in the base's toolbar with the name sheet, and New in a Kanban column's header, which sets the column's value.
- [ ] New Note Settings… in View Options writes `newItemFolder` and `newItemTemplate`.
- [ ] A hosted test: New in an embedded view filtered by `this` makes a note linked to the embedding note, which the view then shows.
- [ ] Checked on an iPad simulator and in a Mac Debug copy with a demo vault.

## 4. Linked views and course dashboards

Issue: [#255](https://github.com/Graphite-Note/Graphite/issues/255)

- [ ] Tests that `this` in an embed is the embedding note in every view type Graphite draws (table, cards, list, Kanban, map, and calendar once that view lands), for filters, formulas and New.
- [ ] Embed Base View… in the Insert menu and the command list writes `![[Path.base#View]]` at the cursor. Test of the written line.
- [ ] The course starter's resource files, and the code that writes the missing ones without overwriting any. Tests of the files made and of a second run that changes nothing.
- [ ] New Course… in the sidebar's New menus and the command list, making the starter where missing and then a course page.
- [ ] A rendered or hosted check of a course page: its two embedded views show only that course's assignments and lectures, and `Courses.base` shows the rollups.
- [ ] Checked on an iPad simulator and in a Mac Debug copy with a demo vault: a course made, an assignment added from its page, marked done, and the percent done in `Courses.base` changed.
- [ ] `Docs/Architecture.md` and `Docs/Coverage.md` describe what was built and how it was checked.
