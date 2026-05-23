# Full-Spectrum Calculation Telemetry Sweep

This sweep is the first retained data set for expression-level math analysis
across a retrieval-like O2 A window.

## Capture Settings

- Path: `research/data-pipeline/data/full-spectrum-758-770-ms/`
- Spectral range: 758-770 nm
- Output samples: 401
- High-resolution step: 0.1 nm
- Radiative transfer: multiple-scattering LABOS
- Aerosol layer placement: default explicit interval bounds, 500-520 hPa
- Data format: direct Parquet from `parquet_lite.zig`

Each scene directory contains:

```text
expression_catalog.parquet
scalar_expression_rows.parquet
reduction_expression_rows.parquet
decision_rows.parquet
run.json
run_summary.json
```

The sweep root also contains:

```text
scene_catalog.parquet
sweep_manifest.json
```

## Data Volume

- Scenes: 12
- Total event rows: 89,933,390
- Total Parquet bytes: 2,470,814,164
- Sum of forward wall time: 83.41 s
- Smallest scene: 1,374,609 event rows
- Largest scene: 14,857,004 event rows

## Scene Catalog

| Scene | Albedo | AOD | SSA | g | SZA/VZA/RAA | Rows | MB | Forward s |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| sza45_vza00_raa000_dark_clean | 0.05 | 0.08 | 1.00 | 0.62 | 45/0/0 | 1,374,609 | 40.1 | 1.48 |
| sza45_vza00_raa000_mid_hazy | 0.20 | 0.80 | 0.94 | 0.78 | 45/0/0 | 1,435,719 | 41.6 | 1.55 |
| sza45_vza00_raa000_bright_dense | 0.45 | 1.50 | 0.90 | 0.82 | 45/0/0 | 1,456,089 | 42.1 | 1.60 |
| sza60_vza30_raa120_dark_clean | 0.05 | 0.08 | 1.00 | 0.62 | 60/30/120 | 6,226,840 | 173.1 | 5.55 |
| sza60_vza30_raa120_mid_reference | 0.20 | 0.30 | 1.00 | 0.70 | 60/30/120 | 8,274,390 | 227.6 | 7.33 |
| sza60_vza30_raa120_bright_hazy | 0.45 | 0.80 | 0.94 | 0.78 | 60/30/120 | 11,372,335 | 310.4 | 10.52 |
| sza70_vza50_raa060_dark_hazy | 0.05 | 0.80 | 0.94 | 0.78 | 70/50/60 | 11,749,949 | 321.6 | 10.75 |
| sza70_vza50_raa060_mid_dense | 0.20 | 1.50 | 0.90 | 0.82 | 70/50/60 | 14,857,004 | 404.6 | 13.76 |
| sza70_vza50_raa060_bright_clean | 0.45 | 0.08 | 1.00 | 0.62 | 70/50/60 | 6,306,404 | 175.2 | 5.73 |
| sza35_vza20_raa170_dark_dense | 0.05 | 1.50 | 0.90 | 0.82 | 35/20/170 | 12,955,836 | 350.0 | 12.23 |
| sza35_vza20_raa170_mid_clean | 0.20 | 0.08 | 1.00 | 0.62 | 35/20/170 | 5,994,742 | 166.5 | 5.49 |
| sza35_vza20_raa170_bright_reference | 0.45 | 0.30 | 1.00 | 0.70 | 35/20/170 | 7,929,473 | 217.9 | 7.40 |

## First Queries

```python
from pathlib import Path

import polars as pl

root = Path("research/data-pipeline/data/full-spectrum-758-770-ms")
scenes = pl.read_parquet(root / "scene_catalog.parquet")

decision = pl.scan_parquet(str(root / "*" / "decision_rows.parquet"))
catalog = pl.scan_parquet(str(root / "*" / "expression_catalog.parquet")).unique(
    subset=["expr_id"]
)

decision.join(catalog.select("expr_id", "expr_name"), on="expr_id").group_by(
    "expr_name"
).agg(
    pl.len().alias("rows"),
    pl.col("taken").mean().alias("taken_fraction"),
    pl.col("margin").quantile(0.01).alias("p01_margin"),
    pl.col("margin").median().alias("p50_margin"),
    pl.col("margin").quantile(0.99).alias("p99_margin"),
).collect()
```

Use `scene_catalog.parquet` to join scene settings to expression rows by
directory or by a scene label added during scan setup.
