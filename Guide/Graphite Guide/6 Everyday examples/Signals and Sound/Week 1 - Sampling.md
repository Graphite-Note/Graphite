---
icon: 📈
course: "[[Signals and Sound]]"
week: 1
date: 2026-09-21
tags:
  - lecture
---
# Week 1: Sampling

A microphone turns air pressure into a voltage that changes smoothly. A computer can only keep numbers, so it measures that voltage many times a second: each measurement is a **sample**, and the number of samples per second is the **sampling rate** $f_s$.

## Too slow, and the sound changes

> [!warning] ⚠️
> Sampled too slowly, a high note comes back as a lower one. This is **aliasing**, the same effect that makes a wheel seem to turn backwards in a film.

A tone of frequency $f$ sampled at $f_s$ is heard at

$$
f_{\text{heard}} = \left| f - k f_s \right|, \quad k \text{ the whole number that makes it smallest.}
$$

## Questions for next time

- [ ] A 7 kHz tone sampled at 10 kHz: what do you hear?
- [ ] Why do phones record at 48 kHz and not 30 kHz?

Next: [[Week 2 - Frequencies]].
