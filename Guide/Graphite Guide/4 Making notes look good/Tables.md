---
tags:
  - guide/markdown
---
# Tables

Tables are edited in place: tap a cell and type, as in a spreadsheet.

**Copy this**

```markdown
| Dish | Minutes | Serves |
| --- | ---: | :---: |
| [[Tomato soup]] | 40 | 4 |
| [[Pancakes]] | 25 | 2 |
| [[Lemon cake]] | 60 | 8 |
```

**What you see**

| Dish | Minutes | Serves |
| --- | ---: | :---: |
| [[Tomato soup]] | 40 | 4 |
| [[Pancakes]] | 25 | 2 |
| [[Lemon cake]] | 60 | 8 |

The second line sets each column's alignment: `---:` to the right, `:---:` in the middle.

## Make and change one

1. Choose **Format** › **Table** (on iPad and iPhone in the note's **More** menu), or run **Insert table** in the Command Palette.
2. Tap a cell to type in it. With a keyboard, Tab and ⇧Tab move between cells.
3. Touch and hold a cell (on the Mac, right-click it) for **Row** and **Column**: add, move, align or delete them.
4. **Edit Source** shows the table's Markdown.

## What fits in a cell

Links, **bold**, `code`, math such as $V = IR$, and small pictures:

| Picture | Formula | Note |
| --- | --- | --- |
| ![[Tomato soup.png\|80]] | $P = V \times I$ | inside a table, the `\|` of a picture's size is written with a backslash: `\|80` |

A wide table scrolls sideways rather than squeezing its columns.

## On iPad, while writing

![[iPad - Tables.jpg|420]]
