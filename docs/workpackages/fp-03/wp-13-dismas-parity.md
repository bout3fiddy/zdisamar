# WP-13 DISMAS Parity

## Metadata

- Created: 2026-03-18
- Scope: implement vendor-faithful direct-intensity DISMAS fitting on top of the repaired spectral forward model and shared retrieval infrastructure
- Input sources:
  - vendor `dismasModule.f90`
  - vendor `readConfigFileModule.f90::{readGeneral,readRetrieval}`
  - vendor DISMAS example configs
  - Zig DISMAS and shared retrieval files
- Dependencies:
  - `WP-04`, `WP-06`, `WP-09`, and `WP-11`
- Reference baseline:
  - vendor `dismasModule.f90`
  - vendor `readConfigFileModule.f90` subsection `specifications_DOAS_DISMAS`
  - vendor example case `Config_O3_profile_SO2_column_DISMAS_5.in`

## Background

DISMAS is not just “another retrieval method name.” The vendor code treats it as a direct-intensity spectral fitting family with its own wavelength selection and handling of smooth versus differential absorption structure. The current Zig DISMAS path is still placeholder-level.

## Overarching Goals

- Implement real direct-intensity fitting on instrument-level spectra.
- Support vendor-like wavelength/window and strong-absorption controls.
- Reuse the shared state and spectral infrastructure without flattening DISMAS into DOAS or OE semantics.

## Non-goals

- Differential DOAS-family logic.
- Broad summary-scalar fitting.
- Treating DISMAS as a minor option on the OE solver.

### WP-13 DISMAS parity [Status: Todo]

Issue:
The current DISMAS path is still a named scaffold, not a method-faithful direct-intensity solver.

Needs:
- instrument-level direct-intensity residuals
- method-specific wavelength and baseline handling
- shared but method-aware state/update infrastructure
- method-specific diagnostics layered cleanly on top of the shared execution-telemetry substrate
- validation on DISMAS-specific example cases

How:
1. Reuse the spectral forward model and typed state access from OE.
2. Implement DISMAS-specific residual assembly and wavelength controls.
3. Add method-specific diagnostics and outputs while reusing the shared execution-telemetry substrate for timing and iteration traces.
4. Validate on at least one vendor DISMAS example.

Why this approach:
DISMAS should share plumbing with the rest of the retrieval stack but not its mathematical assumptions. Building it after OE gives the necessary shared machinery without forcing the method into the wrong shape.

Recommendation rationale:
This comes after DOAS-family work because OE and differential methods supply the shared spectral and covariance infrastructure DISMAS also needs.

Desired outcome:
Zig can run a DISMAS example case through a real direct-intensity spectral fit path with method-appropriate diagnostics and outputs.

Non-destructive tests:
- `zig build test-validation --summary all`
- `zig test tests/validation/dismas_parity_test.zig`
- `zig test tests/integration/retrieval_solver_integration_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Retrieval family targets:
  - `src/retrieval/dismas/solver.zig`
  - `src/retrieval/common/spectral_fit.zig`
  - `src/retrieval/common/forward_model.zig`
  - `src/retrieval/common/state_access.zig`
  - `src/retrieval/common/diagnostics.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
  - `src/model/InverseProblem.zig`
- Engine/provider targets:
  - `src/core/Engine.zig`
  - `src/plugins/providers/retrieval.zig`
- Validation targets:
  - `tests/validation/dismas_parity_test.zig`
  - `tests/integration/retrieval_solver_integration_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/retrieval/dismas/solver.zig`: replace the current placeholder with a method-faithful direct-intensity fit loop.
  - Vendor anchors: `dismasModule.f90`.
  - Build the residual on the instrument-level direct spectrum, not on summary scalars.
  - Keep method-specific state/update logic isolated from OE and DOAS paths.

- [ ] `src/retrieval/common/spectral_fit.zig` and `forward_model.zig`: add DISMAS-specific wavelength selection and fit-window preparation.
  - Vendor anchors: `readConfigFileModule.f90` subsection `specifications_DOAS_DISMAS` and `dismasModule.f90`.
  - Support strong-absorption and wavelength-selection controls that matter for DISMAS.
  - Do not reuse DOAS differential preprocessing blindly.

- [ ] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/InverseProblem.zig`: expose DISMAS controls explicitly in typed config.
  - Vendor anchors: `readGeneral` method selection and DISMAS-related spectral-fit settings.
  - Ensure prepared plans can distinguish DISMAS from other retrieval families without fragile string checks.

- [ ] `src/core/Engine.zig` and `src/plugins/providers/retrieval.zig`: route to DISMAS as a distinct method family.
  - The engine should not force DISMAS through OE or DOAS-specific product assumptions.
  - Result/provenance should name the actual family executed.
  - Execution timing and iteration traces should flow through the shared telemetry substrate from `WP-10`, not through DISMAS-local logging or side-channel counters.

- [ ] `src/retrieval/common/diagnostics.zig`: keep DISMAS scientific diagnostics and fit summaries distinct from execution telemetry.
  - Residual and fit-window diagnostics are part of the scientific result surface.
  - Timing, route, and iteration-span reporting should use the shared telemetry substrate instead of widening scientific diagnostic structs with runtime-only fields.

- [ ] `tests/validation/dismas_parity_test.zig`, `tests/integration/retrieval_solver_integration_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add DISMAS parity cases.
  - Required case: `Config_O3_profile_SO2_column_DISMAS_5.in` or equivalent vendor DISMAS example.
  - Validate fit residuals, retrieved outputs, and method routing.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] DISMAS is a distinct direct-intensity family in config, engine routing, and outputs
- [ ] Instrument-level spectral residuals drive the fit
- [ ] DISMAS scientific diagnostics remain separate from shared execution telemetry
- [ ] At least one vendor DISMAS case validates end-to-end

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

DISMAS can share the repaired spectral forward machinery and the shared execution-telemetry substrate without being collapsed into another family’s math. That preserves method identity while avoiding duplicate plumbing.

## Proof / Validation

- Planned: `zig test tests/validation/dismas_parity_test.zig` -> DISMAS case executes with method-appropriate residuals and outputs
- Planned: `zig test tests/integration/retrieval_solver_integration_test.zig` -> engine and provider routing choose the DISMAS path correctly
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> vendor DISMAS configs map and execute through the new family path

## How To Test

1. Run a vendor DISMAS case through the compatibility harness.
2. Inspect the method routing and fit residuals.
3. Compare retrieved outputs against vendor references or expected metrics.
4. Confirm provenance records a DISMAS run, not a generic OE or DOAS surrogate.
