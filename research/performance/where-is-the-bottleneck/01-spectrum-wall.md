# 01. Spectrum Wall

The retained trace measured `1.958912208 s` of forward wall time. That wall starts from `701` output wavelengths, but those are only the final instrument grid. Before zdisamar can write those 701 values, it has to calculate `3,874` unique high-resolution radiance samples.

Most of the wall is spent prefetching those high-resolution samples. The prefetch section takes `1.670045 s`, or `85.254%` of the full forward wall. Wavelength sampling takes another `0.279496 s`, while the final integration back to the output grid is only a few milliseconds. In practical terms: the expensive step is not "write 701 outputs"; it is "run thousands of exact radiance calculations that the instrument response needs."

The handoff happens in [simulate.zig](../../../src/forward_model/instrument_grid/grid_calculation/simulate.zig#L54-L84):

```zig
// Build the 701 output-wavelength sampling plan. This decides which
// high-resolution radiance wavelengths are needed by the instrument response.
const wavelength_sampling = try WavelengthSampling.buildWavelengthSampling(
    allocator,
    scene,
    prepared,
    &resolved_axis,
    radiance_calibration,
    irradiance_calibration,
    implementations,
);

// Collapse the sampling plan to unique high-resolution forward-model misses.
const forward_misses = try WavelengthSampling.collectUniqueForwardMisses(
    allocator,
    wavelength_sampling,
);

// This is the 1.67 s wall section: calculate all missing high-resolution
// radiance samples before integrating them back to the 701 output grid.
try SpectralEval.prefetchForwardSamples(
    allocator,
    scene,
    route,
    prepared,
    implementations,
    safe_span,
    forward_misses,
    evaluation_cache,
);
```

Each miss then becomes a worker-local forward sample in [spectral_forward.zig](../../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L330-L392):

```zig
const worker_count = preferredForwardWorkerCount(misses.len);
run.addCounter(.high_resolution_misses, @intCast(misses.len));

for (0..worker_count) |worker_index| {
    // The 3,874 high-resolution samples are split across workers.
    workers[worker_index] = .{
        .misses = misses[start_index..end_index],
        .results = results[start_index..end_index],
        .trace = trace_ref,
        .worker_index = worker_index,
    };
}
```

That is why the spectrum wall is dominated by high-resolution radiance prefetch: each miss runs wavelength-specific optical input and then LABOS transport.

## Simple Python Shape

The expensive count is the unique high-resolution radiance list, not the final output wavelength list:

```python
output_wavelengths = range(701)

# Each output wavelength asks the instrument response for nearby
# high-resolution radiance samples. Many outputs overlap.
needed = []
for output_wavelength in output_wavelengths:
    needed.extend(high_resolution_support(output_wavelength))

# zdisamar calculates each unique high-resolution wavelength once.
unique_samples = sorted(set(needed))
for wavelength in unique_samples:          # 3,874 samples in the trace
    cache[wavelength] = run_forward_model(wavelength)

# The cheap final step integrates cached samples back to 701 outputs.
for output_wavelength in output_wavelengths:
    spectrum[output_wavelength] = integrate_from_cache(output_wavelength, cache)
```

That is why `forward_prefetch_wall` dominates and output-grid integration is tiny.
