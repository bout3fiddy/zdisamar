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

### WP-05 Atmospheric intervals, aerosol, cloud, fraction, and subcolumns parity [Status: Todo]

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
- `zig build test-integration --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/optics_preparation_test.zig`
- `zig test tests/integration/forward_model_integration_test.zig`
- `zig test tests/validation/o2a_forward_shape_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

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

- [ ] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/Scene.zig`, `src/model/Atmosphere.zig`: represent vendor atmospheric interval controls explicitly.
  - Vendor anchors: `readConfigFileModule.f90::{readSurface,readAtmosphericIntervals}` and keys such as `numIntervalFit`, pressure bounds, and separate simulation versus retrieval interval grids.
  - Do not silently collapse pressure-bounded intervals into altitude-centered center-width shims during config compilation.

- [ ] `src/model/Aerosol.zig`, `src/model/Cloud.zig`, `src/model/Surface.zig`, `src/model/Geometry.zig`: model aerosol and cloud placement plus fraction semantics as typed scene state.
  - Vendor anchors: `readConfigFileModule.f90::{readCldAerFraction,readCloud,readAerosol}`.
  - Keep fit-interval identity explicit and keep cloud or aerosol fractions separate from later measurement corrections.

- [ ] `src/kernels/optics/prepare.zig`, `src/kernels/optics/prepare/particle_profiles.zig`, `src/model/reference/climatology.zig`, `src/model/reference/rayleigh.zig`: rebuild interval preparation around the vendor pressure-grid semantics.
  - Vendor anchors: `propAtmosphere.f90::{fillHighResolutionPressureGrid}` and the interval-bound conversion logic that maps pressure nodes to altitude bounds.
  - The prepared atmosphere path should preserve interval top and bottom semantics, not only derived layer centers.

- [ ] `src/model/reference/airmass_phase.zig`, `src/kernels/optics/prepare/phase_functions.zig`, `src/core/provenance.zig`: keep cloud and aerosol phase-support choices and effective interval controls auditable.
  - Vendor anchors: `FourierCoefficientsModule.f90`, `radianceIrradianceModule.f90`, and the vendor interval or fit-grid state used by cloud and aerosol pathways.
  - Provenance should make it clear whether Zig honored explicit interval semantics or is still using a declared approximation.

- [ ] `src/model/Atmosphere.zig`, `src/model/Scene.zig`, and later retrieval-facing preparation hooks: add subcolumn and strat-trop partition semantics that later WPs can consume directly.
  - Vendor anchors: `subcolumnModule.f90::fillAltitudeGridCol` and the vendor subcolumn weighting and boundary logic.
  - Preserve subcolumn boundaries, partition labels, and Gaussian support data as typed structures instead of recomputing them from ad hoc rules in each retrieval family.

- [ ] `tests/unit/optics_preparation_test.zig`, `tests/integration/forward_model_integration_test.zig`, `tests/validation/o2a_forward_shape_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add interval-sensitive validation.
  - Required families: `Config_O2_with_CIA.in`, one lower-troposphere NO2 or pollution case, one strat-trop partition case, and one cirrus or cloud-fraction case.
  - Assert that pressure-bounded intervals, fit-interval placement, and fraction controls affect the prepared atmosphere and final outputs in the expected direction.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Pressure-bounded atmospheric intervals are represented explicitly in typed scene state
- [ ] Aerosol and cloud placement plus fraction semantics are honored without collapsing to center-width approximations
- [ ] Subcolumn and strat-trop partition semantics are preserved for later retrieval-family work

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

By fixing interval and particle-placement semantics before instrument and retrieval work, the rest of the parity program stops building on the wrong atmosphere. This keeps the model honest where DISAMAR actually makes important distinctions: pressure bounds, fit interval, cloud and aerosol placement, and subcolumn partitions.

## Proof / Validation

- Planned: `zig test tests/unit/optics_preparation_test.zig` -> interval and particle preparation preserve explicit bounds and fit-interval semantics
- Planned: `zig test tests/integration/forward_model_integration_test.zig` -> forward execution honors pressure-bounded cloud and aerosol placement
- Planned: `zig test tests/validation/o2a_forward_shape_test.zig` and `disamar_compatibility_harness_test.zig` -> O2A, pollution, strat-trop, and cirrus-family cases stop relying on altitude-centered approximations

## How To Test

1. Run the O2A forcing case and confirm the configured aerosol interval stays pressure-bounded through preparation.
2. Run one pollution or PBL-sensitive case and confirm the fit interval and particle placement shift the output in the expected direction.
3. Run one strat-trop partition case and inspect the prepared subcolumn boundaries and labels.
4. Compare provenance and compatibility-harness output to confirm interval and fraction semantics are either honored exactly or called out explicitly.
