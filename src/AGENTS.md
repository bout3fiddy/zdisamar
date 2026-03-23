# Source Tree

- `src/core/` owns engine lifecycle, typed requests/results, provenance, and explicit ownership boundaries.
- `src/model/` owns canonical scene and observation-domain types. Do not fork separate simulation and retrieval object trees.
- `src/kernels/` is for reusable numeric kernels only. Keep hot paths free of I/O and coarse-grained plugin dispatch.
- `src/retrieval/` layers inverse methods on the canonical scene model.
- `src/runtime/` owns caches, schedulers, and per-thread execution support.
- `src/plugins/` owns manifests, capability registration, and plugin ABI boundaries.
- `src/api/` owns the stable C ABI and Zig-facing wrappers.
- `src/adapters/` owns CLI, legacy config import, mission wiring, and export shims.

## Local Rules

- Push domain-heavy guidance into the nearest scoped `AGENTS.md` before expanding this file.
- Prefer moving legacy behavior to `src/adapters/` instead of leaking it back into `src/core/`.

## Scientific Port Commenting Contract

- When refactoring vendor-derived scientific logic into Zig, comments are part of the implementation contract. The goal is not just to describe what the code does, but also what physics it encodes, what vendor routine or phase it comes from, and why the Zig shape differs from the vendor shape.
- Prefer verbose, structured comments over sparse cleverness for vendor-refactor code. Another engineer or agent should be able to recover the scientific intent and refactor rationale without reopening the Fortran sources.
- Use searchable section labels and tags consistently. Do not invent one-off phrasing when a standard label applies.

### Scope

- This contract applies to vendor-derived or vendor-validated scientific code under `src/`.
- It is especially important in `src/kernels/`, `src/retrieval/`, `src/runtime/`, and any adapter or preparation code that translates vendor atmospheric, spectroscopy, optics, or inversion behavior into typed Zig structures.
- More specific subtrees may add stricter variants, but they should not weaken this contract.

### Comment Forms

- Use `//!` for file headers and module-level contracts.
- Use `///` for public types, public functions, and internal functions with nontrivial scientific behavior.
- Use `//` for local phase comments, decision notes, parity notes, gotchas, and unresolved issues inside implementations.

### Required File Header

- Every substantive scientific port or refactor file should start with a header that covers:
- `Purpose:` what responsibility the file owns in the engine.
- `Physics:` what physical quantity, model stage, or scientific transformation it implements.
- `Vendor:` vendor file stem, module, or routine names only. Do not use filesystem paths.
- `Design:` how the Zig version is organized differently from the vendor flow and why.
- `Invariants:` conditions that must always hold in this file.
- `Validation:` relevant tests, parity harnesses, or reference comparisons.

### Required Function Comment

- Every nontrivial scientific function should document the applicable subset of:
- `Purpose:` what the function computes or prepares.
- `Physics:` the scientific meaning of the computation.
- `Vendor:` the vendor routine, phase, or concept this corresponds to.
- `Inputs:` the scientific meaning of important inputs, not just their types.
- `Outputs:` what is returned or mutated in physical or numerical terms.
- `Units:` units or normalization conventions for important quantities.
- `Assumptions:` required ordering, monotonicity, valid ranges, or upstream contracts.
- `Decisions:` why the implementation shape differs from the vendor version, if it does.
- `Validation:` what test, fixture, or parity artifact exercises this function.

### Required Inline Tags

- Use these exact tags for local comments when they apply:
- `INVARIANT:` facts that must remain true.
- `UNITS:` physical units or normalization conventions.
- `VENDOR:` local provenance for a block or transformation.
- `DECISION:` why the code is shaped this way.
- `PARITY:` exact vendor behavior that must be preserved.
- `GOTCHA:` non-obvious behavior that is easy to break during cleanup.
- `ISSUE:` known unresolved correctness, parity, performance, or design problem.
- `TODO:` bounded future work with ownership and removal condition.
- `VALIDATION:` tests, fixtures, or reference outputs relevant to the block.

### Vendor Reference Rules

- Vendor references should use file stems, module names, routine names, or conceptual stage names such as `propAtmosphere::fillHighResolutionPressureGrid` or `classic DOAS polynomial fit stage`.
- Do not include full paths, absolute paths, or brittle line-number references.
- Do not paste large vendor excerpts into comments. Summarize the behavior and preserve the useful name.

### Decision and Divergence Notes

