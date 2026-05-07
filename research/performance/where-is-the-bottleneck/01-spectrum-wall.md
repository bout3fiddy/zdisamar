# 01. Spectrum Wall

The retained trace measured:

```text
forward wall                  1.958912208 s
output wavelengths                    701
high-resolution misses               3,874
workers                                 10
```

The dominant wall section is high-resolution forward prefetch:

```text
forward prefetch wall         1.670045 s   85.254% of wall
wavelength sampling           0.279496 s   14.268% of wall
radiance cache integration    0.002981 s    0.152% of wall
irradiance sampling           0.003161 s    0.161% of wall
```

The 701 output wavelengths are not the expensive count. They are the final measurement grid. The expensive count is the 3,874 high-resolution radiance samples needed before those output wavelengths can be assembled.

The structure is:

```text
701 output wavelengths
-> 3,874 high-resolution radiance samples
-> each sample runs wavelength-specific optical input
-> each sample runs LABOS transport
```

The post-prefetch integration back to the output grid is tiny. The wall is the high-resolution radiance stage.
