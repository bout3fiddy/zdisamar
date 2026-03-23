# WP-11 Optimal Estimation, Jacobian, And Weighting-Function Parity

## Metadata

- Created: 2026-03-18
- Scope: implement a method-faithful OE core with real Jacobians, posterior products, averaging kernels, and weighting functions compatible with the vendor baseline
- Input sources:
  - vendor `optimalEstimationModule.f90`
  - vendor `DISAMARModule.f90`
  - vendor `radianceIrradianceModule.f90`
  - vendor `LabosModule.f90`
  - Zig retrieval, linalg, engine, and transport derivative code
- Dependencies:
  - `WP-02` through `WP-10`
- Reference baseline:
  - vendor `optimalEstimationModule.f90`
  - vendor `DISAMARModule.f90::{prepareOptimalEstimation,doOEIterationStep,doFullOptimalEstimation,numericalDifferentiation,testderivatives}`
  - vendor `radianceIrradianceModule.f90::{calculate_K_clr,calculate_K_cld,fillRadianceDerivativesHRgrid,calculate_wfAerTau_clr,calculate_wfAerSSA_clr,calculate_wfCldTau_cld,setPolynomialDerivatives_clr,setPolynomialDerivatives_cld}`
  - vendor `LabosModule.f90::{CalcWeightingFunctionsInterface,CalcDerivdRdkabs,CalcDerivdRdksca}`

## Background

The current retrieval core is still scaffolded. Even after forward parity improves, the Zig repo needs a real OE implementation with real Jacobians and posterior products before any serious profile or column retrieval claim can stand. The vendor code provides both method structure and derivative paths to guide this work.

## Overarching Goals

- Replace surrogate OE with a real spectral-fit optimal-estimation implementation.
- Implement Jacobian and weighting-function paths tied to the now-real forward model.
- Produce posterior covariance, averaging kernels, DFS, and method-faithful diagnostics.

## Non-goals

- DOAS or DISMAS implementation; those are later WPs.
- Treating finite-difference surrogate sensitivities as final Jacobians.
- Forcing all derivatives through one generic slow path if analytical or structured paths exist.

### WP-11 Optimal estimation, Jacobian, and weighting-function parity [Status: Todo]

Issue:
The current OE lane is still a surrogate relaxation scheme. The repo needs a real inverse core built on the repaired forward model and typed state-access machinery.

Needs:

- real spectral forward residuals
- state and measurement covariance handling
- real Jacobians / weighting functions
- posterior products and convergence logic
- OE iteration and convergence traces exposed through the shared execution-telemetry substrate

How:

1. Build a real OE iteration around the spectral forward model.
2. Implement or stage Jacobian sources: analytical where available, structured finite-difference fallback where not.
3. Compute posterior covariance, gain, AK, DFS, and convergence diagnostics.
4. Expose iteration, cost, and convergence traces through the shared telemetry substrate from `WP-10` instead of widening scientific diagnostics with runtime-only fields.
5. Validate on at least one O2A and one profile-family case.

Why this approach:
Vendor OE is not just “iterate toward the answer”. It carries a full matrix calculus and product surface. Reusing the repaired forward model, typed state access, and the shared telemetry substrate keeps the implementation honest without turning OE diagnostics into a second logging system.

Recommendation rationale:
OE is the first retrieval family because it establishes the shared derivative and covariance infrastructure that later families can reuse.

Desired outcome:
Zig OE behaves like an actual Rodgers-style optimal-estimation solver: it consumes spectra, priors, and covariance, computes a real update, emits posterior products including gain, and converges based on defensible criteria with iteration traces available when telemetry is requested.

Non-destructive tests:

- `zig build test-unit --summary all`
- `zig build test-validation --summary all`
- `zig test tests/validation/oe_parity_test.zig`
- `zig test tests/integration/retrieval_solver_integration_test.zig`
- `zig test tests/unit/retrieval_contracts_test.zig`

Files by type:

- Retrieval core targets:
  - `src/retrieval/oe/solver.zig`
  - `src/retrieval/common/contracts.zig`
  - `src/retrieval/common/forward_model.zig`
  - `src/retrieval/common/jacobian_chain.zig`
  - `src/retrieval/common/covariance.zig`
  - `src/retrieval/common/diagnostics.zig`
  - `src/retrieval/common/state_access.zig`
  - `src/retrieval/common/transforms.zig`
  - `src/retrieval/common/priors.zig`
- Engine/result/telemetry targets:
  - `src/core/Engine.zig`
  - `src/core/Request.zig`
  - `src/core/Result.zig`
  - `src/core/telemetry.zig`
  - `src/runtime/scheduler/ThreadContext.zig`
  - `src/model/InverseProblem.zig`
  - `src/model/StateVector.zig`
- Derivative/linalg targets:
  - `src/kernels/transport/derivatives.zig`
  - `src/kernels/linalg/small_dense.zig`
  - `src/kernels/linalg/cholesky.zig`
  - `src/kernels/linalg/qr.zig`
  - `src/kernels/linalg/svd_fallback.zig`
