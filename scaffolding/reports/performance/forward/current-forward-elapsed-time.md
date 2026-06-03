# Current Forward Elapsed Time

Current retained artifact:

```text
scaffolding/instrumentation/trace/evidence/lauka-forward/forward-run/summary.json
```

Top-level low-overhead timing from the Lauka forward wrapper:

```text
prepare_o2a                      0.057692 s
forward elapsed time             1.328534 s
output wavelengths                     701
high-resolution samples              3,874
```

The accompanying Lauka report records seven forward-only runs:

```text
mean wall time              1.40 s
peak RSS                    182 MB
fixed cycles                165 M
fixed instructions          106 M
```

The timeline trace artifact is:

```text
scaffolding/instrumentation/trace/evidence/labos-bottleneck/summary.json
```

That run is built with ztracy instrumentation enabled. Its current coarse
summary is:

```text
prepare_o2a                      0.045665 s
forward elapsed time             2.443697 s
```

Use the ztracy capture for nested timing, thread overlap, and per-zone evidence.
Use the Lauka wrapper or a non-ztracy harness run for elapsed-time comparisons.

The stable route shape is unchanged:

```text
701 output wavelengths
-> 3,874 high-resolution radiance samples
-> 120,390 LABOS Fourier terms
-> millions of layer, doubling, and orders operations
```

The last detailed pre-ztracy trace that retained operation counters reported:

```text
LABOS Fourier terms      120,390
layer visits           5,417,550
doubled layers         1,075,939
doubling steps         8,389,666
dotGaussPair calls   295,581,240
```
