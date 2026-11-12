# Release checks

What runs before each TestFlight upload, in order (Docs/Release-test-vault-todo.md, section 3). `scripts/release-check.sh` runs every step one at a time, stops at the first failure that is not on its known list, and ends with a summary to paste into the upload's What to Test. The upload itself stays a separate step (Docs/TestFlight.md), made only after the checks pass.

```bash
scripts/release-check.sh /tmp/graphite-release-check
```

The folder must be outside iCloud: codesign fails in iCloud's Desktop. It holds the builds, every step's log, the result bundles, the screenshots and `release-check-summary.txt`. `--ipad <udid>` chooses the iPad simulator (otherwise `scripts/select-ipad-simulator.py` chooses one), and `--from <step>` starts at a later step once the steps before it have passed. A whole run takes about an hour on the owner's Mac.

## The steps

1. **rules**: `scripts/check-rules.py`, `check-imports.py`, `check-test-registration.py`, `check-defect-tests.py` and `check-invariant-pins.py`.
2. **mac-suite**: the full Mac package suite, `swift test --parallel`, built in the build folder.
3. **mac-pass**: the release vault pass on the Mac (`ReleaseVaultPassTests` with `GRAPHITE_RELEASE_PASS=1`): every note of `Tests/ReleaseVault` in Live Preview, the reading view and source mode, page by page, and every PDF, canvas, base and picture in its own view, in the window's root view. It runs as three tests, one per part of the vault (`ReleaseVaultPassPart`: pictures, PDFs, canvas, notebooks and bases; the text notes; the diagrams, daily notes and long lecture), so each stays within the hosted tests' four minutes a test. Its screenshots go to `release-pass-mac/` in the build folder.
4. **ios-build**: the app and the hosted tests built for the iPad simulator; `Package.resolved` of the project is put back afterwards, as Xcode rewrites it.
5. **hosted-suite**: the full hosted suite on the iPad simulator.
6. **ipad-pass**: the release vault pass on the iPad simulator (`ReleaseVaultPassHostedTests`, with `TEST_RUNNER_GRAPHITE_RELEASE_PASS=1`, which xcodebuild hands to the tests). The screenshots are the result bundle's attachments, exported to `ipad-pass-screenshots/`.
7. **iphone-pass**: the same pass on an iPhone simulator the script makes for the run on the newest iOS runtime (`xcrun simctl create`) and deletes after it, so the iPhone's compact layout is checked and no other session's simulator is used. Screenshots in `iphone-pass-screenshots/`.
8. **sizes**: `scripts/size-report.py`.

Then the upload: `scripts/archive-for-testflight.sh <folder>` and `--macos` (Docs/TestFlight.md), with the summary's What to Test.

## What the pass counts as a failure

`ReleaseVaultPass` records a finding, and the step fails, for:

- an error the workspace reports, or a tab that cannot open its file;
- a Live Preview block on screen (properties, a table, a formula, an embed, a line of pictures, a base, a rule, a callout, a diagram, a web page: `LivePreviewBlock.Kind`) with no rendered view over its lines, so its source shows;
- a rendered view in source mode;
- a picture Live Preview did not find and decode, or that the reading view's blocks cannot decode;
- an embed or a section the reading view does not find, or a diagram it leaves as source;
- a stretch of main-thread work longer than the budget (1.5 s on the Mac, 2.5 s in the simulators) at an opening, a switch of view or a scroll;
- the vault's web frame never asked for from the pass's loopback server.

The vault's deliberate failures (an embed of a note not written yet, of a heading that does not exist, and an SVG of another app, which Graphite documents it does not draw in a note) are listed in `ReleaseVaultFinding.intended`; each must still be seen. Every finding is printed as a `GRAPHITE-RELEASE-FINDING` line, and each run as one `GRAPHITE-RELEASE-PASS` line with the files opened, the screenshots taken and the longest main-thread step.

## Rules of a run

- **Nothing may make a sound.** Each test run is watched through `pmset -g assertions`: an `audio-out` assertion made after the run starts (by the Mac or the simulator, a test, or a system sound) stops the run at once and names the test that was running. Assertions another app held before the run started are printed at its start and left alone. A run stopped this way is not retried until it is known why the output opened.
- **One build at a time.** The script waits until no other `xcodebuild`, `swift-build` or `swift-test` runs before it builds.
- **Known failures in one place.** `KNOWN_FAILURES` at the top of the script lists the tests failing on main that are not a release's own, each with why; a failure of one of them is named in the summary and does not stop the run. Any other failure stops it. Take a test off the list when it is fixed.

## What it does not check

A simulator has no Apple Pencil, no real keyboard or trackpad, and not the memory or speed of the owner's iPad; the vault holds no sound. Those are checked on a device (Docs/Release-test-vault-todo.md, section 4).
