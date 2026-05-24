# Perturbation Sensitivity Analysis

This research lane tests which intermediate calculations materially affect the
final forward spectrum or retrieval state. It is an ablation framework, not a
product feature: selected mathematical channels can be zeroed, forced, scaled, or
stopped in a research build, then compared against the unperturbed model.

The implementation should mirror the existing Tracy and calculation telemetry
shape:

- product modules see only a tiny inline facade;
- normal builds import a stub and set the build option to `false`;
- the research executable imports the real perturbation sink and sets the build
  option to `true`;
- all file I/O, experiment catalogs, result tables, and mutable experiment state
  stay outside `src/forward_model/`;
- every hook compiles to the baseline expression in product builds.

## Boundary

The product path must not know about experiment files, perturbation names,
Parquet schemas, CLIs, report generation, or runtime plan loading. It may only
call typed perturbation-channel functions with values it already computed.

Intended module layout:

```text
src/forward_model/perturbation_sensitivity.zig
src/forward_model/perturbation_sensitivity_stub.zig
src/validation/performance/perturbation_sensitivity_sink.zig
src/validation/performance/perturbation_sensitivity_cli.zig
research/data-pipeline/perturbation-sensitivity-analysis/
  README.md
  schema.md
  run_perturbation_sweep.py
  analyze_perturbation_sweep.py
```

Only the research executable should import the real sink. Library, Python
binding, validation, benchmark, and Tracy builds should import the stub.

## Compile-Time Contract

Each hook returns the unmodified value when the research channel is disabled:

```zig
pub inline fn scalar(
    comptime channel: Channel,
    coord: Coord,
    baseline: f64,
) f64 {
    if (comptime !enabled) return baseline;
    return sink.scalar(channel, coord, baseline);
}
```

Decision channels follow the same rule:

```zig
pub inline fn decision(
    comptime channel: Channel,
    coord: Coord,
    baseline: bool,
) bool {
    if (comptime !enabled) return baseline;
    return sink.decision(channel, coord, baseline);
}
```

Loop-control channels should return a small typed result rather than exposing the
research plan to the model code:

```zig
pub const LoopAction = enum { keep_going, stop_after_current };

pub inline fn loopAction(
    comptime channel: Channel,
    coord: Coord,
    baseline: LoopAction,
) LoopAction {
    if (comptime !enabled) return baseline;
    return sink.loopAction(channel, coord, baseline);
}
```

The channel id must be a `comptime` enum value, not a string. The product path
should not allocate, format, parse, or branch on experiment names.

## Channel Types

Use a small set of typed channel functions:

| Type | Baseline value | Perturbations | Use |
| --- | --- | --- | --- |
| scalar | `f64` | zero, scale, clamp-to-zero-below-threshold | Fourier contributions, tangent contributions, small matrix summary terms |
| decision | `bool` | force true, force false | q-series skip, downstream product gates, tail break decisions |
| loop action | enum | force stop, force continue | Fourier tail and scattering-order stop tests |
| count | `usize` | cap, floor, zero | maximum scattering orders or controlled doubling counts |

Do not start with matrix-valued channels. A matrix hook risks copying large
payloads and making the perturbation framework look like a second RTM. Prefer
scalar gates that already decide whether matrix work happens.

## Initial Channels

These are the first channels that match the telemetry report and have a clear
residual question.

| Channel | Source | Baseline expression | Perturbation question |
| --- | --- | --- | --- |
| `fourier_weighted_reflectance` | `src/forward_model/radiative_transfer/labos/execute.zig` | `fourier_weight * refl_fc` | Which Fourier terms can be zeroed without changing spectra beyond tolerance? |
| `fourier_tail_break` | `src/forward_model/radiative_transfer/labos/execute.zig` | current tail-break decision | How early can we stop if cumulative residual stays bounded? |
| `qseries_skip` | `src/forward_model/radiative_transfer/labos/layers.zig` | `abs(trace(R)^2) <= threshold_mul` | Are always-skip coordinates safe to force skip across scenes? |
| `qseries_rd_product` | `src/forward_model/radiative_transfer/labos/layers.zig` | `abs(trace(R) * trace(D)) > threshold_mul` | When `qseries_skip=true`, can rare `R-D` work be suppressed? |
| `qseries_tu_product` | `src/forward_model/radiative_transfer/labos/layers.zig` | `abs(trace(T) * trace(U)) > threshold_mul` | When `qseries_skip=true`, can rare `T-U` work be suppressed? |
| `qseries_td_product` | `src/forward_model/radiative_transfer/labos/layers.zig` | `abs(trace(T) * trace(D)) > threshold_mul` | When `qseries_skip=true`, can rare `T-D` work be suppressed? |
| `orders_convergence` | `src/forward_model/radiative_transfer/labos/orders.zig` | order-loop convergence decision | What residual appears if late scattering orders are stopped earlier? |
| `aerosol_aod_tangent` | `src/forward_model/radiative_transfer/labos/execute.zig` | Fourier-weighted AOD tangent | Which derivative terms matter to OE retrieval state? |
| `aerosol_pressure_tangent` | `src/forward_model/radiative_transfer/labos/execute.zig` | Fourier-weighted pressure tangent | Which pressure derivative terms matter to OE retrieval state? |

