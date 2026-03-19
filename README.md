# zdisamar

`zdisamar` is a Zig radiative-transfer and retrieval platform scaffold for the
DISAMAR model family. The repository is organized around a typed execution
contract:

`Engine -> Plan -> Workspace -> Request -> Result`

That contract is the center of the codebase. Scientific scene state, numerical
kernels, runtime preparation, exporters, and plugin selection are separated so
that execution stays reproducible and provenance stays explicit.

The supported runtime entrypoint is canonical YAML. Historical `Config.in`
inputs are supported only as migration input through the importer.

## What The Repository Contains

- A buildable Zig library and CLI.
- A typed core execution model in `src/core/`.
- Canonical scene, observation, and inverse-problem types in `src/model/`.
- Reusable kernels for transport, optics, interpolation, quadrature, spectra,
  and linear algebra in `src/kernels/`.
- Retrieval layers for OE-, DOAS-, and DISMAS-labeled surrogate solvers in `src/retrieval/`.
- Runtime caches and reference-data preparation in `src/runtime/`.
- Adapter-owned canonical YAML parsing, legacy import, exporter backends, and
  mission wiring in `src/adapters/`.
- Plugin manifests, builtin providers, capability registration, and native ABI
  boundaries in `src/plugins/` and `src/api/`.
- Tracked example experiments and baseline scientific bundles under `data/`.
- Validation assets and executable test lanes under `tests/` and `validation/`.

## Current Runtime Model

The public execution surface is intentionally small:

- `Engine` owns catalogs, registries, allocators, and plan preparation.
- `Plan` freezes the selected scientific and runtime path before execution.
- `Workspace` owns mutable scratch state for one run or run sequence.
- `Request` carries the typed scene and optional inverse-problem intent.
- `Result` owns measurement-space products, retrieval products, diagnostics, and
  provenance.

That structure is why core and kernel code stays free of file I/O, legacy text
parsing, mission-specific control flow, and global mutable state. All of that
belongs in adapters or runtime preparation.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `src/core/` | engine lifecycle, plans, workspaces, requests, results, provenance |
| `src/model/` | canonical scene, geometry, atmosphere, surface, aerosol, cloud, measurement, and inverse types |
| `src/kernels/` | reusable numeric kernels and measurement-space materialization |
| `src/retrieval/` | inverse-method implementations on shared contracts |
| `src/runtime/` | bundle-backed reference preparation, caches, scheduling helpers |
| `src/adapters/` | CLI, canonical config, legacy import, ingest, exporters, mission adapters |
| `src/plugins/` | builtin providers, manifests, capability registry, loader/runtime glue |
| `src/api/` | stable C ABI plus Zig-facing wrappers |
| `packages/` | distributable bundles such as `disamar_standard`, `mission_s5p`, and builtin exporters |
| `data/` | tracked baseline bundles plus example canonical YAML experiments |
| `tests/` | unit, integration, golden, perf, and validation-lane executable checks |
| `validation/` | heavier parity, golden, plugin, perf, and release-readiness evidence |
| `docs/` | architecture, plugin, operational, retrieval, exporter, and validation narrative |

## Prerequisites

- Zig `0.15.2` or newer. The repo currently declares `minimum_zig_version =
  "0.15.2"` in [`build.zig.zon`](./build.zig.zon).

## Build And Verification

Build the library and CLI:

```bash
zig build
```

This produces the CLI at `./zig-out/bin/zdisamar`.

Run the fast local verification loop:

```bash
zig build check
```

Run the focused transport/parity verification loop:

```bash
zig build test-transport
```

Run the fast compatibility smoke loop:

```bash
zig build test-validation-compatibility
```

Run the full verification baseline:

```bash
zig build test
```

Targeted suites are also available:

```bash
zig build test-unit
zig build test-integration
zig build test-golden
zig build test-perf
zig build test-validation
```

## The Canonical Experiment Workflow

Canonical YAML is the supported runtime contract. The CLI surface is:

```text
zdisamar run CONFIG.yaml
zdisamar config validate CONFIG.yaml
zdisamar config resolve CONFIG.yaml
zdisamar config import legacy_config.in
```

### 1. Validate A Config

Use validation first to catch schema and reference issues before execution:

```bash
./zig-out/bin/zdisamar config validate data/examples/canonical_config.yaml
```

That verifies the YAML can be resolved into staged execution with the current
schema and validation rules.

### 2. Inspect The Resolved Execution Plan

Use `config resolve` to see what stages, providers, products, and outputs the
engine will execute:

