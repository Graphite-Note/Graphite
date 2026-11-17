# The lasso: TODO

Created: 2026-11-17.

Status: planned and built 2026-11-17; section 1 done, section 2 built with the second tap on the bar not yet checked by hand, section 3 (the iPad) open. Issues: [#202](https://github.com/Graphite-Note/Graphite/issues/202) to [#204](https://github.com/Graphite-Note/Graphite/issues/204), one per section.

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

- [x] Take Screenshot is the first item of the selection's menu, then Cut, Copy, Duplicate, Color, Delete, Straighten and Smooth, so the compact bar shows the camera and the editing actions before it pages. Done 2026-11-17: `InkSelectionController.selectionMenuElements`; `LassoSelectionKindsHostedTests.testTheSelectionsMenuStartsWithTakeScreenshotThenCutCopyAndDuplicate`, `InkSelectionTests` (menu orders), passed in the iPad simulator. How the compact bar looks on the iPad is section 3.

## 2. The Lasso panel and what the lasso takes

Issue: [#203](https://github.com/Graphite-Note/Graphite/issues/203)

- [ ] A second tap on the lasso in use on the Pencil bar opens the Lasso panel: Rectangle and Freehand as two large choices, and Handwriting, Images and Text Boxes switches under "Included in Selection". Text Boxes shows only where text boxes exist (PDF pages). Built 2026-11-17: `LassoOptionsPanel`, opened from `PencilToolButtons.toolButton(_:tapOnToolInUse:)`; the panel checked in a rendering in the iPad simulator, light and dark; the second tap on the bar not yet checked by hand.
- [x] The lasso takes only the kinds that are on, by loop and by tap; a loop that takes nothing it may take marks the area. Done 2026-11-17: `LassoSelectionKinds`, read by `InkSelectionController` from its `preferences`; `LassoSelectionKindsTests` (Mac), `LassoSelectionKindsHostedTests.testWithHandwritingOffALoopAroundInkMarksItsAreaAndATapOnInkSelectsNothing` (iPad simulator).
- [x] The floating palette's menu has the same switches as an "Included in Selection" submenu. Done 2026-11-17: `PencilToolPalette.lassoKindActions`; `InkSelectionTests.testTheLaserPointsWithoutChangingTheDocumentAndTheBarAndPaletteChooseIt` checks the submenu is there.

## 3. Checked on the iPad

Issue: [#204](https://github.com/Graphite-Note/Graphite/issues/204)

- [ ] The bar's order, the panel, and a loop with each kind off, checked in the iPad simulator and on the owner's iPad.
