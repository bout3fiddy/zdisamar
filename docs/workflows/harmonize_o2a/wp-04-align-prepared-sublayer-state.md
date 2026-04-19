# WP-04 Align prepared sublayer state

## Metadata

- Created: 2026-04-19
- Scope: align the Zig prepared sublayer state and optics-preparation semantics
  with the DISAMAR reference once the probe surfaces are normalized
- Input sources:
  - `src/kernels/optics/preparation/layer_accumulation.zig`
  - `src/kernels/optics/preparation/vertical_grid.zig`
  - `src/kernels/optics/preparation/state_optical_depth.zig`
  - `src/kernels/optics/preparation/prepared_state.zig`
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
  - `out/analysis/o2a/function_diff/20260419T142237Z/vendor/sublayer_optics.csv`
  - `out/analysis/o2a/function_diff/20260419T142237Z/yaml/sublayer_optics.csv`
- Dependencies:
  - `WP-01`
  - `WP-02`
- Reference baseline:
  - current hotspot sublayer-state mismatch after harness normalization

## Background

Even after the harness issues are removed, the two sides still define prepared
state differently. Zig uses its own vertical-grid construction, geometric-mean
pressure handling, and prepared sublayer carriers; the vendor trace uses live
`propAtmosphere` arrays and `RTMweightSub`.

## Overarching Goals

- Make Zig prepared sublayer state comparable to DISAMAR where the vendor
  semantics are known.
- Reduce sublayer thermodynamic and optical-depth divergence before transport.
- Preserve the typed prepared-state architecture in Zig.

## Non-goals

- Turning Zig into a direct Fortran-style global-state optics builder.
- Replacing the current interval-grid model with file-driven vendor input.
- Folding measurement-kernel changes into this package.

### WP-04 Align prepared sublayer state [Status: Todo]

Issue:
The current prepared sublayer carriers differ in pressure realization, path
length realization, interval identity, and gas/CIA optical-depth assembly
relative to the vendor `propAtmosphere` path.

Needs:
- a clear mapping between vendor `propAtmosphere` sublayer fields and Zig
  prepared sublayer fields
- parity-compatible pressure, path-length, and interval assignment where the
  current Zig construction is not vendor-equivalent
- focused checks that show whether remaining divergence is in state prep or
  later transport

How:
1. Normalize the probe surface first, then compare one physical sublayer at a
   time across both implementations.
2. Reconcile Zig sublayer pressure/path-length/interval assignment against the
   vendor `RTMweightSub` and pressure arrays.
3. Revisit gas, Rayleigh, and CIA optical-depth assembly on the prepared
   sublayer surface.
4. Re-run the hotspot probe to confirm the first sublayer divergence is now
   physically meaningful.

Why this approach:
Prepared-state mismatch can leak into spectroscopy weighting and transport, but
it should be fixed at the optics-preparation boundary rather than compensated
later.

Desired outcome:
`sublayer_optics.csv` becomes a trustworthy physics surface, and prepared-state
differences no longer swamp later transport comparisons.

Non-destructive tests:
- `zig build test-fast`
- `zig build test-validation-o2a`
- `zig build o2a-function-diff`

Files by type:
- New targets:
  - none
- Existing targets to refactor:
  - `src/kernels/optics/preparation/layer_accumulation.zig`
  - `src/kernels/optics/preparation/vertical_grid.zig`
  - `src/kernels/optics/preparation/state_optical_depth.zig`
  - `src/kernels/optics/preparation/prepared_state.zig`
- Validation targets:
  - `scripts/testing_harness/o2a_function_trace.zig`
  - `scripts/testing_harness/o2a_function_diff.py`
  - `tests/validation/o2a_forward_shape_test.zig`

## Exact Patch Checklist

- [ ] Establish a one-to-one physical sublayer mapping between vendor and Zig
      probe rows.
- [ ] Reconcile sublayer pressure and path-length semantics with the vendor
      `propAtmosphere` path.
- [ ] Reconcile prepared gas and CIA optical-depth assembly where it differs
      from the vendor reference.
- [ ] Add focused validation for parity-mode prepared-state fields.
- [ ] Re-run the hotspot probe and record the first physically aligned
      sublayer-state divergence.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] `sublayer_optics.csv` is usable as a physics comparison surface
- [ ] Remaining hotspot residual is no longer dominated by prepared-state drift

## Implementation Status (2026-04-19)

Planning only. No code changes yet.

## Why This Works

Prepared-state drift contaminates both spectroscopy weighting and measurement
inputs. Aligning the sublayer carriers makes the later-stage comparisons much
more diagnostic and prevents chasing transport symptoms that were created
earlier.

## Proof / Validation

- Planned: normalized `sublayer_optics.csv` rows compare one-to-one
- Planned: thermodynamic and optical-depth fields move materially closer across
  sides
- Planned: later hotspot probe stages become easier to interpret because the
  prepared-state mismatch shrinks

## How To Test

1. Run `zig build o2a-function-diff`.
2. Compare vendor and Zig `sublayer_optics.csv` rows for the hotspot run.
3. Run `zig build test-validation-o2a`.
4. Confirm later-stage probe summaries are no longer dominated by sublayer-row
   mismatch.

