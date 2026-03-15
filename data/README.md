# Scientific Data Bundles

This directory contains tracked baseline bundle assets for reproducible scaffold
verification. These assets are intentionally small and are not meant to replace
full upstream scientific databases.

## Bundle Roots

- `data/climatologies/`: atmospheric profile bundle metadata and baseline tables.
- `data/cross_sections/`: absorber cross-section bundle metadata and baseline tables.
- `data/luts/`: LUT bundle metadata and baseline tables.
- `data/examples/`: small adapter-ingest fixtures, including vendor-style irradiance/radiance channel text.

## Provenance

Each bundle root includes a `bundle_manifest.json` with:

- owning package
- upstream reference roots in `vendor/disamar-fortran/`
- tracked local assets and SHA-256 digests

Cross-section bundles may include both CSV samples and fixed-width HITRAN-style
line lists. Adapter ingestion normalizes those assets into the typed
`ReferenceData` model before kernels consume them.

## Acquisition Notes

The import mapping for upstream reference subsets lives in
`validation/compatibility/vendor_import_registry.json`.

## Adapter Ingestion

The typed adapter loaders in `src/adapters/ingest/` consume these tracked assets
and validate their digests against the bundle manifests before registering them
with engine caches.
