# WP-01 Critical Correctness and Execution Honesty

## Metadata

- Created: 2026-03-16
- Scope: fix the hard bugs and semantic misbindings that can invalidate every later parity step
- Input sources: audit sections `Core`, `Transport`, `Retrieval`, `Adapters and I/O`, `Bad Zig usage and style issues`
- Dependencies: none; this is the first execution WP
- Reference baseline: the vendored Fortran implementation is the parity target, but this WP is mostly about internal correctness and honest semantics rather than direct source translation

## Background

The audit identified several issues that are not "future parity" work. They are immediate correctness bugs or execution-honesty gaps inside the current scaffold: lifetime-based plan exhaustion, silent external-observation self-binding, derivative-mode validation against the wrong state, singular covariance whitening being masked, `snr_from_input` silently collapsing to zero sigma, and owning-looking result objects backed by borrowed slices.

## Overarching Goals

- Remove correctness bugs that can silently falsify later forward or retrieval results.
- Make measurement binding and noise semantics strict and unsurprising.
- Ensure results and solver outcomes have consistent ownership semantics.
- Keep surrogate labels honest while the numerics are still incomplete.

## Non-goals

- Implementing physically faithful forward transport.
- Implementing real OE/DOAS/DISMAS numerics.
- Large architectural refactors unrelated to the hard bugs in this WP.

### WP-01 Critical correctness and execution honesty [Status: Done 2026-03-16]

Issue:
Current execution can fail for the wrong reasons or succeed with scientifically misleading semantics. Several bugs are independent of method fidelity and must be fixed before any parity effort is trustworthy.

Needs:
- strict plan-capacity semantics
- strict measurement-binding semantics
- strict sigma/covariance semantics
- explicit ownership for result identifiers
- honest product naming where physical normalization is not yet real

How:
1. Fix the plan-capacity and measurement-binding logic in the engine/request path.
2. Fix singular math and missing-input handling in noise/covariance code.
3. Make result and retrieval-outcome ownership explicit.
4. Prevent the runtime from exporting physically misleading product names without qualifiers.

Why this approach:
These fixes are small enough to land before the real parity work and broad enough that every later work package benefits from them immediately.

Recommendation rationale:
This landed first because every later scientific change depends on the engine enforcing the right request semantics and preserving the right errors. The patch set now makes cache capacity explicit, removes silent external-observation reinterpretation, hardens sigma/covariance failures, and renames the placeholder reflectance export so later forward-physics work is not built on misleading semantics.

Desired outcome:
Repeated plan preparation no longer trips a lifetime-total limit, external observations cannot silently self-bind to the just-simulated product, missing `snr_from_input` data becomes an explicit error, zero-variance whitening becomes an explicit error, and results/outcomes no longer disguise borrowed slices as owned state.

Non-destructive tests:
- `zig build test-unit`
- `zig build test-integration`
- Add/update focused unit tests for:
  - repeated plan prepare/deinit cycles
  - stage-product vs external-observation binding
  - missing sigma input for `snr_from_input`
  - zero-variance covariance whitening
  - result/outcome lifetime ownership

Files by type:
- Core/runtime:
  - `src/core/Engine.zig`
  - `src/core/Request.zig`
  - `src/core/Result.zig`
- Transport/noise:
  - `src/kernels/transport/doubling.zig`
  - `src/kernels/transport/measurement_space.zig`
  - `src/kernels/spectra/noise.zig`
  - `src/plugins/providers/noise.zig`
- Retrieval contracts:
  - `src/retrieval/common/contracts.zig`
  - `src/retrieval/common/covariance.zig`
- Ingest and tests:
  - `src/adapters/ingest/spectral_ascii.zig`
  - `tests/unit/runtime_cache_scheduler_test.zig`
  - `tests/unit/retrieval_contracts_test.zig`
  - `tests/unit/adapter_ingest_test.zig`
  - `tests/integration/canonical_config_execution_integration_test.zig`

## Exact Patch Checklist

