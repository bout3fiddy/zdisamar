# Adapters

- Keep CLI flow, legacy `Config.in` import, mission wiring, and exporter shims here.
- Parsing, filesystem conventions, and mission-specific defaults belong here, not in `src/core/` or `src/kernels/`.
- Adapter code should translate into typed core requests instead of mutating global state.
