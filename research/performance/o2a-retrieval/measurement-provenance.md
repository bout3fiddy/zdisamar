# Measurement Provenance

The current paired retrieval evidence is the tracked plot manifest:

```text
validation/outputs/optimal_estimation/paired_oe_plot_manifest.json
```

The generated parquet and per-case DISAMAR directories live under:

```text
out/validation/optimal_estimation/paired_disamar_zdisamar/
```

Those `out/` files are local generated evidence and are intentionally
gitignored. The tracked record is the manifest and plots under:

```text
validation/outputs/optimal_estimation/
```

The current slow-case latency benchmark is:

```text
validation/outputs/optimal_estimation/zdisamar_o2a_slow_forward_jacobian_benchmark.json
```

The paired scene ranges follow the geometry, aerosol, meteorology, and surface
parameter ranges from the AMT 2019 O2 A aerosol-height retrieval study,
`https://doi.org/10.5194/amt-12-6619-2019`, narrowed here to sensible
cloud-free aerosol-only validation ranges.

Regenerate the paired sweep and plots with:

```sh
uv run validation/optimal_estimation/paired_disamar_zdisamar_sweep.py
```
