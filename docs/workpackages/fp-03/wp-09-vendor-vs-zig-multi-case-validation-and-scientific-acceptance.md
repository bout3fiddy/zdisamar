# WP-09 Vendor-Vs-Zig Multi-Case Validation And Scientific Acceptance

## Metadata

- Created: 2026-03-18
- Scope: build a repeatable vendor-vs-Zig scientific validation harness across representative DISAMAR case families, with explicit artifact generation and acceptance thresholds
- Input sources:
  - vendor example configs in `InputFiles/Config_*.in`
  - vendor output formats (`disamar.sim`, `disamar.out`, additional outputs)
  - current findings doc and fresh O2A comparison artifacts
  - Zig validation and exporter tests
- Dependencies:
  - `WP-01` through `WP-08` for forward and config coverage
- Reference baseline:
  - vendor example corpus including O2A, O3 profile, NO2 DOMINO, multi-gas UV/Vis, cirrus/cloud, and SWIR/NIR pressure cases
  - current findings in `current_state_and_findings_2026-03-17.md`

## Background

Parity claims need more than a single O2A overlay. The vendored DISAMAR tree ships a broad example corpus, and the current findings already show how useful a carefully rebuilt O2A comparison can be. This WP turns that idea into a formal validation system covering multiple case families, generated artifacts, metrics, and thresholds.

## Overarching Goals

- Build a curated validation corpus spanning the major vendor capability families.
- Generate the same kind of comparison artifacts for every important case family, not only O2A.
- Tie every parity claim to explicit metrics and reviewable artifacts.

## Non-goals

- Hiding bad agreement behind too-loose thresholds.
- Using validation artifacts as a substitute for unit tests.
- Allowing new features to land without updating the validation corpus if they touch parity-critical behavior.

### WP-09 Vendor-vs-Zig multi-case validation and scientific acceptance [Status: Todo]

Issue:
The current validation story is too concentrated on O2A. That was the right forcing case, but it is not broad enough for full DISAMAR capability parity.

Needs:
- a representative case catalog
- automated artifact generation and comparison
- family-specific thresholds
- a documented acceptance process

How:
1. Curate a vendor case matrix that covers line gases, cross-section gases, profiles, DOMINO, cloud/aerosol, LUT, and operational pathways.
2. Add scripts/tests that run Zig and compare against vendored reference artifacts or metrics.
3. Generate comparison tables and overlay plots as part of validation.
4. Gate parity claims on explicit per-family thresholds.

Why this approach:
DISAMAR capability breadth is too wide for intuition-based validation. A case matrix keeps the program honest and prevents “works for O2A” from turning into “must work everywhere.”

Recommendation rationale:
This should begin once the forward and config layers are strong enough to justify comparison artifacts, and it must stay in sync with later retrieval WPs.

Desired outcome:
The repo has a stable validation matrix where every major vendor capability family has at least one reference case, generated artifacts, and a clear pass/fail interpretation.

Non-destructive tests:
- `zig build test-validation --summary all`
- `zig test tests/validation/main.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`
- `zig test tests/validation/parity_assets_test.zig`

Files by type:
- Validation harness targets:
  - `tests/validation/disamar_compatibility_harness_test.zig`
  - `tests/validation/parity_assets_test.zig`
  - `tests/validation/o2a_forward_shape_test.zig`
  - `tests/validation/oe_parity_test.zig`
  - `tests/validation/doas_parity_test.zig`
  - `tests/validation/dismas_parity_test.zig`
- Export/comparison helpers:
  - `src/adapters/exporters/netcdf_cf.zig`
  - `src/adapters/exporters/zarr.zig`
  - `src/adapters/exporters/diagnostic.zig`
  - `src/adapters/exporters/io.zig`
- New validation assets/scripts:
  - `tests/validation/assets/vendor_cases/` (new)
  - `tests/validation/assets/vendor_metrics/` (new)
  - `tests/validation/assets/vendor_overlays/` (new)
  - `tools/generate_vendor_comparison_artifacts.py` or Zig equivalent (new, local-only if preferred)

## Exact Patch Checklist

- [ ] `tests/validation/assets/vendor_cases/` and `tests/validation/assets/vendor_metrics/` (new): curate a representative case matrix.
  - Include at minimum: `Config_O2_with_CIA.in`, `Config_O2_no_CIA.in`, `Config_O2A_XsecLUT.in`, `Config_NO2_DOMINO.in`, one O3-profile case, one mixed UV/Vis case, one cirrus/cloud case, one H2O/NH3 case, and one CO2/H2O or O2+CO2+H2O pressure case.
  - For each case, store the vendor config, Zig canonical representation, expected output products, and threshold policy.

- [ ] `tests/validation/disamar_compatibility_harness_test.zig`: turn the harness into the central parity executor.
  - It should know how to load a case, report config-surface parity status, execute the Zig path, and compare against vendor references.
  - Add a machine-readable summary output so parity progress can be tracked without re-reading plots manually.

- [ ] `tests/validation/parity_assets_test.zig` and exporter helpers: make artifact generation reproducible.
  - For each case family generate metrics tables, wavelength-grid comparisons, radiance/irradiance/reflectance comparisons, and overlay plots where meaningful.
  - Reuse exporter code instead of building ad hoc one-off dump formats in tests.

- [ ] `tests/validation/o2a_forward_shape_test.zig`, `oe_parity_test.zig`, `doas_parity_test.zig`, `dismas_parity_test.zig`: tie each parity claim to family-specific thresholds.
  - O2A forward: spectral-shape and trough metrics.
  - Profile/OE cases: state and posterior metrics.
  - DOAS/DISMAS cases: fit residual and retrieved quantity metrics.
  - Thresholds should be documented per family, not hidden in magic constants.

- [ ] New local tool or test helper for artifact regeneration: automate vendor-vs-Zig comparison output.
  - The tool should regenerate the artifact bundle for a given case family with one command and store the results in a stable directory structure.
  - This is especially important because earlier hand-built comparisons were too easy to misconfigure.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Every major vendor capability family has at least one curated validation case
- [ ] Artifact regeneration is scripted and reproducible
- [ ] Acceptance thresholds are documented per family and enforced by tests

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

A multi-case validation matrix makes parity measurable across the real vendor surface. It also forces the team to separate “config parses,” “runtime honors,” and “scientific output matches,” which are easy to blur together without artifacts.

## Proof / Validation

- Planned: `zig test tests/validation/main.zig` -> validation corpus executes and emits pass/fail summaries
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> every curated case reports config/runtime/scientific status
- Planned: artifact regeneration tool -> reproducible metrics and overlays for each case family

## How To Test

1. Pick a curated case family and regenerate the vendor-vs-Zig artifact bundle.
2. Review the metrics summary and overlay plots.
3. Confirm the family-specific acceptance threshold passes or fails as expected.
4. Repeat for at least one line-gas, one cross-section-gas, one profile, and one operational case.
