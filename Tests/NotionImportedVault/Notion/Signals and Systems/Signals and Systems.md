---
notion-id: 10000000-0000-4000-8000-00000000a001
---
# Fourier series

A periodic signal is a sum of **sines**.

$$
a_k = \frac{1}{T} \int_T x(t) e^{-jk\omega_0 t} \, dt
$$

```python
coefficients = numpy.fft.fft(samples)
```

> [!tip] 💡
> Coefficients of a real signal are conjugate symmetric.

> [!note]+ Why does it converge?
> Because the signal has finite energy over a period.

- [x] Read chapter 3
- Linear

![[Lectures.base]]