- [x] `src/core/Engine.zig`: replace the monotonic `next_plan_id > max_prepared_plans` check with occupancy-based capacity enforcement driven by `PlanCache`; remove the `.external_observation` fallback that auto-binds retrieval to the current forward product; reject retrieval-only flows that still lack an explicit external measurement binding; stop materializing or naming surrogate AK products as if they were method-faithful.
- [x] `src/core/Request.zig`: validate derivative mode against the prepared route/capability actually selected for execution rather than the template blueprint field; require explicit external-observation bindings; keep stage-product binding semantics strict.
- [x] `src/core/Result.zig`: decide one ownership model for `scene_id`, `workspace_label`, and retrieval product identifiers; duplicate these strings into owned storage or rename/result-type them as borrowed views and update constructors accordingly.
- [x] `src/retrieval/common/contracts.zig`: make `scene_id`, `inverse_problem_id`, and observed-measurement names follow the same ownership rule as `Result`; keep `surrogate_*` implementation labels; reject missing bound measurement products without reinterpretation.
- [x] `src/kernels/transport/doubling.zig`: change the base optical-depth subdivision from `tau / doublings` to `tau / 2^doublings`; retain the singular denominator guard; add a regression test that fails under the old scaling.
- [x] `src/plugins/providers/noise.zig`: implement a real `snr_from_input` path that consumes ingested/measured sigma or SNR vectors; return a typed error when the request asks for `snr_from_input` but no such inputs exist.
- [x] `src/kernels/spectra/noise.zig`: expose one provider-facing sigma validation/materialization path and use it from `plugins/providers/noise.zig` so sigma semantics are centralized.
- [x] `src/retrieval/common/covariance.zig`: replace silent zero-variance whitening with an explicit error; update callers to propagate that error rather than zeroing the residual.
- [x] `src/kernels/transport/measurement_space.zig`: stop emitting the current `reflectance` product under an unqualified physical name until normalization is corrected in `WP-02`; either rename it to a surrogate label or gate it behind a documented temporary field.
- [x] `src/adapters/ingest/spectral_ascii.zig`: thread parsed measured/SNR-like inputs into the runtime structures consumed by the noise provider instead of dropping them on the floor after parsing.
- [x] `tests/unit/runtime_cache_scheduler_test.zig`: add a regression that repeatedly prepares and disposes plans without exhausting the configured cache limit.
- [x] `tests/unit/retrieval_contracts_test.zig`: add regressions for explicit external-observation binding requirements and singular covariance handling.
- [x] `tests/unit/adapter_ingest_test.zig`: add coverage proving that parsed SNR/measured sigma values reach the runtime noise path.
- [x] `tests/integration/canonical_config_execution_integration_test.zig`: add an integration case where an external-observation retrieval fails cleanly without an explicit measurement binding.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Plan-capacity regression no longer depends on lifetime `plan_id`
- [x] External-observation retrieval can no longer self-bind to the current forward product
- [x] `snr_from_input` fails loudly when sigma input is missing and produces nonzero sigma when present
- [x] Singular covariance whitening returns an explicit error

Implementation status (2026-03-16):
- Done. The runtime now treats `max_prepared_plans` as cache capacity rather than a lifetime-total plan counter, requires explicit measurement bindings for stage-product and external-observation retrievals, duplicates result and solver outcome identifiers into owned storage, materializes ingested sigma for `snr_from_input`, fails on singular covariance inputs, and hard-renames the exported placeholder reflectance fields to `surrogate_reflectance` / `fitted_surrogate_reflectance`.

Why this works:
- The plan-capacity fix moved enforcement to `PlanCache`, so repeated prepare/deinit cycles stop failing because `next_plan_id` increases over time.
- Retrieval execution no longer rewrites `.external_observation` requests into the current forward product, and canonical-config retrieval-only flows now fail early as `MissingMeasurementBinding`.
- Noise handling is now strict at the provider boundary: ingested sigma is threaded from spectral ingest into the observation model, copied into the runtime sigma vector only when valid, and rejected when missing or nonpositive.
- Ownership is explicit: result ids, provenance ids, solver outcome ids, observed-measurement names, and state parameter labels are duplicated into allocator-owned storage before long-lived results are stored.
- Surrogate measurement-space exports are no longer emitted under the physically loaded `reflectance` name, and surrogate retrievals stop claiming an averaging-kernel product they do not actually compute.

Proof / validation:
- `zig build test` — passed
- `zig build test-unit` — passed
- `zig build test-integration` — passed
- Added or updated focused regressions for:
  - repeated prepare/deinit cycles without plan-id exhaustion
  - explicit external-observation binding requirements, including observable mismatch rejection
  - ingest-to-noise sigma threading and exact sigma-value checks
  - singular covariance whitening
  - owned result / solver-outcome identifier lifetimes
  - retrieval-only canonical execution failing cleanly without an explicit bound measurement

How to test:
1. Run `zig build test-unit`.
2. Run `zig build test-integration`.
3. Run `zig build test`.
4. Inspect the expert O2A example outputs or exporter schemas and confirm the placeholder ratio is exported as `surrogate_reflectance` rather than `reflectance`.