```bash
./zig-out/bin/zdisamar config resolve data/examples/zdisamar_common_use.yaml
```

This prints:

- resolved metadata and workspace label,
- ordered stages (`simulation` then `retrieval` when both exist),
- selected model family and transport/retrieval providers,
- declared products,
- output jobs with destination URIs.

### 3. Run An Experiment

Execute the tracked common-use experiment:

```bash
./zig-out/bin/zdisamar run data/examples/zdisamar_common_use.yaml
```

As of March 16, 2026 this example runs successfully and produces:

- `out/truth_radiance.nc`
- `out/retrieval.zarr/`

The run command prints a short execution summary including source path,
workspace, stage count, output count, warning count, stage scene ids, plan ids,
and solver route.

### 4. Run Other Tracked Examples

The repository includes three canonical examples with increasing complexity:

- `data/examples/canonical_config.yaml`
  Minimal one-stage smoke example for CLI and release-readiness checks.
- `data/examples/zdisamar_common_use.yaml`
  Two-stage synthetic O2 A-band simulation + retrieval example with NetCDF/CF
  and Zarr outputs.
- `data/examples/zdisamar_expert_o2a.yaml`
  Expert O2 A-band example with tracked assets, ingest adapters, measured
  support data, nuisance-state fitting, and multiple exports.

The expert example can be validated with:

```bash
./zig-out/bin/zdisamar config validate data/examples/zdisamar_expert_o2a.yaml
```

### 5. Know Which Example To Start From

Use the examples in this order:

- `data/examples/canonical_config.yaml`
  Smallest possible CLI smoke case.
- `data/examples/zdisamar_common_use.yaml`
  Best starting point for learning the simulation-plus-retrieval workflow.
- `data/examples/zdisamar_expert_o2a.yaml`
  Advanced example that adds assets, ingests, explicit providers, and
  operational-support-data replacement surfaces.

If you want to learn how to execute an experiment, start from
`zdisamar_common_use.yaml`, not the expert example.

## Provider Names Used In The Examples

The examples mix a few different naming layers. These are the ones that matter
in practice:

| Example field | Meaning |
| --- | --- |
| `transport.solver: dispatcher` | use the builtin transport dispatcher |
| `transport.provider: builtin.transport_dispatcher` | manifest/plugin id for that dispatcher lane |
| resolved `transport_provider: builtin.dispatcher` | the concrete provider name reported by `config resolve` and run provenance |
| `inverse.algorithm.name: oe` | request the OE-labeled surrogate retrieval lane |
| `inverse.algorithm.provider: builtin.oe_solver` | explicit provider id for that OE-labeled surrogate solver |
| `measurement_model.instrument.name: tropomi` | instrument family name; this defaults to `builtin.generic_response` if no explicit response provider is given |
| `surface.model: lambertian` | request the builtin Lambertian-labeled surface-response lane |

These family labels are routing names in the current scaffold. They identify the
intended transport, retrieval, and surface roles without claiming that every
named lane is already a method-faithful implementation of the corresponding
literature algorithm.

## Where The Example Numbers Come From

The example values are not all the same kind of thing.

### `zdisamar_common_use.yaml`

This file is a synthetic scaffold scenario. Its geometry, aerosol, surface, and
prior values are hand-chosen to demonstrate a meaningful two-stage retrieval:

- a truth run and a retrieval run share one O2 A-band template,
- the two stages intentionally use different surface and aerosol settings,
- the retrieval stage starts from a simpler state than the simulation stage,
- the mismatch is deliberate so the inverse problem is nontrivial.

Treat those numbers as representative tutorial values, not as mission-calibrated
constants or a real observed scene.

### `zdisamar_expert_o2a.yaml`

This file is also synthetic, but it is built to exercise more of the runtime:

- asset-backed atmosphere and spectroscopy inputs,
- ingest-backed ISRF table and operational reference-grid replacements,
- nuisance parameters such as wavelength shift and multiplicative offset,
- multiple exporter targets.

Some values in the expert example are copied from the tracked demo ingest
fixtures under `data/examples/irr_rad_channels_operational_*.txt` so that the
config and the ingest-driven tests describe the same small operational-style
scenario.

### `irr_rad_channels_operational_*.txt`

Those files are small demo fixtures consumed by the `spectral_ascii` ingest
adapter. They define metadata such as:

