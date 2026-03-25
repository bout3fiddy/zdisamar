# Full DISAMAR Capability Parity Plan

## Execution Directive (Standard)

```text
REQUIRED: Replace every <VARIABLE> placeholder before running this directive. Do not leave any <...> token unresolved.

start implementing fixes per work package: docs/workpackages/feature_full_disamar_capability_parity_2026-03-18/

if a directory path is provided:
- scan all markdown files in that directory
- read `overview.md` first
- read `coverage-index.md` second
- start from the first non-done `WP-*`

ensure changes are non-destructive.

the app is locally hosted at <APP_URL>, started via <APP_START_COMMAND>.
use browser tooling only when there is a real browser-viewable artifact; otherwise validate with repo commands, artifact inspection, and parity harness outputs.

when each work package item is implemented:
- complete every checkbox in that WP's `## Completion Checklist` individually
- update that WP with:
  - updated Recommendation rationale
  - Implementation status (YYYY-MM-DD)
  - Why this works
  - Proof / validation
  - How to test
- mark the WP title status line as [Status: Done YYYY-MM-DD] only after all checklist boxes are checked
- update `overview.md` with status, last-updated date, proof pointer, and next action
- update `coverage-index.md` if new files were added or ownership changed

a WP item is NOT done until every checklist box is checked.
do not advance to the next WP until the current one's checklist is fully complete.

before every commit:
- stage only intended shipping files with explicit paths
- never use `git add .`, `git add -A`, or `git add -f`
- inspect ignored state before staging
- do not stage workpackage tracking docs unless explicitly requested

commit and push periodically as coherent checkpoints for shipping files only.

