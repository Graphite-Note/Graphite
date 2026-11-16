---
tags:
  - guide/connecting
---
# Graph and map

## The graph

The graph draws every note as a dot and every link as a line. Notes that link to each other gather together, so the shape of your vault appears: here, the recipes around their restaurants, the course around its lectures, the trip in the middle.

- **Open it**: the **graph** button at the top of the file list (on iPad beside the panels' buttons, on the Mac above the file list), View › **Graph View** on the Mac, or ⇧⌘G.
- **Open a note from it**: tap (or click) a dot. The note opens beside the graph, which stays open.
- **One note's neighbours**: the right sidebar's **Graph** panel (⌥⌘G) shows only the open note and what it links to.
- **Only some notes**: touch and hold a tag in the **Tags** panel or a folder in the file list (right-click on the Mac) › **Show in Graph**. The filter at the top of the graph takes `tag:#name` and `path:` too.
- **Colours**: the graph's **settings** › **New Group**, with a search such as `path:"6 Everyday examples/Recipes"`, gives those notes a colour.

Tags are dots too, in green. Tap one to bring its notes forward; the **#** button hides them.

## The map

A note with a `coordinates` property is a place on the map:

**Copy this**

```markdown
---
coordinates:
  - "38.7114"
  - "-9.1305"
---
```

The restaurants of the examples have one. Their base has a map view:

![[iPad - Restaurants map.jpg|380]] ![[iPhone - Restaurants map.jpg|190]]

*The restaurants' map on iPad and iPhone: each marker is a note.*

The live map, drawn from the notes as they are now:

![[Restaurants.base#Map]]

- On iPad and iPhone, run **Map view: Open map view** in the Command Palette; on the Mac, View › **Map View**.
- The right sidebar's **Map** panel shows the open note's places.
- The map can centre on where you are, once you allow it.

Next: [[Canvas]].
