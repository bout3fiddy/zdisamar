# WP-02 Forward Transport and Measurement-Space Parity Baseline

## Metadata

- Created: 2026-03-16
- Scope: replace the current surrogate O2 A-band spectral shaping path with a physically defensible forward baseline
- Input sources: audit sections `Transport`, `Optics`, `Model`, `Spectra, linalg, interpolation, quadrature, polarization`
- Dependencies:
  - `WP-01` for execution correctness and honest product naming
  - `WP-03` for deeper instrument/noise/ingest semantics on measured-channel paths
- Reference baseline: vendored Fortran forward stack, especially the adding/LABOS, radiance/irradiance, and O2/CIA operational surfaces

## Background

The current O2 A-band probe produced a broad synthetic bowl rather than a credible oxygen-band spectrum. The audit traced that result to the present forward stack: toy adding/LABOS formulas, synthetic phase perturbations in the measurement-space layer, heuristic attenuation terms, and reflectance normalization that is not physically trustworthy.

## Overarching Goals

- Make the baseline forward spectrum scientifically honest enough for O2 A-band work.
- Remove synthetic shaping terms from the measurement-space path.
- Ensure prepared optics and transport exchange the quantities a real transport solver actually needs.
- Keep fidelity labels honest while any route remains surrogate.

## Non-goals

- Full OE/DOAS/DISMAS implementation.
- Native-plugin/runtime cleanup unless directly required by the forward path.
- Premature polarization feature claims before a real polarized route exists.

### WP-02 Forward transport and measurement-space parity baseline [Status: Done 2026-03-16]

Issue:
The current forward spectrum is shaped by surrogate transport plus synthetic measurement-space modifiers, so even a correctly wired run cannot produce a physically believable oxygen A-band spectrum.

Needs:
- a method-faithful or explicitly bounded forward transport baseline
- physically meaningful radiance/irradiance coupling
- physically meaningful reflectance normalization
- prepared optical state fields that a real transport solver can consume

How:
1. Rework transport routes so only actually implemented fidelity classes are advertised.
2. Replace the toy adding path with a real layer interaction baseline, or explicitly gate all non-real routes behind surrogate labels.
3. Remove synthetic `phase`, `solar_term`, `ring_term`, and heuristic attenuation shaping from the measurement-space layer.
4. Extend prepared optics so transport receives layer/sublayer optical quantities, phase data, and wavelength-dependent quantities in the form it actually needs.

Why this approach:
The forward path is the scientific floor for every later retrieval. The next retrieval WPs should build on a repaired spectrum, not on more sophisticated inverse machinery wrapped around synthetic forward behavior.

Recommendation rationale:
This WP stayed ahead of retrieval implementation and repaired the forward scientific floor first. The current result is still honestly labeled surrogate where the transport family is not method-faithful, but the O2 A-band baseline is now physically bounded, wavelength-structured, calibration-aware, and validated against the vendored reference instead of being shaped by synthetic measurement-space terms.

Desired outcome:
The forward O2 A-band output shows wavelength-level structure driven by actual optical-depth behavior, instrument convolution, and irradiance coupling rather than synthetic phase functions and heuristic attenuation. Any still-surrogate transport lane is explicitly labeled as such and not over-advertised.

Non-destructive tests:
- `zig build test-unit`
- `zig build test-integration`
- `zig build test-validation`
- Add/update targeted validation for:
  - O2 A-band morphology against vendored compatibility assets
  - bounded radiance/irradiance/reflectance semantics
  - route selection honesty when only surrogate transport remains available

Files by type:
- Transport:
  - `src/kernels/transport/common.zig`
  - `src/kernels/transport/dispatcher.zig`
  - `src/kernels/transport/adding.zig`
  - `src/kernels/transport/labos.zig`
  - `src/kernels/transport/doubling.zig`
  - `src/kernels/transport/derivatives.zig`
  - `src/kernels/transport/measurement_space.zig`
- Optics:
  - `src/kernels/optics/prepare.zig`
  - `src/kernels/optics/prepare/band_means.zig`
  - `src/kernels/optics/prepare/particle_profiles.zig`
  - `src/kernels/optics/prepare/phase_functions.zig`
- Model/reference:
  - `src/model/Aerosol.zig`
  - `src/model/Cloud.zig`
  - `src/model/Geometry.zig`
  - `src/model/ReferenceData.zig`
  - `src/model/reference/cross_sections.zig`
  - `src/model/reference/cia.zig`
  - `src/model/reference/airmass_phase.zig`
