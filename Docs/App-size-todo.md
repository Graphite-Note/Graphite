# App size: TODO

Created: 2026-10-24. Issue: [#105](https://github.com/Graphite-Note/Graphite/issues/105).

Status: main is over its size budget on both platforms, so `scripts/archive-for-testflight.sh` stops before the next upload. Section 1 is not started; section 2 (the welcome tour's pictures with the app) is built and tested in the simulator and the Mac package, and waits for its check on a TestFlight install.

## Request

The owner, 2026-10-21: Graphite stays a small, light core; extras are downloads, and a feature costs nothing while it is off. `scripts/app-size-budget.json` holds the sizes of builds 20261022.0042 (iOS) and 20261022.0051 (Mac), and the archive script refuses an upload that grew past them.

## Measured

Release archives of main f6725107 (2026-10-23), `scripts/archive-for-testflight.sh <folder> [--macos] --archive-only`, 2026-10-24:

| | Budget | Main | Growth |
| --- | --- | --- | --- |
| iOS app | 90.0 MB | 103.5 MB | +13.5 MB |
| iOS binary | 47.8 MB | 61.2 MB | +13.4 MB |
| Mac app | 61.5 MB | 75.0 MB | +13.5 MB |
| Mac binary | 46.6 MB | 60.1 MB | +13.5 MB |

The growth is all in the binary; assets and resource bundles did not change. Symbol sizes in the iOS dSYM (code and constants of named symbols only, so a lower bound) put it at:

- at least 5.6 MB for the PostgreSQL Mirror's client, linked whether the plugin is on or off: PostgresNIO 0.6, SwiftNIO (NIOCore 0.9, NIOPosix 0.6, NIOSSL 0.2, NIOTransportServices 0.2), BoringSSL 1.3, AsyncAlgorithms 0.9 MB, and smaller modules;
- 1.3 MB for `MermaidDiagrams`, against its target of 60 kB per architecture for every type (`Docs/Native-diagrams-todo.md`);
- the rest, about 6.5 MB, not yet named: `GraphiteUI` (11.4 MB in all) grew with the graph view, tabs, hover previews and Mac plugins.

## Scope

### 1. Back under the budget

- [ ] The PostgreSQL Mirror's client costs nothing in the app while the plugin is off, or the owner accepts its size. The mirror feeds desktop apps such as QGIS; one option is to build it only into the Mac app.
- [ ] `MermaidDiagrams` within its size target, or a new target agreed in `Docs/Native-diagrams-todo.md`.
- [ ] The remaining growth named by module (a link map of the Release build) and each part kept or moved out.
- [ ] The budget recorded again (`scripts/app-size-budget.py --record`) only for growth the owner accepts, and the next TestFlight upload passes without `--allow-size-growth`.

### 2. The welcome tour's pictures arrive with the app

Issue: [#166](https://github.com/Graphite-Note/Graphite/issues/166)

The owner, 2026-11-12, after a first launch in the simulator showed the tour's first page with "Downloading the pictures…": the tour's pictures should be there when Graphite is first installed, and the person should be able to delete them later. Today they are an add-on pack (`WelcomeTourScreenshotPack`: 3,142 KB for the iPad and iPhone, 1,680 KB for the Mac) downloaded from GitHub the first time the tour needs them.

- [x] On the iPad and the iPhone, the pictures come with the install, not at first launch: an On-Demand Resources tag in the App Store's initial install tags (`NSBundleResourceRequest`), so the App Store and TestFlight install them with the app and the first page shows its picture at once, offline included. Deleting them (Settings, where the add-on packs are listed) ends the app's use of the tag and lowers its preservation priority, so iOS can take the space back; the tour then downloads them again only if opened.
  Done 2026-11-13: the 28 iPad pictures of `AddOns/WelcomeTour` are resources of the app target for iOS only, tagged `WelcomeTourPictures`, which the project knows (`knownAssetTags`) and names in `ON_DEMAND_RESOURCES_INITIAL_INSTALL_TAGS[sdk=iphone*]` (Debug and Release); the files stay where the GitHub download reads them, so there is one copy in the repository. `WelcomeTourScreenshotPack` says so (`AddOnPackDelivery.onDemandResourcesTag`), `BundleResourceRequestAccess` (GraphiteApple) reads the tag through `NSBundleResourceRequest`, and `AddOnIncludedCopies` (GraphiteUI) is what `AddOnLibrary` asks first: the tag if it is on the device (`conditionallyBeginAccessingResources`, no download), else the system's download of it (`beginAccessingResources`), else Graphite's own download from GitHub as before. A launch asks the system nothing until the tour or Settings needs the pack. Remove in Settings ends the use of the tag, sets its preservation priority to 0 (1 while kept) and remembers the removal on the device (`GraphiteRemovedAddOnPacks`), so a tag iOS has not taken back yet is still shown as removed after a relaunch; opening the tour asks for it again. A new state, `checking`, shows a spinner without "Downloading the pictures…" while the tag is looked for. `NSBundleResourceRequest` is deprecated in the iOS 27 SDK in favour of Background Assets; with warnings as errors, `BundleResourceRequestAccess` alone ignores that deprecation (`@diagnose(DeprecatedDeclaration, as: ignored)`), see Decisions. How Xcode hosts the tag in a Debug build: the asset pack is built beside the app (`Debug-iphonesimulator/OnDemandResources/com.graphite.study.WelcomeTourPictures-….assetpack`, with `AssetPackManifestTemplate.plist` in the app pointing at it), and `xcodebuild test-without-building` installed it with the app in the simulator: on a fresh install the tag was on the device before any request (a probe of `conditionallyBeginAccessingResources`, run once and removed). Tests: `WelcomeTourPicturesHostedTests` (2, iPad simulator, the app's own tag, a download session refusing every request), `AddOnIncludedCopiesTests` (9, Mac package, a tag over a folder). Not checked on a device or a TestFlight install (below).
- [x] On the Mac, where On-Demand Resources may not be offered: the same if it is; otherwise the smallest way to have them at first launch that can still be deleted, or the pictures in the app, with the reason written here.
  Done 2026-11-13: macOS has neither: `NSBundleResourceRequest` and the preservation priority are `API_UNAVAILABLE(macos)` in the macOS 27 SDK, and the Mac App Store installs a Mac app's bundle whole. The 14 Mac pictures (1.7 MB) are now resources of the Mac app (`platformFilters = (macos, )`, no tag), so they cannot be removed (`AddOnPackDelivery.inAppBundle`; Settings shows "included with Graphite", with no button). Chosen over keeping the download with an earlier prefetch: the owner asked for the pictures at first launch, and a prefetch still shows "Downloading the pictures…" offline or on a slow network, and still asks GitHub for files at first launch; 1.7 MB is 2.8 % of the Mac budget's 61.5 MB. Background Assets, which macOS 26 and later do have, would make them removable, but needs App Store Connect hosting and a download extension (Decisions). A build without the files in its bundle (the package's tests) downloads them as before. Checked: the Mac app built from the project holds the 14 `-mac-` pictures in `Contents/Resources`, none of the iPad ones and no asset pack; `AddOnIncludedCopiesTests.testAPackInTheAppBundleIsIncludedAndHasNothingToRemove` and `testAPackMissingFromTheAppBundleIsDownloaded`. The tour's pictures on the Mac were not looked at in the running app.
- [x] Tests: the tour's first page shows a picture with no network on a first launch; a deleted pack is reported as such and asked for again; the size budget counts the tag's files as the App Store does.
  Done 2026-11-13: `WelcomeTourPicturesHostedTests.testOnAFirstLaunchTheFirstPageShowsItsPictureThroughTheTagWithNoNetwork` (the pack fetched as `FirstLaunchWelcomeTour` asks for it, through the tag, with every network request refused and nothing written to Application Support; the first page drawn beside the same page with no pictures until its right half has more than twice the edges: 3,898 against 1,524; screenshot looked at: the welcome page with the iPad picture of a Fourier-series note), `testARemovedPackIsReportedRemovedAndAskedForAgain` (removed, not looked for after a relaunch, then fetched again through the tag), and on the Mac `AddOnIncludedCopiesTests` (the tag used without a download, Settings looking for it, the tour asking for it while Settings looks, a removed tag reported removed across a relaunch and asked for again, the system's download, the GitHub fallback, the bundle). `scripts/app-size-budget.py` now counts the asset packs of initial install tags in `app` and in a new part, `initialInstallTags`, as the App Store counts them in the install size, and leaves other tags out: an archive keeps its asset packs in `Products/OnDemandResources`, and a pack of an initial install tag is the one whose `Info.plist` has `Priority` 1 (found by archiving a small project with and without the setting: without it the key is absent). `--self-test` checks this on a made-up archive; measured on the simulator build, `initialInstallTags` is 3.1 MB. `scripts/check-add-on-packs.py` checks that the project takes exactly the pack's files, each with its platform and tag, and the tag as an initial install tag.
- [ ] Checked on a TestFlight install on an iPad and a Mac: the first page's picture shows at once, and Delete frees the space.

## Decisions

- 2026-11-13, the welcome tour's pictures (section 2): initial install tags count in the install size, so the iOS app grows by their 3.1 MB as the App Store measures it (the download from GitHub no longer happens on a first launch). `scripts/app-size-budget.json` has no budget for `initialInstallTags` yet: the next archive reports it over budget until the owner records the growth with `--record`. The Mac app grows by the 1.7 MB of its pictures in its bundle.
- 2026-11-13: On-Demand Resources, as the owner asked, though the iOS 27 SDK deprecates `NSBundleResourceRequest` ("Use Background Assets instead"). Apple-hosted Background Assets (`AssetPackManager`, iOS and macOS 26 and later) would also serve the Mac and make its pictures removable, but the asset packs are uploaded to App Store Connect apart from the app and need a download extension target with an App Group; that is a change to the TestFlight upload and the project the owner has not asked for. The deprecation is ignored in `BundleResourceRequestAccess` only, with the reason in its `@diagnose` attribute.
- The owner, 2026-11-12: bugs first, size after. Until the open bugs are fixed, TestFlight uploads go out with `--allow-size-growth`; the size work of this file starts once they are.
