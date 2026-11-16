---
tags:
  - guide/markdown
---
# Footnotes and comments

## Footnotes

**Copy this**

```markdown
Risotto wants a short-grain rice.[^rice] Stir it often.^[But not all the time.]

[^rice]: Arborio or Carnaroli both work.
```

**What you see**

Risotto wants a short-grain rice.[^rice] Stir it often.^[But not all the time.]

[^rice]: Arborio or Carnaroli both work.

The footnotes are listed at the end of the note when you read it. The **Footnotes** panel in the right sidebar lists them too.

## Comments only you see

**Copy this**

```markdown
The sauce needs more garlic. %%Sam disagrees.%%
```

**What you see**

The sauce needs more garlic. %%Sam disagrees.%%

Text between `%%` is hidden when the note is read and when it is exported to PDF. It is still in the file, so it is a place for reminders, not secrets. ⌘/ turns the selected text into a comment.
