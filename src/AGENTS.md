# Source Tree

- `src/input/` owns typed atmosphere, geometry, surface, spectroscopy, instrument, and reference-data input structures, plus JSON, defaults, and validation.
- `src/setup/` builds the named physics tables consumed by the hot path: atmosphere layers, line, CIA, aerosol, instrument, solar, phase, and run tables.
- `src/optics/` owns per-sample optical properties: layer depths, Rayleigh, CIA absorption, curved sun path, and source levels.
- `src/rtm/` owns radiative transfer: controls, gauss angles, attenuation, phase basis, scattering orders, layer reflect/transmit, reflectance, and the `solve` entry point.
- `src/spectrum/` owns spectral assembly: sampling table, line physics, solar lookup, radiance wavelengths/results, instrument averaging, and the `spectrum_run` driver.
- `src/retrieval/` owns optimal-estimation algebra and its root entry point.
- `src/output/` owns diagnostic reports and spectrum serialization.
- `src/cache/` owns retained, named memory owners (session, profile-line, radiance, solar-irradiance, spectrum, transport-worker, worker-pool). These are the borrowed write targets the hot path threads through.
- `src/common/` is shared support code only: errors, hashing, math, units, memory, worker partition.
- `src/assets/` owns embedded asset readers.
- `src/validation/` owns validation-only code that consumes the typed baseline.
- `src/instrumentation/` owns narrow no-op-by-default facades for trace, telemetry, and sensitivity hooks. Retained sinks, capture scripts, and reports live under `scaffolding/`.

## Rules

- Inline `test` blocks under `src/` are not allowed. Add tests under `tests/unit/`, mirroring the source path.
- Tests that need non-public symbols should use `src/internal.zig`; keep that access surface named after the current tree.
- Prefer the public flow input -> setup -> optics -> rtm -> spectrum -> output. Do not move product wiring into `src/common/`.
- Comments explain why, not what. Keep comments near non-obvious DISAMAR semantics, unit conversions, sign conventions, ordering, and intentional divergences.
- File I/O and text parsing belong in input, output, validation, scaffolding, CLI, or scripts, not in optics, rtm, spectrum, or retrieval routines.
- Every new input/config field must be consumed, rejected with a typed error, or explicitly documented as inert with focused test coverage.

## Explicit dataflow (hot folders)

Functions in the hot folders `src/optics`, `src/rtm`, `src/spectrum`, and
`src/retrieval` must name what they read and write. Pass explicit scalars,
slices, and named physics tables; borrow read-only data as `*const`; confine
writes to a single named data owner. This keeps each function's dependencies
visible in its signature instead of hidden inside a broad mutable object, which
is what makes the hot path readable and property-testable.

This is enforced by `scripts/linting/check-explicit-dataflow-signatures.py`,
which scans signatures and type declarations in those folders.

- Banned in signatures and as type names: `Case`, `PreparedOpticalState`,
  `ProductStorage`, `Context`, `Workspace`, `Request`, `Cache`, `ComputeCache`,
  `Storage`, and any identifier ending in `Request` or `Workspace`. A
  god-object parameter hides what the function actually touches.
- Allowed named data owners (the only broad-ish types permitted in hot-folder
  signatures): `SolarIrradianceMemory`, `ProfileLineValues`,
  `TransportWorkArrays`, `SpectrumSamplingTable`, `RadianceWavelengthList`.
- The allowed list is the real governance lever. Keep these owners narrow; do
  not let one grow into a catch-all. Adding a name to the list (in the linter)
  is a deliberate decision, not a convenience.
- Document each hot-path function's reads and writes in a `dataflow` section of
  its function map (see `STYLEGUIDE.md`).
