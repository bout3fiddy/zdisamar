# Validation and Scientific Scope

## What Validation Means In This Repository

The purpose of validation in `zdisamar` is to show that the current implementation carries the intended scientific surfaces of the DISAMAR model family and that those surfaces behave coherently across unit tests, integration tests, and bounded reference-implementation comparisons.

An earlier Fortran implementation remains useful as a reference implementation for focused comparisons, but validation in this repository is broader than source-to-source matching. It has to cover:

- scientific input preparation,
- transport and measurement-space behavior,
- operational replacement surfaces,
- retrieval-facing derivatives and contracts,
- provenance and artifact integrity.

## Layers Of Validation

### Unit tests

Unit tests check scientific mechanics in isolation, for example:

- spectroscopy evaluation,
- line-shape and partition handling,
- O2-O2 CIA interpolation,
- Mie and phase-table interpolation,
- operational reference-grid and solar-spectrum validation,
- operational O2 and O2-O2 lookup-table evaluation,
- optics preparation with operational overrides.

### Integration tests

Integration tests check that the engine, mission adapters, runtime bundle layer, and measurement-space path agree on one typed execution flow. These tests are where scene assembly, plan preparation, transport, and result ownership are exercised together.

### Validation harnesses

Validation harnesses make bounded comparison explicit. They record which scientific surfaces are under comparison and which imported datasets support those comparisons. This is where the repository states, in a falsifiable way, what is actually covered by the current validated envelope.

### Performance smoke tests

Performance tests do not prove correctness, but they protect the architecture against regressions that would make scientific validation harder, for example accidental allocation blowups or dispatch-path changes that invalidate existing assumptions.

## Current Validated Envelope

The current implementation is validated for a bounded but operationally important envelope centered on oxygen A-band work and the surrounding scientific infrastructure. That envelope includes:

- bundle-backed climatology and spectroscopy ingestion,
- typed HITRAN-style line lists and strong-line sidecars,
- relaxation matrices and O2-O2 CIA subsets,
- aerosol and cloud phase-table preparation,
- runtime preparation of optical state from tracked bundles,
- measurement-space materialization into owned arrays,
- Sentinel-5P/TROPOMI-style operational replacement surfaces for:
  - geometry and auxiliary fields,
  - explicit slit functions,
  - weighted reference-spectrum grids,
  - external solar spectra,
  - O2 and O2-O2 coefficient cubes.

This is the scientific scope that the current docs and tests can defend.

## Claims The Documentation Should Make Carefully

Safe claims:

- the present repository carries the main oxygen A-band operational surfaces explicitly in typed state,
- measurement-space outputs, provenance, and exporter inputs are validated on the normal execution path,
- the codebase supports OE, DOAS, and DISMAS method families on a shared contracts layer,
- the current implementation is aligned with the DISAMAR literature on forward-model and retrieval structure.

Claims that should remain qualified:

- complete equivalence to every historical DISAMAR dataset,
- mission equivalence beyond the currently exercised Sentinel-5P path,
- equality of every numerical intermediate with any earlier implementation,
- blanket scientific coverage outside the documented and tested data surfaces.

## Literature Context

The literature is part of the validation story because the software must be judged against the science it claims to support.

- de Haan et al. (2022) defines DISAMAR as a coupled radiative-transfer and retrieval system across multiple spectral domains.
- Sanders et al. (2015) anchors the operational oxygen A-band aerosol-layer-height setting.
- Keppens et al. (2024) documents sustained operational ozone profiling with TROPOMI.
- Tilstra et al. (2024) and de Graaf et al. (2025) document the surface-reflectance and oxygen-band context in which operational retrieval behavior should be interpreted.

Those papers are the reason the docs in this repository focus on scientific scope, operational surfaces, and retrieval behavior instead of only on code translation.

## Main Validation Artifacts

Representative files include:

- `tests/unit/adapter_ingest_test.zig`
- `tests/unit/optics_preparation_test.zig`
- `tests/integration/mission_s5p_integration_test.zig`
- `tests/integration/forward_model_integration_test.zig`
- `tests/validation/disamar_compatibility_harness_test.zig`
- `validation/compatibility/parity_matrix.json`
- `validation/compatibility/vendor_import_registry.json`

## Reading Order

If the goal is to understand the current validated envelope quickly:

1. read [DISAMAR Overview](./disamar-overview.md),
2. read [Operational O2 A-Band Path](./operational-o2a.md),
3. inspect `validation/compatibility/parity_matrix.json`,
4. read `tests/validation/disamar_compatibility_harness_test.zig`,
5. inspect the unit and integration tests for the surface you care about.
