# Pen colours arranged by dragging, as in Apple's markup: implementation TODO

Created: 2026-11-13.

Status: planned. Issue: [#178](https://github.com/Graphite-Note/Graphite/issues/178).

## Request

The owner, 2026-11-13, with a screen recording of Apple's markup palette: "see how nice the UX is here... that is what we should do not the hold and move left situation we have" (on the iPad). Today a pen colour of Graphite's bar is moved by holding it and choosing Move Left or Move Right in its menu, one place at a time (`PencilColorButtons.editingMenu`).

In the recording, Apple's palette is a row of colour circles that scrolls sideways when it holds more than fit, with a dashed "+" at its end:

- a tap chooses a colour; the chosen one shows a small chevron, and a second tap on it opens the colour picker ("Pen Color") to change that colour;
- dragging a colour lifts it under the finger or pointer and the others slide aside to show where it will land; letting go puts it there; dragging near the row's end scrolls the row;
- "+" adds a colour, which then appears in the row.

## 1. Drag to arrange the pen colours

Issue: [#178](https://github.com/Graphite-Note/Graphite/issues/178)

- [ ] On the iPad (finger, Apple Pencil and pointer), a colour of the bar's row is dragged to a new place directly: it lifts, follows the finger along the row, the other colours slide aside to make its place, and letting go stores the new order where Settings › Colors keeps it. A drag that starts sideways arranges; a tap still chooses; the row scrolls when the drag nears an end. The same for the highlighter's colours. Move Left and Move Right leave the menu (VoiceOver gets the same moves as actions).
- [ ] A second tap on the chosen colour opens the colour picker for that colour, as Apple's does; "+" adds the colour in use at the end, as today.
- [ ] Dragging a colour off the row (upwards, out of the bar) removes it, with the row closing up, and Undo or a menu item brings it back; Remove stays in the colour's menu.
- [ ] Smooth: the drag follows at the display's rate with no layout of the rest of the bar, and nothing is stored until the drag ends.
- [ ] Tests: the order logic for every drop place (first, last, past either end, on itself), hosted tests that a synthesized drag reorders and a tap still chooses, and a screen recording in the iPad simulator looked at frame by frame.
- [ ] Checked on the iPad with a finger and the Pencil, and on the Mac with the pointer where the bar shows.
