# WP-05 Atmospheric Intervals, Aerosol, Cloud, Fraction, And Subcolumns Parity

## Metadata

- Created: 2026-03-18
- Scope: implement vendor-faithful pressure-interval, aerosol/cloud placement, fraction, and subcolumn semantics so the Zig atmosphere model and prepared optics stop approximating core DISAMAR layering behavior
- Input sources:
  - vendor `readConfigFileModule.f90::{readSurface,readAtmosphericIntervals,readCldAerFraction,readCloud,readAerosol}`
  - vendor `propAtmosphere.f90`
  - vendor `subcolumnModule.f90`
  - vendor aerosol/cloud and strat-trop example configs
  - Zig scene, atmosphere, optics-preparation, and compatibility-harness files
- Dependencies:
  - `WP-01` through `WP-04`
- Reference baseline:
  - vendor `readConfigFileModule.f90::{readAtmosphericIntervals,readCldAerFraction,readCloud,readAerosol}`
  - vendor `propAtmosphere.f90::{fillHighResolutionPressureGrid}`
  - vendor `subcolumnModule.f90::fillAltitudeGridCol`

## Background

The current Zig runtime still approximates some vendor atmosphere semantics too aggressively. The clearest example from the O2A forcing case is aerosol vertical support: DISAMAR defines the aerosol on a pressure interval, while Zig currently maps that to an altitude-centered layer approximation. The vendor code also carries explicit fit-interval, cloud and aerosol fraction, and subcolumn semantics that later retrieval families depend on. This WP makes those semantics first-class instead of letting them hide inside ad hoc conversions.

## Overarching Goals

- Represent simulation and retrieval atmospheric intervals explicitly and honestly.
- Model aerosol and cloud placement, fit-interval, and fraction semantics in the prepared atmosphere path.
- Preserve subcolumn and strat-trop partition semantics so later retrieval WPs can reuse them without rebuilding the scene model.

## Non-goals

- Instrument correction and slit semantics; those belong in `WP-06`.
- Measured-input or mission wiring; those belong in `WP-07`.
- Retrieval-family math for OE, DOAS, or DISMAS; those belong in `WP-11` through `WP-13`.

### WP-05 Atmospheric intervals, aerosol, cloud, fraction, and subcolumns parity [Status: Done 2026-03-25]

Issue:
The current Zig atmosphere path still collapses vendor interval and particle-placement semantics into simpler altitude-centered approximations. That is not good enough for honest forward or retrieval parity.

Needs:
- typed pressure-interval and altitude-boundary representation for simulation and retrieval
- vendor-like aerosol and cloud placement on explicit fit intervals
- cloud and aerosol fraction semantics that are part of the state, not post hoc corrections
- subcolumn and strat-trop partition support for later retrieval-family outputs

How:
1. Compile vendor atmospheric interval sections into typed scene controls instead of one-off derived layers.
2. Rebuild the pressure-grid to altitude-grid preparation so interval bounds and fit-interval placement remain explicit.
3. Prepare aerosol and cloud optical properties against those intervals, including fraction semantics where configured.
4. Add subcolumn and strat-trop partition preparation that later retrieval WPs can consume without reinterpreting the scene.

Why this approach:
Interval, cloud, aerosol, and subcolumn semantics are part of the physics model, not convenience metadata. If Zig changes them during preparation, the forward model and all later retrieval outputs start from the wrong atmosphere.

Recommendation rationale:
This sits between the spectroscopy-family work and the instrument or retrieval WPs because both depend on an honest atmosphere layout. It is the right place to eliminate the current pressure-interval-to-altitude-layer approximation before later work bakes it in.

