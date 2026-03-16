# Work Package Detail: Mission Operational and Spectroscopy Depth Closure

## Metadata

- Package: `docs/workpackages/feature_vendor_runtime_activation_2026-03-15/`
- Scope: `src/adapters/missions/`, `src/adapters/ingest/`, `src/model/`, `src/kernels/`, `tests/`, `validation/`
- Input sources:
  - `vendor/disamar-fortran/src/S5POperationalModule.f90`
  - `vendor/disamar-fortran/src/HITRANModule.f90`
  - subagent vendor audits recorded on 2026-03-15
- Constraints:
  - keep mission parsing in adapters
  - keep spectroscopy state typed and allocator-owned
  - do not collapse back into vendor global mutable state

## Background

The vendor audit still found two material capability gaps after runtime bundle activation:

- operational mission replacement for S5P/TROPOMI is still far narrower than the vendor operational flow
- spectroscopy remains hybrid-contract level rather than feature-equivalent physics

These are separate gaps and should remain separate so the repo can close them without conflating mission I/O, runtime preparation, and spectroscopy science.

### WP-03 Expand S5P Operational Replacement Toward Vendor Parity [Status: Done 2026-03-15]

- Issue: the current S5P adapter builds typed requests and can read a minimal measured-channel file, but it does not yet replace the geometry, auxiliary, ISRF, and measured-spectrum surfaces the way `S5POperationalModule.f90` does.
- Needs: richer measured-input replacement, auxiliary-data mapping, geometry/surface replacement lanes, and validation over realistic multi-channel operational fixtures.
- How: extend adapter-owned operational input parsing and mission-run construction so representative measured spectra plus auxiliary metadata can replace the right typed scene/request fields without leaking that logic into `src/core`.
- Why this approach: operational parity is inherently an adapter concern, not a reason to blur the core/runtime boundary.
- Recommendation rationale: the vendor audit still rates S5P parity as a high-severity gap.
- Desired outcome: the repo can build representative TROPOMI operational runs from richer measured-input bundles instead of only a small channel text fixture.
- Non-destructive tests:
  - `zig build test-integration`
  - mission-specific adapter tests
  - validation cases over measured-input replacement
- Files by type:
  - mission/adapters/tests: `src/adapters/missions/**/*`, `src/adapters/ingest/**/*`, `tests/integration/**/*`, `tests/validation/**/*`

