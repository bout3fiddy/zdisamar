# WP-12 DOAS, Classic DOAS, And DOMINO Parity

## Metadata

- Created: 2026-03-18
- Scope: implement vendor-faithful differential retrieval families for DOAS, classic DOAS, and DOMINO-NO2, reusing the real spectral forward and state infrastructure
- Input sources:
  - vendor `doasModule.f90`
  - vendor `classic_doasModule.f90`
  - vendor `verifyConfigFileModule.f90`
  - vendor `readConfigFileModule.f90::{readGeneral,readRetrieval,readAbsorbingGas}`
  - vendor NO2 and UV/Vis example configs
  - Zig retrieval common and DOAS files
- Dependencies:
  - `WP-04`, `WP-06`, `WP-09`, and `WP-11`
- Reference baseline:
  - vendor `doasModule.f90`
  - vendor `classic_doasModule.f90`
  - vendor `verifyConfigFileModule.f90` DOMINO-specific constraints on `NO2`, `trop_NO2`, and `strat_NO2`
  - vendor `readConfigFileModule.f90` subsection `specifications_DOAS_DISMAS`

## Background

The vendor method menu is broader than one “DOAS-like” path. It includes DOAS, classic DOAS, and DOMINO-NO2, each with distinct fitting assumptions and config constraints. The verifier enforces NO2-specific rules for DOMINO that the Zig runtime currently does not match. This WP brings those families over explicitly instead of flattening them into a single placeholder route.

## Overarching Goals

- Implement real differential spectral fitting, not summary-scalar placeholders.
- Support classic DOAS and DOMINO-specific semantics explicitly.
- Enforce vendor-like config legality for NO2 family cases.

## Non-goals

- Direct-intensity DISMAS fitting; that is `WP-13`.
- Treating DOMINO as “just DOAS with a flag.”
- Hiding family differences behind one giant all-method solver.

### WP-12 DOAS, classic DOAS, and DOMINO parity [Status: Todo]

Issue:
The current Zig DOAS path is still a surrogate. The vendor code distinguishes multiple differential families and also enforces strict DOMINO constraints on which NO2 species may be present and fitted.

Needs:
- real differential spectral residuals
- polynomial baseline and differential/effective cross-section handling
- family-specific mode branching for DOAS, classic DOAS, and DOMINO
- vendor-like legality checks for NO2/trop_NO2/strat_NO2

How:
1. Reuse the real spectral evaluator and state access from OE.
2. Implement differential preprocessing and baseline fitting for DOAS families.
3. Add DOMINO-specific NO2 handling and config verification.
4. Validate against NO2 DOMINO and mixed UV/Vis cases.

Why this approach:
The vendor code treats differential methods as distinct families with distinct data preparation and legal-state assumptions. Zig should mirror that separation to stay scientifically honest.

Recommendation rationale:
This follows OE because it reuses the shared spectral and state infrastructure, but it needs its own implementation rather than being forced into an OE-shaped loop.

Desired outcome:
The Zig runtime can execute DOAS, classic DOAS, and DOMINO-NO2 through distinct, typed paths with method-appropriate outputs and legality checks.

Non-destructive tests:
- `zig build test-validation --summary all`
- `zig test tests/validation/doas_parity_test.zig`
- `zig test tests/integration/retrieval_solver_integration_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Retrieval family targets:
  - `src/retrieval/doas/solver.zig`
  - `src/retrieval/common/spectral_fit.zig`
  - `src/retrieval/common/forward_model.zig`
  - `src/retrieval/common/state_access.zig`
  - `src/retrieval/common/diagnostics.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
  - `src/model/InverseProblem.zig`
  - `src/model/Measurement.zig`
- Engine/provider targets:
  - `src/core/Engine.zig`
  - `src/plugins/providers/retrieval.zig`
- Validation targets:
  - `tests/validation/doas_parity_test.zig`
  - `tests/integration/retrieval_solver_integration_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/retrieval/doas/solver.zig`: split the current placeholder into explicit family routes for DOAS, classic DOAS, and DOMINO.
  - Vendor anchors: `doasModule.f90`, `classic_doasModule.f90`, and `readConfigFileModule.f90` retrieval method values.
  - Each family should declare its own preprocessing, fit basis, and output semantics instead of sharing one summary-based approximation.

- [ ] `src/retrieval/common/spectral_fit.zig` and `forward_model.zig`: add real differential preprocessing and baseline modeling.
  - Vendor anchors: vendor DOAS modules and `readConfigFileModule.f90` subsection `specifications_DOAS_DISMAS`.
  - Support polynomial baselines, strong-absorption flags, wavelength windows, and effective cross sections where configured.
  - Do not treat differential fitting as a wrapper around a broadband summary feature vector.

- [ ] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/InverseProblem.zig`: expose family-specific DOAS and DOMINO controls.
  - Vendor anchors: `readConfigFileModule.f90::{readGeneral,readRetrieval}`; method values `2` (DOAS), `3` (classic DOAS), `4` (DOMINO-NO2).
  - Keep family identity explicit in config and prepared plans.

- [ ] `src/core/Engine.zig` and `src/plugins/providers/retrieval.zig`: route to the correct family and enforce vendor-like legality rules.
  - Vendor anchors: `verifyConfigFileModule.f90` checks involving `NO2`, `trop_NO2`, `strat_NO2`, and DOMINO constraints such as what may be fitted and what must exist but remain unfitted.
  - These checks belong before execution, not inside a late iterative failure.

- [ ] `tests/validation/doas_parity_test.zig`, `tests/integration/retrieval_solver_integration_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add family-specific parity cases.
  - Required cases: `Config_NO2_DOMINO.in`, one standard DOAS-family case, and one mixed-gas UV/Vis case.
  - Validate family choice, legality checks, retrieved outputs, and residual quality separately.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] DOAS, classic DOAS, and DOMINO are distinct runtime families
- [ ] DOMINO NO2 legality checks match the vendor verifier behavior
- [ ] At least one DOMINO and one non-DOMINO differential case validate end-to-end

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

Differential retrieval families differ both mathematically and in what the config is allowed to say. Pulling vendor-specific legality checks and family identity into the Zig runtime prevents accidental overgeneralization and keeps the fit logic scientifically interpretable.

## Proof / Validation

- Planned: `zig test tests/validation/doas_parity_test.zig` -> differential families execute with family-specific outputs and residual behavior
- Planned: `zig test tests/integration/retrieval_solver_integration_test.zig` -> engine routing and family-specific config compilation are correct
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> vendor NO2-family cases classify and execute through the right family path

## How To Test

1. Run `Config_NO2_DOMINO.in` through the compatibility harness.
2. Confirm DOMINO-specific legality checks fire on intentionally invalid NO2-family variants.
3. Run one standard DOAS and one classic DOAS case and compare residual structure and outputs.
4. Verify provenance records which differential family executed.