Desired outcome:
A developer can point to one typed atmosphere representation in Zig and show exactly how vendor interval bounds, fit interval, aerosol and cloud placement, fractions, and subcolumn partitions are compiled and honored.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-integration-forward-model --summary all`
- `zig build test-validation-o2a --summary all`
- `zig build test-validation-compatibility-full --summary all`

Files by type:
- Scene and atmosphere targets:
  - `src/model/Scene.zig`
  - `src/model/Atmosphere.zig`
  - `src/model/Aerosol.zig`
  - `src/model/Cloud.zig`
  - `src/model/Geometry.zig`
  - `src/model/Surface.zig`
  - `src/core/units.zig`
  - `src/core/provenance.zig`
- Reference and preparation targets:
  - `src/model/reference/climatology.zig`
  - `src/model/reference/airmass_phase.zig`
  - `src/model/reference/rayleigh.zig`
  - `src/kernels/optics/prepare.zig`
  - `src/kernels/optics/prepare/particle_profiles.zig`
  - `src/kernels/optics/prepare/phase_functions.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
- Validation targets:
  - `tests/unit/optics_preparation_test.zig`
  - `tests/integration/forward_model_integration_test.zig`
  - `tests/validation/o2a_forward_shape_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [x] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/Scene.zig`, `src/model/Atmosphere.zig`: represent vendor atmospheric interval controls explicitly.
  - Vendor anchors: `readConfigFileModule.f90::{readSurface,readAtmosphericIntervals}` and keys such as `numIntervalFit`, pressure bounds, and separate simulation versus retrieval interval grids.
  - Do not silently collapse pressure-bounded intervals into altitude-centered center-width shims during config compilation.

- [x] `src/model/Aerosol.zig`, `src/model/Cloud.zig`, `src/model/Surface.zig`, `src/model/Geometry.zig`: model aerosol and cloud placement plus fraction semantics as typed scene state.
  - Vendor anchors: `readConfigFileModule.f90::{readCldAerFraction,readCloud,readAerosol}`.
  - Keep fit-interval identity explicit and keep cloud or aerosol fractions separate from later measurement corrections.

- [x] `src/kernels/optics/prepare.zig`, `src/kernels/optics/prepare/particle_profiles.zig`, `src/model/reference/climatology.zig`, `src/model/reference/rayleigh.zig`: rebuild interval preparation around the vendor pressure-grid semantics.
  - Vendor anchors: `propAtmosphere.f90::{fillHighResolutionPressureGrid}` and the interval-bound conversion logic that maps pressure nodes to altitude bounds.
  - The prepared atmosphere path should preserve interval top and bottom semantics, not only derived layer centers.

- [x] `src/model/reference/airmass_phase.zig`, `src/kernels/optics/prepare/phase_functions.zig`, `src/core/provenance.zig`: keep cloud and aerosol phase-support choices and effective interval controls auditable.
  - Vendor anchors: `FourierCoefficientsModule.f90`, `radianceIrradianceModule.f90`, and the vendor interval or fit-grid state used by cloud and aerosol pathways.
  - Provenance should make it clear whether Zig honored explicit interval semantics or is still using a declared approximation.

- [x] `src/model/Atmosphere.zig`, `src/model/Scene.zig`, and later retrieval-facing preparation hooks: add subcolumn and strat-trop partition semantics that later WPs can consume directly.
  - Vendor anchors: `subcolumnModule.f90::fillAltitudeGridCol` and the vendor subcolumn weighting and boundary logic.
  - Preserve subcolumn boundaries, partition labels, and Gaussian support data as typed structures instead of recomputing them from ad hoc rules in each retrieval family.

