---
tags:
  - guide/markdown
---
# Pictures and embeds

An `!` in front of a link shows the file itself inside your note: a picture, a PDF page, another note, a part of a note, or a base. It is the original, not a copy, so a change to it shows everywhere it is embedded.

## A picture

**Copy this**

```markdown
![[Mushroom risotto.png]]
```

![[Mushroom risotto.png]]

## A picture at a size

**Copy this**

```markdown
![[Lemon cake.png|240]]
```

![[Lemon cake.png|240]]

A number after `|` is the width. `|240x160` gives a width and a height.

## Side by side

**Copy this**

```markdown
![[Tomato soup.png|150]] ![[Pancakes.png|150]] ![[Lemon cake.png|150]]
```

![[Tomato soup.png|150]] ![[Pancakes.png|150]] ![[Lemon cake.png|150]]

Tap a picture to zoom into it; its menu has **Open in New Tab**.

## Adding a picture

- **On iPad and iPhone**, the **Attach** menu above the keyboard has **Take Photo**, **Photo Library**, **Choose File**, **Scan Document** and **New Notebook**.
- **On the Mac**, **Insert** › **Attachment…** in the note's toolbar.
- Everywhere, paste a picture or drop a file onto the note.

Graphite saves the file in the attachments folder and writes the embed where the cursor is.

## Another note, or part of one

**Copy this**

```markdown
![[Tomato soup#Ingredients]]
```

**What you see**

![[Tomato soup#Ingredients]]

`![[Tomato soup]]` would show the whole note. `#Ingredients` shows only that section. Tick a box in it, and it is ticked in the recipe itself.

## A page of a PDF

```markdown
![[Week 1 slides.pdf#page=3&height=340]]
```

![[Week 1 slides.pdf#page=3&height=340]]

## A base

```markdown
![[Recipes.base]]
```

![[Recipes.base]]

More on bases in [[Bases]].
