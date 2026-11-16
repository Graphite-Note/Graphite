---
tags:
  - guide/markdown
---
# Math

Formulas are written in LaTeX, the language of scientific papers. You only need a little of it.

## Inside a line

**Copy this**

```markdown
Ohm's law, $V = I R$, links voltage and current.
```

**What you see**

Ohm's law, $V = I R$, links voltage and current.

## On lines of their own

**Copy this**

```markdown
$$
P = V \times I = I^2 R = \frac{V^2}{R}
$$
```

**What you see**

$$
P = V \times I = I^2 R = \frac{V^2}{R}
$$

## Several lines, aligned, with numbers

**Copy this**

```markdown
$$
\begin{aligned}
\tau &= R\,C \\
v(t) &= V_0 \left(1 - e^{-t/\tau}\right)
\end{aligned}
\tag{1}
$$
```

**What you see**

$$
\begin{aligned}
\tau &= R\,C \\
v(t) &= V_0 \left(1 - e^{-t/\tau}\right)
\end{aligned}
\tag{1}
$$

## A few pieces of LaTeX

| You type | You get |
| --- | --- |
| `x^2`, `x_i` | $x^2$, $x_i$ |
| `\frac{a}{b}` | $\frac{a}{b}$ |
| `\sqrt{2}` | $\sqrt{2}$ |
| `\alpha \beta \pi \Omega` | $\alpha \beta \pi \Omega$ |
| `\sum_{k=1}^{n} k` | $\sum_{k=1}^{n} k$ |
| `\int_0^1 x\,dx` | $\int_0^1 x\,dx$ |
| `\leq \geq \neq \approx` | $\leq \geq \neq \approx$ |

**Format** › **Math Block** makes an empty block to type into. A long formula wraps to the page instead of running off it.

## On iPad

![[iPad - Math.jpg|420]]
