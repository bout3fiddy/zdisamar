# Calculation Data Pipeline

This directory is the retained research surface for studying zdisamar forward-model
math as data. It is separate from Tracy profiling. Tracy answers timing and call
shape questions; this pipeline records the numerical state around selected
expressions so we can ask which calculations are scientifically or numerically
irrelevant.

## Boundary

Product builds compile the calculation telemetry away:

- `src/instrumentation/telemetry.zig` is a tiny facade at the math call
  sites.
- Normal library, CLI, test, benchmark, and Tracy trace modules import
  `src/instrumentation/stubs/calculation_telemetry_sink.zig`; `Telemetry.enabled` is a
  comptime false value there.
- The only build module that imports the real sink is the explicit
  `calculation-telemetry` executable.
- The real sink lives under `scaffolding/instrumentation/`, not under
  `src/`, so file I/O and mutable capture state stay out of the
  RTM routines.

The capture path is intentionally opt-in:

```sh
uv run python scaffolding/instrumentation/telemetry/capture/generate_calculation_parquet.py
```

The script runs:

```sh
zig build calculation-telemetry -Doptimize=ReleaseFast -- --output-dir out/scaffolding/telemetry/data/o2a-default
```

The default capture is a compact O2 A window: 760-761 nm, 21 output samples,
0.1 nm high-resolution spacing, forward-only, and single-scattering LABOS. That
keeps the starter dataset quick enough to regenerate while still exercising the
real O2 A preparation, wavelength plan, Fourier loop, order convergence, and
reflectance assembly paths.

The same script forwards larger-capture controls to the Zig harness:

```sh
uv run python scaffolding/instrumentation/telemetry/capture/generate_calculation_parquet.py \
  --sample-count 101 \
  --start-nm 755 \
  --end-nm 776 \
  --high-resolution-step-nm 0.05 \
  --multiple-scattering
```

Use `--jacobian` when the experiment needs derivative columns; keep it off for
the default dataset because it is much slower.

Then it writes Parquet files under:

```text
out/scaffolding/telemetry/data/o2a-default/
```

Generated data under `out/scaffolding/telemetry/data/` is intentionally ignored by
git. Keep the scripts, schemas, and documentation committed; regenerate or move
large Parquet captures through an external data store when needed.

## Output Tables

The canonical data files are Parquet:

```text
out/scaffolding/telemetry/data/o2a-default/
  expression_catalog.parquet
  scalar_expression_rows.parquet
  reduction_expression_rows.parquet
  decision_rows.parquet
  run.json
```

The Zig harness writes these files directly with
`scaffolding/instrumentation/telemetry/zig/parquet_lite.zig`. That writer is intentionally not
a general Parquet library: it supports fixed schemas, PLAIN-encoded flat
numeric/string columns, row-group flushing, and gzip page compression. It has no
reader, nested types, dictionaries, or product-facing API.

The hot row path appends typed values into column buffers. Compression, page
headers, and footer metadata are handled only when a row group flushes, so the
telemetry sink avoids per-row text formatting, per-row allocation after warmup,
and transient CSV staging.

## Full-Spectrum Sweep

The retained 12-scene sweep covers 758-770 nm with 401 output samples,
0.1 nm high-resolution spacing, multiple-scattering LABOS, and varied aerosol,
surface, and geometry settings:

```sh
uv run python scaffolding/instrumentation/telemetry/capture/run_full_spectrum_sweep.py
```

It writes:

```text
out/scaffolding/telemetry/data/full-spectrum-758-770-ms/
  scene_catalog.parquet
  sweep_manifest.json
  <scene-id>/
    expression_catalog.parquet
    scalar_expression_rows.parquet
    reduction_expression_rows.parquet
    decision_rows.parquet
    run.json
```

See `full-spectrum-sweep.md` for the captured scene table, aggregate row counts,
and starter queries.

## Perturbation Sensitivity

The perturbation lane is the retained research surface for ablation experiments:
compile-time-gated hooks can zero, force, or scale selected intermediate
calculation channels, then the runner records only final spectrum and retrieval
movement.

