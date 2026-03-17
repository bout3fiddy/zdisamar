# WP-04 Optimal Estimation Parity

## Metadata

- Created: 2026-03-16
- Scope: replace the current OE-labeled relaxation scaffold with a real Rodgers-style OE implementation
- Input sources: audit sections `Retrieval`, `Model`, `Core`, `Spectra, linalg, interpolation, quadrature, polarization`
- Dependencies:
  - `WP-01` for correctness and sigma/covariance honesty
  - `WP-02` and `WP-03` for a credible spectral forward path and resolved observation/noise semantics
- Reference baseline: vendored `optimalEstimationModule.f90` and the existing typed inverse-problem/state-vector surfaces in Zig

## Background

The current OE lane is truthful about being surrogate, but it is still only an anchor-relaxation scaffold operating on summary features. The audit’s recommendation is to implement one real retrieval family first, and OE is the best first target because it establishes the Jacobian, prior, covariance, posterior, DFS, and AK machinery that later spectral retrieval families can reuse.

## Overarching Goals

- Implement a real Rodgers-style OE update on the repaired spectral forward path.
- Replace string-target heuristics with typed state accessors.
- Materialize real Jacobian, posterior covariance, DFS, and averaging-kernel products.
- Keep the solver contracts and outputs explicitly owned and testable.

## Non-goals

- Implementing DOAS or DISMAS in this WP.
- Preserving any summary-only surrogate fit path as the default OE route.
- Adding speculative factorization backends not justified by the real solver.

### WP-04 Optimal estimation parity [Status: Done 2026-03-16]

Issue:
The current OE lane is not OE: it operates on synthetic summary features, uses anchor relaxation instead of a Rodgers update, and over-claims derived products such as averaging kernels.

Needs:
- real `K`, `Sa`, `Se`, gain, cost, posterior covariance, DFS, and AK machinery
- typed state accessors rather than string suffix matching
- a spectral residual evaluator over real measurement-space products
- owned solver outputs and real retrieval products

How:
1. Replace string-target state application with typed state-access mapping.
2. Replace the surrogate summary evaluator with a spectral residual evaluator that consumes the repaired forward path.
3. Build real prior and covariance assembly around the existing inverse-problem types.
4. Implement Rodgers-style OE updates and materialize the resulting products in the engine/result layer.

Why this approach:
OE is the most reusable first retrieval family. Once the spectral evaluator, Jacobian chain, covariance machinery, and result products are real for OE, DOAS and DISMAS can reuse more of the stack instead of rebuilding their own scaffolding.

Recommendation rationale:
This WP followed the forward-path work because the former summary-based OE scaffold could not be made method-faithful without real spectral measurements, honest sigma semantics, typed state access, and a trustworthy Jacobian path. The implementation therefore hard-cut over to one real spectral-fit family first, then tightened the execution and validation surfaces around it.

Desired outcome:
The OE-labeled route becomes a real state-estimation method with spectral residuals, validated priors/covariances, owned posterior products, and honest convergence/DFS/AK reporting.

Non-destructive tests:
- `zig build test-unit`
- `zig build test-integration`
- `zig build test-validation`
- Add/update focused OE tests for:
  - typed state-target mapping
  - Jacobian assembly
  - posterior covariance and AK consistency
  - convergence on cost/state criteria

Files by type:
- Model:
  - `src/model/InverseProblem.zig`
  - `src/model/Measurement.zig`
  - `src/model/StateVector.zig`
  - `src/model/LayoutRequirements.zig`
- Retrieval common:
  - `src/retrieval/common/contracts.zig`
  - `src/retrieval/common/forward_model.zig`
  - `src/retrieval/common/jacobian_chain.zig`
  - `src/retrieval/common/priors.zig`
  - `src/retrieval/common/diagnostics.zig`
  - `src/retrieval/common/synthetic_forward.zig`
  - `src/retrieval/common/transforms.zig`
- Solver/core:
  - `src/retrieval/oe/solver.zig`
  - `src/core/Engine.zig`
  - `src/core/Result.zig`
- Numerics:
  - `src/kernels/linalg/small_dense.zig`
  - `src/kernels/linalg/qr.zig`
  - `src/kernels/linalg/cholesky.zig`
  - `src/kernels/linalg/svd_fallback.zig`
  - `src/kernels/linalg/vector_ops.zig`
- Tests:
  - `tests/unit/retrieval_contracts_test.zig`
  - `tests/integration/retrieval_solver_integration_test.zig`
  - `tests/validation/oe_parity_test.zig`

## Exact Patch Checklist

