# Core

- Keep `Engine`, `Plan`, `Workspace`, `Request`, and `Result` explicit and allocation-aware.
- No hidden singleton state, saved global pointers, or implicit process-wide caches.
- No file-path defaults, file-unit numbers, or current-working-directory assumptions.
- Provenance belongs here when it is structural; exporter formatting does not.
