# Where Is The Bottleneck?

Scope: one O2 A forward spectrum, using the same 755-776 nm, 701-output-wavelength validation scene used by the retained O2 A performance notes.

This folder explains the current forward wall from the outside in:

```text
forward wall                         1.958912 s
high-resolution radiance samples        3,874
Fourier terms                         120,390
LABOS layer visits                  5,417,550
doubled layers                      1,075,939
doubling steps                      8,389,666
```

The trace is intentionally disabled in normal builds. The trace-enabled binary is built from a separate build-options module where `enable_labos_trace=true`; normal modules set `enable_labos_trace=false`, and trace references become zero-sized types in that configuration.

## Documents

- [00. Methodology](00-methodology.md): how the trace is layered, why wall time and worker CPU time are reported separately, and how to regenerate the artifacts.
- [01. Spectrum wall](01-spectrum-wall.md): why the 1.959 s wall is mostly high-resolution radiance prefetch, not 701 output sampling.
- [02. LABOS top level](02-labos-top-level.md): the split between wavelength-specific optical input, LABOS execution, RT-layer construction, orders, and reflectance integration.
- [03. RT-layer construction](03-rt-layer-construction.md): why layer construction is the dominant LABOS block.
- [04. Layer doubling](04-layer-doubling.md): why the doubling loop is the main final-frontier calculation.
- [05. Phase-matrix construction](05-phase-matrix-construction.md): the remaining phase-kernel cost after PLM basis reuse.
- [06. Scattering orders](06-scattering-orders.md): the multiple-scattering order loop and dot-pair volume.
- [07. Small matrix primitives](07-small-matrix-primitives.md): call counts, microbench timings, and estimated primitive CPU cost.
- [08. Assembly notes](08-assembly-notes.md): when assembly-level inspection is useful and what the current trace implies.

## Evidence

Retained generated artifacts live under:

```text
validation/outputs/performance/labos-bottleneck/
```

The main files are:

- `summary.json`
- `sections.csv`
- `counters.csv`
- `worker_sections.csv`
- `labos_kernel_bench.txt`
- `primitive_estimates.csv`
- `rollup.json`

Regenerate them with:

```sh
research/performance/where-is-the-bottleneck/run-labos-bottleneck-trace.sh
```