default to hard cutovers; do not add fallback branches or shims unless explicitly approved.
```

## Metadata

- Created: 2026-03-18
- Scope: replace the O2A-first parity plan with a full DISAMAR capability-and-config parity program that still uses O2 A-band as the first forcing case
- Input sources:
  - `current_state_and_findings_2026-03-17.md`
  - `workpackage_template.md`
  - the earlier O2A-focused parity workpackage set
  - `vendor_disamar_fortran_2026-03-17.tar.gz`
  - `zdisamar_feature_parity_r2_2026-03-17.bundle`
- Constraints:
  - preserve the typed Zig engine shape; do not recreate the vendor global-state architecture
  - bias strongly toward scientific correctness over architecture polish
  - keep outputs local-only and unversioned unless explicitly requested
  - treat O2 A-band as the first forcing case, not as the full program boundary
  - do not claim config parity until every vendor config key is classified and either honored or explicitly unsupported

## Background

The O2 A-band comparison is still the most useful forcing case because it exposed the actual bottleneck: the dominant mismatch is forward radiance physics and numerics, not retrieval cosmetics. But the vendored DISAMAR codebase is much broader than that single case. It supports line-absorbing and cross-section retrieval families, multiple instrument and mission pathways, measured radiance/irradiance workflows, LUT and XsecLUT generation, Raman/Ring-related corrections, offsets, stray-light controls, aerosol/cloud/subcolumn semantics, and a much larger configuration surface than the current canonical YAML fully represents.

So the objective is no longer just “repair O2A.” The objective is:

1. use O2A to force honest forward-model parity,
2. expand canonical YAML and runtime behavior to cover the full DISAMAR config surface,
3. then close the broader capability families systematically.

## Why This Replaces The Narrower Plan

The earlier O2A-focused set was the right corrective to an overemphasis on retrieval and plugin hygiene, but it still stopped short of your actual goal: a fully capable `zdisamar` that can handle the DISAMAR feature/config surface rather than only the first forcing case.

This plan therefore adds or expands dedicated work for:

- full config-surface and runtime-honor parity
- line-absorbing spectroscopy beyond the single O2A slice
- cross-section gas and effective-xsec pathways
- atmospheric interval, cloud/aerosol fraction, and subcolumn semantics
- measured radiance/irradiance and S5P operational pathways
- LUT and XsecLUT creation and consumption
- additional output and diagnostics parity
- a multi-case vendor-vs-Zig acceptance matrix, not just one O2A overlay

## Overarching Goals

- Reach method-faithful forward parity before declaring retrieval parity.
- Make every scientifically important DISAMAR config item either exactly expressible, approximately expressible with provenance, or explicitly unsupported.
- Separate line-absorbing, cross-section, measured-input, and retrieval-family parity so each has its own validation gate.
- Replace vague “feature parity” claims with artifact-backed, case-backed acceptance criteria.
- Keep the Zig architecture typed and maintainable while broadening scientific scope.

## Non-goals

- Reproducing vendor global state, COMMON-block style flows, or monolithic Fortran wiring.
- Claiming parity from qualitative plots alone.
- Preserving permissive parse-and-ignore behavior in canonical YAML.
- Keeping surrogate forward or retrieval implementations under method-faithful names.
- Letting plugin/runtime hygiene outrank science parity.

## Current Findings To Preserve

- The current O2 A-band mismatch is not primarily a retrieval problem.
- The wavelength grid and solar irradiance are already close enough that forward radiance physics/numerics remain the decisive gap.
- The current YAML port is closer than before, but is still not a 1:1 representation of the vendor config surface.
- The main missing parity areas already identified remain valid: transport semantics, O2 spectroscopy controls, pressure-space aerosol interval handling, and adaptive strong-line sampling.
- The old remainder plan did not directly solve the forward O2 A-band gap.
- Fixing O2 A-band alone is necessary but not sufficient for full DISAMAR parity.

## Program Structure

This plan is intentionally staged.

## Cross-Cutting Rule: Execution Telemetry Vs Scientific Diagnostics

- Structural provenance remains a core concern and stays on the typed `Result`/`Provenance` path.
- Scientific diagnostics remain typed forward/retrieval products and solver summaries; they are not a generic logging stream.
- Execution telemetry is a separate shared substrate for timings, cache-hit and cache-miss reporting, route decisions, and iteration or stage traces when requested.
- The telemetry substrate should land at the core and runtime boundary so later workpackages can consume it without inventing package-local timer or logging side channels.
- `WP-10` owns the shared telemetry substrate, `WP-13` consumes it for DISMAS-specific stage and iteration visibility, `WP-14` keeps scientific diagnostic products distinct from telemetry, and `WP-15` removes or gates any leftover ad hoc runtime instrumentation paths.

### Stage A — Control surface and forward-core parity
- `WP-01` full config surface and canonical YAML parity
- `WP-02` forward transport solver parity
- `WP-03` line-absorbing spectroscopy and strong-line sampling parity
- `WP-04` cross-section gas and effective-xsec parity
- `WP-05` atmospheric intervals, aerosol, cloud, fraction, and subcolumns parity
- `WP-06` instrument, radiance/irradiance, slit, calibration, corrections, and Ring parity
- `WP-07` operational measured-input and S5P interface parity
- `WP-08` LUT and XsecLUT generation, consumption, and cache parity

### Stage B — Proof that parity is real
- `WP-09` vendor-vs-Zig multi-case validation and scientific acceptance
- `WP-10` performance benchmarking and regression thresholds

### Stage C — Retrieval-family parity built on a real forward model
- `WP-11` optimal estimation, Jacobian, and weighting-function parity
- `WP-12` DOAS, classic DOAS, and DOMINO parity
- `WP-13` DISMAS parity

### Stage D — Outputs and cleanup after science parity
- `WP-14` additional output, diagnostics, and export parity
- `WP-15` plugin, adapter, and hygiene after scientific parity

## Priority Ladder

1. `WP-01` full-config-surface-and-canonical-yaml-parity
2. `WP-02` forward-transport-solver-parity
3. `WP-03` line-absorbing-spectroscopy-and-strong-line-sampling-parity
4. `WP-04` cross-section-gas-and-effective-xsec-parity
5. `WP-05` atmospheric-intervals-aerosol-cloud-fraction-and-subcolumns-parity
6. `WP-06` instrument-radiance-irradiance-slit-calibration-corrections-and-ring-parity
7. `WP-07` operational-measured-input-and-s5p-interface-parity
8. `WP-08` lut-and-xseclut-generation-consumption-and-cache-parity
9. `WP-09` vendor-vs-zig-multi-case-validation-and-scientific-acceptance
10. `WP-10` performance-benchmarking-and-regression-thresholds
11. `WP-11` optimal-estimation-jacobian-and-weighting-function-parity
12. `WP-12` doas-classic-doas-and-domino-parity
13. `WP-13` dismas-parity
14. `WP-14` additional-output-diagnostics-and-export-parity
15. `WP-15` plugin-adapter-and-hygiene-after-scientific-parity

## Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| [WP-01](./wp-01-full-config-surface-and-canonical-yaml-parity.md) | Done | 2026-03-18 | 34/34 unit, 35/35 validation; 415-entry matrix fully classified; 13 typed sub-doc structs | Start `WP-02` |
| [WP-02](./wp-02-forward-transport-solver-parity.md) | Done | 2026-03-21 | Typed RTM controls, scalar LABOS/adding route split, source-harness adding proofs, prepared-route RTM quadrature proofs, pseudo-spherical prepared-shell handoff, targeted RTM-sensitive integration, compatibility-harness route check, and the O2A morphology gate are all green on the completed scalar forward-core slice; the latest local revalidation added the promoted prepared-adding RTM subgrid-node slice plus direct `transport_source_tests`, O2A morphology, and compatibility-harness checks on the current head | Start `WP-03` |
| [WP-03](./wp-03-line-absorbing-spectroscopy-and-strong-line-sampling-parity.md) | Done | 2026-03-23 | Multi-gas line-absorber prep, adaptive strong-line sampling, bundled O2A CIA/line-asset gating, and prepared-RTM quadrature stabilization are now in place; `zig build check`, `zig build test-unit --summary all` -> `46/46`, `zig build test-validation-line-gas --summary all` -> `2/2`, and `zig build test-validation-o2a --summary all` -> `5/5` are green on the current branch state | Start `WP-04`; keep the broader canonical-config and typed-forward O2A red lanes tracked outside WP-03 acceptance |
| [WP-04](./wp-04-cross-section-gas-and-effective-xsec-parity.md) | Done | 2026-03-24 | Fresh independent verifier loop cleared the current shipping diff: correctness audit passed, coverage/context audit passed, and `zig build test-unit --summary all` -> `129/129` plus `zig build test-validation-cross-section-parity --summary all` -> `3/3` were reproduced on the live branch | Start `WP-05` |
| [WP-05](./wp-05-atmospheric-intervals-aerosol-cloud-fraction-and-subcolumns-parity.md) | Done | 2026-03-25 | Explicit pressure-bounded interval grids, typed aerosol/cloud placement and fraction controls, prepared-optics provenance metadata, and subcolumn-partition parity checks are in place; post-review hardening also aligned explicit-grid workspace sizing and tightened fraction-grid validation, and `zig build test-unit --summary all`, `zig build test-integration-forward-model --summary all`, `zig build test-validation-o2a --summary all`, and `zig build test-validation-compatibility-full --summary all` are green on the WP-05 branch state, while broader integration and validation red lanes were reproduced on clean `HEAD` and remain out of scope for this WP | Start `WP-06` |
| [WP-06](./wp-06-instrument-radiance-irradiance-slit-calibration-corrections-and-ring-parity.md) | Todo | 2026-03-18 | Radiance / irradiance / Ring / correction acceptance in `WP-09` | Wait for `WP-05` |
| [WP-07](./wp-07-operational-measured-input-and-s5p-interface-parity.md) | Todo | 2026-03-18 | Measured-input and S5P operational path acceptance in `WP-09` | Wait for `WP-06` |
| [WP-08](./wp-08-lut-and-xseclut-generation-consumption-and-cache-parity.md) | Todo | 2026-03-18 | LUT/XsecLUT regeneration and runtime use acceptance in `WP-09` | Wait for `WP-07` |
| [WP-09](./wp-09-vendor-vs-zig-multi-case-validation-and-scientific-acceptance.md) | Todo | 2026-03-18 | Multi-case artifact manifest, metrics, overlays, and review notes | Wait for `WP-08` |
| [WP-10](./wp-10-performance-benchmarking-and-regression-thresholds.md) | Todo | 2026-03-23 | Shared execution-telemetry substrate plus forward / retrieval benchmark report | Wait for `WP-09`, then land the core/runtime telemetry substrate before case-family thresholds |
| [WP-11](./wp-11-optimal-estimation-jacobian-and-weighting-function-parity.md) | Todo | 2026-03-23 | OEM convergence, posterior, gain, AK, DFS, weighting-function, and iteration-telemetry report | Wait for `WP-10` after the shared telemetry substrate is in place |
| [WP-12](./wp-12-doas-classic-doas-and-domino-parity.md) | Todo | 2026-03-18 | Differential residuals and DOMINO-style case acceptance | Wait for `WP-11` |
| [WP-13](./wp-13-dismas-parity.md) | Todo | 2026-03-23 | Direct-intensity fit acceptance report with DISMAS stage and iteration telemetry | Wait for `WP-11` and reuse the shared telemetry substrate from `WP-10` |
| [WP-14](./wp-14-additional-output-diagnostics-and-export-parity.md) | Todo | 2026-03-23 | Additional-output comparison matrix, scientific diagnostic product inventory, and exporter acceptance | Wait for `WP-13`; keep scientific outputs separate from execution telemetry |
| [WP-15](./wp-15-plugin-adapter-and-hygiene-after-scientific-parity.md) | Todo | 2026-03-23 | Build / test / export stability after cleanup and telemetry/logging seam cleanup | Wait for `WP-14` and collapse leftover ad hoc instrumentation paths |

## Acceptance Doctrine

The phrase “parity” has a strict meaning in this plan.

- **Exact parity** means a vendor control is expressible in canonical YAML, honored by runtime behavior, and validated against one or more vendor cases.
- **Approximate parity** means the same scientific intent is represented, but the runtime still differs in a declared and bounded way; provenance and validation must say so.
- **Unsupported** means the canonical YAML may expose a placeholder or reject the field explicitly, but the runtime does not pretend to honor it.
- **Parsed-but-ignored is forbidden** by the end of `WP-01`.

## Coverage Proof

See `coverage-index.md` for the second-pass ownership map. It assigns:

- every planning input,
- every representative vendor config family,
- every important vendor Fortran source module,
- every current Zig subsystem file,
- and every known comparison artifact family

to a specific workpackage or an explicit preserve-only bucket.

The point of the coverage index is to prevent accidental omission while the plan broadens from O2A-first parity to full DISAMAR capability parity.
