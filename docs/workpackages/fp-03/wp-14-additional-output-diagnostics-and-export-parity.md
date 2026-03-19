# WP-14 Additional Output, Diagnostics, And Export Parity

## Metadata

- Created: 2026-03-18
- Scope: support vendor additional-output surfaces, diagnostic products, internal-field outputs, and export parity needed to cover the full config surface
- Input sources:
  - vendor `readConfigFileModule.f90::readAdditionalOutput`
  - vendor `writeModule.f90`
  - vendor `DISAMARModule.f90::getOutput` and related output helpers
  - vendor `radianceIrradianceModule.f90` internal-field and contribution routines
  - Zig result/export/diagnostic code
- Dependencies:
  - `WP-02` through `WP-13`
- Reference baseline:
  - vendor `writeModule.f90::{print_results,print_asciiHDF,writeSimulatedSpectra1,writeSimulatedSpectra2,writeRingSpec,writeDiffRingSpec,writeFillingInSpec,writeContribRad_Refl,writeInternalField,writeAltResolvedAMF,writeColumnProperties,write_disamar_sim}`
  - vendor `DISAMARModule.f90::{getOutput,getOutputInt1,getOutputString}`
  - vendor `radianceIrradianceModule.f90::{calcUD_conv,calcContribRRS}`

## Background

If the goal is “handle all config items in DISAMAR,” then `ADDITIONAL_OUTPUT` cannot remain a second-tier concern. The vendor code can emit far more than a single spectrum: internal fields, contribution terms, Ring products, column properties, profile outputs, and diagnostic grids. This WP makes the Zig output surface honest and broad enough to cover those controls.

## Overarching Goals

- Represent vendor additional-output requests explicitly.
- Emit typed results for diagnostic products instead of burying them in ad hoc exporter logic.
- Keep output availability aligned with actual forward/retrieval capabilities.

## Non-goals

- Claiming an output product exists before its physics path exists.
- Using exporters as a substitute for typed result models.
- Copying vendor ASCII/HDF formats byte-for-byte if they do not fit the Zig output model.

### WP-14 Additional output, diagnostics, and export parity [Status: Todo]

Issue:
The vendor config surface includes additional-output and diagnostic controls that the current Zig runtime does not fully expose or honor.

Needs:
- typed additional-output request representation
- result carriers for internal fields, contributions, Ring products, and column/property diagnostics
- exporters that can serialize those products consistently
- validation that the runtime only advertises outputs it can actually compute

How:
1. Parse additional-output requests into typed product descriptors.
2. Add typed result carriers for the corresponding forward/retrieval diagnostics.
3. Extend exporters to write those products where they exist.
4. Validate on cases that explicitly request additional outputs.

Why this approach:
Vendor output breadth is part of the product surface, not an afterthought. If Zig ignores these outputs, it cannot honestly claim full config parity.

Recommendation rationale:
This comes after the science WPs because output parity depends on the underlying forward and retrieval products actually existing.

Desired outcome:
A caller can request vendor-style additional outputs through canonical config, the engine can return typed result products for supported items, and exporters can serialize them without inventing unsupported data.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/contracts_test.zig`
- `zig test tests/unit/exporters_catalog_link_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Result/diagnostic targets:
  - `src/core/Result.zig`
  - `src/core/diagnostics.zig`
  - `src/model/Measurement.zig`
- Export targets:
  - `src/adapters/exporters/spec.zig`
  - `src/adapters/exporters/diagnostic.zig`
  - `src/adapters/exporters/netcdf_cf.zig`
  - `src/adapters/exporters/zarr.zig`
  - `src/adapters/exporters/writer.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
- Validation targets:
  - `tests/unit/contracts_test.zig`
  - `tests/unit/exporters_catalog_link_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/Measurement.zig`: represent `ADDITIONAL_OUTPUT` requests explicitly.
  - Vendor anchors: `readConfigFileModule.f90::readAdditionalOutput`.
  - Map vendor output requests to a typed product-descriptor enum rather than a generic string list.
  - Keep unsupported outputs explicit so config parity remains honest.

- [ ] `src/core/Result.zig` and `src/core/diagnostics.zig`: add typed result carriers for additional outputs that the runtime can compute.
  - Vendor anchors: `writeModule.f90::{writeRingSpec,writeDiffRingSpec,writeFillingInSpec,writeContribRad_Refl,writeInternalField,writeAltResolvedAMF,writeColumnProperties}` and `DISAMARModule.f90::getOutput`.
  - Add result families for internal fields, Ring spectra, contribution terms, alt-resolved AMFs, and column properties where the underlying physics path exists.
  - Do not fake unsupported outputs with empty arrays.

- [ ] `src/adapters/exporters/spec.zig`, `diagnostic.zig`, `netcdf_cf.zig`, `zarr.zig`, `writer.zig`: serialize the new typed outputs coherently.
  - Use typed product IDs from `Result.zig`; do not duplicate output-shape logic in each exporter.
  - If a product is unsupported for a given route, the exporter should report that clearly instead of silently omitting it.

- [ ] `src/core/Engine.zig`: wire additional-output requests into execution planning.
  - Requesting an internal field or alt-resolved AMF may require retaining intermediate state that ordinary forward output does not.
  - The plan should know which extra products are needed so execution can prepare the right intermediates once.

- [ ] `tests/unit/contracts_test.zig`, `tests/unit/exporters_catalog_link_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add additional-output coverage.
  - Required cases: at least one forward case requesting internal or contribution outputs, and one retrieval case requesting profile/column diagnostics.
  - Assert that unsupported output requests fail clearly with a typed error or compatibility status.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Additional-output requests are parsed into typed descriptors
- [ ] Supported additional outputs have typed result carriers and exporter support
- [ ] Unsupported additional outputs fail explicitly rather than disappearing silently

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

By moving additional outputs into typed result and export layers, Zig can cover the vendor config surface honestly: supported outputs become first-class products, unsupported ones become explicit compatibility gaps, and nothing is hidden in exporter-specific logic.

## Proof / Validation

- Planned: `zig test tests/unit/contracts_test.zig` -> result/product descriptors and exporter contracts stay aligned
- Planned: `zig test tests/unit/exporters_catalog_link_test.zig` -> exporters know about every supported typed product
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> additional-output cases report support status and runtime behavior correctly

## How To Test

1. Run a case that requests one or more additional outputs.
2. Inspect the typed result object and confirm the products are present and populated.
3. Export to NetCDF or Zarr and confirm the requested products serialize with stable names and dimensions.
4. Request an unsupported additional output and confirm the runtime reports it explicitly.
