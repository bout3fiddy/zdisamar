# Data-Oriented Design Study: R. Fabian x zdisamar

Generated on 2026-06-04 from the current `zdisamar` checkout.

This folder is a study index, not a refactor plan. It maps concrete code in
`zdisamar` to ideas from Richard Fabian's *Data-Oriented Design*, and separates
places where the current implementation is only partially data-oriented.

## Book Source

Use Richard Fabian's online book as the source of record:

- <https://www.dataorienteddesign.com/dodbook/>

The online page says this is the free online reduced version of
*Data-Oriented Design* by Richard Fabian. Some formatting, images, and listings
may be imperfect because the HTML was generated from the book source.

Do not commit a local PDF copy into this study folder. Chapter files should
link to the matching online section. Printed-book page numbers are kept only as
orientation hints for people using the 2018 paper book.

## Files

- `dod_index.md` - main index: code path, what was done, Fabian chapter/page.
- `dod_book/` - one study note per Fabian section referenced by the index.
- `dod_book/codegen/README.md` - compiler-output companion for representative
  Zig lesson shapes.
- `dod_book/codegen/benchmark_results.md` - local microbenchmark numbers used
  by the chapter compiler notes.
- `non_data_oriented_divergences.md` - separate study file for places that are
  not fully aligned with Fabian-style data-oriented design.
- `fabian_page_anchors.md` - compact online-section and printed-page map used
  by the study.

## How To Extend This Study

When adding a new entry:

- start from a concrete `zdisamar` code path and name the data it reads or
  writes;
- link the relevant Fabian section from `fabian_page_anchors.md`;
- update `dod_index.md` when the code is a good or partial DOD example;
- update `non_data_oriented_divergences.md` when the code is a useful mismatch
  or tradeoff to study;
- add or update one `dod_book/` chapter note when the Fabian lesson needs a
  plain-language explanation for this repo;
- include a `Wrong pattern` / `Better pattern` contrast when it makes the lesson
  easier to see;
- back performance claims with a benchmark, trace, compiler output, or another
  concrete artifact. Code shape alone is not proof;
- do not commit local PDFs or generated object files.

## High-Level Answer

`zdisamar` uses a lot of data-oriented design in the Zig forward-model path:

- public flow is shaped as `input -> prepare -> run -> output`;
- expensive input/reference data is reduced into prepared model state;
- repeated runs reuse explicit caller-owned workspaces;
- wavelength/instrument work is planned up front into dense tables and index
  arrays;
- per-wavelength RTM work uses caller-provided buffers;
- LABOS owns scratch memory separately from physics;
- trace and telemetry facades exist to measure phase costs.

The code is not a pure Fabian-style data layout everywhere. Important scientific
state is still represented as broad domain structs, many hot paths retain
runtime branching over physics/configuration, and several structs carry booleans
or ownership flags. Those are listed in `non_data_oriented_divergences.md`.

## Study Scope

This pass focused on the Zig product path under:

- `src/root.zig`
- `src/input/`
- `src/forward_model/`
- `src/output/`

Python wrappers, packaging, validation scripts, and benchmark scripts were not
exhaustively indexed except where they influence the public data flow.