```sh
uv run python scaffolding/instrumentation/perturbation/sweep/run_perturbation_sweep.py
```

It writes one compact ignored artifact:

```text
out/scaffolding/perturbation/data/o2a-default/summary.json
```

and refreshes the human report:

```text
scaffolding/instrumentation/perturbation/analysis/report.md
```

This path intentionally does not write per-expression tables or a database. It
keeps spectra in memory just long enough to compute aggregate residuals and
stores hook hit/changed counters as the work proxy.

## Analysis Reports

Run the local analysis bundle with:

```sh
uv run python scaffolding/instrumentation/telemetry/analysis/analyze_calculation_telemetry.py
```

It writes aggregate CSV tables, HTML plots, and a Markdown report under:

```text
out/scaffolding/telemetry/reports/calculation-telemetry-latest/
```

For a Markdown/table-only refresh, skip plot generation:

```sh
uv run python scaffolding/instrumentation/telemetry/analysis/analyze_calculation_telemetry.py --skip-plots
```

Reports are also ignored by git. Commit analysis code and report templates, not
the generated report output.

## Perturbation Sensitivity Analysis

The perturbation lane is documented under
`scaffolding/instrumentation/perturbation/`. It is an architecture for
research-only perturbation channels that can zero, force, scale, or stop
selected intermediate calculations, then compare final spectra and retrieval
states against an unperturbed baseline.

The implementation should follow the same compile-time boundary as calculation
telemetry: product modules import a stub and receive comptime-disabled inline
facade calls, while the explicit research executable imports the real sink and
writes result tables.

## Analysis Start

```python
from pathlib import Path

import polars as pl

base = Path("out/scaffolding/telemetry/data/o2a-default")
catalog = pl.read_parquet(base / "expression_catalog.parquet")
scalar = pl.read_parquet(base / "scalar_expression_rows.parquet")
decision = pl.read_parquet(base / "decision_rows.parquet")
reduction = pl.read_parquet(base / "reduction_expression_rows.parquet")

decision.join(catalog.select("expr_id", "expr_name"), on="expr_id").group_by(
    "expr_name"
).agg(
    pl.len().alias("rows"),
    pl.col("taken").mean().alias("taken_fraction"),
    pl.col("margin").quantile(0.01).alias("p01_margin"),
    pl.col("margin").median().alias("p50_margin"),
    pl.col("margin").quantile(0.99).alias("p99_margin"),
)
```

Useful first questions:

- Which decision expressions spend most rows far from the threshold?
- Which scalar expressions are almost always zero, clamped, skipped, or
  non-finite?
- Which reductions have high `zero_count / term_count` or tiny `l1_norm`?
- Which Fourier, layer, or derivative-state coordinates dominate nonzero
  results?

## Current Capture Scope

The first retained dataset focuses on expressions that are already strong pruning
or cheaper-math candidates:

- wavelength integration kernel shape and side-storage pressure;
- forward wavelength-cache miss reuse;
- reflectance denominator clamping and maximum reflectance;
- Jacobian column mean and maximum absolute derivative;
- LABOS effective scattering depth and layer-doubling trigger;
- LABOS q-series skip threshold and downstream `R-D`, `T-U`, and `T-D` product
  gates;
- scattering-order convergence;
- Fourier contribution size and tail break;
- final LABOS reflectance clamp and Jacobian norm.

The expression catalog stores the equation, source file, function, inputs,
result name, units, and capture reason for every `expr_id`.

## Scale Notes

The schema is intentionally columnar and split by row shape:

- scalar rows record one expression result and its local inputs;
- decision rows record a threshold comparison and work proxy;
- reduction rows record aggregate statistics for loops or vectors;
- the catalog carries strings and equation text once per expression, not once per
  event row.

That shape keeps the event tables numeric and suitable for Parquet compression,
predicate pushdown, and lazy Polars scans. Missing coordinates are currently
encoded as `-1`, and missing floating values are encoded as `NaN`; normalize
those sentinels to nulls in analysis when null semantics are needed.
