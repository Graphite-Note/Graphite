---
course: "[[Everyday Electronics]]"
week: 2
date: 2026-11-16
tags:
  - lecture
---
# Week 2: Capacitors

A capacitor stores charge, like a small bucket for electricity. With a resistor in front of it, it fills slowly: that is how a camera flash charges and why a light can fade out gently.

## The RC circuit

Drawn in class with Apple Pencil, inside this note:

![[Circuit drawing.png|460]]

Tap the drawing's **Edit** button to change it stroke by stroke. See [[Drawings in notes]].

## How fast it fills

The time constant is $\tau = R C$. After one $\tau$ the capacitor is about 63 % full; after five it is practically full:

$$
v(t) = V_0 \left(1 - e^{-t/\tau}\right)
$$

```mermaid
xychart-beta
    title "Charging, as a share of full"
    x-axis "time constants" [0, 1, 2, 3, 4, 5]
    y-axis "percent" 0 --> 100
    line [0, 63, 86, 95, 98, 99]
```

## Questions for next time

- [ ] Why does a bigger capacitor take longer to fill?
- [ ] What happens if $R$ is halved?

Back to [[Everyday Electronics]], or the slides from [[Week 1 - Voltage and current|week 1]].
