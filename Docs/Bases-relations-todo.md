# Relations, rollups, new notes from a view and course dashboards in Bases: TODO

Created: 2026-11-26.

Status: built and checked 2026-11-26, every section, on an iPad simulator and in the running Mac app. Not checked: the rollup builder's pickers operated by a test, a Kanban column's plus on a device, the iPhone. Issues: [#252](https://github.com/Graphite-Note/Graphite/issues/252) to [#255](https://github.com/Graphite-Note/Graphite/issues/255), one per section, linked under each heading.

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
- **Copy Embed Link** in a base's View Options copies `![[Path.base#View]]` (the base's vault path, so it reaches the base from any note) to paste into a note, where `this` is then that note. Decided 2026-11-26 while building, in place of a picker in the editor's Insert menu: the copied line is the same embed, written from the place that knows the base and its view, without a second list of every base of the vault.
- **Off costs nothing.** All of it lives in Bases: the picker, the builder and the sheets are made when opened, and with Bases off none of the buttons, menus or commands exist.

## Storage rules

- A relation is the frontmatter list of links Obsidian reads. Nothing is stored twice: the reverse side and every rollup are formulas in the `.base` file, evaluated on demand.
- Graphite adds no `.base` key beyond those Obsidian 1.15 reads (`newItemFolder`, `newItemTemplate`, `formulas`, `order`).
- A new note is an ordinary Markdown note whose frontmatter Obsidian reads as written.

## 1. Relations: a picker in base views