Avoid perturbing physical scene inputs first. Zeroing optical depth, single
scatter albedo, or phase coefficients answers a different question: it changes
the atmosphere rather than testing whether an intermediate calculation can be
approximated or skipped.

## Execution Shape

The research executable should run paired cases:

1. Build the scene and route once using the normal input path.
2. Run the baseline model and keep spectra/retrieval outputs in memory.
3. For each experiment plan, set the research sink's active plan and rerun the
   same scene.
4. Write only residual summaries and suppression counters, not full per-event
   traces by default.

This keeps the output size closer to the number of experiments times the number
of wavelengths, not the number of q-series events.

The first retained command should look like:

```sh
uv run python research/data-pipeline/perturbation-sensitivity-analysis/run_perturbation_sweep.py
```

That script should run an explicit Zig build step, for example:

```sh
zig build perturbation-sensitivity -Doptimize=ReleaseFast -- \
  --output-dir research/data-pipeline/data/perturbation-sensitivity/o2a-default
```

Generated data stays ignored under `research/data-pipeline/data/`.

## Current Compact Output

The initial retained sweep intentionally writes one compact artifact:

```text
research/data-pipeline/data/perturbation-sensitivity/o2a-default/summary.json
```

Each experiment row stores final spectrum residual summaries, final retrieval
state deltas, wall-clock timings, and fixed suppression counters. It does not
store per-expression rows or a wavelength-by-wavelength table. This is the
default for the perturbation work because the useful question is whether a
calculation can move the final observable, not what every event value was.

`analyze_perturbation_sweep.py` converts that JSON into:

```text
research/data-pipeline/perturbation-sensitivity-analysis/report.md
```

The report is the human artifact for this lane. Generated data remains ignored
under `research/data-pipeline/data/`.

## Future Result Tables

If an experiment graduates into a broader scene matrix, the compact output can
be expanded into Parquet tables. The intended normalized form is:

```text
experiment_catalog.parquet
spectrum_residual_rows.parquet
retrieval_residual_rows.parquet
suppression_summary_rows.parquet
run_manifest.json
```

`experiment_catalog` records the channel, perturbation mode, coordinate filter,
thresholds, scene scope, and commit metadata.

`spectrum_residual_rows` records one row per experiment, scene, and wavelength:
baseline reflectance/radiance, perturbed reflectance/radiance, absolute residual,
relative residual, and noise-normalized residual when available.

`retrieval_residual_rows` records one row per experiment and retrieval case:
baseline state, perturbed state, state deltas, iteration count deltas, and final
cost/residual deltas.

`suppression_summary_rows` records the amount of work suppressed: channel hit
count, suppressed count, fraction suppressed, and any channel-specific work
proxy such as q-series matrix products avoided or Fourier terms zeroed.

## Acceptance Rules

A perturbation is only actionable when all three are true:

- residuals stay inside the chosen scientific tolerance for the target workflow;
- the suppressed-work counter is large enough to plausibly matter;
- a same-boundary benchmark confirms that a real implementation is faster.

Sensitivity analysis can reject ideas quickly, but it does not by itself prove a
safe optimization. Any accepted perturbation needs a later clean implementation
that removes or simplifies work without carrying the research channel.

## Product-Impact Checks

Every perturbation-channel implementation must prove:

- `zig build check` passes with product modules importing the stub;
- optimized product disassembly for touched hot symbols has no call into the
  perturbation sink;
- the research executable is the only build target with
  `enable_perturbation_sensitivity=true`;
- no file I/O or experiment state is reachable from `src/forward_model/` in
  product builds;
- no unused channel hooks remain after an experiment is rejected.
