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

### WP-06 Expand Compatibility Coverage Beyond the Current OE Anchor [Status: Done 2026-03-15]

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

- Implementation status (2026-03-15): done. `validation/compatibility/parity_matrix.json` now covers bounded O2 A-band optics preparation and Mie-influenced measurement-space cases in addition to the earlier OE anchor. `tests/validation/disamar_compatibility_harness_test.zig` now materializes bundle-backed optical state per case, validates O2 A-band strong-line mixing, validates Mie-driven phase-coefficient preparation, and runs `measurement_space` representative cases. The runtime execution path now also consumes tracked bundle assets through `src/runtime/reference/BundledOptics.zig`, and both `src/core/Engine.zig` and `src/retrieval/common/synthetic_forward.zig` use that path instead of the older demo-only builders.
- Why this works: the closure criterion for this WP was broader representative evidence, not a single anchor retrieval. The repo now exercises the remaining bounded scientific surfaces that were still missing from the matrix: O2 A-band spectroscopy preparation, aerosol/Mie optical preparation, and runtime measurement-space execution against the tracked bundles that the vendor comparison is based on.
- Proof / validation: `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test-perf`, `zig test src/exporters_wp12_test_entry.zig`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed on 2026-03-15 after switching runtime execution to bundle-backed optics preparation.
- How to test:
  - `zig build test-validation`
  - `zig build test`
  - `zig build`
  - `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`
  - inspect `validation/compatibility/parity_matrix.json` and the `optics` / `measurement_space` branches in `tests/validation/disamar_compatibility_harness_test.zig`

### WP-07 Write Public Docs Only After the Parity Audit Closes [Status: In Progress 2026-03-15]

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

- Implementation status (2026-03-15): in progress. The later runtime-activation package closed the remaining operational parity blockers by landing typed weighted refspec grids, external high-resolution solar spectra, and O2 / O2-O2 operational LUT inputs across the S5P adapter, optics, and measurement-space paths. Public docs are now active in `docs/README.md`, `docs/disamar-overview.md`, `docs/zig-architecture.md`, `docs/operational-o2a.md`, and `docs/retrieval-and-measurement-space.md`, with the remaining detail work tracked in `docs/workpackages/feature_vendor_runtime_activation_2026-03-15/wp-03-public-docs.md`.
- Why this works so far: the old blocker condition for this WP was “do not write docs while concrete runtime/scientific parity gaps remain.” That condition is no longer true, so the docs pass can now proceed without overstating a missing implementation surface.
- Proof / validation so far: the public-docs handoff happened only after `zig build test-unit`, `zig build test-integration`, `zig build test-validation`, `zig build test-perf`, `zig build test`, `zig build`, `zig test src/exporters_wp12_test_entry.zig`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` passed with the weighted refspec and high-resolution solar paths enabled.
- How to test:
  - read `docs/workpackages/feature_vendor_runtime_activation_2026-03-15/wp-03-public-docs.md`
  - cross-check the new `docs/` files against the current source tree and the vendored operational references
  - verify the cited papers are the primary literature for the scientific explanations
- Remaining gap before done: finish the active `docs/` pass and run a final consistency review so the public docs and workpackage history align.
