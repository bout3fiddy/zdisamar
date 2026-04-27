# zdisamar

`zdisamar` is a Zig O2 A forward-model lab built around the DISAMAR scientific
path. The repository is organized around a direct forward-model calculation
sequence:

`Case -> Data -> Optics -> Spectrum -> Report`

That sequence is the center of the codebase. Scientific scene state, reference
data, optical-property preparation, radiative-transfer routines, spectral
integration, and report generation are kept explicit so execution stays
reproducible and parity-focused.

## What The Repository Contains

- A buildable Zig library and O2 A profile CLI.
- A small O2 A product surface in `src/o2a/`.
- Retained typed atmosphere, geometry, spectroscopy, and instrument types in `src/model/`.
- Reusable numerical routines for radiative transfer, optics, interpolation,
  quadrature, spectra, and linear algebra in `src/kernels/`.
- Narrow ingestion helpers for bundled reference assets in `src/adapters/`.
- Tracked O2 A scientific bundles and reference assets under `data/`.
- Retained O2 A validation assets and executable test lanes under `tests/` and `validation/`.

## Current Runtime Model

The public execution surface is intentionally small:

- `Case` owns the retained O2 A inputs.
- `Data` owns the loaded reference datasets and bundled helper assets.
- `Optics` owns the prepared wavelength-dependent optical state.
- `RunStorage` owns reusable internal storage for the forward model.
- `Result` owns the generated spectrum and summary outputs.
- `Report` owns timings, counters, and diagnostic artifacts.

That structure is why numerical routines stay free of file I/O, CLI parsing,
and global mutable state. Product wiring belongs in `src/o2a/`, while hot
numerics stay in the routines.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `src/o2a/` | O2 A case, data loading, optical-property preparation, forward model, spectrum, reporting, and CLI |
| `src/model/` | retained atmosphere, geometry, surface, spectroscopy, and instrument types |
| `src/kernels/` | reusable numeric routines and instrument-grid materialization |
| `src/adapters/` | narrow ingestion helpers that still support the O2 A data path |
| `src/core/` | reduced support code such as units and error helpers |
| `data/` | tracked O2 A bundles and reference assets |
| `tests/` | retained O2 A executable checks |
| `validation/` | O2 A compatibility and reference evidence |
| `docs/` | O2 A architecture, telemetry, parity, and operational narrative |

## Prerequisites

- Zig `0.15.2` or newer. The repo currently declares `minimum_zig_version =
  "0.15.2"` in [`build.zig.zon`](./build.zig.zon).
- [`uv`](https://docs.astral.sh/uv/) for Python-based harness helpers. Python helper scripts in this repo are run via `uv run ...`.

## Build And Verification

Build the library and CLI:

```bash
zig build
```

This produces the CLI at `./zig-out/bin/zdisamar-o2a-forward-profile`.

Run the fast local verification loop:

```bash
zig build check
```

Run the focused radiative-transfer/parity verification loop:

```bash
zig build test-transport
```

Run the retained O2A shape lane:

```bash
zig build test-validation-o2a
```

Run the optional O2A vendor trend assessment lane when you need a vendor comparison:

```bash
zig build test-validation-o2a-vendor
```

Regenerate the tracked O2A comparison bundle that is meant to be committed:

```bash
zig build o2a-plot-bundle
```

Run the full verification baseline:

```bash
zig build test
```

When disk is tight and you do not want `zig build` to leave a persistent
`.zig-cache` or global Zig cache behind, use the ephemeral wrapper instead:

```bash
./scripts/zig-build-ephemeral.sh check
./scripts/zig-build-ephemeral.sh test-fast --summary all
```

That wrapper points both Zig cache roots at temporary directories and removes
them automatically when the build exits. It is slower than the default flow
because it disables cache reuse across runs.

If you only need to reclaim space from prior runs, remove the repo-local caches
after the build finishes:

```bash
./scripts/clean-zig-caches.sh
```

That deletes `.zig-cache`, `.zig-cache-int`, and the repo's disposable
`zig-cache/` test-output directory.

## Tracked O2A Plot Bundle

The committed O2A comparison evidence lives directly under `validation/`.

- Canonical refresh command: `zig build o2a-plot-bundle`
- Default vendor input: `validation/o2a_with_cia_disamar_reference.csv`
- Default policy: refresh the tracked plots from the committed vendor reference in `validation/o2a_with_cia_disamar_reference.csv`.

## The O2A Workflow

The retained executable surface is a single O2A forward-profile CLI. The normal
local workflow is:

1. build the library and CLI,
2. run the retained fast verification lanes,
3. run the stock O2A diagnostic path when you need artifacts,
4. refresh the tracked plot bundle only when the O2A spectrum or report shape changes.

The CLI surface is:

```text
zdisamar-o2a-forward-profile [--output-dir DIR] [--repeat N] [--write-spectrum]
```

Example:

```bash
./zig-out/bin/zdisamar-o2a-forward-profile --write-spectrum
```

That writes:

- `out/analysis/o2a/profile/summary.json`
- `out/analysis/o2a/profile/generated_spectrum.csv` when `--write-spectrum` is enabled

## Using `zdisamar` As A Zig Library

The shipped Zig surface is intentionally small and literal:

```zig
const std = @import("std");
const zdisamar = @import("zdisamar");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

var case: zdisamar.Case = .{
    .spectral_grid = .{ .start_nm = 758.0, .end_nm = 771.0, .sample_count = 121 },
};
var prepared = try zdisamar.prepare(allocator, &case);
defer prepared.deinit(allocator);

var result = try zdisamar.run(
    allocator,
    &prepared,
    .exact,
    .{},
    null,
);
defer result.deinit(allocator);
```

`Prepared` owns the resolved case, bundled data, prepared optics, and reusable
storage. Data loading, optical-property preparation, and spectrum generation are
not separate public entrypoints.

## Data, Packages, And Exporters

- `data/` contains tracked O2A climatologies, cross-sections, LUTs, and vendor reference assets.
- `validation/` contains the tracked O2A comparison bundle.
- The retained artifact outputs are diagnostic summaries and generated spectra, not exporter backends.

## Validation And Scientific Scope

This repository is meant to be testable as a scientific system, not only as a
build artifact.

- `tests/validation/` carries the retained O2A executable checks.
- `validation/reference/` carries the committed vendor comparison CSV.
- `validation/compatibility/` stores bounded O2A compatibility artifacts such as the tracked plot bundle.

## Recommended Reading

- [`docs/disamar-overview.md`](./docs/disamar-overview.md)
- [`docs/o2a-forward.md`](./docs/o2a-forward.md)
- [`docs/parity-harness.md`](./docs/parity-harness.md)
- [`docs/python-bindings.md`](./docs/python-bindings.md)
- [`docs/o2a-telemetry.md`](./docs/o2a-telemetry.md)
- [`docs/o2a-vendor-stage-map.md`](./docs/o2a-vendor-stage-map.md)
- [`docs/reference-data-and-bundles.md`](./docs/reference-data-and-bundles.md)
- [`docs/validation-and-parity.md`](./docs/validation-and-parity.md)

## Short Version

If you only need the essentials:

```bash
zig build
zig build check
zig build test-transport
zig build test-validation-o2a
# optional: zig build test-validation-o2a-vendor
zig build o2a-forward-profile
./zig-out/bin/zdisamar-o2a-forward-profile --write-spectrum
zig build test
```
