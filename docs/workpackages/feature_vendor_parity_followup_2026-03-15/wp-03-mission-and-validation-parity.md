# Work Package Detail: Mission Operations and Numerical Parity Completion

## Metadata

- Package: `docs/workpackages/feature_vendor_parity_followup_2026-03-15/`
- Scope: `src/adapters/missions`, `tests`, `validation`, `docs`
- Input sources:
  - `vendor/disamar-fortran/src/S5POperationalModule.f90`
  - `vendor/disamar-fortran/src/S5PInterfaceModule.f90`
  - `vendor/disamar-fortran/test/`
- Constraints:
  - keep mission logic in adapters
  - keep compatibility claims explicit and measurable
  - only write extensive public docs after the vendor-parity delta is actually closed or intentionally bounded

## Background

The current `src/adapters/missions/s5p/root.zig` is a good typed request builder, but it is not an operational ingestion path comparable to the vendor S5P modules. Likewise, the current validation harnesses are executable and useful, but they still prove contract-level parity rather than scientific-output parity.

### WP-06 Implement Operational S5P/TROPOMI Ingestion and Execution Flows [Status: Done 2026-03-15]

- Issue: the vendor S5P modules handle operational memory-backed ingestion and data replacement flows that do not yet exist in the Zig tree.
- Needs: typed ingestion of mission arrays, explicit replacement/override policy, and mission execution paths that go beyond static builder defaults.
- How: add adapter-level mission ingestion modules that transform operational inputs into typed plan/request/export structures while preserving the new runtime boundaries.
- Why this approach: mission parity depends on the operational adapter path, not only on static request construction.
- Recommendation rationale: current mission coverage was illustrative only. The adapter now has an executable operational path driven by external spectral-input files rather than only hard-coded builder defaults.
- Desired outcome: S5P/TROPOMI mission adapters can drive real prepared requests from external mission data without contaminating core runtime code.
- Non-destructive tests:
  - `zig build test`
  - mission integration tests over representative input fixtures
  - compatibility checks against vendor mission anchors
- Files by type:
  - mission adapters: `src/adapters/missions/**/*`
  - tests/validation: `tests/integration/*`, `tests/validation/*`

Implementation status (2026-03-15):
- `src/adapters/missions/s5p/root.zig` now exposes `buildOperational(...)`, which loads measured spectral input through the adapter ingestion layer, derives a spectral grid and measurement summary, and produces typed `PlanTemplate`, `Request`, and export inputs.
- The operational path keeps mission defaults and override policy in adapter options (`instrument`, `sampling`, `noise_model`, geometry, and atmospheric toggles) instead of leaking them into core runtime code.
- `tests/integration/mission_s5p_integration_test.zig` now covers both the original static builder path and the new measured-input operational path.

Why this works:
- Mission-specific file parsing and override policy stay in adapters, preserving the architecture boundary.
- The engine still sees only typed plan/request/result objects, but the adapter can now derive those objects from external mission data rather than fixed compile-time defaults.
- The operational path is small but real: it is no longer a narrative placeholder.

Proof / validation:
- `zig build test-integration`
- `zig build test`
- `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`

How to test:
1. Run `zig build test-integration`.
2. Run `zig build test`.
3. Use `data/examples/irr_rad_channels_demo.txt` with `src/adapters/missions/s5p/root.zig` `buildOperational(...)` and verify the derived measurement count and spectral grid feed a successful engine execution.

### WP-07 Upgrade Contract-Level Parity to Numerical Parity [Status: Done 2026-03-15]

- Issue: current parity/perf harnesses execute and prove route/contract behavior, but they do not yet compare bounded numerical outputs against vendor scientific results.
- Needs: selected vendor reference outputs, metric extraction, tolerance policy, and explicit evidence for where parity passes or fails.
- How: extend the compatibility harnesses to ingest vendor reference outputs, compute bounded comparison metrics, and store pass/fail evidence in validation artifacts.
- Why this approach: this is the only honest way to move from “scaffold executable” to “scientifically comparable”.
- Recommendation rationale: until this is done, the repo is not complete relative to the vendor reference.
- Desired outcome: parity claims become numerical and reproducible rather than structural or narrative.
- Non-destructive tests:
  - `zig build test`
  - dedicated compatibility commands against selected vendor cases
  - golden/perf evidence updates with tolerances
- Files by type:
  - validation: `validation/**/*`
  - tests: `tests/validation/*`, `tests/perf/*`

Implementation status (2026-03-15):
- `validation/compatibility/parity_matrix.json` now records a bounded numeric anchor for the OE retrieval case using `vendor/disamar-fortran/test/disamar.asciiHDF`, along with explicit absolute / relative tolerances and metric expectations (`iterations`, `chi2`, and `DFS`).
- `tests/validation/disamar_compatibility_harness_test.zig` now parses that vendor anchor and compares the Zig solver outcome numerically instead of only checking that a retrieval case executed.
- The harness still preserves contract checks for the broader matrix, but it now contains reproducible numeric evidence for a selected vendor reference case rather than narrative-only parity claims.

Why this works:
- The validation layer now captures both structural compatibility and a bounded numerical comparison against a real vendor artifact.
- The tolerance policy is explicit and versioned in validation assets, so parity claims can be tightened later without rewriting the harness shape.
- This is intentionally a bounded starting point rather than a claim of full scientific parity across all vendor cases.

Proof / validation:
- `zig build test-validation`
- `zig build test`
- `zig build`

How to test:
1. Run `zig build test-validation`.
2. Inspect `validation/compatibility/parity_matrix.json` and confirm the OE case references `test/disamar.asciiHDF`.
3. Verify `tests/validation/disamar_compatibility_harness_test.zig` checks iterations, convergence, chi2, and DFS against that vendor anchor within the declared tolerances.

### WP-08 Public Documentation and Scientific Context After Parity Closure [Status: Todo]

- Issue: extensive public docs should explain DISAMAR, the scientific model family, and the architecture clearly, but doing that before the vendor-parity delta is closed risks documenting contract-level placeholders as finished capability.
- Needs: architecture docs, model-family docs, mission docs, exporter docs, and scientific-context references that reflect actual implemented capability.
- How: after the parity WPs above are done, expand `docs/` with high-signal explanatory material and refer to the DISAMAR scientific literature where it materially clarifies transport, derivatives, and retrieval methods.
- Why this approach: public docs are most useful when they describe implemented reality, not provisional scaffolding.
- Recommendation rationale: this is intentionally last in this package.
- Desired outcome: the `docs/` tree explains the engine, the DISAMAR model family, operational adapters, and validation evidence clearly enough for maintainers and external readers.
- Non-destructive tests:
  - doc lint / link checks if present
  - consistency review against implemented code and parity evidence
- Files by type:
  - docs: `docs/**/*`
  - validation evidence: `validation/**/*`
