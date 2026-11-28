---
icon: 🔁
course: "[[Signals and Sound]]"
date: 2026-10-08
tags:
  - lab
---
# Lab 2: An echo

An echo is the same sound, later and quieter, added to itself:

$$
y[n] = x[n] + 0.5\, x[n - D]
$$

With $D = 12\,000$ samples at 48 kHz, the echo comes back after a quarter of a second.

- [ ] Add the echo to your recording from [[Lab 1 - Recording a tone]]
- [ ] Try $D$ = 480, 4,800 and 24,000: when does it stop sounding like a room and start sounding like a canyon?
- [ ] Write the echo as a filter, as in [[Week 3 - Filters]]
