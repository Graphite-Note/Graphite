---
tags:
  - guide/handwriting
---
# Drawings in notes

A drawing lives inside a note, between the paragraphs, exactly where you put it. It is saved as an ordinary picture, so every app can show it, and Graphite keeps your strokes inside the file so you can change it later.

Here is one, from the example course:

![[Circuit drawing.png|480]]

In the note it is just one line:

```markdown
![[Circuit drawing.png|480]]
```

The `|480` is its width on the page. Without it, the drawing is as wide as the note.

This is how the lecture note that holds it looks on iPad, with the drawing's **Edit** button, and on the Mac in the dark appearance:

![[iPad - A drawing in a note.jpg|420]] ![[Mac - A drawing in a note, dark.jpg|560]]

## Draw one

1. While writing, put the cursor where the drawing should go.
2. Tap **Draw**, in the toolbar or in the bar above the keyboard. With Apple Pencil you can also double-tap or squeeze it (Settings › Pencil Drawings › **Double-Tap or Squeeze to Draw in Notes**).
3. Draw. The canvas is as wide as the note and grows downward as you write.
4. Tap **Insert**. Graphite saves the drawing in the attachments folder and embeds it where the cursor was. **Cancel** leaves the note as it was.

## Change it later

Tap the drawing's **Edit** button. The canvas opens with every stroke as you left it. On a photo or any other picture, **Draw on Image** draws over it.

The canvas's **Drawing Options** menu has **Paper** (to draw on lines or squares), **Add Image**, **Draw with Finger** and **Export a Copy**.

## Which file format

Settings › Pencil Drawings › **Save Drawings As**:

| Format | Good for |
| --- | --- |
| **PNG** (the default) | keeps every brush, including pencil grain and watercolour, exactly as drawn |
| **PDF** | sharp at any size, small files |
| **SVG** | sharp at any size, and opens in a web browser |

Each opens in Graphite for editing stroke by stroke. Obsidian, Preview or a browser simply sees a picture.

> [!tip] On iPhone
> Without a Pencil, turn on **Draw with Finger** in **Drawing Options**.

Next: [[Pencil tools]].