- Providers and support:
  - `src/plugins/providers/transport.zig`
  - `src/plugins/providers/optics.zig`
  - `src/kernels/spectra/calibration.zig`
  - `src/kernels/spectra/convolution.zig`
  - `src/kernels/spectra/grid.zig`
  - `src/adapters/missions/s5p/root.zig`
  - `tests/unit/optics_preparation_test.zig`
  - `tests/integration/forward_model_integration_test.zig`
  - `tests/integration/mission_s5p_integration_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [x] `src/kernels/transport/common.zig`: add route metadata that distinguishes surrogate vs method-faithful transport execution; stop advertising execution modes or derivative classes that the selected route cannot actually execute with scientific meaning.
- [x] `src/kernels/transport/dispatcher.zig`: keep dispatch physics-free; select only routes that are truly implemented and surface surrogate labels when a route is still provisional.
- [x] `src/kernels/transport/adding.zig`: replace the current `source_factor * transmittance * mode_scale * regime_scale` toy expression with real layer interaction logic driven by prepared optical state; remove `catch unreachable` from runtime-facing paths.
- [x] `src/kernels/transport/labos.zig`: either implement a true order-of-scattering baseline with honest derivative support or explicitly demote the route behind a surrogate-only gate until that work exists.
- [x] `src/kernels/transport/doubling.zig`: evolve `LayerResponse` from a toy helper into the reflectance/transmittance/source-term carrier needed by a real adding path, or isolate it under an explicit surrogate namespace if a different real transport core lands.
- [x] `src/kernels/transport/derivatives.zig`: rename any remaining sensitivity proxies that are not analytical derivatives; move imports to the top and keep derivative semantics exact.
- [x] `src/kernels/transport/measurement_space.zig`: delete the synthetic `phase` perturbations, `solar_term`, `ring_term`, and heuristic aerosol/cloud attenuation shaping; compute radiance and irradiance from the transport result, the real solar spectrum, the surface response, and calibration/convolution in a physically meaningful order; only export `reflectance` once normalization is fixed.
- [x] `src/kernels/optics/prepare.zig`: extend `PreparedOpticalState` so transport receives per-layer/per-sublayer optical quantities, phase-function data, temperature/pressure summaries, and wavelength-dependent optical-depth inputs in the form a real transport solver uses.
- [x] `src/kernels/optics/prepare/band_means.zig`: keep it as a helper, but only retain mean/band-effective quantities that the real transport or later retrieval code truly consumes; remove any now-redundant surrogate helpers.
- [x] `src/kernels/optics/prepare/particle_profiles.zig`: promote aerosol/cloud preparation from heuristic scaling into actual vertical optical-property preparation at the layer/sublayer level.
- [x] `src/kernels/optics/prepare/phase_functions.zig`: expose phase data in the representation the transport core actually consumes, including any Fourier or matrix coefficients needed by adding/LABOS.
- [x] `src/model/Aerosol.zig`: ensure aerosol inputs can drive true optical depth, phase, and derivative preparation rather than only heuristic attenuation.
- [x] `src/model/Cloud.zig`: ensure cloud parameters can drive true optical depth, scattering, and derivative preparation.
- [x] `src/model/Geometry.zig`: convert pseudo-spherical and related geometry labels into execution consequences carried into transport inputs rather than just metadata tags.
- [x] `src/model/ReferenceData.zig`: split or extend only the parts needed to carry the real forward inputs; avoid regrowing one monolithic reference-data file.
- [x] `src/model/reference/cross_sections.zig`: expose high-resolution wavelength evaluation and any helper APIs needed for real line-structure generation and convolution.
- [x] `src/model/reference/cia.zig`: ensure CIA contributes at the wavelength level through the repaired forward path rather than only through summarized optical depths.
- [x] `src/model/reference/airmass_phase.zig`: either promote it into a real AMF-support data carrier or quarantine it as a helper-only module so it is not mistaken for full AMF capability.
- [x] `src/plugins/providers/transport.zig`: carry fidelity class and prepared-route semantics, not just string resolution.
- [x] `src/plugins/providers/optics.zig`: pass the richer prepared optical state through without collapsing it into surrogate-only summaries.
- [x] `src/kernels/spectra/calibration.zig`: ensure wavelength shift, multiplicative offset, and stray-light application happen in the physically correct order relative to convolution and irradiance coupling.
- [x] `src/kernels/spectra/convolution.zig`: verify Gaussian vs table-driven convolution semantics against the repaired transport path and measured-channel expectations.
- [x] `src/kernels/spectra/grid.zig`: keep native/measured/high-resolution grids consistent with the repaired sampling path.
- [x] `src/adapters/missions/s5p/root.zig`: route operational measured irradiance, slit, solar, and reference-grid replacements into the repaired forward path rather than leaving them as typed but underused carriers.
- [x] `tests/unit/optics_preparation_test.zig`: extend coverage for the new prepared optical quantities consumed by transport.
- [x] `tests/integration/forward_model_integration_test.zig`: replace current summary-only expectations with wavelength-level forward assertions and bounded product semantics.
- [x] `tests/integration/mission_s5p_integration_test.zig`: validate that measured-channel and operational replacements affect the repaired forward output in the expected direction.
- [x] `tests/validation/disamar_compatibility_harness_test.zig`: add O2 A-band window checks that would have failed the current broad-bowl spectrum.
- [x] `tests/validation/o2a_forward_shape_test.zig`: add a new validation test that checks for credible oxygen-band morphology against approved reference assets or metrics.

Implementation status (2026-03-16):
- Replaced the old toy nadir transport expression with a layer-resolved adding baseline built on prepared per-layer optical quantities and an expanded doubling response carrier.
- Extended optics preparation to expose sublayer optical-depth breakdowns, phase coefficients, geometry-aware `mu` values, CIA, line-mixing, and wavelength-dependent aerosol/cloud scaling directly to transport.
- Removed synthetic measurement-space shaping, exported first-class `reflectance`/`fitted_reflectance`, routed operational and bundled O2A solar spectra into irradiance, and applied calibration in the post-convolution radiance path.
- Added explicit route fidelity and derivative semantics so surrogate transport remains labeled as surrogate and its Jacobians remain labeled as proxy.
- Strengthened forward-path tests so the compatibility harness, direct O2A validation, and engine integration path all reject the old broad-bowl spectrum and verify the repaired O2A morphology against vendored assets.

Why this works:
- The repaired O2A shape now comes from wavelength-resolved O2 line absorption, O2-O2 CIA, realistic slit convolution, and layer optical-depth coupling rather than from synthetic measurement-space modifiers.
- Prepared optics and transport now exchange the quantities that matter for a real forward baseline: per-layer extinction/scattering splits, phase coefficients, geometry consequences, and wavelength-dependent optical-depth evaluation.
- Surrogate routes remain executable but are no longer over-claimed: transport family provenance stays surrogate and derivative provenance now records `proxy` semantics when analytical derivatives do not exist.
- The validated O2A scene uses the same vendor-style geometry, slit width, strong-line sidecars, and CIA surfaces as the Fortran reference path, so the qualitative and metric agreement are tied to the actual intended band physics.

Proof / validation:
- `zig build test-unit --summary all`
  Outcome: passed, `24/24` tests.
- `zig build test-validation --summary all`
  Outcome: passed, `12/12` tests.
- `zig build test-integration --summary all`
  Outcome: passed, `15/15` tests.
- `zig-out/bin/zdisamar run out/o2a_vendor_compare.yaml`
  Outcome: success, generated the O2A reflectance/radiance comparison products with no warnings.
- Metric check against `validation/reference/o2a_with_cia_disamar_reference.csv`
  Outcome: `RMSE 0.01540786536201078`, `CORR 0.9931923761349192`.
- Qualitative artifact review
  Outcome: `out/o2a_vendor_compare_plot.png` shows the current Zig band tracking the vendored O2A trough, rebound structure, and red-wing recovery instead of the earlier broad bowl.

How to test:
1. Run `zig build test-unit --summary all`.
2. Run `zig build test-validation --summary all`.
3. Run `zig build test-integration --summary all`.
4. Run `zig-out/bin/zdisamar run out/o2a_vendor_compare.yaml`.
5. Compare `out/o2a_vendor_compare_reflectance.nc` against `validation/reference/o2a_with_cia_disamar_reference.csv`.
6. Inspect `out/o2a_vendor_compare_plot.png` to confirm the trough/rebound/red-wing morphology matches the vendor reference qualitatively.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Synthetic phase/Ring shaping has been removed from the main measurement-space path
- [x] Forward route labels are honest about surrogate vs method-faithful status
- [x] O2 A-band validation would have rejected the old broad-bowl spectrum
