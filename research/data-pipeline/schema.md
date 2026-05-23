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
| `subsystem` | string | Coarse model subsystem, currently `instrument_grid` or `labos`. |
| `equation` | string | Math equation or decision rule being captured. |
| `result_name` | string | Scientific name of the captured result. |
| `inputs` | string | Comma-separated input variable names captured in `input_*` or `param_*`. |
| `units` | string | Physical or logical unit for the result. |
| `source_file` | string | Source path for the expression hook. |
| `function` | string | Function or function group containing the expression. |
| `capture_reason` | string | Why this expression is useful for pruning or cheaper-math analysis. |

## Shared Event Columns

These columns appear in all row tables.

| Column | Type | Meaning |
| --- | --- | --- |
| `run_id` | string | Dataset run identifier. |
| `event_index` | unsigned integer | Monotonic row index assigned by the sink. |
| `expr_id` | integer | Foreign key to `expression_catalog.parquet`. |
| `wavelength_nm` | float or null | Wavelength coordinate when the hook has one. |
| `layer_index` | integer or null | Atmospheric layer coordinate. |
| `fourier_index` | integer or null | Fourier term coordinate. |
| `order_index` | integer or null | Multiple-scattering order coordinate. |
| `state_index` | integer or null | Jacobian state coordinate. |
| `branch` | integer or null | Expression-specific branch label, such as phase max index or convergence phase. |

The Zig staging writer uses `-1` and `nan` sentinels. The Python pipeline
normalizes those to Parquet nulls.

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
| `clamped` | boolean | The expression result was clamped before leaving the local calculation. |
| `skipped` | boolean | The row belongs to a path that was skipped or terminated. |
| `finite` | boolean | `result` was finite in the Zig sink. |

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
| `taken` | boolean | Whether the branch was taken. |
| `work_if_taken` | integer | Small work proxy for the taken path. |
| `work_if_not_taken` | integer | Small work proxy for the opposite path. |

Primary uses:

- find thresholds with very large positive or negative margins;
- estimate work controlled by a branch;
- identify branches that are effectively constant for an O2 A workload.

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
- Zig staging summary, including forward wall time and row counts;
- Parquet file paths and final row counts.
