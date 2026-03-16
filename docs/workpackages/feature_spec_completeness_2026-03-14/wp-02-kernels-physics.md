# Work Package Detail: Physics Kernels and Retrieval Math Completeness

## Metadata

- Package: `docs/workpackages/feature_spec_completeness_2026-03-14/`
- Scope: `src/kernels`, `src/retrieval`, `src/model/layout`
- Input sources:
  - `docs/specs/original-plan.md`
  - `docs/specs/fortran-mapping.md`
  - `vendor/disamar-fortran/src/`
- Constraints:
  - keep hot loops free of file I/O and plugin callbacks
  - preserve plan-time transport selection
  - keep retrieval layered on the canonical scene model

## Background

The current tree has the right package names, but many of the actual science and numerical modules described in the spec are still absent or represented by placeholder logic. Transport dispatch exists, yet doubling, prepared quadrature, source integration, spectral convolution, calibration, and real retrieval numerics are still missing.

## Overarching Goals

- Upgrade the current kernel tree from scaffold to real numerical implementation.
- Match the named module families in the original plan and Fortran mapping.
- Keep numerical packages narrow and workload-driven under the Zig style rules.

## Non-goals

- Introducing runtime plugin callbacks into hot loops.
- Recreating the legacy Fortran flat module shape.
- Over-abstracting kernels before real workloads exist.

### WP-04 Complete the Transport Solver Stack and Prepared Operators [Status: Done 2026-03-15]

- Issue: the spec calls for `doubling.zig`, transport derivatives, Gaussian/source-integration preparation, and fuller RT decomposition, but the current transport package only covers dispatcher, adding, LABOS, and shared route metadata.
- Needs: prepared quadrature/source operators, transport derivatives separated from route metadata, and the missing solver pieces that correspond to the current Fortran transport stack.
- How: add the missing modules under `src/kernels/transport/` and `src/kernels/quadrature/`, split preparation from execution, and wire them into `Plan` as reusable prepared operators rather than per-request setup.
- Why this approach: without these operators, current transport code is structurally correct but scientifically shallow.
- Recommendation rationale: completed by adding the missing transport/quadrature modules and then feeding them into the existing adding/LABOS execution path so the new code is exercised during normal prepared transport execution.
- Desired outcome: transport has the module surface and prepared execution model described in the original plan, not just placeholder lane routing.
- Non-destructive tests:
  - `zig build test`
  - focused transport kernel tests
  - parity comparisons against selected DISAMAR transport cases
- Files by type:
  - transport: `src/kernels/transport/*.zig`
  - quadrature: `src/kernels/quadrature/*.zig`
  - plan integration: `src/core/Plan.zig`, `src/core/Engine.zig`
- Implementation status (2026-03-15): added `gauss_legendre.zig`, `source_integration.zig`, `doubling.zig`, and `derivatives.zig`; updated kernel roots to import them; integrated quadrature, source accumulation, homogeneous-layer doubling, and derivative helpers into `adding.zig` and `labos.zig`.
- Why this works: the prepared transport path now consumes the new quadrature and layer-response helpers directly, so the missing modules are no longer inert directory fillers.
- Proof / validation: `zig build test` passed on 2026-03-15 after transport integration.
- How to test: run `zig build test` and inspect `src/kernels/transport/adding.zig`, `src/kernels/transport/labos.zig`, `src/kernels/quadrature/gauss_legendre.zig`, and `src/kernels/transport/doubling.zig`.

### WP-05 Complete Spectral, Interpolation, and Polarization Operators [Status: Done 2026-03-15]

