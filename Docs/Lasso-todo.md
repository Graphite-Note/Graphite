# The lasso: TODO

Created: 2026-11-17.

Status: planned and built 2026-11-17; section 1 done, section 2 built with the second tap on the bar not yet checked by hand, section 3 (the iPad) open: the owner's first check found two things to fix, built the same day. Issues: [#202](https://github.com/Graphite-Note/Graphite/issues/202) to [#204](https://github.com/Graphite-Note/Graphite/issues/204), one per section.

## Request

The owner, 2026-11-17, with a screen recording of the lasso on a PDF page on the iPad, Goodnotes' Lasso Tool panel and Goodnotes' camera button beside a lasso: "the select tool needs improvments... and a direct take screenshot button etc". Shown seven options as mockups, the owner chose:

- **A2:** Take Screenshot is the first button of the selection's bar, always shown, never behind More.
- **B1:** a Lasso panel, opened by tapping the lasso again when it is already in use: Rectangle and Freehand as two large choices, and "Included in Selection" switches for the kinds Graphite's lasso takes.
- **C2:** the selection's bar stays the system's compact edit menu, with icons only, reordered so the most used come first.

## Decisions

1. **The kinds are Handwriting, Images and Text Boxes**: what Graphite's lasso can select today. Graphite has no tape or sticky notes; shapes and equations are ink strokes, so they come with Handwriting.
2. **The kinds are kept on the device**, as the lasso's type is, for every canvas (`LassoSelectionKinds`, UserDefaults).
3. **At least one kind stays on**: the last switch that is on cannot be turned off, so the lasso never takes nothing by choice.
4. **A loop around only excluded things marks the area**, as a loop around nothing does: its menu takes a screenshot or pastes.
5. **The floating palette gets the same switches** as an "Included in Selection" submenu of its menu, beside Lasso Type; a menu cannot show the panel itself.

## 1. Screenshot first in the selection's bar

Issue: [#202](https://github.com/Graphite-Note/Graphite/issues/202)

- [x] Take Screenshot is the first item of the selection's menu, then (as first built) Cut, Copy, Duplicate, Color, Delete, Straighten and Smooth; section 3 moves Color and Delete forward, so the compact bar shows the camera and the editing actions before it pages. Done 2026-11-17: `InkSelectionController.selectionMenuElements`; `LassoSelectionKindsHostedTests` (menu order), `InkSelectionTests` (menu orders), passed in the iPad simulator. How the compact bar looks on the iPad is section 3.

## 2. The Lasso panel and what the lasso takes

Issue: [#203](https://github.com/Graphite-Note/Graphite/issues/203)

- [ ] A second tap on the lasso in use on the Pencil bar opens the Lasso panel: Rectangle and Freehand as two large choices, and Handwriting, Images and Text Boxes switches under "Included in Selection". Text Boxes shows only where text boxes exist (PDF pages). Built 2026-11-17: `LassoOptionsPanel`, opened from `PencilToolButtons.toolButton(_:tapOnToolInUse:)`; the panel checked in a rendering in the iPad simulator, light and dark; the second tap on the bar not yet checked by hand.
- [x] The lasso takes only the kinds that are on, by loop and by tap; a loop that takes nothing it may take marks the area. Done 2026-11-17: `LassoSelectionKinds`, read by `InkSelectionController` from its `preferences`; `LassoSelectionKindsTests` (Mac), `LassoSelectionKindsHostedTests.testWithHandwritingOffALoopAroundInkMarksItsAreaAndATapOnInkSelectsNothing` (iPad simulator).
- [x] The floating palette's menu has the same switches as an "Included in Selection" submenu. Done 2026-11-17: `PencilToolPalette.lassoKindActions`; `InkSelectionTests.testTheLaserPointsWithoutChangingTheDocumentAndTheBarAndPaletteChooseIt` checks the submenu is there.

## 3. Checked on the iPad

Issue: [#204](https://github.com/Graphite-Note/Graphite/issues/204)

- [ ] The bar's order, the panel, and a loop with each kind off, checked in the iPad simulator and on the owner's iPad.

The owner's check on their iPad, 2026-11-17 (a recording of a PDF page in a test vault): the bar's Freehand and Rectangle, Take Screenshot ("The screenshot is nice") and the bar starting with Take Screenshot passed; the panel opened by a second tap and a loop with Handwriting off were not shown. Two things to fix came out of it:

- [ ] A loop around a smaller part of a stroke takes the whole stroke, as Goodnotes does: "when I selected like a bit of ink at some point, it didn't select all of it. I had to select a lot of like the ink to select it." A loop around the right third of a zigzag took nothing, since a stroke needed 35 % of its length inside. Built 2026-11-17: `InkLasso.takesStroke(sampledAt:inLoop:)` takes a stroke with 15 % of its length inside when that part is at least 12 points long, or with 35 % inside however short (a dot, a short letter); a loop cutting a few points off a stroke's end is still a graze. Tests: `InkLassoSelectionThresholdsTests.testALoopAroundTheLastThirdOfALongZigzagTakesIt`, `testAShareOfAStrokeFromASixthIsTakenAndUnderItIsNot`, `testALoopTouchingAStrokesEndByAHairDoesNotTakeIt`, `InkLassoTests`, and the hosted `LassoClosingHostedTests` (a grazed line stays). Not yet checked on the owner's iPad.
- [ ] Color and Delete are in the compact bar, not behind its ">": "a lot of the useful stuff is not visible at shorthand. Like, why do I have Ask Siri and I have to click on it, click on the arrow, then on Color". The bar showed Take Screenshot, Cut, Copy, Duplicate and iOS's Ask Siri, which iOS adds after an app's own items. Built 2026-11-17: the menu is Take Screenshot, Color, Delete, Copy, Cut, Duplicate, Straighten, Smooth (`InkSelectionController.selectionMenuElements`); `LassoSelectionKindsHostedTests.testTheSelectionsMenuStartsWithTakeScreenshotColorAndDelete`, `InkSelectionTests`. Ask Siri stays: UIKit adds it to an edit menu after the delegate's menu, and has no public way to leave it out. Not yet checked on the owner's iPad.