- Add a `DECISION:` comment whenever the Zig implementation intentionally does not mirror the vendor control flow, memory layout, or state model.
- A good `DECISION:` comment explains:
- what changed in structure,
- why the change was made,
- what physical or numerical behavior must remain equivalent.

### TODO, ISSUE, and GOTCHA Rules

- `TODO:` means planned work, not a vague idea. Every `TODO:` should include owner or area, a tracking issue or work package, and the condition for removal.
- Preferred format: `TODO(owner=<owner>, issue=<ticket-or-wp>, remove_when=<condition>):`
- `ISSUE:` marks a known current problem or design risk. State what is wrong, what it affects, and the boundary of the problem.
- `GOTCHA:` marks behavior that another engineer might "simplify" incorrectly, such as unit conversions, indexing direction, sign conventions, layer ordering, implicit vendor clamping, or parity-sensitive edge handling.

### Preferred Templates

- File header template:

```zig
//! Purpose:
//!   What this file is responsible for in the engine.
//!
//! Physics:
//!   What physical quantity, model stage, or transformation it implements.
//!
//! Vendor:
//!   `moduleOrFileStem::routineName`
//!
//! Design:
//!   How the Zig structure differs from the vendor flow and why.
//!
//! Invariants:
//!   Conditions that must always hold in this file.
//!
//! Validation:
//!   Relevant tests, parity harnesses, or reference comparisons.
```

- Function comment template:

```zig
/// Purpose:
///   What the function computes or prepares.
///
/// Physics:
///   The scientific meaning of the computation.
///
/// Vendor:
///   `moduleOrFileStem::routineName`
///
/// Inputs:
///   The meaning of the important inputs.
///
/// Outputs:
///   What is returned or mutated in physical terms.
///
/// Units:
///   Units or normalization conventions for important quantities.
///
/// Assumptions:
///   Ordering, monotonicity, range, or upstream-contract requirements.
///
/// Decisions:
///   Why this shape differs from the vendor implementation, if it does.
///
/// Validation:
///   Which test, fixture, or parity artifact exercises this function.
```

- Inline issue-tracking template:

```zig
// GOTCHA:
//   Non-obvious behavior that is easy to break during cleanup.
//
// ISSUE:
//   Known limitation, why it matters, and the current boundary.
//
// TODO(owner=<owner>, issue=<ticket-or-wp>, remove_when=<condition>):
//   Concrete follow-up work.
```

### Minimum Standard for Vendor-Refactor Changes

- New scientific port files should have a file header.
- New or substantially changed nontrivial scientific functions should have structured doc comments.
- Intentional divergences from vendor structure should have nearby `DECISION:` comments.
- Physically meaningful quantities should document units either at the declaration site or at first non-obvious transformation.
- Known gaps should be recorded inline with `ISSUE:` or `TODO:` rather than left implicit in external notes only.

### Avoid

- Comments that only restate the next line of code.
- Comments that mention "ported from DISAMAR" without naming the relevant routine or phase.
- Long historical narratives that do not help a future maintainer preserve parity or physics.
- Silent unresolved oddities. If something is known to be awkward, fragile, or incomplete, say so with `ISSUE:` or `GOTCHA:`.

## Port Regression Notes

- Temporary checklist: remove an item once the Zig port and its tests prove that failure mode is impossible.
- Avoid 1-based/0-based flattening mistakes when mapping multidimensional coefficient tensors; no linearized port path may read a synthetic element `0` or transpose coefficient axes silently.
- Avoid backtracking underflow in config/text readers; rewinds and backspaces must stop cleanly at the start of a buffer instead of reading before the first byte.
- Avoid calling `len`/`size`-equivalent operations on absent or uninitialized storage just to validate required inputs; return a typed configuration/input error first.
- Avoid allocate-without-reset behavior for static config buffers; repeated config loads must free, reuse, or overwrite existing storage safely.
- Avoid allocate-without-reset behavior for per-request workspace buffers; repeated retrievals on the same workspace must be idempotent with respect to owned memory.
- Avoid cleanup paths that assume full initialization; partial-init and early-error teardown must guard every optional resource before release.
- Avoid singular/plural field-name drift between declarations and use sites; shared ported structures need one canonical name per field and compile-time coverage in tests.
- Avoid build-order assumptions in Zig build logic or generated C/Fortran interop steps; dependency edges must be explicit so parallel builds stay correct.
