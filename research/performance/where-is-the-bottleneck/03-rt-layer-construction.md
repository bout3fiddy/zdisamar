# 03. RT-Layer Construction

RT-layer construction takes `8.026027 s`, which is `69.888%` of aggregate LABOS CPU. This is the largest child inside the Fourier loop.

What that means: for every active Fourier term, LABOS walks the atmospheric layers and builds a reflection/transmission pair for each layer that can contribute. The trace counted `5,417,550` layer visits. Most of those visits are cheap skips: `4,133,184` visits are skipped because the current Fourier term is outside that layer's phase-function range. The expensive subset still contains `1,284,366` phase matrix builds, `1,075,939` doubled layers, and `8,389,666` doubling steps.

This is already one of the optimizations from the earlier performance work: [layers and Fourier terms that cannot contribute are skipped](../why-zdisamar-is-faster/07-skip-empty-layer-work.md), and [tiny Fourier tails stop early](../why-zdisamar-is-faster/08-fourier-tail-and-basis-reuse.md). The remaining cost is the subset that still has active phase coefficients and scattering optical depth.

The layer walk is in [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L340-L367):

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

Once a layer survives those skips, it enters the expensive path in [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L369-L463):

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
    const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
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
    doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, geo, b_start, &R, &T, &E, trace);
}
```

The measured split inside active RT-layer construction is: phase matrix construction costs `1.038334 s`; effective-scattering scans cost `0.043808 s`; initial exponentials cost `0.074818 s`; single-scatter setup costs `0.201130 s`; phase renormalization costs `0.055815 s`; and layer doubling costs `6.036863 s`. The conclusion is direct: RT-layer construction dominates because it contains the doubling loop, and the doubling loop is repeated 8.39 million times for this spectrum.
