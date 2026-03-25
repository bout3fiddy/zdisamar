# Core

- Keep `Engine`, `Plan`, `Workspace`, `Request`, and `Result` explicit and allocation-aware.
- No hidden singleton state, saved global pointers, or implicit process-wide caches.
- No file-path defaults, file-unit numbers, or current-working-directory assumptions.
- Provenance belongs here when it is structural; exporter formatting does not.
- Constructors, clone helpers, and `init` paths with more than one fallible allocation must stage owned locals and use `errdefer`. Do not hide multiple `try allocator.*` calls inside a final struct literal.
- Replacement of owned slices or owned nested structs must leave the object in a valid state on every early return path. Prefer helper patterns that make partial-init cleanup and replace-in-place semantics explicit.
- New `Engine`/`Plan`/`Workspace`/`Request`/`Result` fields, flags, or semantic hints require an end-to-end propagation test from adapter or API entrypoint through execution or validation.
- Keep one source of truth for derived counts, interval hints, and prepared metadata. If a hint can be recomputed after later config application, either delay assignment or add coverage that proves the chosen ordering is correct.
