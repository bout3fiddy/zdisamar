# O2 A Forward Performance

Scope: one O2 A forward spectrum on the 755-776 nm, 701-output-wavelength
validation route.

The current retained trace is:

```text
low-overhead prepare_o2a              0.057692 s
low-overhead forward elapsed time     1.328534 s
ztracy forward elapsed time           2.443697 s
high-resolution radiance samples  3,874
LABOS Fourier terms             120,390
LABOS layer visits            5,417,550
doubling steps                8,389,666
```

The forward elapsed time is not dominated by writing 701 output values. The instrument
response expands those output wavelengths into 3,874 high-resolution radiance
samples. Each sample builds wavelength-specific optical input and runs LABOS
Fourier transport.

Current retained evidence:

```text
scaffolding/instrumentation/trace/evidence/labos-bottleneck/summary.json
```

Read these notes in order:

- [Measurement provenance](measurement-provenance.md)
- [Current forward elapsed time](current-forward-elapsed-time.md)
- [Optimization history](optimization-history.md)
- [Optimisation notes](optimisation-notes/)
- [Remaining bottlenecks](remaining-bottlenecks.md)
- [Rejected ideas](rejected-ideas.md)
