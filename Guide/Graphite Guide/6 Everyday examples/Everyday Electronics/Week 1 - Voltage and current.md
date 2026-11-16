---
course: "[[Everyday Electronics]]"
week: 1
date: 2026-11-09
slides: "[[Week 1 slides.pdf]]"
tags:
  - lecture
---
# Week 1: Voltage and current

> [!abstract] In one line
> Voltage pushes, current flows, resistance holds back: $V = I R$.

## Ohm's law

![[Week 1 slides.pdf#page=2&height=320]]

Voltage $V$ in volts, current $I$ in amperes, resistance $R$ in ohms:

$$
V = I R \qquad\Longleftrightarrow\qquad I = \frac{V}{R}
$$

Doubling the voltage across the same resistor doubles the current.

## Power

Power is what the electricity bill counts:

$$
P = V I = I^2 R = \frac{V^2}{R}
$$

| Appliance | Voltage | Current | Power |
| --- | ---: | ---: | ---: |
| Phone charger | 5 V | 2 A | 10 W |
| Torch | 3 V | 0.3 A | 0.9 W |
| Kettle | 230 V | 8.7 A | ≈ 2,000 W |

## Series and parallel

![[Week 1 slides.pdf#page=3&height=320]]

In series, resistances add: $R = R_1 + R_2$. In parallel, $\frac{1}{R} = \frac{1}{R_1} + \frac{1}{R_2}$. Lamps in a house are in parallel, which is why one broken bulb leaves the others on.

## Exercise

A kettle draws 8.7 A from 230 V. What is its power, and how long does it take to use 1 kWh?

> [!example]- Solution
> $P = 230 \times 8.7 \approx 2{,}000\ \text{W} = 2\ \text{kW}$, so 1 kWh takes $\frac{1}{2}$ hour.

Next week: [[Week 2 - Capacitors]].
