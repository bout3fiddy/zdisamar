# Exporters and Result Artifacts

## Why Exporters Matter

Scientific software is judged not only by the forward model it runs but also by the artifacts it produces for downstream analysis, validation, and operations. In `zdisamar`, exporters sit after the scientific run:

1. the engine executes a typed request,
2. the forward and retrieval layers materialize a typed `Result`,
3. exporter adapters serialize that result for downstream use.

This sequencing is deliberate. Output formats should not shape the transport kernels or mission adapters.

## The Result Surface

`src/core/Result.zig` is the source of truth for exporter backends. It can carry:

- measurement-space spectral arrays,
- physical summary scalars,
- diagnostics,
- provenance and capability inventory,
- export-ready metadata.

The exporter layer is therefore not a separate scientific pipeline. It is a serialization and packaging layer built on a fully typed result.

## Current Artifact Families

The current implementation exposes three main artifact families through `src/adapters/exporters/`.

### NetCDF/CF-oriented output

Files:

- `src/adapters/exporters/netcdf_cf.zig`
- `src/adapters/exporters/spec.zig`

Purpose:

- structured scientific output in a CF-oriented layout,
- preservation of wavelength-space arrays and physical summaries,
- explicit dataset naming and provenance.

### Zarr-oriented output

Files:

- `src/adapters/exporters/zarr.zig`
- `src/adapters/exporters/spec.zig`

Purpose:

- array-oriented output for chunked or cloud-style processing,
- direct reuse of typed result arrays,
- the same scientific content in a storage layout suited to scalable downstream analysis.

### Diagnostic output

Files:

- `src/adapters/exporters/diagnostic.zig`
- `src/adapters/exporters/writer.zig`

Purpose:

- human-readable CSV and text products,
- smoke validation and debugging,
- quick parity inspection without changing the scientific path.

## Relationship To The Plugin Catalog

The official NetCDF/CF and Zarr formats also appear in the builtin exporter catalog under `src/plugins/builtin/exporters/`. That catalog makes format identity explicit and versionable. The actual serialization still happens in the adapter-owned exporter backends, which keeps result writing tied to typed `Result` data rather than to ad hoc plugin-side state.

## What Exporters Must Not Do

Exporters are adapters. They must not:

- rerun optics preparation,
- rerun transport,
- parse mission inputs,
- alter the plan or scene,
- invent physical quantities that are not already present in `Result`.

If an output format needs an additional scientific quantity, that quantity should first be added to typed result state. Only then should the exporter write it.

## Provenance And Reproducibility

An exported file should answer a scientific provenance question, not only a storage question. The relevant provenance surfaces include:

- model-family identity,
- transport route and numerical mode,
- plugin inventory and version labels,
- dataset hashes,
- plan identity and scene identity.

That information is what makes it possible to compare exported products across runs and across validation campaigns.

## Reading Order In Code

To follow the artifact path:

1. read `src/core/Result.zig`,
2. read `src/core/provenance.zig`,
3. read `src/adapters/exporters/spec.zig`,
4. read `src/adapters/exporters/writer.zig`,
5. inspect one concrete backend such as `src/adapters/exporters/netcdf_cf.zig` or `src/adapters/exporters/zarr.zig`.
