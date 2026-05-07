# Where Is The Bottleneck?

Scope: one O2 A forward spectrum, using the same 755-776 nm, 701-output-wavelength validation scene used by the retained O2 A performance notes.

This folder explains the current forward wall from the outside in. The retained run takes `1.958912 s` of caller-visible wall time. That wall is not 701 independent wavelength calculations. The instrument response expands the 701 output wavelengths into `3,874` high-resolution radiance samples; those samples run `120,390` LABOS Fourier terms; those Fourier terms visit `5,417,550` layer/Fourier combinations; and the active layer subset performs `8,389,666` doubling steps.

That chain is the bottleneck: the individual kernels are already small, but the exact O2 A calculation repeats them at spectrum scale.

The trace is intentionally disabled in normal builds. The trace-enabled binary is built from a separate build-options module where `enable_labos_trace=true`; normal modules set `enable_labos_trace=false`, and trace references become zero-sized types in that configuration.

The trace run itself is wired in [labos_bottleneck_trace_cli.zig](../../../src/validation/performance/labos_bottleneck_trace_cli.zig#L60-L75):

```zig
var trace = Trace.Run.init();
var implementations = internal.forward_model.implementations.exact();
implementations.trace = &trace;

const product = try InstrumentGrid.simulateProductWithWorkspace(
    allocator,
    &storage,
    &prepared_case.scene,
    prepared_case.route,
    &prepared_case.prepared,
    implementations,
);
```

That is the only path that installs a live trace sink. Normal forward calls keep the trace reference zero-sized.

## Simple Python Shape

The whole folder is explaining this multiplication of work:

```python
output_wavelengths = 701
high_resolution_samples = 3_874
fourier_terms = 120_390
layer_visits = 5_417_550
doubling_steps = 8_389_666

print(high_resolution_samples / output_wavelengths)  # about 5.5 radiance samples per output
print(fourier_terms / high_resolution_samples)       # about 31 Fourier terms per sample
print(doubling_steps / layer_visits)                 # many visits are cheap skips
```

The bottleneck is not one big operation. It is many small exact operations repeated through this hierarchy.

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
