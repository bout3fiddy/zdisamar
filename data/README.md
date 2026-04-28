# Scientific Data Bundles

This directory contains tracked baseline bundle assets for reproducible scaffold
verification. These assets are intentionally small and are not meant to replace
full upstream scientific databases.

## Bundle Roots

- `data/reference_data/climatologies/`: atmospheric profile bundle metadata and baseline tables.
- `data/reference_data/cross_sections/`: absorber cross-section bundle metadata and baseline tables.
- `data/reference_data/luts/`: LUT bundle metadata and baseline tables.
- `data/reference_data/solar/`: solar reference spectra used by O2 A examples and validation.
- `data/examples/`: tracked YAML and ingest fixtures. `vendor_o2a_parity.yaml`
  is the current executable YAML example; the irradiance/radiance text files
  are bounded parser fixtures.

## Provenance

Each bundle root includes a `bundle_manifest.json` with:

- owning package
- upstream reference roots in `vendor/disamar-fortran/`
- tracked local assets and SHA-256 digests

Cross-section bundles may include CSV samples, fixed-width HITRAN-style
line lists, strong-line sidecars, relaxation-matrix subsets, and bounded
collision-induced absorption tables. Reference-data ingestion normalizes those
assets into typed `ReferenceData` structures before the forward model consumes
them.

## Acquisition Notes

Upstream reference subsets are tracked by the bundle manifests next to the data
they describe. O2 A parity evidence lives under `validation/`.

## Reference-Data Ingestion

The typed loaders in `src/input/reference_data/ingest/` consume these tracked
assets and validate their digests against the bundle manifests before preparing
them for the forward model.
