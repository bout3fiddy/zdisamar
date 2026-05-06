# O2 A Per-Spectrum Wall

Scope: one O2 A forward spectrum. Retrieval iteration reuse and `prepare_o2a` are excluded.

## Finding

The wall is the exact high-resolution radiance support set. In the instrumented validation case, 701 nominal wavelengths produced 3,874 unique radiance forward solves. `prefetch_forward_samples` took 1.958706 s of a 2.252623 s forward run, about 87% of wall time.

## Measured Split

Representative instrumented timing for the standard O2 A validation spectrum:

```text
forward_model_s=2.252623
prepare_o2a_s=0.175714
sample_count=701
forward_miss_count=3874
prefetch_forward_samples=1958.706ms
wavelength_sampling=283.174ms
collect_forward_misses=3.549ms
integrate_radiance_nominals=3.225ms
integrate_irradiance_nominals=3.286ms
```

Aggregate worker time inside the 3,874 solves:

```text
configured_input_total=3744.483ms  mean=0.967ms/solve
transport_total=14236.660ms        mean=3.675ms/solve
radiance_total=1.067ms
```

LABOS transport split:

```text
labos_samples=3874
fourier_terms=120390               31.076 Fourier terms/solve
rt_layers=10760.022ms              75.6% of LABOS transport
orders=2758.174ms                  19.4% of LABOS transport
attenuation=333.512ms
reflectance=286.904ms
labos_layers=5417550
doubled_layers=1075939
double_steps=8389666
```

Current retained output is still in the same shape: [out/ci/o2a_validation_spectrum/summary.json](../../out/ci/o2a_validation_spectrum/summary.json) has `forward_model_s=2.033145166002214` for 701 samples.

## Code Path

1. [simulate.zig:51-75](../../src/forward_model/instrument_grid/grid_calculation/simulate.zig#L51-L75) builds wavelength plans, collects unique radiance misses, and prefetches every exact-wavelength forward solve before nominal integration.
2. [wavelength_sampling.zig:109-135](../../src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig#L109-L135) computes `unique(bitcast(radiance_wavelength_nm + integration.offset_nm))`. That exact-key policy is why only bit-identical support wavelengths deduplicate.
3. [spectral_forward.zig:256-295](../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L256-L295) runs each worker over its miss slice with reusable scratch.
4. [spectral_forward.zig:228-249](../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig#L228-L249) does the per-wavelength work: configure optical input, execute transport, convert reflectance to radiance.
5. [forward_input.zig:21-103](../../src/forward_model/instrument_grid/grid_calculation/forward_input.zig#L21-L103) builds the wavelength-specific layer, RTM quadrature, source-interface, and pseudo-spherical carriers.
6. [execute.zig:245-340](../../src/forward_model/radiative_transfer/labos/execute.zig#L245-L340) loops Fourier terms, builds RT layers, propagates scattering orders, and adds the weighted Fourier reflectance contribution.

## Exact Work Count

Let `lambda_i` be each nominal radiance wavelength and `delta_ij` be the instrument integration offsets for that nominal sample.

```text
Lambda_forward = unique(bitcast(lambda_i + delta_ij))
N_forward = |Lambda_forward| = 3874
```

For each `lambda`:

```text
T(lambda) = T_configured_input(lambda)
          + sum_m [T_Plm(m) + T_RT_layers(lambda, m)
                   + T_orders(lambda, m) + T_reflectance(lambda, m)]
```

The measured sum over all `lambda` had `120390` Fourier terms. The wall is therefore not `701` output samples; it is approximately `3874 * 31` Fourier evaluations, with active layer/doubling work below each Fourier term.

## Optimization Boundary

The optimized path has already removed avoidable overhead: carrier caches, LABOS workspaces, fixed-size matrix kernels, Fourier tail cutoffs, active-layer skips, and unused local-order accumulation. The remaining wall is call-count times core math. Further per-spectrum wins need to reduce `N_forward`, reduce active Fourier/layer/doubling work per solve, or replace a math primitive without changing DISAMAR parity.
