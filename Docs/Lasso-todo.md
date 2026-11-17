# The lasso: TODO

Created: 2026-11-17.

Status: planned and built 2026-11-17; sections 1 and 2 done; section 3 (the iPad) open: the owner's first check found two things to fix, built and checked in the simulator the same day; a loop with Text Boxes off is not checked, as ending a PDF text box's editing froze the app in that run (reported to the PDF annotation work). Issues: [#202](https://github.com/Graphite-Note/Graphite/issues/202) to [#204](https://github.com/Graphite-Note/Graphite/issues/204), one per section.

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

- [x] A second tap on the lasso in use on the Pencil bar opens the Lasso panel: Rectangle and Freehand as two large choices, and Handwriting, Images and Text Boxes switches under "Included in Selection". Text Boxes shows only where text boxes exist (PDF pages). Built 2026-11-17: `LassoOptionsPanel`, opened from `PencilToolButtons.toolButton(_:tapOnToolInUse:)`; the panel checked in a rendering in the iPad simulator, light and dark. Done 2026-11-17: checked on the Graphite Lasso iPad simulator (iPad Pro 13-inch (M5), iOS 27.2), finger drawing, Debug build of main 1daa263a: on the fixed bar a first tap chooses the lasso, a second opens the panel with Rectangle and Freehand and the three switches on a PDF page; Rectangle chosen in the panel shows on the bar's Freehand/Rectangle control. The floating palette's menu shows the same three under "Included in Selection", and turning Handwriting off there is kept (`GraphiteLassoSelectionKinds` 6).
- [x] The lasso takes only the kinds that are on, by loop and by tap; a loop that takes nothing it may take marks the area. Done 2026-11-17: `LassoSelectionKinds`, read by `InkSelectionController` from its `preferences`; `LassoSelectionKindsTests` (Mac), `LassoSelectionKindsHostedTests.testWithHandwritingOffALoopAroundInkMarksItsAreaAndATapOnInkSelectsNothing` (iPad simulator).
- [x] The floating palette's menu has the same switches as an "Included in Selection" submenu. Done 2026-11-17: `PencilToolPalette.lassoKindActions`; `InkSelectionTests.testTheLaserPointsWithoutChangingTheDocumentAndTheBarAndPaletteChooseIt` checks the submenu is there.

## 3. Checked on the iPad

Issue: [#204](https://github.com/Graphite-Note/Graphite/issues/204)

- [ ] The bar's order, the panel, and a loop with each kind off, checked in the iPad simulator and on the owner's iPad. The owner, 2026-11-17, through the PDF annotation session: sessions check on simulators of their own with finger drawing. Checked on the Graphite Lasso iPad simulator (iPad Pro 13-inch (M5), iOS 27.2), finger drawing, Debug build of main 1daa263a: the bar's order (below), the panel (section 2), a loop around ink with Handwriting off and around a picture with Images off each marked the area with Take Screenshot only, and with Images on the picture was taken with Take Screenshot, Delete and Copy. Open: a loop with Text Boxes off, as placing a text box on the PDF page and tapping Done (typed or empty), or another tool, held the main thread at 100 % in `PDFTextBoxEditor.end()` resigning first responder inside the PDF view's SwiftUI update, three runs of three.

The owner's check on their iPad, 2026-11-17 (a recording of a PDF page in a test vault): the bar's Freehand and Rectangle, Take Screenshot ("The screenshot is nice") and the bar starting with Take Screenshot passed; the panel opened by a second tap and a loop with Handwriting off were not shown. Two things to fix came out of it:

- [x] A loop around a smaller part of a stroke takes the whole stroke, as Goodnotes does: "when I selected like a bit of ink at some point, it didn't select all of it. I had to select a lot of like the ink to select it." A loop around the right third of a zigzag took nothing, since a stroke needed 35 % of its length inside. Built 2026-11-17: `InkLasso.takesStroke(sampledAt:inLoop:)` takes a stroke with 15 % of its length inside when that part is at least 12 points long, or with 35 % inside however short (a dot, a short letter); a loop cutting a few points off a stroke's end is still a graze. Tests: `InkLassoSelectionThresholdsTests.testALoopAroundTheLastThirdOfALongZigzagTakesIt`, `testAShareOfAStrokeFromASixthIsTakenAndUnderItIsNot`, `testALoopTouchingAStrokesEndByAHairDoesNotTakeIt`, `InkLassoTests`, and the hosted `LassoClosingHostedTests` (a grazed line stays). Done 2026-11-17 (2130a6fd): checked on the Graphite Lasso iPad simulator (iPad Pro 13-inch (M5), iOS 27.2), finger drawing, Debug build of main 1daa263a: a 720-point zigzag drawn with the pen and a freehand loop around its last third took the whole stroke.
- [x] Color and Delete are in the compact bar, not behind its ">": "a lot of the useful stuff is not visible at shorthand. Like, why do I have Ask Siri and I have to click on it, click on the arrow, then on Color". The bar showed Take Screenshot, Cut, Copy, Duplicate and iOS's Ask Siri, which iOS adds after an app's own items. Built 2026-11-17: the menu is Take Screenshot, Color, Delete, Copy, Cut, Duplicate, Straighten, Smooth (`InkSelectionController.selectionMenuElements`); `LassoSelectionKindsHostedTests.testTheSelectionsMenuStartsWithTakeScreenshotColorAndDelete`, `InkSelectionTests`. Ask Siri stays: UIKit adds it to an edit menu after the delegate's menu, and has no public way to leave it out. Done 2026-11-17 (2130a6fd): checked on the Graphite Lasso iPad simulator (iPad Pro 13-inch (M5), iOS 27.2), finger drawing, Debug build of main 1daa263a: the bar showed Take Screenshot, Color, Delete, Copy and ">", Color opened its swatches in one tap and red recoloured the stroke.