Issue: [#252](https://github.com/Graphite-Note/Graphite/issues/252)

- [x] A Core decision of what a relation is and what choosing notes writes (`BaseRelation`): whether a property is one, one link or a list, the written link text, and the value after a note is added or removed. Tests with plain values.
  Done 2026-11-26: `BaseRelation` (`isRelation`, `shape`, `links(in:)`, `propertyValue(chosen:shape:)`). Test: `BaseRelationTests` (4).
- [x] The picker's notes: the property's linked notes across the vault, then the other notes of their folders, then the typed text's matches, each named by its title with its folder, the chosen ones checked. Bounded queries of the index only.
  Done 2026-11-26: `BaseDocumentModel.relationCandidates` (`BaseDocumentModelRelations.swift`): the property's values from `VaultIndex.propertyValues` resolved from the row's note, then `VaultIndex.notes(directlyInside:limit:)` (new, at most 40 a folder, never the vault's root), then the quick switcher's matches through `BaseNoteServices.searchNotes`, at most 60, the row itself left out. The counts are not shown. Test: `BaseDocumentModelRelationsTests.testThePickerOffersTheLinkedNotesThenTheirFolderThenWhatTheQueryFinds`.
- [x] The base's property sheet shows the picker for a relation, and Link Notes for any text or list property. Choosing and removing notes writes the frontmatter once on Save, through the checked write, and the row shows the links.
  Done 2026-11-26: `BaseRelationPicker` in `BasePropertyEditorSheet` (opens on it when `isRelation`, Link Notes and Edit as Text switch), saved with `BaseRelation.propertyValue` through `BaseDocumentModel.setProperty`.
- [x] Tests: the Core decision, the candidates query, and a hosted test that choosing a note in the sheet writes `"[[Note]]"` into the row's note.
  Done 2026-11-26: `BaseRelationTests`, `BaseDocumentModelRelationsTests` (3, the write read back as `course:\n  - "[[VLSI 3]]"\n  - "[[Signals]]"`), hosted `BaseRelationsHostedTests.testTheSheetOfARelationOpensOnThePickerAndChoosingANoteSavesItsLink`.
- [x] Checked on an iPad simulator and in a Mac Debug copy with a demo vault.
  Done 2026-11-26: the picker on an iPad Pro 11-inch (M5) simulator of its own, iOS 27.2, a Debug build: `BaseRelationsHostedTests` in the app, its picture looked at (two linked notes with remove buttons, the offered notes checked, Edit as Text). The Mac: in the running Mac app (Debug, unsigned, bundle `com.graphite.study.repro`), `MacCourseDashboardInAppHostedTests` with `TEST_RUNNER_GRAPHITE_MAC_COURSES`, its pictures looked at, the picker of a made assignment's `course` read from the vault (Digital Design linked and offered, from its folder).

## 2. Reverse relations and rollups

Issue: [#253](https://github.com/Graphite-Note/Graphite/issues/253)

- [x] `asFile()` on a file returns the file, so formulas written for Obsidian's `file.backlinks` links evaluate the same. Test.
  Done 2026-11-26: `BaseEvaluator.typedMethod` answers `asFile()` on a file with the file. Test: `BaseRollupFormulaTests.testAsFileOnAFileReturnsTheFile`.
- [x] A Core builder of rollup formulas (`BaseRollupFormula`): through a link property of the rows, or through the notes linking here by a property, of the related notes themselves or one of their properties, with count, sum, average, minimum, maximum or percent checked. Each formula evaluated over records in tests.
  Done 2026-11-26: `BaseRollupFormula` (`relatedNotes`, `sourceText`, `uniqueName`), plus `percentChecked` 0 with no notes and `countChecked`. Test: `BaseRollupFormulaTests` (5), each formula evaluated by `BaseEvaluator` over courses and assignments, body-only backlinks left out.
- [x] `BaseDefinitionEditor` sets a formula and adds a column to a view, keeping the rest of the file as written. Tests.
  Done 2026-11-26: `BaseDefinitionEditor.setFormula(named:to:)` and `setText(_:for:)` (`BaseDefinitionEditorFormulas.swift`), the column through `setOrder`. Test: `BaseDefinitionEditorFormulasTests` (4, a comment kept, a formula replaced in place, a list refused).
- [x] Add Rollup… in View Options: the relation, the property, the calculation and the column's name, a preview of the formula, and Save writing the formula and the column.
  Done 2026-11-26: `BaseRollupBuilderSheet` (related notes through their property, this note's property or a formula, the calculation, the name, the formula shown) saving with `BaseDocumentModel.addRollup`, which writes the reverse relation once (`course backlinks`) and reuses a formula holding it. Save's path is tested in `BaseDocumentModelRollupsTests`, and the sheet was drawn in the running Mac app. Its pickers were not operated by a test.
- [x] A hosted or rendered check that a saved rollup shows its values in the table.
  Done 2026-11-26: `BaseDocumentModelRollupsTests` (the rollup's values in the base's rows, and a rollup run again when a note it reads is saved), hosted `BaseRelationsHostedTests.testACoursePageShowsItsOwnAssignmentsInEveryViewAndTheCoursesShowTheirRollups` (50 percent done). Found by this check on the iPad: a base whose formulas read other notes kept its old result when only those notes were saved (`BaseDocumentModel.showsTheSame`), and it now runs again (`otherNotesReadingFunctions`), the test failing before the fix.
- [x] Checked on an iPad simulator and in a Mac Debug copy with a demo vault.
  Done 2026-11-26: an iPad Pro 11-inch (M5) simulator of its own, iOS 27.2, a Debug build, a course page's Progress view (`Courses.base#Progress`) going from 0 to 100 percent done when its assignment's `done` was set on disk, after the fix above. The Mac: in the running Mac app (Debug, unsigned, bundle `com.graphite.study.repro`), `MacCourseDashboardInAppHostedTests` with `TEST_RUNNER_GRAPHITE_MAC_COURSES`, its pictures looked at, Done 1 and Percent done 100.

## 3. New notes from a view

Issue: [#254](https://github.com/Graphite-Note/Graphite/issues/254)

- [x] `newItemFolder` and `newItemTemplate` read into `BaseDefinition` and kept by the editor, with tests.
  Done 2026-11-26: `BaseDefinition.newItemFolder`, `newItemTemplate`, written by `BaseDefinitionEditor.setText(_:for:)`. Test: `BaseDefinitionEditorFormulasTests.testNewItemKeysAreWrittenReadAndRemoved`.
- [x] A Core planner (`BaseNewItemPlan`) of the folder and the properties a new note gets from the base's and the view's filters, `this`, the view's columns, the template and `newItemFolder`, by the rules above. Tests per rule.
  Done 2026-11-26: `BaseNewItemPlanner.plan` (`BaseNewItemPlan.swift`) and `BaseNewItemNote` (folder, values as properties, text). Tests: `BaseNewItemPlannerTests` (9, one or more per rule), `BaseNewItemNoteTests` (5).
- [x] Making the note: a unique name in the folder, the template's body filled in, the frontmatter written once, saved as a new file, the index told, the note opened in a new tab. Failure-injection test of the save.
  Done 2026-11-26: `BaseDocumentModel.createNewItem` (`BaseDocumentModelNewItem.swift`): planning off the main actor, `VaultStore.uniquePath`, links named by `BaseNoteServices.linkTarget`, the template filled by `fillTemplate`, saved `expecting: .absent`, shown by `showNewNote` (index, new tab, file list). Tests: `BaseDocumentModelNewItemTests` (5), with a missing template and a folder that cannot be made reported and no note made.
- [x] The New button in the base's toolbar with the name sheet, and New in a Kanban column's header, which sets the column's value.
  Done 2026-11-26: `BaseNewItemButton` in `BaseToolbar`, `BaseNewItemSheet`, and `BaseKanbanMoves.newNote` in each column's header (`BaseKanbanView`). Test: `BaseDocumentModelNewItemTests.testNewInAKanbanColumnSetsTheColumnsValue`. The column's button was not pressed on a device.
- [x] New Note Settings… in View Options writes `newItemFolder` and `newItemTemplate`.
  Done 2026-11-26: `BaseNewItemSettingsSheet` saving with `BaseDocumentModel.setNewItemSettings`. Test: `BaseDocumentModelRollupsTests.testTheNewNoteSettingsAreWrittenAsObsidiansKeys`.
- [x] A hosted test: New in an embedded view filtered by `this` makes a note linked to the embedding note, which the view then shows.
  Done 2026-11-26: `BaseRelationsHostedTests.testNewInAViewEmbeddedInACourseNoteMakesANoteLinkedToThatCourse` (the New button activated, Create pressed, the note written `course:\n  - "[[VLSI 3]]"\nweight:\ndone:`), and `BaseDocumentModelNewItemTests.testNewInAViewEmbeddedInACourseLinksTheNoteToTheCourseAndTheViewShowsIt`.
- [x] Checked on an iPad simulator and in a Mac Debug copy with a demo vault.
  Done 2026-11-26: an iPad Pro 11-inch (M5) simulator of its own, iOS 27.2, a Debug build, driven by a temporary XCUITest runner outside the repository: the plus of the course page's Assignments view tapped, Lab 1 named and created, the note opened in a new tab with `course:\n  - "[[Digital Design]]"`, and the page then listing it. New of the Progress view made a course from the template in `Courses`. The Mac: in the running Mac app (Debug, unsigned, bundle `com.graphite.study.repro`), `MacCourseDashboardInAppHostedTests` with `TEST_RUNNER_GRAPHITE_MAC_COURSES`, its pictures looked at, through the model's `createNewItem` the button calls (SwiftUI's buttons cannot be pressed from inside the app).

## 4. Linked views and course dashboards

Issue: [#255](https://github.com/Graphite-Note/Graphite/issues/255)

- [x] Tests that `this` in an embed is the embedding note in every view type Graphite draws (table, cards, list, Kanban, map, and calendar once that view lands), for filters, formulas and New.
  Done 2026-11-26: `BaseEmbedLinkTests.testThisIsTheEmbeddingNoteInEveryViewType` (table, cards, list, Kanban and map, each embedded in two courses), hosted `BaseRelationsHostedTests` (a table, cards and a list on screen) and the New tests above. The calendar view was not on main yet: its check joins that test when it lands.
- [x] Copy Embed Link in a base's View Options copies `![[Path.base#View]]`. Test of the written line.
  Done 2026-11-26: `BaseNoteMenuEntries` in View Options, the line from `BaseEmbedLink.text`. Test: `BaseEmbedLinkTests.testTheEmbedNamesTheBaseByItsPathAndTheView`.
- [x] The course starter's resource files, and the code that writes the missing ones without overwriting any. Tests of the files made and of a second run that changes nothing.
  Done 2026-11-26: `Resources/CourseStarter` (`Courses.base`, `Assignments.base`, `Lectures.base`, `Course.md`), `CourseStarter`, `CourseStarterResources`, `WorkspaceModel.createCourse`, with types declared only where the vault has none. Tests: `WorkspaceCourseStarterTests` (2: the files, the page, a second course that changes no starter file, every base read without a problem).
- [x] New Course… in the sidebar's New menus and the command list, making the starter where missing and then a course page.
  Done 2026-11-26: `CreationKind.course` in the New menu, the sidebar's and a folder's menus, and `GraphiteCommand.newCourse` (`graphite:new-course`, Bases: Create new course) in the command palette. Tests: `CreatableItemTests`, `WorkspaceCommandIdentifiersTests`.
- [x] A rendered or hosted check of a course page: its two embedded views show only that course's assignments and lectures, and `Courses.base` shows the rollups.
  Done 2026-11-26: `BaseRelationsHostedTests.testACoursePageShowsItsOwnAssignmentsInEveryViewAndTheCoursesShowTheirRollups` on the iPad simulator, and the course page drawn in the running Mac app.
- [x] Checked on an iPad simulator and in a Mac Debug copy with a demo vault: a course made, an assignment added from its page, marked done, and the percent done in `Courses.base` changed.
  Done 2026-11-26: an iPad Pro 11-inch (M5) simulator of its own, iOS 27.2, a Debug build: New › Course made Digital Design with the starter, an assignment was added from its page, set done on disk, and Percent done went to 100. The Mac: in the running Mac app (Debug, unsigned, bundle `com.graphite.study.repro`), `MacCourseDashboardInAppHostedTests` with `TEST_RUNNER_GRAPHITE_MAC_COURSES`, its pictures looked at, the same steps through the workspace and the model.
- [x] `Docs/Architecture.md` and `Docs/Coverage.md` describe what was built and how it was checked.
  Done 2026-11-26: `Docs/Architecture.md` (Markdown views, Relations, rollups and new notes in Bases) and `Docs/Coverage.md` (2026-11-26 entry).
