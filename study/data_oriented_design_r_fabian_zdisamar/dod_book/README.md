# Fabian Book Section Notes

This folder expands each Richard Fabian reference used by `../dod_index.md`.
Each file is keyed by the book chapter/section and extracts:

- the main lesson needed for studying `zdisamar`;
- the relevant code or table idea where code actually helps explain the lesson,
  adapted as short pseudocode instead of reproducing long book listings
  verbatim;
- the concrete `zdisamar` reading angle for that section.

Many chapter compiler notes include a `Wrong pattern` or `Wrong evidence`
snippet. Those snippets are not recommendations. They mean "wrong for this hot
loop or study claim," not "always wrong in every program." They are included so
the better pattern is easier to see, and each one is tied to a compiler
artifact or benchmark result where possible.

Compiler-output companion notes live in
[`codegen/README.md`](codegen/README.md). They compile small Zig kernels that
mirror the lesson shapes and explain the optimized `arm64` codegen.

Source: <https://www.dataorienteddesign.com/dodbook/>. Each chapter note links
to the matching online section and keeps the printed-book page number only as a
locator for readers using the 2018 paper book.
