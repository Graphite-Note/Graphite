# Math

Inline math: $e^{i\pi} + 1 = 0$, a fraction $\frac{a}{b}$, a root $\sqrt{x^2 + y^2}$, Greek $\alpha, \beta, \Gamma$ and a price of 5 dollars that is not math.

## Display formulas

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

$$
\begin{aligned}
X(z) &= \sum_{n=-\infty}^{\infty} x[n] z^{-n} \\
H(z) &= \frac{1 - z^{-1}}{1 - 0.9 z^{-1}}
\end{aligned}
$$

A numbered equation:

$$
E = m c^2 \tag{1}
$$

A matrix:

$$
A = \begin{pmatrix} 1 & 2 & 3 \\ 4 & 5 & 6 \\ 7 & 8 & 9 \end{pmatrix}, \quad
\det\begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc
$$

Cases:

$$
f(x) = \begin{cases} x^2 & x \ge 0 \\ -x & x < 0 \end{cases}
$$

## A long formula

$$
\mathcal{F}\{x(t)\}(f) = \int_{-\infty}^{\infty} x(t)\, e^{-j 2 \pi f t}\, dt = \sum_{k=-\infty}^{\infty} c_k \, \delta\!\left(f - \frac{k}{T}\right) + \lim_{N \to \infty} \frac{1}{N} \sum_{n=0}^{N-1} \left| x[n] \right|^2 \cdot \prod_{m=1}^{M} \left(1 - \frac{f^2}{f_m^2}\right)
$$

## In a list

- $$
  \nabla \cdot \vec{E} = \frac{\rho}{\varepsilon_0}
  $$
- Inline in a list: $\nabla \times \vec{B} = \mu_0 \vec{J}$