- [x] `tests/unit/optics_preparation_test.zig`, `tests/integration/forward_model_integration_test.zig`, `tests/validation/o2a_forward_shape_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add interval-sensitive validation.
  - Required families: `Config_O2_with_CIA.in`, one lower-troposphere NO2 or pollution case, one strat-trop partition case, and one cirrus or cloud-fraction case.
  - Assert that pressure-bounded intervals, fit-interval placement, and fraction controls affect the prepared atmosphere and final outputs in the expected direction.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Pressure-bounded atmospheric intervals are represented explicitly in typed scene state
- [x] Aerosol and cloud placement plus fraction semantics are honored without collapsing to center-width approximations
- [x] Subcolumn and strat-trop partition semantics are preserved for later retrieval-family work

## Implementation Status (2026-03-25)

Implementation is present on branch `codex/wp05-atmospheric-intervals`, and the scene/config/runtime path now carries vendor-style interval, fraction, and subcolumn semantics end to end. Canonical config compilation emits explicit pressure-bounded interval grids, aerosol/cloud placement and fraction controls, and typed subcolumn partitions into `Scene`; optics preparation preserves interval top/bottom altitude and pressure bounds, fit-interval identity, particle fractions, subcolumn labels, and phase-support metadata in `PreparedOpticalState`; and forward execution stamps those semantics into typed provenance for downstream retrieval work.

The final post-review hardening pass also aligned measurement-workspace sizing with explicit interval sublayer totals, tightened `FractionControl` validation so wavelength-dependent fraction grids must be strictly monotonic before runtime interpolation is allowed, rejects threshold-only fraction configs that omit a simulation or retrieval target, infers retrieval HG aerosol and cloud optical-thickness inputs as `hg_scattering`, fails explicit interval-index particle placements when the scene never enabled an interval grid, rejects pressure gaps and non-monotonic explicit interval altitude boundaries across adjacent intervals, restores the legacy finite-layer padding and top-of-atmosphere clamp for non-interval particle placements, documents that bottom-up explicit-grid sublayers still preserve declared vendor interval identities, and simplifies relative-azimuth normalization to the canonical modulo form.

The landed validation covers the new surface from three angles: canonical-config compilation into typed scene state, direct optics preparation and forward execution against explicit intervals and fractions, and validation-harness proofs for O2A morphology plus compatibility-harness strat-trop partition preservation.

## Why This Works

By making interval grids, particle placement, fractions, and subcolumns first-class typed state, WP-05 removes the old pressure-interval-to-altitude-center approximation from the critical preparation path. The canonical compiler now resolves those semantics once, the optics builder preserves top/bottom bounds and fit-interval identity instead of collapsing them to anonymous midpoints, and aerosol or cloud fractions scale the prepared particulate optical depth where the vendor config actually applies them. Because the prepared state and provenance both carry the explicit interval and subcolumn metadata, later retrieval WPs can consume the same atmosphere layout without silently rebuilding or reinterpreting it.

## Proof / Validation

- `zig build test-unit --summary all` -> `Build Summary: 4/4 steps succeeded; 152/152 tests passed.`
- `zig build test-integration-forward-model --summary all` -> `Build Summary: 4/4 steps succeeded; 9/9 tests passed.`
- `zig build test-validation-o2a --summary all` -> `Build Summary: 4/4 steps succeeded; 6/6 tests passed.`
- `zig build test-validation-compatibility-full --summary all` -> `Build Summary: 4/4 steps succeeded; 1/1 tests passed.`
- `zig build test-integration --summary all` -> `Build Summary: 2/4 steps succeeded; 32/33 tests passed; 1 failed.` The failing case is `canonical_config_execution_integration_test.test.canonical execution applies deterministic stage noise when requested`, and the same failure reproduces on clean `HEAD` worktree `d335e5f`, so it is not introduced by WP-05.
- `zig build test-validation --summary all` -> `Build Summary: 11/13 steps succeeded; 44/46 tests passed; 2 failed.` The failing cases are `oe_parity_test.test.oe parity executes the full expert o2a scenario and improves the masked spectral fit` and `oe_parity_test.test.oe reference scenario matches the golden spectral-fit anchor`; both reproduce on clean `HEAD` worktree `d335e5f`, so they are not introduced by WP-05.
- Direct `zig test tests/...` invocations remain unsupported in this repo because those standalone test modules do not declare the `zdisamar` imports outside the build graph. The supported reproducible entry points for this WP are the `zig build ...` commands above.

## How To Test

1. Run `zig build test-unit --summary all`.
2. Run `zig build test-integration-forward-model --summary all`.
3. Run `zig build test-validation-o2a --summary all`.
4. Run `zig build test-validation-compatibility-full --summary all`.
5. Inspect the new canonical-config, optics-preparation, forward-model, O2A, and compatibility-harness assertions to confirm interval bounds, fit-interval identity, fractions, and subcolumn labels survive compilation and preparation.
6. Optionally run `zig build test-integration --summary all` and `zig build test-validation --summary all` to reproduce the current repo-wide baseline red lanes outside WP-05 ownership.