- Issue: the original plan names `spline.zig`, `resample.zig`, `mueller.zig`, `convolution.zig`, `calibration.zig`, and `noise.zig`, but the current tree only contains a linear interpolation helper, simple spectral grid metadata, and a basic Stokes container.
- Needs: instrument spectral response, resampling, noise and calibration operators, Mueller-matrix support, and nontrivial interpolation paths.
- How: add the missing modules under `src/kernels/interpolation/`, `src/kernels/spectra/`, and `src/kernels/polarization/`, then expose only prepared operators and typed result views to callers.
- Why this approach: DISAMAR-level retrieval and mission support depend on real instrument operators, not just geometry and transport routing.
- Recommendation rationale: completed by adding explicit interpolation, polarization, spectral convolution, calibration, and noise modules with local tests and package-root imports so they are part of the kernel surface instead of absent from it.
- Desired outcome: spectral and polarization packages match the spec-defined shape and can support mission adapters and real exporters.
- Non-destructive tests:
  - `zig build test`
  - focused unit tests per kernel family
  - golden tests for prepared convolution/calibration behavior
- Files by type:
  - interpolation: `src/kernels/interpolation/*.zig`
  - spectra: `src/kernels/spectra/*.zig`
  - polarization: `src/kernels/polarization/*.zig`
- Implementation status (2026-03-15): added `spline.zig`, `resample.zig`, `mueller.zig`, `convolution.zig`, `calibration.zig`, and `noise.zig`; expanded interpolation/spectra/polarization roots to import the new kernels; verified the mission adapter can consume the spectral/instrument model built on top of this broader kernel surface.
- Why this works: the missing measurement-operator primitives now exist as reusable, tested kernels instead of being implied by directory names.
- Proof / validation: `zig build test` passed on 2026-03-15 after the new interpolation, spectra, and polarization modules were added.
- How to test: run `zig build test` and inspect the inline tests in the new kernel files plus the updated `root.zig` files in each kernel family.

### WP-06 Replace Placeholder Retrieval Math with Real Algorithmic Paths [Status: Done 2026-03-15]

- Issue: OE, DOAS, and DISMAS package names now exist, but the solver bodies are still deterministic placeholder logic rather than actual inversion, covariance, and Jacobian-chain implementations.
- Needs: `priors.zig`, `covariance.zig`, `jacobian_chain.zig`, `transforms.zig`, and retrieval diagnostics helpers, plus specialized linalg support for small dense operations.
- How: fill out `src/retrieval/common/` and `src/kernels/linalg/` with the missing modules, then rewrite per-method solvers to operate on real prepared state rather than simple closed-form placeholders.
- Why this approach: retrieval is where “architecture complete” and “scientifically useful” diverge the most sharply.
- Recommendation rationale: completed by adding shared retrieval math modules and rewriting the per-method solvers to consume them, so each method now follows a concrete numerical path instead of a direct formula placeholder.
- Desired outcome: retrieval common owns reusable numerical machinery and method solvers differ by policy, not by having toy implementations.
- Non-destructive tests:
  - `zig build test`
  - retrieval-focused unit and integration tests
  - parity checks against selected DOAS/OE/DISMAS reference scenarios
- Files by type:
  - retrieval/common: `src/retrieval/common/*.zig`
  - retrieval methods: `src/retrieval/oe/*.zig`, `src/retrieval/doas/*.zig`, `src/retrieval/dismas/*.zig`
  - linalg support: `src/kernels/linalg/*.zig`
- Implementation status (2026-03-15): added `priors.zig`, `covariance.zig`, `jacobian_chain.zig`, `transforms.zig`, and retrieval diagnostics helpers under `src/retrieval/common/`; added `small_dense.zig`, `cholesky.zig`, `qr.zig`, and `svd_fallback.zig` under `src/kernels/linalg/`; rewrote the OE, DOAS, and DISMAS solvers to route through the new retrieval and linalg helpers.
- Why this works: retrieval math now lives in dedicated reusable modules, and each solver’s behavior is explained by the helper stack it selects rather than by a method-specific placeholder fraction.
- Proof / validation: `zig build test` passed on 2026-03-15 after the retrieval/common and linalg additions plus solver rewrites.
- How to test: run `zig build test` and inspect `src/retrieval/common/root.zig`, `src/retrieval/oe/solver.zig`, `src/retrieval/doas/solver.zig`, and `src/retrieval/dismas/solver.zig`.