- geometry,
- albedo,
- cloud and aerosol summary properties,
- wavelength shift,
- instrument line shape / ISRF table samples,
- reference-grid and solar-spectrum samples,
- small O2 and O2-O2 lookup-table coefficient blocks.

They are intentionally tiny and readable. They exist to exercise the parser and
the operational-support-data path, not to represent a production Sentinel-5P
granule.

### Practical Rule

When you adapt an example for your own experiment:

- keep the structure,
- replace the numbers with your own scene geometry, bands, absorber setup,
  surface state, aerosol/cloud state, and measurement inputs,
- keep only the providers and ingest surfaces you actually understand and need.

## Anatomy Of A Canonical YAML Experiment

The canonical schema is designed around typed execution rather than a flat list
of runtime flags.

### `schema_version`

Pins the document format. The current examples use `schema_version: 1`.

### `metadata`

Run metadata such as:

- `id`
- `workspace`
- `description`

`workspace` labels the runtime workspace used during execution. If omitted, the
CLI falls back to `metadata.id` and then `canonical-config`.

### `inputs`

Optional tracked inputs used by richer experiments:

- `assets`
  Named file assets such as profiles, spectroscopy tables, or metadata text.
- `ingests`
  Adapter-level parsed products derived from those assets, such as
  `spectral_ascii` ingestion for operational grids or ISRF tables.

Relative asset paths are resolved from the config location and, if needed, by
walking up parent directories until the asset is found.

### `templates`

Reusable stage templates that bundle:

- `plan`
  Model family, transport provider selection, execution mode, derivative mode,
  transport hints, and backend selection.
- `scene`
  Geometry, atmosphere, spectral bands, absorbers, surface, aerosols, clouds,
  and measurement model.

Templates let multiple stages share one baseline scientific definition and then
override only what changes.

### `experiment`

The execution body. Today the runtime supports up to two ordered stages:

- `simulation`
- `retrieval`

Each stage can inherit from a template via `from`, then override `plan`,
`scene`, `inverse`, `products`, and `diagnostics`.

Important semantics:

- The simulation stage runs first when present.
- The retrieval stage can bind its measurement source to a measurement-space
  product created earlier in the experiment.
- Retrieval requests automatically inherit derivative requirements from the
  stage plan.
- The same typed scene vocabulary is used for both simulation and retrieval.

### `products`

Products are named stage outputs that later stages or exporter jobs can target.
The current product kinds are:

- `measurement_space`
- `state_vector`
- `fitted_measurement`
- `averaging_kernel`
- `jacobian`
- `result`
- `diagnostics`

The most common flow is:

1. a simulation stage materializes a `measurement_space` product,
2. a retrieval stage points `inverse.measurement.source` at that product,
3. outputs serialize selected products after execution finishes.

### `outputs`

Outputs define exporter jobs:

- `from`
  The name of a previously declared product.
- `format`
  Currently `netcdf_cf` or `zarr`.
- `destination_uri`
  A required `file://...` URI.
- `include_provenance`
  Whether exporter artifacts should include extra provenance fields.

Exporter backends create parent directories automatically. A URI such as
`file://out/truth_radiance.nc` writes to `out/truth_radiance.nc` relative to the
current working directory.

### `validation`

Validation policy is part of the document. Current rules include options such
as:

- `strict_unknown_fields`
- `require_resolved_assets`
- `require_resolved_stage_references`
- synthetic retrieval warnings for identical truth/retrieval models

That means bad references and contract violations are meant to fail before the
engine starts normal execution.

## A Minimal Example

This is the smallest tracked pattern for a simulation-stage run:

```yaml
schema_version: 1

metadata:
  id: canonical-cli-smoke
  workspace: canonical-cli-smoke

templates:
  base:
    plan:
      model_family: disamar_standard
      transport:
        solver: dispatcher
      execution:
        solver_mode: polarized
        derivative_mode: semi_analytical
    scene:
      geometry:
        model: plane_parallel
        solar_zenith_deg: 32.5
        viewing_zenith_deg: 9.0
        relative_azimuth_deg: 145.0
      atmosphere:
        layering:
          layer_count: 48
      bands:
        band_1:
          start_nm: 405.0
          end_nm: 465.0
          step_nm: 0.5
      absorbers: {}
      surface:
        model: lambertian
        albedo: 0.0
      measurement_model:
        regime: nadir
        instrument:
          name: tropomi
        sampling:
          mode: native
        noise:
          model: shot_noise

experiment:
  simulation:
    from: base
    scene:
      id: s5p-no2
    products:
      radiance:
        kind: measurement_space
        observable: radiance

outputs: []
```

