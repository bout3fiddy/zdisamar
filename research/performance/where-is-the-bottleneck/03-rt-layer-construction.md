# 03. RT-Layer Construction

RT-layer construction takes `6.497375 s`, which is `68.755%` of aggregate LABOS CPU. This is the largest child inside the Fourier loop.

What that means: for every active Fourier term, LABOS walks the atmospheric layers and builds a reflection/transmission pair for each layer that can contribute. The trace counted `5,417,550` layer visits. Most of those visits are cheap skips: `4,133,184` visits are skipped because the current Fourier term is outside that layer's phase-function range. The expensive subset still contains `1,284,366` phase matrix builds, `1,075,939` doubled layers, and `8,389,666` doubling steps.

This is already one of the optimizations from the earlier performance work: [layers and Fourier terms that cannot contribute are skipped](../why-zdisamar-is-faster/07-skip-empty-layer-work.md), and [tiny Fourier tails stop early](../why-zdisamar-is-faster/08-fourier-tail-and-basis-reuse.md). The remaining cost is the subset that still has active phase coefficients and scattering optical depth.

The layer walk is in [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L344-L367):

```zig
for (0..nlayer) |layer_idx| {
    // One trace "layer visit". This happened 5,417,550 times.
    const layer = layers[layer_idx];

    // Cheap skip: this Fourier order is outside the global basis range.
    if (i_fourier >= basis.max_phase_coef) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        continue;
    }

    // Cheap skip: this Fourier order is outside this layer's phase range.
    if (i_fourier > max_phase_index) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        continue;
    }

    // Cheap skip: no optical depth or no scattering means the layer cannot
    // contribute to this Fourier term.
    if (layer.optical_depth < 1.0e-20 or layer.scattering_optical_depth <= 0.0) {
        rt[rt_idx] = zeroLayerRt(geo.nmutot);
        continue;
    }
}
```

Once a layer survives those skips, it enters the expensive path in [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L374-L466):

```zig
// Build Zplus/Zmin phase matrices for this active layer/Fourier pair.
var z = basis.fillZplusZminFromBasisLimited(
    i_fourier,
    phase_coefs,
    max_phase_index,
    geo,
    plm_basis,
);

// Scan phase coefficients to decide whether the layer is optically thick
// enough to require doubling.
for (i_fourier..max_phase_index + 1) |ic| {
    const beta_eff = @abs(phase_coefs[ic]) * phase_odd_reciprocal[ic];
    if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
}

// If multiple scattering through the layer is too thick for the starting
// layer, split it and repeatedly double it back up.
if (controls.scattering == .multiple and a_eff * b > controls.threshold_doubl) {
    use_doubling = true;
    while (a_eff * bd >= controls.threshold_doubl) {
        bd /= 2.0;
        ndouble += 1;
    }
}

if (use_doubling) {
    doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, &R, &T, &E, trace);
}
```

The measured split inside active RT-layer construction is: phase matrix construction costs `1.020827 s`; effective-scattering scans cost `0.041305 s`; initial exponentials cost `0.076714 s`; single-scatter setup costs `0.185008 s`; phase renormalization costs `0.055546 s`; and layer doubling costs `4.536551 s`. The conclusion is direct: RT-layer construction dominates because it contains the doubling loop, and the doubling loop is repeated 8.39 million times for this spectrum.

## Simple Python Shape

RT-layer construction is a repeated layer walk with cheap skips and an expensive active path:

```python
for wavelength in high_resolution_samples:
    for fourier in active_fourier_terms(wavelength):
        for layer in atmosphere_layers:
            visits += 1

            if fourier > layer.max_phase_index:
                skipped += 1
                continue

            if layer.optical_depth == 0 or layer.single_scatter_albedo == 0:
                skipped += 1
                continue

            zplus, zmin = build_phase_matrices(layer, fourier)
            r, t = build_single_scatter_layer(layer, zplus, zmin)

            if needs_doubling(layer):
                r, t = double_until_original_thickness(r, t, layer)
```

Most visits are filtered out. The bottleneck is the active remainder that still has to build phase matrices and run layer doubling.
