# Perturbation Sensitivity Analysis Report

## Run

- Summary artifact: `out/scaffolding/perturbation/data/o2a-default/summary.json`
- Storage policy: `compact_summary_only`
- Spectrum: 758.000-770.000 nm, 241 samples
- Experiments: 17
- Baseline retrieval: AOD=3.000018451e-01, mid-pressure=510.007339 hPa, iterations=3
- Summary file size: 23.6 KiB

## Learnings

- No perturbation was exactly neutral once both spectrum and retrieval state were checked. That means the current candidates need tolerance-bounded, not zero-difference, optimization rules.
- Near-neutral candidates under max reflectance 1e-6, AOD 1e-5, and pressure 1e-2 hPa: fourier_zero_ge_8, fourier_zero_ge_12, fourier_zero_ge_16, fourier_zero_ge_24, fourier_tail_stop_ge_8, fourier_tail_stop_ge_12, fourier_tail_stop_ge_16, aod_tangent_zero_ge_12, pressure_tangent_zero_ge_12.
- The q-zero downstream gates are the cleanest redundancy test: they only act inside already-recognized q-series skip branches and directly count avoided matrix-product decisions.
- Forcing q-series skip itself is not safe in this run: it suppresses millions of gates, but moves reflectance by about 2.4e-3 and pressure by about 21.5 hPa.
- Stopping scattering orders too early is also visibly sensitive: order 8 still moves reflectance by about 1.4e-4 and pressure by about 1.56 hPa.
- Fourier and scattering-order perturbations are useful as threshold probes, but large residuals there mean any production optimization should be framed as a tighter convergence rule, not unconditional deletion.
- Tangent perturbations show retrieval sensitivity separately from forward reflectance sensitivity; these channels are where OE-specific pruning needs to be judged.

## Near-Neutral Candidates

| Experiment | Changed / Hit | Max abs refl delta | AOD abs delta | Pressure abs delta hPa |
| --- | ---: | ---: | ---: | ---: |
| `fourier_zero_ge_8` | 255831 / 342268 | 6.170e-07 | 5.171e-06 | 1.830e-03 |
| `fourier_zero_ge_12` | 217104 / 342268 | 4.542e-07 | 3.806e-06 | 1.348e-03 |
| `fourier_zero_ge_16` | 178676 / 342268 | 2.386e-07 | 1.999e-06 | 7.082e-04 |
| `aod_tangent_zero_ge_12` | 162715 / 256566 | 0.000e+00 | 4.258e-11 | 1.365e-07 |
| `pressure_tangent_zero_ge_12` | 162715 / 256566 | 0.000e+00 | 8.172e-11 | 1.431e-06 |
| `fourier_zero_ge_24` | 101832 / 342268 | 7.433e-09 | 6.229e-08 | 2.206e-05 |
| `fourier_tail_stop_ge_8` | 9751 / 96199 | 5.726e-07 | 4.799e-06 | 1.698e-03 |
| `fourier_tail_stop_ge_12` | 9607 / 134771 | 4.322e-07 | 3.622e-06 | 1.282e-03 |
| `fourier_tail_stop_ge_16` | 9607 / 173199 | 1.973e-07 | 1.654e-06 | 5.852e-04 |

## Highest Work Suppression

| Experiment | Changed / Hit | Max abs refl delta | AOD abs delta | Pressure abs delta hPa |
| --- | ---: | ---: | ---: | ---: |
| `qseries_skip_ge_3` | 9882816 / 24615914 | 2.443e-03 | 2.292e-02 | 2.150e+01 |
| `qseries_skip_ge_5` | 9432179 / 24615914 | 2.443e-03 | 2.292e-02 | 2.150e+01 |
| `qzero_td_suppress` | 1143287 / 24518666 | 3.540e-06 | 2.850e-05 | 2.769e-02 |
| `qzero_rd_suppress` | 563874 / 24518833 | 1.050e-06 | 8.527e-06 | 6.642e-03 |
| `qzero_tu_suppress` | 396775 / 24518833 | 1.002e-06 | 8.132e-06 | 6.390e-03 |

## Largest Spectral Movement

| Experiment | Changed / Hit | Max abs refl delta | AOD abs delta | Pressure abs delta hPa |
| --- | ---: | ---: | ---: | ---: |
| `orders_stop_ge_4` | 76051 / 349754 | 8.918e-03 | 1.332e-01 | 1.205e+02 |
| `qseries_skip_ge_5` | 9432179 / 24615914 | 2.443e-03 | 2.292e-02 | 2.150e+01 |
| `qseries_skip_ge_3` | 9882816 / 24615914 | 2.443e-03 | 2.292e-02 | 2.150e+01 |
| `orders_stop_ge_6` | 48007 / 488310 | 1.117e-03 | 9.100e-03 | 1.179e+01 |
| `orders_stop_ge_8` | 22691 / 430398 | 1.448e-04 | 1.070e-03 | 1.560e+00 |

## Largest Retrieval Movement

| Experiment | Changed / Hit | Max abs refl delta | AOD abs delta | Pressure abs delta hPa |
| --- | ---: | ---: | ---: | ---: |
| `orders_stop_ge_4` | 76051 / 349754 | 8.918e-03 | 1.332e-01 | 1.205e+02 |
| `qseries_skip_ge_5` | 9432179 / 24615914 | 2.443e-03 | 2.292e-02 | 2.150e+01 |
| `qseries_skip_ge_3` | 9882816 / 24615914 | 2.443e-03 | 2.292e-02 | 2.150e+01 |
| `orders_stop_ge_6` | 48007 / 488310 | 1.117e-03 | 9.100e-03 | 1.179e+01 |
| `orders_stop_ge_8` | 22691 / 430398 | 1.448e-04 | 1.070e-03 | 1.560e+00 |

## Fast Benchmark Canary

- Source: `benchmark/fast_results.json`
- Forward fast-mode median: 2.397986 s
- OE session retrieval median: 1.072964 s
- OE sweep session total median: 8.587983 s

## Storage Discipline

The sweep writes one compact JSON summary. It does not write per-expression rows, per-wavelength residual tables, or a database. Spectra are held only long enough to compute aggregate residuals, then discarded.

## Next Actions

- Promote only tolerance-stable findings into production math changes; the research hooks themselves should stay behind the compile-time build option.
- Expand the scene set after the first actionable candidate appears; the current compact schema can add scene ids without changing the product path.
