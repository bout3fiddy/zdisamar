# Source Tree

- `src/input/` owns typed atmosphere, geometry, surface, spectroscopy, instrument, and reference-data input structures.
- `src/forward_model/` owns optical-property preparation, radiative transfer, instrument-grid calculation, and built-in implementation bindings.
- `src/output/` owns diagnostic report and spectrum serialization.
- `src/common/` is shared support code only. Do not grow it into forward-model preparation or product wiring.
- `src/validation/disamar_reference/` owns the DISAMAR reference comparison harness and CLI helpers.

## Local Rules

- Inline `test` blocks under `src/` are not allowed. Add new tests under `tests/unit/`, mirroring the source path. The `check-no-inline-src-tests.sh` guard (run by `zig build check`) fails when `^test "` reappears under `src/`. Tests that need non-`pub` symbols use the `internal` module re-exports in `src/internal.zig` and the per-directory `internal.zig` shims under `src/`.
- Push domain-heavy guidance into the nearest scoped `AGENTS.md` before expanding this file.
- Prefer the simple public flow: input -> forward model -> output. Keep product wiring out of `src/common/`.
- When a feature exists in both exact and alternate forms, name the source of truth clearly and keep derived hints, prepared state, and runtime consumers synchronized by tests rather than convention.
- Do not add typed fields whose only consumer is an eventual TODO. New scene/request/model controls must either affect runtime behavior now or be rejected explicitly.

## Scientific Port Commenting Contract

- Comments explain why the code has this shape, not what the next declaration says.
- Keep comments where they protect DISAMAR semantics, parity-sensitive arithmetic, units, sign conventions, ordering, or intentional divergence from the Fortran flow.
- Prefer short comments near the non-obvious code. Do not add template headers or label blocks just to document ownership, inputs, outputs, or tests.
- File-level comments are optional. Use them only when a module has a scientific gotcha or vendor divergence that is not obvious from the file name and imports.
- Public declarations do not need doc comments when their names and types are clear.

### Plain Comment Style

- Use plain `//` comments in Zig. Do not use `//!` or `///` narrative blocks for routine commentary.
- Short tags like `PARITY:`, `DECISION:`, `GOTCHA:`, `ISSUE:`, `TODO:`, `UNITS:`, and `VENDOR:` are allowed when they make the reason easy to scan.
- Do not stack tags into a template. One short comment beside the relevant code is better than a file header.

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
- `GOTCHA:` marks behavior that another engineer might simplify incorrectly, such as unit conversions, indexing direction, sign conventions, layer ordering, implicit vendor clamping, or parity-sensitive edge handling.

### Minimum Standard for Vendor-Refactor Changes

- New or changed scientific code should be understandable from names and types first.
- Intentional divergences from vendor structure need a nearby `DECISION:` or `PARITY:` comment.
- Physically meaningful quantities need units only where the unit is not obvious from the field name or type.
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
- Avoid allocate-without-reset behavior for per-request storage buffers; repeated retrievals on the same storage must be idempotent with respect to owned memory.
- Avoid cleanup paths that assume full initialization; partial-init and early-error teardown must guard every optional resource before release.
- Avoid singular/plural field-name drift between declarations and use sites; shared ported structures need one canonical name per field and compile-time coverage in tests.
- Avoid build-order assumptions in Zig build logic or generated C/Fortran interop steps; dependency edges must be explicit so parallel builds stay correct.
