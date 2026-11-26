# Presenting a note: TODO

Created: 2026-11-26.

Status: 2026-11-26, sections 1 and 2 built and checked, sections 3 to 5 built with their tests, open items named in each. Planned the same day. Issues: [#246](https://github.com/Graphite-Note/Graphite/issues/246) to [#251](https://github.com/Graphite-Note/Graphite/issues/251), one per section.

## Request

Feature 6 of [Notion-features-for-Graphite.md](Notion-features-for-Graphite.md): a note presented as slides, full screen, as Notion's presentation mode and Obsidian's Slides core plugin do. The note's reading view is split at `---` separators by Obsidian's rule, each part drawn full screen, moved through with keys, swipes and clicks, shown on an external display through AirPlay or a cable while the iPad or the Mac shows the presenter's view (this slide, the next one, the time), and Apple Pencil draws on the iPad with the laser or with ink that fades. Presenting never changes the note.

## What the result must be

- **The note is the deck.** Slides are the note's own text split at its separators. No slide file, no sidecar, no property Graphite needs. A note presented in Graphite is the same deck in Obsidian's Slides.
- **Read only.** Presenting reads the note as it is on screen, edits not yet saved included, and writes nothing to the vault or the note.
- **The reading view, full screen.** A slide is drawn by the reading view's own blocks: text, math, callouts, code, tables, images, drawings, diagrams and embeds look as they do when reading.
- **No new bar.** The command lives in menus that exist (the Mac's menu bar, the note's More menu, the file list, the command palette). While presenting, the slide fills the screen.
- **Off costs nothing.** Nothing is built until a presentation starts, and everything it built is released when it ends. The Slides core plugin switches the command off.

## How Obsidian splits a note into slides

Read in Obsidian 1.15.1's own code (`obsidian-1.15.1.asar`, the `slides` core plugin, command `slides:start`, "Start presentation"):

- The whole note is parsed to a Markdown tree. Its top-level children are walked in order, and each `thematicBreak` node starts a new slide. Every other node goes to the current slide.
- So only a thematic break at the top level separates slides: `---`, `***`, `___` and their spaced forms (`- - -`) all count. A `---` under a paragraph line is a heading underline, not a break. A `---` inside a fenced code block, a math block, a quote or callout, or a list item is not at the top level.
- An empty group is skipped (two breaks in a row make no empty slide).
- The frontmatter is the first child of the first slide and is not drawn (no properties on a slide).
- Link reference definitions of the whole note are passed to every slide, so a `[text][ref]` link works whichever slide defines `ref`.
- Escape closes the presentation. The deck is reveal.js, with its keys: right, down, space, Page Down and `N` go forward, left, up, Page Up and `P` go back, Home and End go to the first and last slide.
- The theme is reveal.js's dark one, or its light one when the vault uses the light base theme.

## Decisions

1. **Obsidian's rule decides what a slide is**, as above, with one difference: a slide with nothing to draw (only frontmatter, blank lines or `%%` comments) is skipped, where Obsidian draws a blank slide for frontmatter followed by a separator.
2. **A footnote shows on the slide that defines it.** Each slide is built as the reading view builds a note, so its footnotes are listed at its foot. A reference to a footnote defined on another slide shows as written. Obsidian's Slides behaves the same way, as it renders each slide on its own.
3. **Slides are 16 by 9.** A slide is laid out on a fixed canvas of 1,280 by 720 points at a text size of 32 and scaled to the screen, so the device and an external display show the same lines and the Pencil's marks land on the same words. Diagrams are drawn as shapes and stay sharp at any scale. A slide whose content is taller than the canvas is shrunk until it fits: nothing scrolls during a talk.
4. **Colours follow the app's appearance**, as Obsidian's slides follow its base theme: light or dark, with the vault theme's colours where the reading view uses them.
5. **Links do not leave the presentation.** Tapping or clicking a slide moves to the next slide, and links on a slide are not followed.
6. **Moving between slides:** the keys above, with Return also going forward and Delete and Shift-space going back. On the iPad and the iPhone, a finger swipes left for the next slide and right for the one before, and a tap on the left quarter goes back, elsewhere forward. On the Mac a click goes forward. Apple Pencil never moves the slides: it points or draws.
7. **The command** is "Start Presentation", Obsidian's `slides:start`. On the Mac, View › Start Presentation with ⌥⌘P (Keynote's Play Slideshow). On the iPad and the iPhone, in the File submenu of the note's More menu beside Export to PDF, and in the file list's menu of a note, where Obsidian puts it. The command palette lists it while a note is in front. It belongs to a new Slides core plugin, on by default.
8. **External display:** with a second display (AirPlay, a cable, or the Mac's second screen), the slide fills that display and the device shows the presenter's view: this slide large, the next slide, the slide number and the time since the presentation started. Without one, the device shows the slide alone. A display connected or disconnected during a talk switches between the two without stopping it.
9. **The Pencil on the iPad** points with the laser by default, Graphite's own laser of pages and drawings, or writes with ink that fades a moment after the Pencil lifts. Both show on the external display at the same place on the slide. Changing slides clears them.
10. **Nothing is saved.** The laser and the fading ink leave nothing behind. Keeping ink would be a later, separate choice that saves a drawing through the existing drawing embed, only when asked (section 6).

## 1. What a slide is

Issue: [#246](https://github.com/Graphite-Note/Graphite/issues/246)

- [x] `NoteSlides` in Core splits a note's text into slides by Obsidian's rule and decision 1: the separators found as the reading view finds them (fences, math, callouts, tables, heading underlines, comments), left out inside list items, frontmatter left out, empty slides skipped, each slide's range in the note kept. Done 2026-11-26: `NoteSlides.slides(in:)` (Core) takes the rules of `LivePreviewBlockScanner` and drops a rule inside a list item with `ListItemContainers.containerColumn(ofLineAt:in:)`. `NoteSlidesTests` (11).
- [x] The note's link reference definitions are given to every slide that uses them. Done 2026-11-26: appended with `ReferenceLinkDefinitions.appendingDefinitions`, `NoteSlidesTests.testAReferenceLinkFindsItsDefinitionOnAnotherSlide`.
- [x] Unit tests with plain text: each separator form, a heading underline, separators inside code, math, quotes, callouts and list items, frontmatter, empty slides, Windows line endings, a note with no separator (one slide), reference links across slides. Done 2026-11-26: `NoteSlidesTests`, `SlidePositionTests` (3).

## 2. Drawing a slide

Issue: [#247](https://github.com/Graphite-Note/Graphite/issues/247)

- [x] A slide is built by the reading view's builder off the main actor and drawn by its blocks at a 16 by 9 canvas scaled to the screen, laid out as decision 3 says, centred vertically, shrunk to fit when taller. Done 2026-11-26: `NotePresentation` builds with `ReadingViewBuilder`, `NoteSlideView` and `NoteSlideCanvas` draw `ReadingBlocksView`. `NotePresentationTests`, `NoteSlideViewRenderingTests`.
- [x] Light and dark follow the app (decision 4), selection and links are off (decision 5), wide tables and code wrap. Done 2026-11-26: `slideEnvironment` (`readingIsPrinted`), `PresentationAppearance` for the screens outside the window. The dark and light pictures of the rendered check.
- [x] Slides are built as the presentation needs them, the first at once and the rest in order after it, and the presentation's work is cancelled when it ends. Done 2026-11-26: one task owned by `NotePresentation`, cancelled and the slides released by `end()`. `NotePresentationTests.testEndingReleasesTheSlidesAndLeavesTheNoteAsItWas`.
- [x] A rendered check: pictures of slides with text, a callout, display math, a Mermaid diagram and an image, light and dark, looked at, and a slide too tall shown shrunk. Done 2026-11-26: `NoteSlideViewRenderingTests` (2) draws the slides as the screen does and reads the pictures (in the margins, centred, the formula, the diagram's four boxes, the picture, the background of each appearance), and the pictures were looked at. The callout was seen in the iPad hosted runs.

## 3. Starting, moving and ending

Issue: [#248](https://github.com/Graphite-Note/Graphite/issues/248)

- [ ] The Start Presentation command (decision 7): the Mac's View menu with ⌥⌘P, the note's More › File menu and the file list's menu on the iPad and the iPhone, the command palette, and Settings › Keyboard Shortcuts. Dimmed while no note is in front, absent while the Slides core plugin is off.
- [x] Full screen on each platform: a cover over the window on the iPad and the iPhone, a window over the whole screen on the Mac with the menu bar and Dock hidden. Done 2026-11-26: `NotePresentationLauncher` (`fullScreenCover`), `MacPresentationWindows`. Checked: `NotePDFMenuHostedTests.testStartPresentationFromTheMoreMenuShowsTheSlidesFullScreenAndLeavesTheNoteAsItWas` (iPad simulator, the window's own More › File menu) and `MacPresentationInAppHostedTests` (the running Mac app, a Debug copy under the bundle identifier `com.graphite.study.repro`: the window covers the screen, the menu bar and the Dock come back after).
- [x] The keys, swipes, taps and clicks of decision 6, and Escape (or a close button that fades in at a corner) to end. The slide number shows briefly after each move. Done 2026-11-26: `PresentationKeys`, `PresentationTouches`, `PresentationTouchSurface` (UIKit recognizers), a click on the Mac (its hosting view takes the first click). Checked in the running Mac app: right arrow, space, Home, a click and Escape. On the iPad simulator: swipes and taps, and End.
- [x] Tests: the key table and moves with plain values, the command's menus and shortcut, and a hosted check on the iPad simulator of swiping and tapping through a note's slides. Done 2026-11-26: `NotePresentationTests`, `GraphiteCommandTests` and `KeyboardShortcutsPageContentTests` (the new command), `NotePresentationHostedTests.testFingerSwipesAndTapsMoveBetweenTheSlides`.
- [ ] Checked by hand in a Mac Debug copy and in a dedicated iPad simulator. 2026-11-26: checked inside the running apps by the hosted tests above (a Debug copy of the Mac app, and the app on a dedicated iPad Pro 11-inch (M5) simulator, iOS 27.2), not by hand: the simulator panel was not granted for that simulator, and the menu bar cannot be clicked from a test. Still to do by hand: View › Start Presentation and ⌥⌘P on the Mac, the file list's menu and the command palette.

## 4. An external display and the presenter's view

Issue: [#249](https://github.com/Graphite-Note/Graphite/issues/249)

- [ ] iPad and iPhone: the app takes the external display's scene (AirPlay or a cable) only while a presentation runs, so the screen is mirrored as before at other times, and shows the slide there.
- [ ] The Mac: with a second screen, the slide fills the screen the Graphite window is not on, and the presenter's view fills the other.
- [x] The presenter's view: this slide, the next one, the slide number and the elapsed time, with the same keys and gestures. Done 2026-11-26: `PresenterView` in `NotePresentationScreen`. `NotePresentationHostedTests.testWithAnotherDisplayTheDeviceShowsThePresentersViewAndBackWithout`, its pictures looked at.
- [ ] A display connected or removed during a talk switches views without stopping it. Built 2026-11-26: `PresentationExternalDisplays` reads the connected scenes again after each connection or disconnection, `MacPresentationWindows` arranges again when the screens change, and the device's view follows `hasAudienceDisplay` (tested by setting it in the hosted test above). Not seen with a real display.
- [ ] Checked with an external display simulated (the iPad simulator's external display) and with the Mac's screens as present. 2026-11-26: `xcrun simctl io <device> screenConfig --display=external power on` gives the simulator a 1920 by 1080 TV-out screen, but no app scene is made for it on the iPad or the iPhone simulator (Settings shows nothing there either), so `NotePresentationExternalDisplayHostedTests`, which needs that scene, could not run yet. `testInfoPlistNamesTheDisplaySceneDelegateForTheExternalDisplayRole` passes. The development Mac has one screen, where the slide alone was checked. To do: an AirPlay or cable display on a device, and a Mac with two screens.

## 5. Apple Pencil: the laser and ink that fades

Issue: [#250](https://github.com/Graphite-Note/Graphite/issues/250)

- [x] On the iPad, the Pencil points with Graphite's laser (dot or line, as chosen for pages) over the slide, and fingers keep moving slides. Done 2026-11-26: `PresentationMarks`, `PresentationMarksView` over `LaserPointerOverlayView`.
- [x] Ink that fades: the Pencil writes in a chosen colour, and the strokes fade together a few seconds after the last lift. Done 2026-11-26: `FadingInkView`, three seconds after the last lift, a fade of 0.6 seconds.
- [ ] A choice between the laser and the ink in the presenter's corner controls, kept on the device. Built 2026-11-26: `PresentationPencilMenu` in the corner and in the presenter's buttons, kept as `GraphitePresentationPencilTool` and `GraphitePresentationInkColor`, read when a presentation starts (`NotePresentationTests.testThePencilsChoicesAreReadFromTheDevicesPreferences`). The menu itself was not opened in a check.
- [x] The laser and the ink show on the external display at the same place of the slide, and are cleared when the slide changes. Done 2026-11-26: marks travel in canvas points (`PresentationCanvasMapping`). `NotePresentationHostedTests.testThePencilDrawsOnEveryScreenWithoutMovingAndTheMarksGoWithTheSlide` draws with a synthesized Pencil touch and finds each mark on a second screen's slide, both gone after a move. On a real external display: not seen (section 4).
- [ ] Tests of the mapping between the device's slide and the external slide with plain values, and a hosted check of a stroke drawn by a synthesized touch. Checked in the simulator by finger with finger drawing on, as Pencil checks are. 2026-11-26: the tests are done (`NotePresentationTests.testAPointOfTheSlideIsTheSameCanvasPointOnEveryScreen`, the hosted test above, whose pictures of the laser and the ink were looked at). The check by finger was not made: the simulator panel was not granted. Still to do, with Apple Pencil on a device.

## 6. Later: keeping the ink

Issue: [#251](https://github.com/Graphite-Note/Graphite/issues/251)

- [ ] Only when asked, at the end of a talk: the ink of a slide kept as a drawing, saved through the existing drawing embed (`![[…png]]` in the attachment folder) under the slide's last line, as an ordinary edit of the note with its own undo. Not built: fading ink is meant to go, and a saved drawing changes the note, so this waits for a request.
