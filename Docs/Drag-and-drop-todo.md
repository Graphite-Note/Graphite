# Drag and drop photos and files: TODO

Created: 2026-11-09.

Status: built 2026-11-09, covered by Mac package tests; not yet tried with a real drag from another app on a device (see each item). Issues: [#144](https://github.com/Graphite-Note/Graphite/issues/144) (section 1), [#145](https://github.com/Graphite-Note/Graphite/issues/145) (section 2).

## Request

The owner, 2026-11-09: "drag and drop photos and files (both into notes and into the repo) to work (on iphone ipad and mac)". Asked where it fails, the owner picked every place: into a note, into the file tree, onto a note in Reading view, "all of it". Later the same day: "also a pictre or pdf or any file type drag and drop from any app etc ( messages uni campus app etc)".

So a photo or any file dragged from another app (Photos, Files, the Finder, Safari, Mail) can be dropped:

- onto an open note, in Source, Live Preview and Reading view: it is saved as an attachment where the vault's settings say and embedded (or linked, for files Obsidian does not embed) where it was dropped;
- onto the file tree, a folder in it, or the library: it is copied into that folder.

On the iPhone, the iPad and the Mac.

## What exists today (2026-11-09)

- The note editor takes drops on both platforms. iOS: `MarkdownTextView.paste(itemProviders:)` in `Sources/GraphiteUI/NativeMarkdownEditor.swift`, reached through the text view's `pasteConfiguration`, which accepts only Graphite's vault items, images, PDFs, audio and movies; any other file (a Word document, a ZIP, a text file) is refused. Mac: `MarkdownMacTextView.performDragOperation` takes file addresses and image data (`MacPastedAttachment`), but not the file promises that Photos and Mail drag, so a photo dragged from Photos is refused.
- Reading view takes no drops at all.
- The file tree only moves its own items: the iPad and iPhone sidebar (`VaultSidebar`) and the Mac outline (`MacFileTree`) accept `VaultItemTransfer` only, so a file from Files, the Finder or Photos is refused.
- The library already copies files from other apps into a folder (`LibraryDropReader`, `LibraryDropPlan`, `WorkspaceModel.receiveDrop(_:into:)`), and that reader handles file addresses, file representations and Graphite's own items. `Docs/Obsidian-mobile-gaps.md` lists drops as "not yet tried on a device".

## 1. Drop onto a note

Issue: [#144](https://github.com/Graphite-Note/Graphite/issues/144)

- [ ] The iOS editor accepts any file, not only images, PDFs, audio and movies; dropped text stays text (a text selection is inserted as text, a text file from Files becomes an attachment). Built 2026-11-09: the text view's `pasteConfiguration` takes every type (`public.item`), `MarkdownTextView.insertDroppedItems` saves anything a file can be made of (`LibraryDropReader.importableType`) and hands text and links back to the text view. Compiled for iOS; not tried with a real drag.
- [ ] The Mac editor accepts file promises (Photos, Mail) as well as file addresses and image data, and saves each as an attachment. Built 2026-11-09 (`MacDroppedFiles`, `MarkdownMacTextView.performDragOperation`): a promise is preferred over the picture data Photos may also put on the pasteboard, so the photo keeps its name and format. Not tried with a real drag from Photos.
- [ ] Reading view accepts the same drops and adds each embed without switching to editing. Built 2026-11-09 at the end of the note, in the order dropped (`WorkspaceModel.receiveDrop(_:intoNote:)`): the reading view has no cursor, and finding the block under the drop is left for later. Tested by `WorkspaceImportFilesTests.testFilesDroppedOnANoteInTheReadingViewAreEmbeddedAtItsEnd`; not tried with a real drag.
- [ ] Any file type from any app (Messages, a school's or campus app, Mail, Safari): an app's own type that declares no conformance is still a file when the app names it. Built 2026-11-09 in `LibraryDropReader.importableType`, used by the editor, the reading view and the file tree; tested by `LibraryDropReaderTests.testAFileOfAnAppsOwnTypeArrivesUnderItsName`. Not tried with those apps.
- [ ] Tests: the reader decides by type the same way for each platform (image, PDF, other file, text selection, vault item, file promise); a hosted test drops into Reading view and checks the note's text. Done 2026-11-09 as Mac package tests: `LibraryDropReaderTests` (HEIC and JPEG offered together take the JPEG; an app's own type), `WorkspaceImportFilesTests` (a drop on a note in the reading view; a web address refused). Not done: a hosted iPad test, a test of a file promise.
- [ ] Checked on the iPad (Photos and Files in Split View), the iPhone (drag from Photos while switching apps) and the Mac (Photos, Finder, Safari).

## 2. Drop onto the file tree

Issue: [#145](https://github.com/Graphite-Note/Graphite/issues/145)

- [ ] The iPad and iPhone sidebar takes files from other apps on a folder, a file (its folder) and the list (the vault's root), copying them in as the library does; its own items still move. Built 2026-11-09: `VaultSidebar`'s rows and list use `LibraryDropDestination` and `WorkspaceModel.receiveDrop`. Compiled for iOS; not tried with a real drag.
- [ ] The Mac file tree takes files from the Finder, Photos and Mail (file addresses and file promises) the same way; its own items still move. Built 2026-11-09 (`MacFileTree` registers `MacDroppedFiles.pasteboardTypes`). Tested by `UiFileTreeNativeMacTests.testAFileFromTheFinderIsCopiedIntoTheFolderItLandsIn`; promises not tested.
- [x] Tests: the shared reader and plan; a Mac test that the outline accepts a file address drop and imports it. Done 2026-11-09: `LibraryDropReaderTests`, `LibraryDropPlanTests`, `UiFileTreeNativeMacTests.testAFileFromTheFinderIsCopiedIntoTheFolderItLandsIn` (copied, the source kept, a web address refused).
- [ ] Checked on the iPad, the iPhone and the Mac with photos and with other files.
