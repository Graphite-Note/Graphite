---
tags:
  - guide/markdown
---
# Web pages in notes

A web page can sit inside a note, in a frame. It is HTML's `<iframe>`, which Obsidian understands too.

**Copy this**

```html
<iframe src="https://en.wikipedia.org/wiki/Lisbon" width="100%" height="320" title="Lisbon"></iframe>
```

**What you see**

<iframe src="https://en.wikipedia.org/wiki/Lisbon" width="100%" height="320" title="Lisbon"></iframe>

The page scrolls inside its frame, and the note around it scrolls as usual. Pages load only when you have a connection. A frame's menu has **Open in Browser** and **Copy Address**.

A plain link opens the page in your browser instead: [Lisbon on Wikipedia](https://en.wikipedia.org/wiki/Lisbon).
