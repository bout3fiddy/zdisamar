# Current Forward Elapsed Time

Current retained artifact:

```text
research/performance/tracing/output/labos-bottleneck/summary.json
```

Top-level timing:

```text
prepare_o2a                      0.177154 s
forward elapsed time             1.799918 s
workers                                10
output wavelengths                     701
high-resolution samples              3,874
```

Elapsed-time split:

```text
wavelength sampling         0.281548 s
forward prefetch            1.508676 s
final radiance integration  0.003147 s
irradiance sampling         0.003423 s
```

`forward_prefetch_wall` is the artifact field name for the expensive elapsed
section. It calculates the
high-resolution radiance samples before they are averaged back to the output
grid.

Worker CPU is larger than elapsed time because the high-resolution radiance samples
run across workers:

```text
wavelength-specific optical input   4.055074 s aggregate CPU
LABOS transport                     9.777328 s aggregate CPU
```

Inside LABOS:

```text
Fourier loop              9.351779 s
RT-layer construction     6.783443 s
layer doubling            4.777200 s
scattering orders         2.327972 s
phase matrix build        1.040362 s
reflectance integral      0.198543 s
PLM basis                 0.008432 s
```

The stable counts are:

```text
LABOS Fourier terms      120,390
layer visits           5,417,550
doubled layers         1,075,939
doubling steps         8,389,666
dotGaussPair calls   295,581,240
```

The concise model is:

```text
701 output wavelengths
-> 3,874 high-resolution radiance samples
-> 120,390 Fourier terms
-> millions of layer, doubling, and orders operations
```
