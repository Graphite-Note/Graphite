---
tags:
  - guide/connecting
---
# Bases

A base shows notes as a table, cards, a list, a board or a map, built from their [[Tags and properties|properties]]. It is a small `.base` file that Obsidian opens too. The examples have three:

| Base | Shows | Views |
| --- | --- | --- |
| [[Recipes.base]] | the recipes | cards with a picture of each dish, and a table sorted by time |
| [[Restaurants.base]] | the restaurants | a map, and a table sorted by rating |
| [[Reading list.base]] | the books | covers, a table grouped by status, and a list |

![[iPad - Recipes gallery.jpg|380]] ![[iPad - Reading list.jpg|380]]

*The recipes as a gallery, and the reading list's covers in the dark, on iPad.*

![[Mac - Recipes gallery, dark.jpg|620]]

*The same gallery on the Mac, in the dark appearance.*

## A base inside a note

**Copy this**

```markdown
![[Reading list.base]]
```

**What you see**

![[Reading list.base]]

`![[Restaurants.base#Map]]` shows only the view called *Map*.

## Make one

1. Choose **New** › **Base** (on the Mac, the menu of the **New Note** button › **New Base**) and name it. It starts as a table of your notes.
2. **View Options** › **Edit View…** chooses the **Layout** (Table, Cards, List, Kanban or Map), which properties show, the **Sort**, **Group By** and **Filters for This View**.
3. **New View** adds another view of the same notes; the view's name at the top switches between them.

## A gallery

Give each note a `cover` property naming a picture, choose the **Cards** layout, and set **Cover Image** to that property. The recipes do it:

```markdown
---
cover: "[[Tomato soup.png]]"
---
```

## A filter

A filter keeps only some notes. The recipes base keeps the notes tagged *recipe* in the recipes folder, so the *Recipe* template, which has the tag too, stays out:

```yaml
filters:
  and:
    - file.hasTag("recipe")
    - file.inFolder("6 Everyday examples/Recipes")
```

Next: [[Graph and map]].
