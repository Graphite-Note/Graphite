---
notion-id: c98da037ffb92e28286230345c72d7ec
---
# Fourier series

A periodic signal is a sum of sines: **bold**, _italic_, `inline code`, ==highlighted== and ~~struck~~.

Inline math: $x(t) = \sum_k a_k e^{jk\omega_0 t}$ for every t.

$$a_k = \frac{1}{T} \int_T x(t) e^{-jk\omega_0 t} \, dt$$

> [!important] Remember: the coefficients of a real signal are conjugate symmetric.

- Why does it converge?
    
	Because the signal has finite energy over a period.
    

## Worked example

A square wave has only odd harmonics.

```Python
import numpy
coefficients = numpy.fft.fft(samples) / len(samples)
```

- [x] Read chapter 3

- Linear
	- Time invariant

1. Sample
2. Transform

> Everything is a filter.

---

|Signal|Period|
|---|---|
|Square|T|
|Sawtooth|2T|

![[spectrum plot.png]]

The spectrum

![[Problem set 1.pdf]]

> [!info] Fourier series notes  
> An invented reference page.  
> https://example.com/fourier  

[[Lectures]]