## O2A Forward Architecture

`zdisamar` now ships as a narrow O2 A forward-model lab. The product shape is:

`case -> data -> optics -> solver -> spectrum -> report`

The public Zig surface is exported from [src/o2a.zig](../src/o2a.zig) and re-exported by [src/root.zig](../src/root.zig). The retained API is intentionally small:

- `Case`
- `Data`
- `Optics`
- `Method`
- `Work`
- `Result`
- `Report`
- `loadData`
- `buildOptics`
- `runSpectrum`
- `writeReport`

## Source Layout

- [src/o2a/case.zig](../src/o2a/case.zig) defines the retained O2 A inputs.
- [src/o2a/data.zig](../src/o2a/data.zig) and [src/o2a/data/](../src/o2a/data) load reference assets and vendor fixtures.
- [src/o2a/optics.zig](../src/o2a/optics.zig) and [src/o2a/optics/](../src/o2a/optics) prepare layer optical properties.
- [src/o2a/solver.zig](../src/o2a/solver.zig) and [src/o2a/solver/](../src/o2a/solver) expose the exact scalar LABOS path.
- [src/o2a/spectrum.zig](../src/o2a/spectrum.zig) sweeps the spectral grid and assembles radiance products.
- [src/o2a/report.zig](../src/o2a/report.zig) and [src/o2a/report/](../src/o2a/report) own timings, counters, snapshots, and JSON output.
- [src/o2a/cli/profile.zig](../src/o2a/cli/profile.zig) is the retained executable surface.

## Deliberate Removals

The repo no longer ships the generic platform perimeter:

- engine and planner scaffolding
- plugin registries and native plugin ABI
- retrieval families
- general config-driven CLI
- mission wiring and exporters
- runtime cache and scheduler layers

Those surfaces are removed rather than preserved behind compatibility wrappers.

## Method Seam

[src/o2a/method.zig](../src/o2a/method.zig) is the only retained experimentation seam. Milestone 1 implements only `.exact`. Future sampled or emulator-style methods should attach at the spectral runner level, not by rebuilding a plugin framework.
