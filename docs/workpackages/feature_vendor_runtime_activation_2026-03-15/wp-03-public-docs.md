# Work Package Detail: Public Docs After Actual Vendor Parity Closure

## Metadata

- Package: `docs/workpackages/feature_vendor_runtime_activation_2026-03-15/`
- Scope: `docs/`
- Input sources:
  - the completed runtime/output/mission/spectroscopy packages
  - the relevant DISAMAR scientific paper(s) and related literature
- Constraints:
  - do not write public docs while material runtime or scientific gaps remain
  - distinguish clearly between bounded parity, intentional architecture drift, and true feature equivalence
  - cite the literature where the docs explain DISAMAR concepts or scientific lineage

## Background

Public docs are still the last step. The repo needs them, but only after the implementation and vendor audit are honest. Once WP-02 through WP-04 are closed or explicitly re-scoped, the public docs should explain what DISAMAR is inside `zdisamar`, how the Zig architecture differs intentionally from the legacy Fortran application, and what scientific scope the repo actually covers.

### WP-05 Write Public Docs Only After Runtime and Scientific Closure [Status: In Progress 2026-03-15]

- Issue: public documentation is still deferred correctly, but it now needs an explicit closure gate tied to the real remaining vendor gaps.
- Needs: architecture-aware docs for DISAMAR-in-zdisamar, mission/runtime flow, bounded vs full parity language, and literature-backed scientific context.
- How: after WP-02 through WP-04 are done or explicitly re-scoped, author a focused `docs/` set covering scientific context, engine architecture, runtime bundle flow, retrieval/transport concepts, and operational boundaries, citing the relevant DISAMAR paper and related references where appropriate.
- Why this approach: public docs should explain the system truthfully, not advertise a parity level that the implementation does not yet support.
- Recommendation rationale: this keeps the docs phase honest and prevents the repo from documenting an implementation state it has not actually reached.
- Desired outcome: `docs/` explains DISAMAR, the Zig architecture, the validated parity scope, and the remaining intentional drift in a way that is technically defensible.
- Non-destructive tests:
  - docs review against actual code and validation state
  - link/reference checks where applicable
  - final vendor audit summary recorded in the docs set
- Files by type:
  - docs: `docs/**/*`

- Recommendation rationale: now that the remaining implementation blocker has been cleared, the docs pass can start without overstating unfinished scientific work.
- Implementation status (2026-03-15): in progress. Added a tracked docs index at `docs/README.md`, a scientific/context primer at `docs/disamar-overview.md`, an architecture mapping document at `docs/zig-architecture.md`, an O2 A-band operational-path explainer at `docs/operational-o2a.md`, and a result-surface explainer at `docs/retrieval-and-measurement-space.md`. These documents cross-reference the tracked architecture specs, current source-tree boundaries, and the DISAMAR literature instead of relying on migration-only notes.
- Why this works so far: the new docs explain the current repository truth from three angles that users actually need: scientific context, architecture boundaries, and the most operationally important mission path. That is enough to replace “read the workpackages” as the main explanation entry point while leaving room for more domain-specific docs.
- Proof / validation so far: the new docs were written after the O2/O2-O2 operational LUT work landed and after `zig build test-unit`, `zig build test-integration`, `zig build test-validation`, `zig build test-perf`, `zig build test`, `zig build`, `zig test src/exporters_wp12_test_entry.zig`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. The literature links point to the underlying primary papers instead of tertiary summaries.
- How to test:
  - read `docs/README.md` and verify it routes cleanly into the three new docs
  - cross-check the file and module references in the docs against the current source tree
  - verify the cited papers are the primary DISAMAR and O2 A-band references intended by the docs
- Remaining gap before done: extend the top-level docs set with more retrieval-specific and exporter-specific detail, then do a final consistency pass so the public docs and the workpackage history do not diverge.
