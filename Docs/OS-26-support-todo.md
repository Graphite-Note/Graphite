# Running on macOS 26 and iPadOS 26: TODO

Created: 2026-11-18.

Status: built on the branch `macos-26-support` 2026-11-18, not merged into `main`. Section 1 builds and passes the Mac package suite; nothing has run on a device with macOS 26 or iPadOS 26 yet. Issue: [#213](https://github.com/Graphite-Note/Graphite/issues/213).

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
- [ ] Hosted unit test for `AudioSessionInterruption(interruptionNotification:)` (iOS only, so not in the Mac package suite): began, ended with and without should-resume, another notification.
- [ ] Run the Mac app on macOS 26: open a vault, a note, a PDF with markup, the Library; the camera preview of a video recording; a neural voice reading (silently routed).
- [ ] Run the iPad app on an iPadOS 26 simulator or device: the bar's More menu in a note, a PDF, a canvas and an empty tab; Library drag of one tile; a recording interrupted by another app's audio.
- [ ] Hosted iPad suite on an iPadOS 26 simulator.
- [ ] TestFlight: the build's minimum OS shows 26.0 once the branch is merged and uploaded.
