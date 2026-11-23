---
tags:
  - guide/handwriting
---
# Writing on slides

Lecture slides, papers, handouts and forms are PDFs, and Graphite writes on them directly. Your marks are saved inside the PDF as standard annotations, so Preview, Acrobat and Obsidian show them.

Try it on the example course's slides: open [[Week 1 slides.pdf]] and tap the **pencil** button at the top right.

![[iPad - Slides.jpg|460]]

*The slides open for writing on iPad, with the Pencil tools in the fixed bar.*

## Write and highlight

1. Open a PDF. Bring one in with **New** › **Import**, or put it in the vault's folder with the Files app.
2. Tap the **pencil** button to show the [[Pencil tools]]. To write with a finger, choose **More** › **Draw with Finger**.
3. Select text to **Highlight** it (pick a colour), **Underline** it, **Strikethrough** it, **Copy as Quote**, or quote it in a note.
4. With the **Text Box** tool, tap the page and type. A box can be moved, resized, turned, and given a font, size, colour, fill and border.

## A slide inside a note

A note can show one page of a PDF, at the height you choose. The page scrolls and zooms inside the note, and **Annotate** writes on it without leaving the note:

```markdown
![[Week 1 slides.pdf#page=2&height=380]]
```

![[Week 1 slides.pdf#page=2&height=380]]

In the example course's lecture note, on iPad and on the Mac:

![[iPad - A slide in a lecture note.jpg|380]] ![[Mac - A slide in a lecture note.jpg|560]]

A plain link to a page opens the PDF there, and when the PDF is open on the other side of a split, follows it on that side so your note stays where it is:

```markdown
[[Week 1 slides.pdf#page=4|the slide on capacitors]]
```

Here it is: [[Week 1 slides.pdf#page=4|the slide on capacitors]].

## Put a section of a note on a page

Rather than copy part of your notes onto a slide, link it there. Drag a heading of a note onto a page of a PDF: the page shows a picture of that section, as the reading view draws it, and the picture is a link back to it.

1. Open the note and the PDF side by side, or one above the other with **Split Down** (see [[Library and list#Tabs and splits]]).
2. Drag the heading onto the page. In the **reading view**, touch and hold the heading, then drag it. While **writing**, select the heading's text, touch and hold the selection, and drag it. Text dragged from a paragraph or a list item links just that block, which gets a block ID, as Obsidian's *Copy link to block* gives one. A note dragged from the file list links the whole note.
3. Let go where the picture should be. It lands there, selected, so you can move or resize it at once, like any picture on a page; **Undo** takes it off again.

To go to the section, tap the picture, then **Open** (the arrow out of a square) at the start of its bar: the section opens on the other side of the split, at its heading, and the PDF stays where it is.

![[iPad - A section link on a slide.jpg|460]]

*Split Down on iPad: the Power section of the Week 1 lecture note dragged onto the first slide, and **Open** in the picture's bar has brought the note below to it.*

The picture keeps up with the note. Change the section and the page shows the new version the next time it comes into view; the PDF is saved with it, so other apps show the new version too. Rename or move the note, with **Automatically Update Internal Links** on, and the link follows it. A renamed heading is not followed, as in Obsidian: the picture then says the section can't be found.

The link is a standard PDF link to Obsidian's address of the section, `obsidian://open?vault=…&file=…`, naming the vault, the note and the heading, and the picture is drawn into the page, so Preview and other PDF apps show it.

## Copy a link to a page

In a PDF, **More** › **Copy Link to This Page** gives a link like the one above, ready to paste into your notes.

Next: [[Recording a lecture]].
