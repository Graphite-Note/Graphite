---
icon: 🎚️
course: "[[Signals and Sound]]"
week: 3
date: 2026-10-05
tags:
  - lecture
---
# Week 3: Filters

A filter keeps some frequencies and weakens others. The bass and treble knobs of a speaker are filters; so is a wall, which lets the bass of the neighbours' music through and keeps the rest.

## The simplest one

The average of the last two samples smooths a signal, so it keeps low frequencies and weakens high ones:

$$
y[n] = \frac{x[n] + x[n-1]}{2}
$$

```mermaid
flowchart LR
    In[Microphone] --> Filter[Average of two samples] --> Out[Speaker]
```

> [!tip] 💡
> Hearing is the best check: play a recording before and after the filter, and listen for what is gone.

Practice: [[Lab 2 - An echo]].
