# Calculation Telemetry Schema

The data model separates expression metadata from event rows. Join every event
table to `expression_catalog.parquet` on `expr_id`.

## `expression_catalog.parquet`

One row per captured expression.

| Column | Type | Meaning |
| --- | --- | --- |
| `expr_id` | integer | Stable numeric expression identifier used by event rows. |
| `expr_name` | string | Human-readable expression name. |
| `row_table` | string | Event table that contains rows for this expression. |
| `subsystem` | string | Coarse model subsystem, currently `spectrum` or `rtm`. |
| `equation` | string | Math equation or decision rule being captured. |
| `result_name` | string | Scientific name of the captured result. |
| `inputs` | string | Comma-separated input variable names captured in `input_*` or `param_*`. |
| `units` | string | Physical or logical unit for the result. |
| `source_file` | string | Source path for the expression hook. |
| `function` | string | Function or function group containing the expression. |
| `capture_reason` | string | Why this expression is useful for pruning or cheaper-math analysis. |

The retained LABOS decision IDs currently include:

| `expr_id` | `expr_name` | Decision rule |
| ---: | --- | --- |
| `11` | `labos_doubling_trigger` | `tau_eff > threshold_doubl` |
| `12` | `labos_qseries_skip` | `abs(trace(R)^2) <= threshold_mul` |
| `13` | `labos_qseries_rd_product` | `abs(trace(R) * trace(D)) > threshold_mul` |
| `14` | `labos_qseries_tu_product` | `abs(trace(T) * trace(U)) > threshold_mul` |
| `15` | `labos_qseries_td_product` | `abs(trace(T) * trace(D)) > threshold_mul` |
| `20` | `orders_convergence` | `max_outgoing_upward < threshold_conv` |
| `31` | `fourier_tail_break` | `m >= floor && abs(rho_m) <= epsilon` |

## Shared Event Columns

These columns appear in all row tables.

| Column | Type | Meaning |
| --- | --- | --- |
| `event_index` | integer | Monotonic row index assigned by the sink. |
| `expr_id` | integer | Foreign key to `expression_catalog.parquet`. |
| `wavelength_nm` | float | Wavelength coordinate when the hook has one, `NaN` otherwise. |
| `layer_index` | integer | Atmospheric layer coordinate, `-1` otherwise. |
| `fourier_index` | integer | Fourier term coordinate, `-1` otherwise. |
| `order_index` | integer | Multiple-scattering order coordinate, doubling step, or expression-local order coordinate, `-1` otherwise. |
| `state_index` | integer | Jacobian state coordinate, phase-count coordinate, or expression-local state coordinate, `-1` otherwise. |
| `branch` | integer | Expression-specific branch label; `-1` otherwise. |

The direct Zig writer keeps the event tables allocation-light by writing numeric
sentinels directly. Use `-1 -> null` and `NaN -> null` in analysis if a query
needs explicit nulls.

Coordinate meanings are expression-specific but stable inside each expression:

- `labos_doubling_trigger` stores `branch = phase_max_index`.
- `labos_qseries_skip` stores `order_index = doubling_step_index` and
  `state_index = phase_max_index`.
- `labos_qseries_rd_product`, `labos_qseries_tu_product`, and
  `labos_qseries_td_product` store `order_index = doubling_step_index`,
  `state_index = phase_max_index`, and `branch = qseries_is_zero`.
- `jacobian_column` uses `state_index` as the derivative state index.

## `scalar_expression_rows.parquet`

One row per scalar expression result.

| Column | Type | Meaning |
| --- | --- | --- |
| shared columns | mixed | See Shared Event Columns. |
| `input_0` ... `input_3` | float or null | Local expression inputs. Names are defined by the catalog row. |
| `param_0`, `param_1` | float or null | Threshold, weight, or other control value. Names are defined by the catalog row. |
| `result` | float or null | Captured expression output. |
| `abs_result` | float or null | `abs(result)` for finite results. |
| `relative_scale` | float or null | `abs(result) / sum(abs(finite inputs and params))`. |
| `clamped` | integer | `1` when the expression result was clamped before leaving the local calculation. |
| `skipped` | integer | `1` when the row belongs to a path that was skipped or terminated. |
| `finite` | integer | `1` when `result` was finite in the Zig sink. |

Primary uses:

- detect scalar results that are nearly always zero;
- compare `relative_scale` across coordinates;
- find clamped or non-finite math.

## `decision_rows.parquet`

One row per threshold or branch decision.

| Column | Type | Meaning |
| --- | --- | --- |
| shared columns | mixed | See Shared Event Columns. |
| `lhs` | float or null | Left side of the branch comparison. |
| `rhs` | float or null | Secondary value, often the retained result or iteration cap. |
| `threshold` | float or null | Threshold used by the decision. |
| `margin` | float or null | `lhs - threshold`. |
| `taken` | integer | `1` when the branch was taken. |
| `work_if_taken` | integer | Small work proxy for the taken path. |
| `work_if_not_taken` | integer | Small work proxy for the opposite path. |

Primary uses:

- find thresholds with very large positive or negative margins;
- estimate work controlled by a branch;
- identify branches that are effectively constant for a workload.

## `reduction_expression_rows.parquet`

One row per loop, vector, or table reduction.

| Column | Type | Meaning |
| --- | --- | --- |
| shared columns | mixed | See Shared Event Columns. |
| `term_count` | integer | Number of terms represented by the reduction. |
| `nonzero_count` | integer | Count of nonzero, active, or retained terms. |
| `zero_count` | integer | Count of zero, inactive, reused, clamped, or skipped terms. |
| `min_term` | float or null | Minimum term value when available. |
| `max_term` | float or null | Maximum term value when available. |
| `sum` | float or null | Sum or count-like aggregate. |
| `mean` | float or null | Arithmetic mean or fraction. |
| `l1_norm` | float or null | L1-like magnitude or work proxy. |
| `l2_norm` | float or null | L2-like magnitude when available. |
| `result` | float or null | Main reduction result. |

Primary uses:

- find low-density reductions with many inactive terms;
- compare active counts to result magnitude;
- study vector columns and wavelength plans without storing every element.

## Run Manifest

`run.json` stores:

- `run_id`;
- generation timestamp;
- git commit and dirty-worktree flag;
- capture command;
- Zig capture summary, including scene settings, forward wall time, and row counts;
- Parquet file paths and final row counts.

## Sweep Manifest

`run_full_spectrum_sweep.py` writes `scene_catalog.parquet` and
`sweep_manifest.json` at the sweep root. `scene_catalog.parquet` contains one row
per scene with the surface, aerosol, geometry, spectral-grid controls, row
counts, elapsed forward time, and byte size for the scene directory.
