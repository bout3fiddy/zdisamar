# Work Package Detail: Parity Expansion and Public Docs Closure

## Metadata

- Package: `docs/workpackages/feature_vendor_parity_closure_2026-03-15/`
- Scope: `tests/validation/`, `tests/perf/`, `validation/`, `docs/`
- Input sources:
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `vendor/disamar-fortran/src/S5POperationalModule.f90`
  - `docs/workpackages/feature_vendor_parity_followup_2026-03-15/wp-03-mission-and-validation-parity.md`
- Constraints:
  - keep public docs blocked until the parity audit is honest
  - separate “bounded representative parity” from “full upstream equivalence”
  - cite scientific sources where public docs explain DISAMAR behavior or context

## Background

The repo now has a meaningful parity harness, but it is still narrow. Public docs are intentionally blocked because the remaining audit still points at concrete missing scientific/runtime surfaces. This package closes that last mile in two stages: broader bounded parity evidence first, public docs second.

### WP-06 Expand Compatibility Coverage Beyond the Current OE Anchor [Status: Todo]

- Issue: the current compatibility matrix is still centered on a bounded OE case and does not yet cover the remaining representative surfaces needed for an honest closure claim.
- Needs: additional bounded cases for O2A spectroscopy, aerosol/cloud optical-property behavior, and measurement-space outputs where vendor outputs can be compared safely.
- How: add more tracked validation cases, explicit tolerances, and parity-harness outputs that cover the remaining representative physics surfaces without pretending to reproduce the full upstream database.
- Why this approach: the repo should only exit the parity phase with evidence that spans the remaining vendor surfaces.
- Recommendation rationale: a closure claim without broader bounded parity evidence would still be overstated.
- Desired outcome: the validation matrix demonstrates bounded agreement across gas-only, spectroscopy-heavy, and aerosol/cloud-influenced representative cases.
- Non-destructive tests:
  - `zig build test-validation`
  - `zig build test-perf`
  - targeted compatibility harness runs
- Files by type:
  - validation/tests: `validation/**/*`, `tests/validation/**/*`, `tests/perf/**/*`

### WP-07 Write Public Docs Only After the Parity Audit Closes [Status: Todo]

- Issue: the public `docs/` pass has been deferred correctly, but it still needs a concrete closure package so it is not forgotten once the scientific gap is actually bounded.
- Needs: architecture-aware scientific docs explaining DISAMAR-in-zdisamar, bounded parity scope, mission/adaptor flow, and the relevant literature context.
- How: after the remaining vendor delta is reduced to intentional architecture drift, author a focused public-docs package covering scientific context, engine architecture, retrieval/transport concepts, and operational boundaries, citing the relevant DISAMAR paper and related references where appropriate.
- Why this approach: the docs should explain both what the system does and what parts are bounded approximations, not present a misleading equivalence claim.
- Recommendation rationale: public docs are only useful once the implementation status is honest and stable.
- Desired outcome: `docs/` explains DISAMAR in the context of the Zig architecture, the bounded parity claim, and the scientific papers underpinning the model family.
- Non-destructive tests:
  - docs review against actual code and validation state
  - link/reference checks where applicable
  - final vendor audit summary recorded in the docs set
- Files by type:
  - docs/workpackages/public docs: `docs/**/*`
