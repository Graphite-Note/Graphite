# Suggestions for properties and tags in notes: implementation TODO

Created: 2026-11-12.

Status: not started. Issues: [#167](https://github.com/Graphite-Note/Graphite/issues/167) (section 1), [#168](https://github.com/Graphite-Note/Graphite/issues/168) (section 2), [#169](https://github.com/Graphite-Note/Graphite/issues/169) (section 3).

## Request

The owner, 2026-11-12: "auto complete for properties tags etc in notes". While a property's name, a property's value or a tag is being typed in a note, Graphite suggests the ones the vault already uses, as Obsidian does in its Properties view and in the frontmatter, so a note gets `course: VLSI 3` and `tags: [eth/vlsi]` spelled exactly as in the other notes instead of a near-duplicate.

## What exists today (2026-11-12)

- In a note's body, typing `[[` suggests notes, headings and blocks, and typing `#` suggests the vault's tags (`LinkCompletion.context` in `Sources/GraphiteCore/LinkCompletion.swift`, `CompletionModel` and its popup in `Sources/GraphiteUI/EditorCompletion.swift`, tags from `VaultIndex.tags(matching:limit:)`).
- The Properties panel above a note (`Sources/GraphiteUI/PropertiesPanel.swift`) edits names, text, numbers, dates and list items in plain `TextField`s: nothing is suggested, so a new property's name, a list item of `tags` or `aliases`, and a text value are typed in full.
- The frontmatter written as text (Source mode, or the YAML block in Live Preview) gets no suggestions: a tag under `tags:` has no `#`, so the body's tag suggestions never start there, and a property's name or value has no trigger at all.
- The Bases property editor sheet (`Sources/GraphiteUI/BasePropertyEditorSheet.swift`) edits values in plain fields too.
- The index already knows the vault's property names, with their types and how many notes use each (`VaultIndex.propertyUsages`, shown in the sidebar's Properties view, `Sources/GraphiteUI/WorkspaceTagsAndProperties.swift`), and the tags with their counts. It has no query for the values one property takes across the vault.

## Decisions

- One completion popup for all of it: the body's existing `CompletionModel` popup in the text editor, and the same rows (title with the matched letters highlighted, a count as subtitle, keyboard selection, Return or Tab to accept, Escape to close) in a menu under the Properties panel's fields. No second look for suggestions.
- Suggestions come from the index only, never by reading notes while typing; an unindexed vault simply shows none.

## 1. Property names and values in the Properties panel

Issue: [#167](https://github.com/Graphite-Note/Graphite/issues/167)

- [ ] Typing a new property's name suggests the vault's property names that contain the typed text, most used first, each with its type's icon and how many notes use it; choosing one gives the new property that name and its type (a `date` property gets the date field, a list property the list field). A name the note already has is not offered.
- [ ] Typing a list item of `tags` suggests the vault's tags (without `#`), nested tags included, most used first; a tag the note already lists is not offered. Accepting adds it as a list item and leaves the field ready for the next one.
- [ ] Typing a value of any other text or list property suggests the values that property already takes in the vault (`course` suggests `VLSI 3`, `Computer Architecture`), most used first. Needs an index query for one property's values with their counts, bounded (top values only, from the index's property table).
- [ ] `aliases` and properties whose values are links: typing `[[` in the field suggests notes as in the body, and accepting writes `"[[Note]]"` as Obsidian does.
- [ ] Keyboard on the Mac and the iPad's keyboard: arrows move through the suggestions, Return or Tab accepts, Escape closes them without leaving the field. On touch, a tap on a suggestion accepts it.
- [ ] Answers within one frame of a keystroke in the owner's 32,843-file vault on the iPad (a timing budget in `App/Tests/TimingBudgets.swift`).
- [ ] Tests: index tests of the value query (counts, limit, list and text values, accents); UI or hosted tests that a new property's name is suggested with its type, that a `tags` item suggests a vault tag and skips one the note has, and that accepting writes the frontmatter once.
- [ ] Checked on the Mac and the iPad with the owner's vault.

## 2. Property names, values and tags in the frontmatter as text

Issue: [#168](https://github.com/Graphite-Note/Graphite/issues/168)

- [ ] In the frontmatter block of the text editor (Source mode, and Live Preview when the YAML is shown), the cursor at the start of a line, typing a name, suggests the vault's property names; accepting writes `name: `.
- [ ] After `tags:` (inline `tags: [a, b]` or as `- ` items under it), typing suggests the vault's tags without `#`; after any other `name:` or under it as `- ` items, typing suggests that property's values from the vault (the query of section 1).
- [ ] A new `CompletionContext` case for the frontmatter, found by `LinkCompletion.context` only inside the block `FrontmatterLocator` finds, so the body's `[[` and `#` suggestions are unchanged and nothing is looked up outside the frontmatter. `[[` inside a frontmatter value still suggests notes.
- [ ] Tests: Core tests of the context (name at line start, value after `name: `, list items, inline lists, quoted values, the cursor just after the closing `---`, which is body); a hosted test that typing under `tags:` shows a vault tag and accepting writes it.
- [ ] Checked on the Mac and the iPad with the owner's vault, in Source mode and Live Preview.

## 3. Other places that take a property or a tag

Issue: [#169](https://github.com/Graphite-Note/Graphite/issues/169)

- [ ] The Bases property editor sheet suggests the edited property's values, and tags for `tags`, as section 1 does.
- [ ] The sidebar's search field suggests tags after `tag:` and property names after `[`, then that property's values after `[name:`, beside the operators it already suggests.
- [ ] Tests: a test per place that a vault tag or value is suggested and accepting writes it.
- [ ] Checked on the Mac and the iPad.
