# Multistart Calculation Telemetry Probe

Question: for repeated starts on one fixed O2 A scene, which forward/Jacobian
calculations look invariant enough to justify session-level reuse?

## Probe

Scene: validation scene 008.

Starts: 5 LHS starts from the multistart sweep generator, using the start value
as the prior.

Boundary: one calculation-telemetry forward/Jacobian probe per start. This is a
first-evaluation dataflow probe, not a full converged OE trace.

Storage policy: each start wrote raw Parquet under `/tmp`, was aggregated, and
was deleted immediately. The retained local scratch output is only the compact
summary under:

```text
out/calculation-telemetry-multistart-scene008-5starts/
```

The retained scratch directory is 24 KiB. The deleted raw chunks were 125-166 MB
per start.

## Result

The scene-invariant instrument-grid reductions were identical:

```text
sampling_kernel_shape: side_sample_count = 1042 for all 5 starts
forward_miss_reuse:   unique_fraction = 1.0 for all 5 starts
```

The state-dependent scalar values were not reusable across starts. No scalar
coordinate group had a near-identical aggregate mean at `1e-12` relative
tolerance. Representative relative spans:

```text
labos_effective_scattering_depth median relative span: 0.896
fourier_weighted_reflectance     median relative span: 0.689
labos_jacobian_norm1             relative span:        0.712
labos_reflectance_clamp          relative span:        0.064
```

The useful signal is structural, not numeric. Some LABOS decision coordinates
keep the same row count and taken-count across the five starts:

| Decision expression | Rows across starts | Coordinate groups | Same-shape groups | Same-shape rows |
| --- | ---: | ---: | ---: | ---: |
| `labos_qseries_skip` | 6,215,332 | 2,861 | 27.8% | 33.3% |
| `labos_qseries_rd_product` | 6,215,332 | 3,253 | 24.2% | 32.7% |
| `labos_qseries_tu_product` | 6,215,332 | 3,253 | 24.0% | 32.6% |
| `labos_qseries_td_product` | 6,215,332 | 3,253 | 23.8% | 32.3% |
| `labos_doubling_trigger` | 869,570 | 345 | 40.6% | 41.9% |
| `fourier_tail_break` | 81,800 | 33 | 9.1% | 9.6% |
| `orders_convergence` | 81,800 | 16 | 0.0% | 0.0% |

## Interpretation

Do not cache full forward/LABOS numeric values across arbitrary starts. AOD and
ALH materially change optical depth, scattering depth, reflectance, and
Jacobian norms.

The better reuse target is prepared structure:

- instrument-grid sampling shape and output buffers;
- route and sparse-stage setup;
- pressure/profile setup that is fixed for the scene;
- decision masks or active-list shapes for LABOS coordinates that stay stable.

The current telemetry can only prove aggregate decision-shape stability because
LABOS rows do not carry OE iteration, start index, or wavelength coordinates.
To make a reusable active-mask decision safely, the next telemetry pass should
add those coordinates or a compact per-forward-evaluation fingerprint.
