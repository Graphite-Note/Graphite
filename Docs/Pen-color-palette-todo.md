# Pen colours arranged by dragging, as in Apple's markup: implementation TODO

Created: 2026-11-13.

Status: built and tested in the simulator 2026-11-13; the check on the owner's iPad is open. Issue: [#178](https://github.com/Graphite-Note/Graphite/issues/178).

## Request

The owner, 2026-11-13, with a screen recording of Apple's markup palette: "see how nice the UX is here... that is what we should do not the hold and move left situation we have" (on the iPad). Today a pen colour of Graphite's bar is moved by holding it and choosing Move Left or Move Right in its menu, one place at a time (`PencilColorButtons.editingMenu`).

In the recording, Apple's palette is a row of colour circles that scrolls sideways when it holds more than fit, with a dashed "+" at its end:

- a tap chooses a colour; the chosen one shows a small chevron, and a second tap on it opens the colour picker ("Pen Color") to change that colour;
- dragging a colour lifts it under the finger or pointer and the others slide aside to show where it will land; letting go puts it there; dragging near the row's end scrolls the row;
- "+" adds a colour, which then appears in the row.

## 1. Drag to arrange the pen colours

Issue: [#178](https://github.com/Graphite-Note/Graphite/issues/178)

- [x] On the iPad (finger, Apple Pencil and pointer), a colour of the bar's row is dragged to a new place directly: it lifts, follows the finger along the row, the other colours slide aside to make its place, and letting go stores the new order where Settings › Colors keeps it. A drag that starts sideways arranges; a tap still chooses; the row scrolls when the drag nears an end. The same for the highlighter's colours. Move Left and Move Right leave the menu (VoiceOver gets the same moves as actions).
  Done 2026-11-13: `PencilColorSwatchRow` draws black (fixed, first) and the favorite or highlighter colours; one clear UIKit view over the row (`PencilColorRowTouchView`, `PencilColorTouchRecognizers.swift`) takes the tap, the drag (a pan on the bar; a 0.25 s hold in the scrolling strip, where a sideways drag scrolls) and the long-press menu, so finger, Pencil and pointer all reach it. The lifted colour grows and follows; the others slide by offsets from `PencilColorArrangement` (pure: landing place, slide offsets, removal, scroll direction); letting go stores the order once through `FavoriteColorEditing.moving(_:toIndex:in:)` under the key Settings › Colors reads. The strip scrolls under a drag held near either end (`PencilColorRowAutoscroller`, `PencilColorStrip` with `ScrollPosition`). Move Left and Move Right left the menu and are VoiceOver actions of each colour. Tests: `PencilColorArrangementTests` (7), hosted `PencilColorDragHostedTests.testAFingerDraggedAlongTheRowPutsTheColorWhereItLetGo`. Not checked: the strip's hold-then-drag and its autoscroll on screen, a pointer's drag.
- [x] A second tap on the chosen colour opens the colour picker for that colour, as Apple's does; "+" adds the colour in use at the end, as today.
  Done 2026-11-13: a tap on the colour in use opens `UIColorPickerViewController` ("Pen Color" or "Highlighter Color") in a popover pointing at it (`PencilColorPickerPresenter`); a pick changes the ink as it moves and, when it ends, that favourite's hex (`FavoriteColorEditing.changingHex`, not to another colour's hex); black's picker changes only the ink. "+" is unchanged. Tests: `PencilColorArrangementTests.testThePickerChangesTheColorsHexUnlessAnotherColorHasIt`, hosted `testASecondTapOnTheChosenColorOpensItsColorPicker`.
- [x] Dragging a colour off the row (upwards, out of the bar) removes it, with the row closing up, and Undo or a menu item brings it back; Remove stays in the colour's menu.
  Done 2026-11-13: a drag more than the row's height up or down removes the colour (it fades while it would), the later colours close up, and for six seconds an Undo glyph after the last colour and "Put Back <name>" in every colour's menu bring it back at its place (`PencilColorRemovalUndo`, `FavoriteColorEditing.puttingBack`); Remove stays in the menu. Down as well as up, since the bar can stand at the top of the screen. Tests: `testADragFarAcrossTheRowRemovesAndTheLaterColorsCloseUp`, `testARemovedColorIsPutBackAtItsPlaceOnce`, hosted `testADragOffTheRowRemovesTheColorAndUndoPutsItBack`.
- [x] Smooth: the drag follows at the display's rate with no layout of the rest of the bar, and nothing is stored until the drag ends.
  Done 2026-11-13: the drag is state of the row's own view and moves colours by offsets and scale only, so nothing else of the bar is laid out; the order is written once, when the finger lifts. Hosted `testATapStillChoosesAndADragStoresNothingUntilItEnds` holds a drag over a new place and finds nothing stored until the lift. Frame rate on a device not measured.
- [x] Tests: the order logic for every drop place (first, last, past either end, on itself), hosted tests that a synthesized drag reorders and a tap still chooses, and a screen recording in the iPad simulator looked at frame by frame.
  Done 2026-11-13: `PencilColorArrangementTests` (every drop place: first, last, past either end, on itself; slides; removal; scroll edges); `PencilColorDragHostedTests` (4, synthesized touches through UIKit: a drag reorders, a tap chooses, nothing stored before the lift, a drag off removes and Undo restores, a second tap opens the picker); a simulator recording of those tests looked at frame by frame: the lifted colour follows, orange then green slide aside one place each, the drop settles, and orange fades off the row as the row closes up.
- [ ] Checked on the iPad with a finger and the Pencil, and on the Mac with the pointer where the bar shows.
  Open 2026-11-13: needs the owner's iPad (finger and Pencil on the fixed bar over a PDF, and the scrolling strip upright beside the sidebar). The Pencil bar is iPad code only (`canImport(UIKit)`); the Mac shows no such bar, so the pointer check is the iPad's with a trackpad.
