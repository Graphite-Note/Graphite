# Reading view speed

## Request

Scrolling the reading view should drop no frame on the iPad and the iPhone. The diagrams speed run of 2026-11-24 (Docs/Native-diagrams-todo.md, Speed, issue #223) made a note full of diagrams scroll without dropped frames by showing its diagrams as pictures; what is left is the reading view's own text blocks, which every note pays for, diagrams or not.

Measured with `DiagramNoteScrollingHostedTests` (a demo note of 35 diagrams under headings and a line of text each, and the same note with each diagram's fence a plain code block, scrolled 30 points a frame by a display link) and `ReadingTextBlockCostHostedTests` (the main thread's work from showing a batch of 24 headings and paragraphs until it is idle), in an iPad Pro 11-inch (M5) and an iPhone 17 Pro simulator of their own, iOS 27.2, Release with testability.

## 1. Text blocks made with less main-thread work

Issue: [#226](https://github.com/Graphite-Note/Graphite/issues/226)

- [x] The selection's gesture recognizers made on first touch. Done 2026-11-24: Textual patch 27 (`UITextInteractionView` adds its `UITextInteraction`, link tap and link gestures the first time a touch, the pointer or a hover finds the view, in `hitTest`, where upstream made a dozen recognizers for every text). A heading or paragraph took 2.1 ms of the main thread to come on screen on the iPad, 1.8 ms after it. Tests: `ReadingLinkFollowingTests`, `PagePreviewCardHostedTests`, `ReadingTasksAndEquationsTests` (synthesized taps, holds and the pointer on links and tags).
- [x] A fragment's text built in its first update, and no geometry readers for overlays it does not need. Done 2026-11-24: Textual patches 28 and 29 (`TextFragment` builds its text in the update that shows it instead of in `onChange` after an empty first layout; rounded backgrounds, attachments and the link tap read the layout only for a text that has them; one block is shown without the block stack); with patch 27 a block costs 1.5 to 1.7 ms (a plain `Text` 0.4 ms; four runs, both simulators). `ObsidianMarkdownParser` resolves the vault folder's links (a file system read) only for a text with a picture of a file. Checked by the hosted tests above and the whole Mac package suite (5,118 tests, 0 failures).
- [ ] A note of code blocks scrolls without dropped frames. The diagram note with its fences as plain code blocks still drops 7 to 18 of 391 frames on the iPad and 4 to 10 of 407 on the iPhone (2026-11-24, 15 to 28 ms of main thread work in the late frames): a code block is Textual's `CodeBlock` with its colored lines, its own horizontal scroll view and the selection's overlay inside it.
- [ ] What SwiftUI spends making a heading or a paragraph, four times a plain `Text`. Ideas, none measured yet: one selection overlay for the whole reading view instead of one view per text (each text makes two UIKit views, and in a frame where one appears the iPad's focus system searches the window, about 2 ms); the text's Markdown parsed off the main actor before it is shown (`FR-103`; 0.05 ms for a one-line block, more for a long paragraph).
- [ ] Checked on a device: the simulators run on the Mac's processor, and the iPad simulator's focus system works as with a hardware keyboard attached.
