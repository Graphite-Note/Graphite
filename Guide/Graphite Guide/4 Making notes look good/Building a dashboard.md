---
icon: 🧱
banner: "[[Cover - Signals and Sound.png]]"
---
# Building a dashboard

A dashboard is a note that opens a part of your vault: a cover, an icon, a few words, then columns of links, a table that fills itself, and the rest folded away until you need it. Notion made pages like this popular. In Graphite they are ordinary Markdown, so the same file opens in Obsidian and in any text editor.

This note builds [[Signals and Sound]], the example course's page, in eight steps. Each step shows what to type in a grey box (**Copy this**), then what Graphite draws from it (**What you see**). Open the finished page beside this one with **Split Right** ([[Library and list]]) to compare.

The guide has three finished dashboards to take apart: [[Signals and Sound]] (a course), [[Solar Boat Team]] (a team's wiki) and [[Balcony Garden]] (a project at home).

> [!tip] 💡
> The cover, the large icon and the icons before links are drawn in the **reading view**: tap the **pencil** button at the top right (on the Mac, ⌘E). Live Preview, where you write, shows the columns, colours and callouts, and lists the cover and icon as properties.

## 1. A cover and an icon

Both are [[Tags and properties|properties]] at the top of the note. `banner` names a picture of your vault; `icon` is an emoji.

**Copy this**

```markdown
---
icon: 🎧
banner: "[[Cover - Signals and Sound.png]]"
---
```

**What you see**

This note has a cover and an icon of its own: look at its top, in the reading view. The cover runs across the page, and the icon sits over its lower left. The button at the cover's right folds it to a thin strip.

- **More** › **Icon…** sets the icon for you, with an emoji field and 64 symbols.
- An icon can also be a picture of your vault: `icon: "[[Solar boat.svg]]"`, as [[Solar Boat Team]] has.
- Any picture makes a cover: a photo, a screenshot, a gradient. Wide pictures work best, since the cover is cut to the width of the window.
- On iPhone covers are off, to keep the screen for the note: Settings › Appearance › **Covers on iPhone** turns them on.

## 2. A quote and a callout

A line or two under the title says what the page is for. A callout with only an emoji on its first line looks like a Notion callout: the emoji, then your text.

**Copy this**

```markdown
> Every sound you hear is a signal: a number that changes with time.

> [!tip] 💡
> Lectures on Mondays at 10:15 in room B2, labs on Thursday afternoons.
```

**What you see**

> Every sound you hear is a signal: a number that changes with time.

> [!tip] 💡
> Lectures on Mondays at 10:15 in room B2, labs on Thursday afternoons.

Any callout type works: `[!info]`, `[!warning]`, `[!note]` and the others in [[Quotes and callouts]] each have their own colour. Without an emoji, `no-title` after a `|` draws the type's own icon before the text instead of a title row:

**Copy this**

```markdown
> [!info|no-title]
> Copy the formula sheet onto your one page for the exam.
```

**What you see**

> [!info|no-title]
> Copy the formula sheet onto your one page for the exam.

## 3. Columns

A `[!multi-column]` callout puts the blocks inside it side by side. Each column is a `[!blank]` callout, nested with a second `>`, and an empty `>` line separates the columns.

**Copy this**

```markdown
> [!multi-column]
> > [!blank]
> > Lectures go here.
>
> > [!blank]
> > Labs go here.
>
> > [!blank]
> > The exam goes here.
```

**What you see**

> [!multi-column]
> > [!blank]
> > Lectures go here.
>
> > [!blank]
> > Labs go here.
>
> > [!blank]
> > The exam goes here.

Each column is at least 200 points wide. When the window is narrower than that, on iPhone or in a split, the columns stack one under the other.

To make a column wider than the others, write `wide-2` to `wide-5` after a `|`: `> > [!blank|wide-2]` takes twice the room. [[Solar Boat Team]] uses it for its list of divisions.

## 4. Lists of links, with their icons

Put each link on a line of its own, and end each line but the last with two spaces. The notes linked have an `icon` property, and the reading view draws that icon before each link, as Notion does for its pages.

**Copy this**

```markdown
[[Week 1 - Sampling]]  
[[Week 2 - Frequencies]]  
[[Week 3 - Filters]]
```

**What you see**

[[Week 1 - Sampling]]  
[[Week 2 - Frequencies]]  
[[Week 3 - Filters]]

In a list where some notes have no icon, those get a small grey page instead, so the names still line up. A name too long for its column ends in "…" rather than wrapping.

> [!note] 📝
> The two spaces are a line break that every Markdown app keeps; without them some apps join the lines into one. The Notion importer writes them too. Links with an empty line between them make the same compact list in Graphite.

## 5. Colours

Coloured headings tell the columns apart at a glance. `~={#hex}` and `=~` around words colour them.

**Copy this**

```markdown
> [!multi-column]
> > [!blank]
> > ## ~={#D44C47}Lectures=~
> > [[Week 1 - Sampling]]  
> > [[Week 2 - Frequencies]]
>
> > [!blank]
> > ## ~={#337EA9}Labs=~
> > [[Lab 1 - Recording a tone]]  
> > [[Lab 2 - An echo]]
```

**What you see**

> [!multi-column]
> > [!blank]
> > ## ~={#D44C47}Lectures=~
> > [[Week 1 - Sampling]]  
> > [[Week 2 - Frequencies]]
>
> > [!blank]
> > ## ~={#337EA9}Labs=~
> > [[Lab 1 - Recording a tone]]  
> > [[Lab 2 - An echo]]

Notion's own text colours, to copy:

| Colour | Code | Colour | Code |
| --- | --- | --- | --- |
| ~={#D44C47}Red=~ | `#D44C47` | ~={#337EA9}Blue=~ | `#337EA9` |
| ~={#D9730D}Orange=~ | `#D9730D` | ~={#9065B0}Purple=~ | `#9065B0` |
| ~={#CB912F}Yellow=~ | `#CB912F` | ~={#C14C8A}Pink=~ | `#C14C8A` |
| ~={#448361}Green=~ | `#448361` | ~={#9F6B53}Brown=~ | `#9F6B53` |

Graphite darkens a colour on a light page and lightens it on a dark one just enough to stay readable, so the same note works in both appearances. Select words and choose **Format** › **Color** to write the code for you; `==words==` highlights instead. More in [[Headings and text]].

## 6. A table that fills itself

A base shows notes as a table or as cards, from their properties. Each problem set of the course is a note with `due`, `status` and `points`:

**Copy this**

```markdown
---
icon: 📝
due: 2026-10-05
status: done
points: 18
tags:
  - problem-set
---
```

The base [[Problem sets.base]] keeps the notes with that tag and sorts them by date. Put it in the dashboard with `!`:

**Copy this**

```markdown
## ~={#9065B0}Problem sets=~

![[Problem sets.base#Due next]]
```

**What you see**

## ~={#9065B0}Problem sets=~

![[Problem sets.base#Due next]]

Add a problem set, and the table has a new row; change a `status`, and the row changes. `#Due next` picks the view of that name; leave it out for the base's first view. [[Bases]] shows how to make one, and [[Balcony Garden]] shows its plants as a board, one column per stage.

## 7. Folds, for what is not needed every day

A `-` after a callout's type starts it folded, like Notion's toggles. Tap its title to open it.

**Copy this**

```markdown
> [!faq]- How is the course graded?
> Problem sets 30 %, labs 20 %, the written exam 50 %.
```

**What you see**

> [!faq]- How is the course graded?
> Problem sets 30 %, labs 20 %, the written exam 50 %.

Headings fold too: the arrow beside a heading hides everything under it, down to the next heading of the same size.

## 8. A formula and a checklist

Both are ordinary Markdown, and both work inside columns as well.

**Copy this**

```markdown
$$
f_s > 2 f_{\max}
$$

- [x] Hand in problem set 1
- [ ] Finish problem set 3
```

**What you see**

$$
f_s > 2 f_{\max}
$$

- [x] Hand in problem set 1
- [ ] Finish problem set 3

[[Math]] and [[Lists and tasks]] show more.

## Your own

1. Make a folder for the subject, and a note in it with the folder's name: that note is the dashboard.
2. Give it a cover and an icon (step 1), a line and a callout (step 2).
3. Write the notes it will link to, each with its own `icon` (**More** › **Icon…**).
4. Lay out the links in columns with coloured headings (steps 3 to 5).
5. Add a base for anything with a date or a status (step 6), and fold what is rarely read (step 7).

To see a finished page as plain text, open it and choose **More** › **View** › **Source Mode**.

> [!info] 📥
> Coming from Notion? **Import from Notion…** writes exactly this Markdown: covers, icons, columns, link lists with icons, coloured text, callouts and databases as bases. An imported Notion page and a dashboard built by hand are the same kind of note. See [[Moving in from Notion]].
