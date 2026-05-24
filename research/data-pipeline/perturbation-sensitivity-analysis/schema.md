# Perturbation Sensitivity Schema

The implemented first-pass schema records paired baseline-vs-perturbed outcomes
in one compact JSON file. It should not mirror the calculation telemetry event
stream. The purpose is to answer: "If this channel is suppressed, how much does
the final observable move?"

## `summary.json`

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | integer | Current compact-summary schema version. |
| `storage_policy` | string | Always `compact_summary_only` for the first-pass runner. |
| `wavelength_range_nm` | object | Start, end, and sample count for the spectrum. |
| `measurement_sigma_reflectance` | float | Noise scale used by the retrieval experiment. |
| `baseline` | object | Baseline forward timing, mean spectrum values, and retrieved state. |
| `experiments` | array | One row per perturbation plan. |

Each experiment row contains:

| Field | Type | Meaning |
| --- | --- | --- |
| `experiment_id` | integer | Stable id for one perturbation plan in the run. |
| `name` | string | Human-readable plan name. |
| `channel` | string | Perturbation channel enum name. |
| `mode` | string | `zero`, `scale`, `force_true`, or `force_false`. |
| `filters` | object | Coordinate filters for Fourier order, scattering order, branch, and retrieval state. |
| `forward` | object | Wall time plus aggregate reflectance/radiance deltas. |
| `retrieval` | object | Wall time, convergence state, iteration count, and retrieved-state deltas. |
| `suppression` | object | Hook hit count, changed count, and changed fraction. |

This file is intentionally small: no per-expression rows, no per-wavelength
residual rows, and no database.

## Future Parquet Expansion

The normalized tables below are reserved for wider scene matrices where a JSON
summary stops being enough. They are not emitted by the current runner.

## `experiment_catalog.parquet`

| Column | Type | Meaning |
| --- | --- | --- |
| `experiment_id` | integer | Stable id for one perturbation plan in the run. |
| `experiment_name` | string | Human-readable plan name. |
| `channel` | string | Perturbation channel enum name. |
| `mode` | string | `zero`, `scale`, `force_true`, `force_false`, `force_stop`, `cap`, or `continue`. |
| `scale` | float | Multiplicative scale for scalar modes, `NaN` otherwise. |
| `threshold` | float | Magnitude threshold or decision threshold used by the plan, `NaN` otherwise. |
| `layer_filter` | string | Coordinate filter description, or `all`. |
| `fourier_filter` | string | Coordinate filter description, or `all`. |
| `order_filter` | string | Coordinate filter description, or `all`. |
| `state_filter` | string | Coordinate filter description, or `all`. |
| `scene_filter` | string | Scene set included in the experiment. |
| `rationale` | string | Question this perturbation answers. |

## `spectrum_residual_rows.parquet`

| Column | Type | Meaning |
| --- | --- | --- |
| `experiment_id` | integer | Foreign key to `experiment_catalog`. |
| `scene_id` | string | Scene label. |
| `wavelength_nm` | float | Output wavelength. |
| `baseline_reflectance` | float | Unperturbed reflectance. |
| `perturbed_reflectance` | float | Perturbed reflectance. |
| `reflectance_delta` | float | `perturbed_reflectance - baseline_reflectance`. |
| `reflectance_abs_delta` | float | Absolute reflectance delta. |
| `reflectance_rel_delta` | float | Relative delta against baseline magnitude. |
| `noise_normalized_delta` | float | Delta divided by available scene noise, `NaN` otherwise. |
| `baseline_radiance` | float | Unperturbed radiance if available, `NaN` otherwise. |
| `perturbed_radiance` | float | Perturbed radiance if available, `NaN` otherwise. |
| `radiance_abs_delta` | float | Absolute radiance delta, `NaN` otherwise. |

## `retrieval_residual_rows.parquet`

| Column | Type | Meaning |
| --- | --- | --- |
| `experiment_id` | integer | Foreign key to `experiment_catalog`. |
| `case_id` | integer | Retrieval case id. |
| `state_name` | string | Retrieved state element. |
| `baseline_value` | float | Unperturbed retrieved value. |
| `perturbed_value` | float | Perturbed retrieved value. |
| `delta` | float | `perturbed_value - baseline_value`. |
| `abs_delta` | float | Absolute retrieved-state delta. |
| `baseline_iterations` | integer | Baseline iteration count. |
| `perturbed_iterations` | integer | Perturbed iteration count. |
| `cost_delta` | float | Final cost/residual delta if available. |

## `suppression_summary_rows.parquet`

| Column | Type | Meaning |
| --- | --- | --- |
| `experiment_id` | integer | Foreign key to `experiment_catalog`. |
| `scene_id` | string | Scene label. |
| `channel` | string | Perturbation channel. |
| `hit_count` | integer | Number of hook calls observed. |
| `suppressed_count` | integer | Number of hook calls changed by the experiment. |
| `suppressed_fraction` | float | `suppressed_count / hit_count`. |
| `work_proxy_name` | string | Channel-specific proxy, such as `qseries_product`, `fourier_term`, or `order_iteration`. |
| `work_proxy_saved` | integer | Estimated count of avoided work units. |

## `run_manifest.json`

The manifest should record:

- git commit and dirty state;
- command line;
- build mode;
- scene set;
- wavelength range;
- retrieval cases;
- output table paths and row counts;
- tolerance settings used by the analysis script.
