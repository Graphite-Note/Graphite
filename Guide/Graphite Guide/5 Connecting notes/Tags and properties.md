---
tags:
  - guide/connecting
---
# Tags and properties

## Tags

A tag is a word after `#`. Put it anywhere in a note:

**Copy this**

```markdown
Quick to make on a weeknight. #quick #vegetarian
```

**What you see**

Quick to make on a weeknight. #quick #vegetarian

Tap a tag to search for every note that has it. Tags can be nested, as in `#recipe/dessert`. The left sidebar's **Tags** panel lists every tag with how many notes have it.

## Properties

Properties are facts about a note, written between two `---` lines at the very top:

**Copy this**

```markdown
---
cuisine: Portuguese
rating: 5
visited: 2026-10-04
tags:
  - restaurant
---
```

Once a note has them, Graphite shows them as a panel at the top of the note, where you can change them without touching the text. **Add Property** adds one; a property's menu has **Change Type** and **Remove Property**. Look at the top of [[Blue Tile Tasca]] to see a panel.

A property has a type, which decides how it is shown and edited:

| Type | Example |
| --- | --- |
| Text | `cuisine: Portuguese` |
| Number | `rating: 5` |
| Checkbox | `booked: true` |
| Date | `visited: 2026-10-04` |
| List | `tags: [restaurant, lisbon]` |
| A link | `recipe: "[[Tomato soup]]"` |

The left sidebar's **Properties** panel lists every property in the vault. Search finds notes by property: `[cuisine:Portuguese]`.

## Why bother

Properties are what [[Bases]] read to build tables, cards and maps, and what the map reads to place a note (see [[Graph and map]]). A recipe with `minutes: 25` can be sorted by how quick it is.

Next: [[Bases]].
