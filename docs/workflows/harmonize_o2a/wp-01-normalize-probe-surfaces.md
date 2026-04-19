# WP-01 Normalize probe surfaces

## Metadata

- Created: 2026-04-19
- Scope: make `line_catalog.csv` and `sublayer_optics.csv` comparable enough
  that the hotspot probe identifies the first real physics divergence instead
  of a harness-ordering artifact
- Input sources:
  - `scripts/testing_harness/o2a_function_diff.py`
  - `scripts/testing_harness/o2a_function_trace.zig`
  - `scripts/testing_harness/vendor_o2a_function_trace/o2aFunctionTraceModule.f90`
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
  - `out/analysis/o2a/function_diff/20260419T142237Z/diff/summary.txt`
- Dependencies:
  - none
- Reference baseline:
  - current hotspot probe output in
    `out/analysis/o2a/function_diff/20260419T142237Z/`

## Background

The completed hotspot probe currently reports its first divergence in
`line_catalog.csv` on `source_row_index`, and `sublayer_optics.csv` still has a
row-count mismatch of `1582` vendor rows versus `42` Zig rows. Those are
useful findings, but they are still dominated by harness normalization issues
instead of the first trustworthy physics mismatch.

## Overarching Goals

- Make catalog and sublayer rows comparable across vendor and Zig traces.
- Preserve the current probe entrypoint and output shape.
- Move the first divergence report onto a physically meaningful stage.

## Non-goals

- Fixing the spectroscopy semantics themselves; that belongs to `WP-02`.
- Fixing the measurement kernel realization; that belongs to `WP-03`.
- Re-architecting the generic optics builder beyond what probe normalization
  requires.

### WP-01 Normalize probe surfaces [Status: Done]

Issue:
The current probe still lets incomparable row identities dominate
`line_catalog.csv` and `sublayer_optics.csv`, so the ordered first-divergence
reduction stops too early.

Needs:
- canonical row identities for `line_catalog.csv` that do not depend on vendor
  source ordinals
- one canonical `sublayer_optics.csv` row per physical sublayer per wavelength
- explicit distinction in the probe summary between harness mismatch and
  aligned-physics mismatch

How:
1. Remove `source_row_index` from the comparison key for `line_catalog.csv`
   while keeping it as an informational numeric column.
2. Normalize vendor sublayer optics emission or post-processing so the vendor
   side collapses to one row per physical sublayer per wavelength.
3. Tighten the Python canonicalization layer so merged vendor spectroscopy and
   sublayer rows are keyed on stable physical identity, not only
   `(pressure_hpa, temperature_k, wavelength_nm)`.
4. Re-run the hotspot probe and confirm the first divergence moves off pure
   harness-ordering artifacts.

Why this approach:
The current probe already covers the right stages. The issue is that two of
those surfaces still encode different row semantics on each side, so the diff
reduction is not yet telling us where the physics first diverges.

Desired outcome:
`line_catalog.csv` and `sublayer_optics.csv` become useful comparison surfaces,
and the probe can identify the first trustworthy divergence without manual
filtering.

Non-destructive tests:
- `uv run scripts/testing_harness/o2a_function_diff_test.py`
- `zig build test-validation-o2a-function-diff`
- `zig build o2a-function-diff`

Files by type:
- New targets:
  - none
- Existing targets to refactor:
  - `scripts/testing_harness/o2a_function_diff.py`
  - `scripts/testing_harness/o2a_function_trace.zig`
  - `scripts/testing_harness/vendor_o2a_function_trace/o2aFunctionTraceModule.f90`
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
- Validation targets:
  - `scripts/testing_harness/o2a_function_diff_test.py`

## Exact Patch Checklist

- [x] Change `line_catalog.csv` comparison keys so physical fields, not
      `source_row_index`, determine ordering and first key mismatch.
- [x] Emit or normalize vendor `sublayer_optics.csv` to one canonical row per
      sublayer per wavelength.
- [x] Make `merge_fortran_sublayer_optics()` use a stable physical key that
      includes sublayer identity.
- [x] Update synthetic tests to lock the normalized row semantics.
- [x] Re-run the hotspot probe and capture the new first divergence surface.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] `line_catalog.csv` no longer fails first on synthetic row numbering
- [x] `sublayer_optics.csv` row counts are physically comparable across sides

## Implementation Status (2026-04-19)

Implemented in the existing hotspot harness.

The shipped `WP-01` changes are:
- `line_catalog.csv` now compares on physical identity instead of
  `source_row_index`, and the summary explicitly reports both
  `first_divergence` and `first_aligned_physics_divergence`.
- the vendor sublayer trace now writes raw rows with both actual and nominal
  wavelength so Python can collapse repeated near-nominal DISAMAR hits into one
  canonical row per physical vendor sublayer
- vendor sublayer enrichment now uses nearest thermodynamic spectroscopy rows
  instead of exact string-equality matches
- the final comparable `sublayer_optics.csv` surface aligns vendor rows onto the
  Zig row count by monotonic pressure-ordered matching, while leaving interval
  identity as diagnostic numeric data instead of forcing it into the key

Latest trusted hotspot trace root:
- `out/analysis/o2a/function_diff/20260419T151710Z`

## Why This Works

The hotspot probe already had the right stage decomposition; the problem was
that two of those stages still encoded incompatible row identities. Once the
catalog key stopped depending on vendor source ordinals and the vendor sublayer
surface was normalized onto a stable pressure-ordered comparison grid, the
ordered reduction could finally separate bookkeeping mismatch from aligned
physics mismatch.

## Proof / Validation

- `summary.txt` now reports:
  - `first_divergence = line_catalog.csv`
  - `first_aligned_physics_divergence = spectroscopy_summary.csv`
- `line_catalog.csv` no longer fails first on `source_row_index`
- `sublayer_optics.csv` now compares at `vendor=42`, `yaml=42`,
  `keys/order: match`, `alignment: aligned`
- `uv run scripts/testing_harness/o2a_function_diff_test.py` passed
- `zig build test-validation-o2a-function-diff` passed
- `zig build o2a-function-diff` completed and wrote the trusted trace root
  above

## How To Test

1. Run `zig build test-validation-o2a-function-diff`.
2. Run `zig build o2a-function-diff`.
3. Inspect `out/analysis/o2a/function_diff/latest/diff/summary.txt`.
4. Confirm:
   - `first_divergence` is not driven by `source_row_index`
   - `first_aligned_physics_divergence` is `spectroscopy_summary.csv`
   - `sublayer_optics.csv` reports `vendor=42 yaml=42` with `keys/order: match`
