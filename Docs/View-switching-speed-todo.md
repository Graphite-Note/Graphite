# Fast view switching: TODO

Created: 2026-11-09.

Status: not started. Issues: [#146](https://github.com/Graphite-Note/Graphite/issues/146) (section 1), [#147](https://github.com/Graphite-Note/Graphite/issues/147) (section 2).

## Request

The owner, 2026-11-09: "switching views is also slow like really slow". Asked which switch, the owner answered "do some proper testing": measure every switch and fix the slow ones.

## 1. Measure every switch

Issue: [#146](https://github.com/Graphite-Note/Graphite/issues/146)

- [ ] Time, on the iPad simulator and the Mac, with a long note full of tables and pictures and with the owner-shaped vault: Reading view to Live Preview and back, Source mode, another tab, another note in the same tab, List to Library and back, the sidebar's panels, and opening a picture.
- [ ] Record each time and what the main thread spent it on (Instruments Time Profiler or `sample`), in this file.

## 2. Fix the slow ones

Issue: [#147](https://github.com/Graphite-Note/Graphite/issues/147)

- [ ] Every switch measured over 100 ms gets a fix or a written reason; numbers before and after in this file.
- [ ] A test that keeps each fixed switch from doing the slow work again.
- [ ] Checked on the iPad and the Mac.
