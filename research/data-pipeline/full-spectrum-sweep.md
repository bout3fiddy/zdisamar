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
- Total event rows: 295,466,180
- Total Parquet bytes: 8,058,730,452
- Sum of forward wall time: 240.94 s
- Smallest scene: 4,669,077 event rows
- Largest scene: 49,133,117 event rows

## Scene Catalog

| Scene | Albedo | AOD | SSA | g | SZA/VZA/RAA | Rows | MB | Forward s |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| sza45_vza00_raa000_dark_clean | 0.05 | 0.08 | 1.00 | 0.62 | 45/0/0 | 4,669,077 | 123.7 | 3.83 |
| sza45_vza00_raa000_mid_hazy | 0.20 | 0.80 | 0.94 | 0.78 | 45/0/0 | 4,913,517 | 131.1 | 4.12 |
| sza45_vza00_raa000_bright_dense | 0.45 | 1.50 | 0.90 | 0.82 | 45/0/0 | 4,994,997 | 132.9 | 4.14 |
| sza60_vza30_raa120_dark_clean | 0.05 | 0.08 | 1.00 | 0.62 | 60/30/120 | 19,437,469 | 524.1 | 15.23 |
| sza60_vza30_raa120_mid_reference | 0.20 | 0.30 | 1.00 | 0.70 | 60/30/120 | 26,718,849 | 727.8 | 21.35 |
| sza60_vza30_raa120_bright_hazy | 0.45 | 0.80 | 0.94 | 0.78 | 60/30/120 | 37,934,263 | 1038.0 | 30.66 |
| sza70_vza50_raa060_dark_hazy | 0.05 | 0.80 | 0.94 | 0.78 | 70/50/60 | 38,199,350 | 1045.5 | 31.22 |
| sza70_vza50_raa060_mid_dense | 0.20 | 1.50 | 0.90 | 0.82 | 70/50/60 | 49,133,117 | 1346.3 | 40.48 |
| sza70_vza50_raa060_bright_clean | 0.45 | 0.08 | 1.00 | 0.62 | 70/50/60 | 19,476,755 | 527.7 | 15.87 |
| sza35_vza20_raa170_dark_dense | 0.05 | 1.50 | 0.90 | 0.82 | 35/20/170 | 44,543,820 | 1226.2 | 37.17 |
| sza35_vza20_raa170_mid_clean | 0.20 | 0.08 | 1.00 | 0.62 | 35/20/170 | 19,203,799 | 518.5 | 15.35 |
| sza35_vza20_raa170_bright_reference | 0.45 | 0.30 | 1.00 | 0.70 | 35/20/170 | 26,241,167 | 716.8 | 21.52 |

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
