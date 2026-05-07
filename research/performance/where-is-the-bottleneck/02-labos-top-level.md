# 02. LABOS Top Level

The worker CPU trace measured:

```text
configured forward input      3.927454 s
LABOS execute                11.484103 s
```

These are aggregate worker CPU times, not wall times. The forward wall is lower because 10 workers overlap.

Inside LABOS, the scopes are nested. `Fourier loop` is the parent scope that contains RT-layer construction, orders, PLM basis work, reflectance integration, and a small amount of loop overhead. Do not add the parent percentage to its children.

```text
Fourier loop                 11.080734 s   96.488% of LABOS CPU
non-Fourier LABOS overhead    0.403369 s    3.512% of LABOS CPU
```

Inside the Fourier loop:

```text
RT-layer build                8.026027 s   69.888% of LABOS CPU
orders total                  2.826031 s   24.608% of LABOS CPU
reflectance integral          0.190831 s    1.662% of LABOS CPU
PLM basis                     0.006664 s    0.058% of LABOS CPU
loop overhead and tail checks  0.031181 s    0.272% of LABOS CPU
```

The important result is that the remaining wall is not setup, allocation, or output-grid assembly. It is the exact LABOS Fourier transport calculation.

The loop shape is:

```text
for high-resolution wavelength:
  build wavelength-specific optical input
  for Fourier order:
    build/reuse basis
    build RT layers
    propagate scattering orders
    integrate reflectance contribution
```

That makes RT-layer construction and scattering orders the next two layers to explain.