- [x] `src/model/InverseProblem.zig`: strengthened OE-specific validation for covariance blocks, convergence controls, and measurement semantics once a real OE lane existed.
- [x] `src/model/Measurement.zig`: tightened measurement masks and error-floor semantics so OE consumes a real bound spectral product and covariance definition.
- [x] `src/model/StateVector.zig`: replaced string targets with typed target IDs and stopped relying on string suffix matching.
- [x] `src/model/LayoutRequirements.zig`: confirmed no extra layout surface was needed beyond the repaired typed matrix shapes.
- [x] `src/retrieval/common/contracts.zig`: added owned outcome fields for posterior covariance, DFS, and AK while keeping surrogate labels only for unfinished lanes.
- [x] `src/retrieval/common/forward_model.zig`: replaced the summary-only evaluator with a spectral residual evaluator over repaired measurement-space products.
- [x] `src/retrieval/common/jacobian_chain.zig`: assembled the real Jacobian path used by OE, including transform-aware column scaling and inverse-covariance weighting.
- [x] `src/retrieval/common/priors.zig`: built real prior vectors and covariance matrices from the inverse-problem description.
- [x] `src/retrieval/common/diagnostics.zig`: reported Rodgers-style cost, step norm, DFS, and convergence diagnostics from the real solver path.
- [x] `src/retrieval/common/synthetic_forward.zig`: retired the old synthetic summary evaluator, moved surviving surrogate-only helpers into `surrogate_forward.zig`, and split state access into typed helpers.
- [x] `src/retrieval/common/transforms.zig`: kept transform derivatives available to the real OE solver and Jacobian chain.
- [x] `src/retrieval/oe/solver.zig`: implemented the OE update using `K`, `Sa`, `Se`, gain, posterior covariance, DFS, and AK with state/cost convergence checks.
- [x] `src/core/Engine.zig`: routed retrieval product materialization through real OE outputs and rejected missing solver-owned OE products.
- [x] `src/core/Result.zig`: added owned containers for posterior covariance and other OE retrieval products.
- [x] `src/kernels/linalg/small_dense.zig`: kept and used the small dense operations needed by the real OE solver.
- [x] `src/kernels/linalg/qr.zig`: retained only the needed QR support with top-level imports.
- [x] `src/kernels/linalg/cholesky.zig`: used it for positive-definite covariance work and exercised failure paths through OE solve/inversion coverage.
- [x] `src/kernels/linalg/svd_fallback.zig`: kept it as the explicit fallback for singular or ill-conditioned solves.
- [x] `src/kernels/linalg/vector_ops.zig`: kept the vector helpers actually used by the new solver.
- [x] `tests/unit/retrieval_contracts_test.zig`: extended contract tests for typed state accessors, owned outputs, and OE-specific validation.
- [x] `tests/integration/retrieval_solver_integration_test.zig`: replaced surrogate expectations with real spectral-fit, covariance, and product-shape assertions.
- [x] `tests/validation/oe_parity_test.zig`: added parity-oriented validation for OE behavior against an approved checked-in golden reference scenario.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] State targets are no longer resolved by string suffix heuristics
- [x] OE uses a real spectral residual and real covariance machinery
- [x] DFS and AK are derived from the actual solver math rather than surrogate placeholders

Implementation status: 2026-03-16

Why this works:
- OE now linearizes real spectral measurements instead of summary scalars, so the update uses an explicit residual vector, Jacobian, measurement covariance, prior covariance, and transform-aware state mapping.
- The solver owns and returns posterior covariance, averaging kernel, DFS, fitted scene, and fitted measurement, and the engine now treats those as required OE products rather than fabricating them downstream.
- The retrieval state path preserves the original observation sampling semantics, which removed a hidden `.native -> .operational` mismatch that was corrupting linearization behavior in real spectral scenarios.
- Validation is no longer only “twin self-fit improves residual”; it now also includes a checked-in golden OE anchor for a real spectral-fit scenario plus stronger canonical-example checks for seeded stage noise and nominal-grid wavelength export.

Proof / validation:
- `zig build test-unit --summary all`
  - passed: `28/28 tests passed`
- `zig build test-integration --summary all`
  - passed: `22/22 tests passed`
- `zig build test-validation --summary all`
  - passed: `15/15 tests passed`
- Reviewer-agent acceptance:
  - `Pauli`: `ACCEPT`
  - `Zeno`: `ACCEPT`
  - `Raman`: `ACCEPT`

How to test:
1. Run `zig build test-unit --summary all`.
2. Run `zig build test-integration --summary all`.
3. Run `zig build test-validation --summary all`.
4. Inspect the expert canonical example path through `tests/integration/canonical_config_execution_integration_test.zig` and the golden OE anchor path through `tests/validation/oe_parity_test.zig`.