- Validation targets:
  - `tests/validation/oe_parity_test.zig`
  - `tests/integration/retrieval_solver_integration_test.zig`
  - `tests/unit/retrieval_contracts_test.zig`

## Exact Patch Checklist

- [ ] `src/retrieval/oe/solver.zig`, `src/retrieval/common/forward_model.zig`: replace the surrogate OE loop with a real spectral-fit update.
  - Vendor anchors: `optimalEstimationModule.f90`; `DISAMARModule.f90::{prepareOptimalEstimation,doOEIterationStep,doFullOptimalEstimation}`.
  - The solver should compute a real cost function and update state from the Jacobian, prior covariance, and measurement covariance.
  - Do not force convergence to `true` if thresholds are not met.

- [ ] `src/retrieval/common/state_access.zig`, `src/model/StateVector.zig`, `src/model/InverseProblem.zig`: make state access precise and typed enough for Jacobian assembly.
  - Vendor anchors: vendor state-vector logic and the gas/profile sections used by OE cases.
  - Replace any remaining text-suffix or hash-based target matching with typed accessors.
  - Include profile node access, column scalars, surface terms, cloud/aerosol terms, and instrument fit parameters where supported.

- [ ] `src/kernels/transport/derivatives.zig` plus forward/transport modules: build real Jacobian sources and weighting functions.
  - Vendor anchors: `radianceIrradianceModule.f90::{calculate_K_clr,calculate_K_cld,fillRadianceDerivativesHRgrid,calculate_wfAerTau_clr,calculate_wfAerSSA_clr,calculate_wfCldTau_cld,setPolynomialDerivatives_*}` and `LabosModule.f90::{CalcWeightingFunctionsInterface,CalcDerivdRdkabs,CalcDerivdRdksca}`.
  - Keep the derivative source provenance explicit: analytical, semi-analytical, or finite-difference fallback.
  - A finite-difference fallback is acceptable as a bridge, but it must not masquerade as a closed-form derivative.

- [ ] `src/retrieval/common/contracts.zig`, `src/retrieval/common/covariance.zig`, `src/kernels/linalg/*`, `src/core/Result.zig`: add real posterior products.
  - Vendor anchors: `optimalEstimationModule.f90` posterior and covariance handling.
  - Emit posterior covariance, gain, AK, DFS, and consistent convergence diagnostics through explicit typed carriers.
  - Singular or zero-variance cases must fail loudly, not whiten to zero.

- [ ] `src/core/Engine.zig`: separate forward-only execution from OE execution and stop forcing unnecessary product materialization.
  - OE should be able to evaluate the spectral forward model and Jacobians without always allocating every forward product.
  - This also keeps performance manageable for later validation and benchmark work.

- [ ] `src/core/Engine.zig`, `src/core/Request.zig`, `src/core/Result.zig`, `src/core/telemetry.zig`, `src/runtime/scheduler/ThreadContext.zig`: expose OE iteration and convergence traces through the shared execution-telemetry substrate from `WP-10`.
  - Requested telemetry should be able to report per-iteration cost, residual norm, step norm, and convergence state.
  - Keep these traces separate from scientific fit diagnostics and posterior products.

- [ ] `tests/validation/oe_parity_test.zig`, `tests/integration/retrieval_solver_integration_test.zig`, `tests/unit/retrieval_contracts_test.zig`: add real OE acceptance tests.
  - Required families: one O2A-like column case and one profile-family case.
  - Assert not just convergence, but also posterior product presence including gain, plausible state updates, and iteration telemetry when requested.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] OE uses a real spectral cost function and Jacobian-based update
- [ ] Posterior covariance, gain, AK, and DFS are emitted from real OE math
- [ ] OE iteration and convergence traces flow through the shared telemetry substrate when requested
- [ ] At least one profile-family OE case is validated end-to-end

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

A real OE core creates the shared derivative, covariance, posterior, and iteration-trace infrastructure that the rest of the retrieval stack needs. Building it after the forward layers are fixed avoids tuning retrieval math to compensate for forward-model errors, while reusing the shared telemetry substrate avoids a second bespoke tracing path.

## Proof / Validation

- Planned: `zig test tests/validation/oe_parity_test.zig` -> real OE metrics, posterior products including gain, and iteration telemetry match family-specific expectations
- Planned: `zig test tests/integration/retrieval_solver_integration_test.zig` -> spectral forward + Jacobian + OE loop integrate cleanly
- Planned: `zig test tests/unit/retrieval_contracts_test.zig` -> retrieval products and error handling stay consistent

## How To Test

1. Run an O2A retrieval case with real priors and covariance.
2. Inspect the requested telemetry output for iteration history, then inspect posterior covariance, gain, AK, and DFS.
3. Repeat on one profile-family case and confirm the state-access and Jacobian paths scale to profile dimensions.
4. Intentionally trigger a singular/noisy case and confirm the solver fails with a typed error instead of silently masking the problem.