## Running A Synthetic Simulation + Retrieval Experiment

The common-use example demonstrates the intended two-stage pattern:

1. define a shared template for geometry, atmosphere, bands, absorbers, surface,
   and measurement model,
2. run a `simulation` stage that produces a named measurement-space product,
3. run a `retrieval` stage that points `inverse.measurement.source` at that
   product,
4. export selected outputs after the typed results are available.

Typical workflow:

```bash
./zig-out/bin/zdisamar config validate data/examples/zdisamar_common_use.yaml
./zig-out/bin/zdisamar config resolve data/examples/zdisamar_common_use.yaml
./zig-out/bin/zdisamar run data/examples/zdisamar_common_use.yaml
```

That example currently resolves to:

- a `simulation` stage for `truth_scene`,
- a `retrieval` stage for `retrieval_scene`,
- a measurement-space export to NetCDF/CF,
- a retrieved-state export to Zarr.

## Legacy `Config.in` Migration

Legacy execution is not a supported runtime path. The importer exists to convert
historical flat `Config.in` inputs into canonical YAML for review and cleanup.

Example:

```bash
./zig-out/bin/zdisamar config import data/examples/legacy_config.in > migrated.yaml
```

The importer writes canonical YAML to stdout and emits warnings for
approximations. Current importer caveats include:

- only the flat adapter subset is supported,
- some historical concepts are approximated,
- unmapped requested products may be imported as `kind: result` for
  traceability,
- manual review is still required before treating the result as a canonical
  experiment.

See `specs/legacy_config_mapping.md` for the supported mapping policy.

## Using `zdisamar` As A Zig Library

The CLI is a thin adapter over the typed runtime. The equivalent Zig flow looks
like this:

```zig
const std = @import("std");
const zdisamar = @import("zdisamar");

var engine = zdisamar.Engine.init(std.heap.page_allocator, .{});
defer engine.deinit();

try engine.bootstrapBuiltinCatalog();

var plan = try engine.preparePlan(.{});
defer plan.deinit();

var workspace = engine.createWorkspace("demo");
const request = zdisamar.Request.init(.{
    .id = "scene-demo",
    .spectral_grid = .{ .sample_count = 8 },
});

var result = try engine.execute(&plan, &workspace, request);
defer result.deinit(std.heap.page_allocator);
```

That is the same lifecycle the canonical-YAML CLI eventually drives after
resolution and compilation.

## Data, Packages, And Exporters

- `data/` contains tracked baseline bundles and small example assets used by
  adapter ingestion and validation.
- `packages/` contains distributable package definitions layered on the shared
  runtime rather than reimplementing it.
- Builtin exporter families currently include NetCDF/CF and Zarr. Exporters run
  after typed results exist; they do not rerun transport or retrieval.

## Validation And Scientific Scope

This repository is meant to be testable as a scientific system, not only as a
build artifact.

- `tests/integration/` exercises end-to-end typed execution.
- `tests/golden/` checks stable provenance expectations.
- `tests/validation/` checks schema and evidence assets.
- `validation/compatibility/` stores bounded hybrid-contract parity assets
  against the local upstream Fortran reference.
- `validation/release/` ties commands, provenance expectations, and readiness
  gates together.

## Recommended Reading

- [`docs/disamar-overview.md`](./docs/disamar-overview.md)
- [`docs/zig-architecture.md`](./docs/zig-architecture.md)
- [`docs/plugin-system-end-to-end.md`](./docs/plugin-system-end-to-end.md)
- [`docs/operational-o2a.md`](./docs/operational-o2a.md)
- [`docs/reference-data-and-bundles.md`](./docs/reference-data-and-bundles.md)
- [`docs/retrieval-and-measurement-space.md`](./docs/retrieval-and-measurement-space.md)
- [`docs/exporters-and-artifacts.md`](./docs/exporters-and-artifacts.md)
- [`docs/plugins-and-extension-boundaries.md`](./docs/plugins-and-extension-boundaries.md)
- [`docs/validation-and-parity.md`](./docs/validation-and-parity.md)

## Short Version

If you only need the essentials:

```bash
zig build
zig build check
zig build test-transport
zig build test-validation-compatibility
./zig-out/bin/zdisamar config validate data/examples/zdisamar_common_use.yaml
./zig-out/bin/zdisamar config resolve data/examples/zdisamar_common_use.yaml
./zig-out/bin/zdisamar run data/examples/zdisamar_common_use.yaml
zig build test
```
