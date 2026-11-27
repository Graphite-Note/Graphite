# Running on macOS 26 and iPadOS 26: TODO

Created: 2026-11-18.

Status: built on the branch `macos-26-support` 2026-11-18 and merged into `main` (f8d86359). Section 1 is done: the app and the hosted suite ran on an iPadOS 26.5 simulator on 2026-11-27; macOS 26 was not run, since this Mac runs macOS 27.2. That run found that iOS 26's PDFKit drops data at every save, which Graphite's PDF features depend on (section 2). Issues: [#213](https://github.com/Graphite-Note/Graphite/issues/213) (section 1), [#261](https://github.com/Graphite-Note/Graphite/issues/261) (section 2).

## Request

Requested 2026-11-18: "i think we should also support macos26 as a lot of people are still on it", then iPadOS 26 as well, kept off `main` on a branch of its own ("do not push on main as that is a side quest").

## What the result must be

- **The same app on 26 and 27.** Graphite installs and runs on macOS 26.0 and iOS/iPadOS 26.0 and later. It is still built with Xcode 27 and the 27 SDKs.
- **27 keeps what it has.** Each API the system has only from 27 (or 26.1) sits behind `#available`; on 27 the code that runs is the code that ran before.
- **The compiler guards it.** With the deployment targets at 26.0, any new use of a 27-only API fails to build until it has a fallback.

## Decisions

- Deployment targets 26.0 for both platforms (`Package.swift`, `Packages/MermaidDiagrams`, `Packages/NotebookImport`, the Xcode project's four build configurations), not 26.1: 26.0 is the first release most people still on 26 have, and the one 26.1 API (`visibilityPriority` on the Mac) has a harmless fallback.
- What 26 shows instead, where 27's API has no older equal:
  - **Library drag (iOS 26).** Drag containers (`dragContainer`, `draggable(containerItemID:)`) are iOS 27 (macOS 26). On iOS 26 a tile drags alone; a drag that starts on a chosen tile does not take the other chosen tiles. `LibraryDragging.swift`.
  - **More menu (iOS 26).** The system's overflow menu (`ToolbarOverflowMenu`) is iOS 27. On iOS 26 the More commands are a More (•••) menu button of their own, as on the Mac, and items the bar has no room for are folded by the system as before 27. `ToolbarFallbacks.swift`.
  - **Items kept in view (iOS 26, macOS 26.0).** `visibilityPriority(.high)` is iOS 27 and macOS 26.1; before, those items fold like any other (`keptInViewWhenNarrow()`).
  - **Audio interruptions (iOS 26).** The deactivation and resumption-recommendation notifications are iOS 27; on iOS 26 `AudioSessionInterruption` reads the interruption notification, which only the system posts.
  - **Neural voice playback (26).** `connectNode(_:to:format:)` and `playAudio()` throw from 27; on 26 the engine uses `connect(_:to:format:)` and `play()`, whose failures raise an Objective-C exception instead of an error.
  - **Camera preview (macOS 26).** `sampleBufferReceiver(adding:)` is macOS 27 (iOS 26); on macOS 26 the renderer is added to the synchronizer and frames are enqueued in it directly, flushing it first when it needs a flush to decode again.

## 1. Build and run on 26

Issue: [#213](https://github.com/Graphite-Note/Graphite/issues/213)

- [x] Done 2026-11-18: deployment targets lowered to 26.0 and the fallbacks above added. Checked: the Graphite scheme builds for macOS and for iOS (generic device) with the 26.0 targets; the Mac package suite passes compiled for macOS 26 (run on macOS 27, so the fallbacks themselves do not run; Read Aloud, speech, dictation, audio, voice and recording classes left out under the no-sound rule); rules, test registration and sizes.
- [x] Hosted unit test for `AudioSessionInterruption(interruptionNotification:)` (iOS only, so not in the Mac package suite): began, ended with and without should-resume, another notification.
  Done 2026-11-27: `AudioSessionInterruptionHostedTests` (5): began; ended with should-resume; ended without options and with empty options; a route-change notification, one without a type and one with an unknown type read as no interruption; and the notifications observed for the running system's version. The notifications are made by the test, so no audio session is activated. Passed on a dedicated iPad Pro 11-inch (M5) simulator (iOS 27.2) with the silent hosted-suite script. Running on iOS 27, it checks the iOS 26 reader directly, not the `#available` branch that picks it.
- [ ] ~~Run the Mac app on macOS 26: open a vault, a note, a PDF with markup, the Library; the camera preview of a video recording; a neural voice reading (silently routed).~~
  Dropped 2026-11-27: the development Mac runs macOS 27.2 and no macOS 26 machine or virtual machine is at hand, so the Mac's fallbacks (`visibilityPriority` before 26.1, the camera preview's synchronizer, `connect` and `play` of the neural voice) are built and compiled for 26.0 but have not run on it.
- [x] Run the iPad app on an iPadOS 26 simulator: the bar's More menu in a note, a PDF, a canvas and an empty tab; Library drag of one tile.
  Done 2026-11-27 on an iPad Pro 13-inch (M5) simulator with iOS 26.5 (23F77), the Debug build of main 455ca457 and a made-up vault, driven with real touches by an XCUITest of the installed app: the More (•••) button of a note (views, Format, Insert, Fold, Save Now, Local Graph, File, Icon…, Bookmark), a PDF (Copy Link to This Page, the Pencil items, Writing Guides, Add Image, Bookmark, Rotate, Duplicate, Export, Delete Page), a canvas (zoom, Select All, snapping, Save Now, Copy Graphite URL, Bookmark, Quick Switcher, Command Palette, Focus) and an empty tab (Quick Switcher, Command Palette, Focus) each opened its menu; in the Library, the tile Welcome.md dragged onto the tile Courses moved the file into `Courses/`. Also with real touches: Show Sidebar, Graph View from the file list, a folder chosen while the file tree is filtered, a presentation's swipe and tap, and the Font Size slider (16 to 21 points, kept after Appearance was opened again).
- [ ] ~~A recording interrupted by another app's audio on iPadOS 26.~~
  Dropped 2026-11-27: an interruption needs another app's audio to play, and nothing may play sound on the development Mac. iOS 26's reader of the interruption notification is covered by `AudioSessionInterruptionHostedTests`.
- [x] Hosted iPad suite on an iPadOS 26 simulator.
  Done 2026-11-27 on the same simulator, Read Aloud, speech, audio and recording classes left out: 749 tests, 677 passed, 24 failed. The same failing tests on an iOS 27.2 simulator with the same build: 22 passed, so 22 failures come from iOS 26; `SidebarAtKeyboardHostedTests` fails on both and is HUNT-379 (its 834-point window does not fit the 13-inch simulator), and `PDFInkOnTheDeviceHostedTests.testWritingOnAFullPageAsItComesOnScreenFreezesNoFrame` is an expected failure on 27.2.
  The causes, each checked against the installed app with real touches on iOS 26.5: iOS 26 draws the system's Show Sidebar button only in a scene's own window, not in a hosted test's (`SettingsHostedTestCase.showSidebar(in:)` asks the split view there; 5 tests); the More menu is the bar's own button on 26, where 27 has the overflow menu (`MoreMenuReader` reads either; 5 tests); `LassoSelectionKindsHostedTests` did not keep its canvas, which the selection controller holds `unowned` and nothing else kept on 26 (a crash in the test only). Five steps need a control that takes no synthesized touch or accessibility activation from a hosted test on iOS 26 (Graph View in the file list, a filtered folder's row, a presentation's slide, the Font Size slider, the scan question's Stop button); those tests stop there on 26 through `SynthesizedInputCapability`, after the checks before. With those changes the classes pass on iOS 27.2 (23 of 23, `SettingsPagesHostedTests` 15 of 15) and on iOS 26.5 (the five skips; `FileTreeFilterHostedTests.testFilteringThirtyThousandFilesFitsInAFrame` once took 16.6 ms against its 16 ms budget, passing in the full run). Not checked on iOS 26: VoiceOver's own step of the slider, and stopping a scan. The ten other failures come from iOS 26's PDFKit (section 2).
- [x] TestFlight: the build's minimum OS shows 26.0 once the branch is merged and uploaded.
  Done 2026-11-27: App Store Connect's `minOsVersion` is 26.0 for every build uploaded since the merge, read from `/iris/v1/builds`: iOS 20261119.2258, 20261123.2116, 20261123.2132, 20261124.0759 and 20261124.1608, and Mac 20261123.2149, 20261124.0804 and 20261124.1618 (the newest two of main 0812f8ff).

## 2. PDFs saved on iPadOS 26

Issue: [#261](https://github.com/Graphite-Note/Graphite/issues/261)

Found 2026-11-27 by the hosted suite on an iOS 26.5 simulator: a small PDF with page labels, named destinations, viewer settings, a form, an outline, a link and another application's annotation, read by PDFKit and written again with no edit, comes out of iOS 26's PDFKit as PDF 1.3 without the catalog's `/PageLabels`, `/Names`, `/ViewerPreferences` and `/PageLayout` and without any annotation's `/NM`; macOS 27's PDFKit, writing the same file, keeps all of them. Graphite saves a PDF through PDFKit, and recognises its own pictures, text boxes, section links and ink by `/NM` (`PDFPicture`, `PDFTextBoxAnnotationReading`, `PDFMarkup`), so on iPadOS 26 a saved and reopened PDF loses those entries and Graphite's objects on it are no longer read as Graphite's.

- [ ] Decide how iPadOS 26 handles PDF saving: restore what PDFKit drops after it writes (each annotation's `/NM` from the document in memory, the catalog's entries from the file read), raise the iOS and iPadOS deployment target to 27.0 while macOS keeps 26.0, or open PDFs read-only on iPadOS 26.
- [ ] Build what is decided, with the ten hosted tests that fail on iOS 26.5 passing there or answered: `PDFObjectCompactionTests` (the saved catalog; a picture and a turned picture stored as their JPEG), `PDFAnnotationTests` (an outlined ink's `/NM`; ink removed by another application), `PDFPictureTests` (pictures of inserted pages), `PDFPageSharpnessHostedTests`, `PDFPageInkReadingTests` and `PDFInkOnTheDeviceHostedTests` (2). The dropped data is shown for the first five; the causes of the other five are not examined yet.