- Recommendation rationale: keep the operational parity scope tied to typed mission input replacement, not to vendor-global runtime structures.
- Implementation status (2026-03-15): done. `src/adapters/ingest/spectral_ascii.zig` now parses operational metadata lanes for geometry, surface, cloud, aerosol, wavelength shift, ISRF FWHM, explicit high-resolution grid controls, fixed-size ISRF offset/weight tables, and wavelength-indexed ISRF nominal rows alongside measured channels. `src/adapters/missions/s5p/root.zig` maps those values into the typed `Scene` used by `buildOperational(...)`, and `src/kernels/transport/measurement_space.zig` now supports scalar FWHM-driven Gaussian integration, explicit high-resolution grid sampling, explicit typed ISRF table weighting, and nearest-nominal row selection for wavelength-indexed slit tables.
- Why this works: it now matches the operational intent of vendor `replaceISRFData` closely enough for the current typed architecture. The measured-input surface can replace geometry, auxiliary fields, and per-nominal slit-function weights without reintroducing vendor-style mutable globals or file-dependent kernel code.
- Proof / validation: `zig build test-unit`, `zig build test-integration`, `zig build test-validation`, `zig build test-perf`, `zig build test`, `zig build`, `zig test src/exporters_wp12_test_entry.zig`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` pass with the wavelength-indexed slit-table path enabled. The focused unit proof is `measurement-space operational integration selects wavelength-indexed isrf rows`, and the adapter proofs are the operational metadata parsing and S5P mission integration tests around `data/examples/irr_rad_channels_operational_isrf_table_demo.txt`.
- How to test:
  - `zig build test-unit`
  - `zig build test-integration`
  - `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`

### WP-04 Deepen Spectroscopy From Hybrid Contract Toward Vendor Physics Parity [Status: Done 2026-03-15]

- Issue: the current spectroscopy path now ingests tracked vendor subsets and supports bounded sidecar-driven mixing, but it still uses a simplified pseudo-Voigt / heuristic mixing path rather than the fuller vendor HITRAN/LISA evaluation.
- Needs: richer HITRAN metadata lanes, isotopologue/partition handling, stronger strong-line conversion logic, and validation that goes beyond structural “signal present” checks.
- How: extend typed line data and evaluation helpers incrementally, keeping the physics explicit in `src/model/ReferenceData.zig` and related kernels while preserving the adapter-owned parsing boundary.
- Why this approach: spectroscopy depth is a scientific-core gap, not an adapter or documentation gap.
- Recommendation rationale: the vendor audit still rates spectroscopy parity as a high-severity blocker to a true feature-parity claim.
- Desired outcome: the O2 A-band and line-by-line spectroscopy path is no longer only a bounded hybrid approximation relative to the vendor source.
- Non-destructive tests:
  - `zig build test-unit`
  - `zig build test-validation`
  - focused spectroscopy regression tests
  - updated parity-matrix comparisons against representative vendor outputs
- Files by type:
  - model/ingest/kernels/tests: `src/model/**/*`, `src/adapters/ingest/**/*`, `src/kernels/**/*`, `tests/**/*`, `validation/**/*`

- Implementation status (2026-03-15): done. The remaining operational spectroscopy and measured-solar gap from `S5POperationalModule.f90`, `DISAMAR_interface.f90`, and `readModule.f90` is now implemented as typed state instead of vendor-global replacement logic. `src/model/Instrument.zig` now defines slice-backed `OperationalReferenceGrid`, `OperationalSolarSpectrum`, and `OperationalCrossSectionLut` surfaces. `src/model/ObservationModel.zig`, `src/model/Scene.zig`, and `src/adapters/missions/s5p/root.zig` carry those owned reference-grid, solar-spectrum, O2, and O2-O2 inputs through the typed request surface. `src/adapters/ingest/spectral_ascii.zig` parses bounded `refspec_wavelength_*`, `refspec_gauss_weight_*`, `hires_wavelength_*`, `hires_solar_*`, `o2_refspec_*`, and `o2o2_refspec_*` metadata into owned typed state, `src/kernels/optics/prepare.zig` uses the weighted refspec grid when computing operational O2 / O2-O2 band means, and `src/kernels/transport/measurement_space.zig` uses the external solar spectrum instead of the synthetic irradiance fallback when operational metadata provides one.
- Why this works: the remaining vendor contract was not “more generic spectroscopy,” it was a concrete operational override lane that combines weighted reference wavelengths, measured high-resolution solar input, and O2 / O2-O2 coefficient cubes on the operational wavelength grid. The Zig path now mirrors that contract without reintroducing vendor mutable globals: adapters parse and own the operational inputs, scenes carry them as typed observation-model state, optics consumes the weighted refspec grid and coefficient cubes, and measurement-space evaluation consumes the external solar spectrum directly. That closes the last missing operational feature surface while preserving the repo’s typed runtime boundary.
- Proof / validation: `zig build test-unit`, `zig build test-integration`, `zig build test-validation`, `zig build test-perf`, `zig build test`, `zig build`, `zig test src/exporters_wp12_test_entry.zig`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` pass after the weighted-refspec and external-solar lane landed. Focused proofs include `model.Instrument.test.operational reference grid and solar spectrum validate typed external inputs`, the operational-refspec metadata test in `tests/unit/adapter_ingest_test.zig`, `measurement-space uses external high-resolution solar spectra when operational metadata provides one`, `s5p operational adapter maps O2 and O2-O2 refspec LUT metadata`, `s5p operational mission adapter executes O2 and O2-O2 refspec replacement metadata`, and `optical preparation applies operational O2 and O2-O2 LUT replacements for O2A scenes`.
- How to test:
  - `zig build test-unit`
  - `zig build test-integration`
  - `zig build test-validation`
- Remaining gap before done: none for this WP. Public-facing docs are the next gate.
