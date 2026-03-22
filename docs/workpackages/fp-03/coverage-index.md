# Coverage Index

## Purpose

This file is the second-pass coverage proof for the full DISAMAR capability parity plan. Every scientifically important input, vendor feature family, current Zig subsystem, and validation artifact family inspected during this planning pass is assigned to a specific workpackage or to an explicit preserve-only bucket.

## Legend

- `WP-01` full config surface and canonical YAML parity
- `WP-02` forward transport solver parity
- `WP-03` line-absorbing spectroscopy and strong-line sampling parity
- `WP-04` cross-section gas and effective-xsec parity
- `WP-05` atmospheric intervals, aerosol, cloud, fraction, and subcolumns parity
- `WP-06` instrument, radiance/irradiance, slit, calibration, corrections, and Ring parity
- `WP-07` operational measured-input and S5P interface parity
- `WP-08` LUT and XsecLUT generation, consumption, and cache parity
- `WP-09` vendor-vs-Zig multi-case validation and scientific acceptance
- `WP-10` performance benchmarking and regression thresholds
- `WP-11` optimal estimation, Jacobian, and weighting-function parity
- `WP-12` DOAS, classic DOAS, and DOMINO parity
- `WP-13` DISMAS parity
- `WP-14` additional output, diagnostics, and export parity
- `WP-15` plugin, adapter, and hygiene after scientific parity
- `Preserve` keep under observation; no immediate patch in this plan

## Planning Inputs

| File | Assignment | Why |
| --- | --- | --- |
| `current_state_and_findings_2026-03-17.md` | `WP-01`, `WP-02`, `WP-03`, `WP-05`, `WP-09` | Baseline statement of what is already known, especially the forward-first O2A gap. |
| `workpackage_template.md` | All WPs | Template and formatting baseline for the refreshed plan set. |
| earlier O2A-focused parity workpackage set | `WP-02`, `WP-03`, `WP-05`, `WP-06`, `WP-09`, `WP-11`, `WP-12`, `WP-13`, `WP-15` | The new plan preserves its strongest forward-first insight but broadens the scope. |
| `vendor_disamar_fortran_2026-03-17.tar.gz` | `WP-01` through `WP-14` | Scientific and config-reference baseline. |
| `zdisamar_feature_parity_r2_2026-03-17.bundle` | `WP-01` through `WP-15` | Current Zig implementation under audit. |

## Fresh And Ongoing Comparison Artifact Families

| Artifact family | Assignment | Why |
| --- | --- | --- |
| O2A forward overlays, metrics, and NetCDF outputs | `WP-09` | First forcing-case acceptance gate. |
| non-O2A forward overlays and metrics (UV, NO2, O3, SWIR, cloud/aerosol) | `WP-09` | Prevent overfitting to the O2A case. |
| LUT/XsecLUT regeneration artifacts | `WP-08`, `WP-09` | Needed to validate both generation and runtime consumption. |
| retrieval residual plots, posterior diagnostics, AK/DFS outputs | `WP-11`, `WP-12`, `WP-13`, `WP-14` | Retrieval-family-specific proof. |
| benchmark tables and profiler summaries | `WP-10` | Performance regressions must be measured explicitly. |

## Vendor Example Config Corpus

Representative vendor example configs are listed below. The complete key-by-key config inventory belongs to `WP-01`; this section assigns the example-case families that should drive later validation.

| Vendor config example | Assignment | Why |
| --- | --- | --- |
| `Config_O2_with_CIA.in` | `WP-02`, `WP-03`, `WP-05`, `WP-06`, `WP-09` | Primary forcing case for line-absorbing forward parity. |
| `Config_O2_no_CIA.in` | `WP-02`, `WP-03`, `WP-09` | Separates CIA handling from the rest of O2A physics. |
| `Config_O2A_XsecLUT.in` | `WP-03`, `WP-08`, `WP-09` | Tests line-vs-LUT/XsecLUT parity. |
| `Config_O2-O2.in` | `WP-03`, `WP-04`, `WP-09` | O2-O2 behavior outside the exact O2A forcing case. |
| `Config_O2-O2_UV.in` | `WP-04`, `WP-09` | Cross-section / UV O2-O2 pathway. |
| `Config_O2-O2_UV_external.in` | `WP-04`, `WP-07`, `WP-09` | External/measured input semantics intersect with UV O2-O2. |
| `Config_O2_UV.in` | `WP-04`, `WP-09` | Cross-section-like O2 UV family. |
| `Config_NO2_DOMINO.in` | `WP-04`, `WP-07`, `WP-12`, `WP-14` | DOMINO and operational NO2 pathway. |
| `Config_NO2_O2-O2.in` | `WP-04`, `WP-05`, `WP-12`, `WP-14` | Mixed NO2 and O2-O2 pathway. |
| `Config_NO2_PBL.in` | `WP-04`, `WP-05`, `WP-11`, `WP-12` | Lower-tropospheric profile/AMF sensitivity. |
| `Config_NO2_camelot_european_background.in` | `WP-04`, `WP-12`, `WP-14` | Cross-section retrieval family coverage. |
| `Config_NO2_camelot_european_polluted.in` | `WP-04`, `WP-05`, `WP-12`, `WP-14` | Stress case for pollution and aerosol/cloud interactions. |
| `Config_trop_NO2_strat_NO2_camelot_european_polluted.in` | `WP-05`, `WP-11`, `WP-12`, `WP-14` | Strat/trop partition semantics. |
| `ConfigStratTrop_NO2_2_pixels.in` | `WP-05`, `WP-11`, `WP-12` | Multi-pixel strat/trop split behavior. |
| `Config_column_O3.in` | `WP-04`, `WP-11`, `WP-14` | O3 column pathway. |
| `Config_columns_O3_HCHO_BrO_NO2.in` | `WP-04`, `WP-11`, `WP-14` | Multi-gas cross-section case family. |
| `Config_O3_profile_1band.in` | `WP-04`, `WP-11`, `WP-14` | O3 profile pathway. |
| `Config_O3_profile_OMI_grid_1band.in` | `WP-04`, `WP-07`, `WP-11`, `WP-14` | OMI-grid operational path. |
| `Config_O3_profile_MLW_MLS_OMI.in` | `WP-04`, `WP-07`, `WP-11`, `WP-14` | OMI measured-input/profile pathway. |
| `Config_O3_profile_S5_band1_2.in` | `WP-04`, `WP-07`, `WP-11`, `WP-14` | S5-related operational profile pathway. |
| `Config_O3_profile_TROPOMI_band1_2.in` | `WP-04`, `WP-07`, `WP-11`, `WP-14` | TROPOMI profile pathway. |
| `Config_O3_profile_TROPOMI_band2.in` | `WP-04`, `WP-07`, `WP-11`, `WP-14` | TROPOMI variant coverage. |
| `Config_O3_profile_ozone_hole.in` | `WP-04`, `WP-11`, `WP-14` | Stress case for extreme-profile behavior. |
| `Config_O3_profile+SO2_column.in` | `WP-04`, `WP-11`, `WP-13`, `WP-14` | Mixed profile-plus-column retrieval family. |
| `Config_O3_profile_SO2_column_DISMAS_5.in` | `WP-04`, `WP-13`, `WP-14` | Direct DISMAS-relevant case. |
| `ConfigStratTrop_O3_2_pixels.in` | `WP-05`, `WP-11`, `WP-14` | Strat/trop and multi-pixel O3 semantics. |
| `Config_H2O_NH3.in` | `WP-03`, `WP-09`, `WP-11`, `WP-14` | Line-absorbing multi-gas case beyond O2A. |
| `Config_ESA_project_CO2+H2O.in` | `WP-03`, `WP-06`, `WP-09`, `WP-14` | SWIR/NIR line-absorbing family. |
| `Config_ESA_project_CO2+H2O_SWIR2.in` | `WP-03`, `WP-06`, `WP-09`, `WP-14` | SWIR2 specialization. |
| `Config_ESA_project_NIR-2_pressure.in` | `WP-03`, `WP-06`, `WP-09`, `WP-14` | NIR pressure family. |
| `Config_ESA_project_SWIR-2_pressure.in` | `WP-03`, `WP-06`, `WP-09`, `WP-14` | SWIR pressure family. |
| `Config_ESA_project_O2+CO2+H2O.in` | `WP-03`, `WP-06`, `WP-09`, `WP-14` | Multi-band line-absorbing family. |
| `Config_ESA_project_O2+CO2+H2O_3bands.in` | `WP-03`, `WP-06`, `WP-09`, `WP-14` | Multi-band extension. |
| `Config_ESA_project_O2+CO2+H2O_cirrus.in` | `WP-03`, `WP-05`, `WP-06`, `WP-09`, `WP-14` | Cirrus plus multi-band instrument/transport semantics. |
| `Config_ESA_project_O2+CO2+H2O_radianceVII.in` | `WP-06`, `WP-07`, `WP-09`, `WP-14` | Radiance-driven operational variant. |
| `Config_AAI.in` | `WP-04`, `WP-05`, `WP-06`, `WP-14` | UV/aerosol/diagnostic output family. |

## Vendor Fortran Source Modules

| Vendor module | Assignment | Why |
| --- | --- | --- |
| `readConfigFileModule.f90` | `WP-01` | Source of truth for how the vendor config surface is parsed. |
| `verifyConfigFileModule.f90` | `WP-01` | Separates “parsed” from “valid and honored” behavior. |
| `DISAMARModule.f90` | `WP-02`, `WP-06`, `WP-07`, `WP-08`, `WP-09`, `WP-14` | Top-level simulation wiring and execution orchestration. |
| `dataStructures.f90` | `WP-01`, `WP-02`, `WP-05`, `WP-11`, `WP-14` | Vendor state layout reference. |
| `inputModule.f90` | `WP-07`, `WP-14` | Operational/ingest context. |
| `propAtmosphere.f90` | `WP-05` | Pressure-grid, interval, and atmospheric subdivision semantics. |
| `subcolumnModule.f90` | `WP-05` | Subcolumn semantics and profile partitioning. |
| `LabosModule.f90` | `WP-02`, `WP-11` | Scalar multiple-scattering and weighting-function reference. |
| `addingToolsModule.f90` | `WP-02` | Adding recursion and top/down propagation reference. |
| `FourierCoefficientsModule.f90` | `WP-02`, `WP-05` | Fourier / phase-function support in scalar transport. |
| `radianceIrradianceModule.f90` | `WP-02`, `WP-05`, `WP-06`, `WP-11`, `WP-13` | Central forward spectral, normalization, and derivative pathways. |
| `calibrateIrradianceModule.f90` | `WP-06`, `WP-07` | Irradiance calibration reference. |
| `readIrrRadFromFileModule.f90` | `WP-06`, `WP-07` | Measured radiance/irradiance ingestion path. |
| `S5PInterfaceModule.f90` | `WP-07`, `WP-14` | Mission-specific S5P bridge semantics. |
| `S5POperationalModule.f90` | `WP-07`, `WP-14` | Operational measured-input and product flow. |
| `HITRANModule.f90` | `WP-03`, `WP-08` | Line-absorbing spectroscopy and LUT support. |
| `createLUTModule.f90` | `WP-08`, `WP-09` | LUT/XsecLUT generation path. |
| `readModule.f90` | `WP-07`, `WP-08`, `WP-14` | Input asset reading and operational data support. |
| `writeModule.f90` | `WP-14` | Vendor output production reference. |
| `netcdfModule.f90` | `WP-14` | Export parity reference. |
| `optimalEstimationModule.f90` | `WP-11` | OEM baseline. |
| `doasModule.f90` | `WP-12` | Main DOAS baseline. |
| `classic_doasModule.f90` | `WP-12` | Classic DOAS and effective-xsec reference. |
| `dismasModule.f90` | `WP-13` | DISMAS baseline. |
| `ramanspecsModule_v2.f90` | `WP-06`, `WP-14` | Ring/Raman-related correction and output context. |
| `mathToolsModule.f90` | `WP-02`, `WP-03`, `WP-11`, `WP-12`, `WP-13` | Supporting numerical reference. |
| `pqf_module.f90` | `WP-06`, `WP-07` | Instrument/slit or operational support context. |
| `staticDataModule.f90` | `WP-03`, `WP-04`, `WP-08` | Bundled reference-data context. |
| `DISAMAR_interface.f90` | `WP-07`, `WP-14` | Interface/output context. |
| `DISAMAR_file.f90` | `WP-14` | File-output behavior. |
| `DISAMAR_log.f90` | `WP-14`, `WP-15` | Logging and diagnostic reporting context. |
| `asciiiHDFtoolsModule.f90` | `WP-07`, `WP-14` | Operational measured-data support. |
| `errorHandlingModule.f90` | `WP-15` | Late cleanup and runtime error-surface hardening reference. |
| `main_DISAMAR.f90` | Preserve | Entry wiring reference only; not a primary parity target. |
| `create_slit_function_file.f90` | `WP-06` | Useful slit-function generation reference. |

## Current Zig Core / Model / Config Files

| File | Assignment | Why |
| --- | --- | --- |
| `src/core/Plan.zig` | `WP-01`, `WP-02`, `WP-06`, `WP-11` | Prepared control state and route typing. |
| `src/core/Engine.zig` | `WP-02`, `WP-06`, `WP-07`, `WP-08`, `WP-09`, `WP-11`, `WP-14` | Main orchestration hotspot. |
| `src/core/Request.zig` | `WP-01`, `WP-07`, `WP-11`, `WP-12`, `WP-13` | Measurement-source and retrieval request semantics. |
| `src/core/Result.zig` | `WP-06`, `WP-09`, `WP-11`, `WP-14` | Output ownership and honesty of produced products. |
| `src/core/Workspace.zig` | `WP-02`, `WP-10`, `WP-15` | Execution-context and later cleanup/perf work. |
| `src/core/Catalog.zig` | `WP-01`, `WP-15` | Capability registration and narrowing. |
| `src/core/diagnostics.zig` | `WP-14` | Diagnostic output path. |
| `src/core/errors.zig` | `WP-01`, `WP-11`, `WP-15` | Error-domain honesty. |
| `src/core/logging.zig` | `WP-14`, `WP-15` | Logging/output surface. |
| `src/core/provenance.zig` | `WP-01`, `WP-02`, `WP-03`, `WP-04`, `WP-05`, `WP-06`, `WP-08`, `WP-09`, `WP-14` | Must record effective controls for parity review. |
| `src/core/units.zig` | `WP-01`, `WP-05` | Geometry/control typing. |
| `src/model/Scene.zig` | `WP-01`, `WP-05` | Scene-level config structure. |
| `src/model/ObservationModel.zig` | `WP-01`, `WP-06`, `WP-07` | Instrument/control representation is still too stringly. |
| `src/model/Instrument.zig` | `WP-01`, `WP-06`, `WP-07`, `WP-08` | Instrument and operational data carriers. |
| `src/model/instrument/reference_grid.zig` | `WP-06`, `WP-07`, `WP-08` | Operational spectral-grid parity. |
| `src/model/instrument/solar_spectrum.zig` | `WP-06` | Solar input handling. |
| `src/model/instrument/line_shape.zig` | `WP-06`, `WP-07` | Slit/ISRF parity. |
| `src/model/instrument/cross_section_lut.zig` | `WP-04`, `WP-08` | XsecLUT representation and runtime use. |
| `src/model/instrument/constants.zig` | `WP-06` | Instrument constant support. |
| `src/model/Absorber.zig` | `WP-01`, `WP-03`, `WP-04` | Gas family typing. |
| `src/model/ReferenceData.zig` | `WP-03`, `WP-04`, `WP-08` | Large science-data umbrella that must be split conceptually by parity family. |
| `src/model/reference/cross_sections.zig` | `WP-03`, `WP-04` | Line and cross-section data support. |
| `src/model/reference/cia.zig` | `WP-03`, `WP-04` | CIA parity. |
| `src/model/reference/climatology.zig` | `WP-05` | Atmospheric profile defaults and support. |
| `src/model/reference/airmass_phase.zig` | `WP-05`, `WP-11`, `WP-12`, `WP-13` | AMF-related support path. |
| `src/model/reference/rayleigh.zig` | `WP-02`, `WP-05` | Scattering support. |
| `src/model/reference/demo_builders.zig` | `WP-09` | Test/example support only. |
| `src/model/Aerosol.zig` | `WP-01`, `WP-05` | Aerosol config and interval semantics. |
| `src/model/Cloud.zig` | `WP-01`, `WP-05` | Cloud config and interval semantics. |
| `src/model/Atmosphere.zig` | `WP-01`, `WP-05` | Pressure-grid and layering semantics. |
| `src/model/Geometry.zig` | `WP-01`, `WP-05`, `WP-06` | Typed geometry inputs. |
| `src/model/Measurement.zig` | `WP-01`, `WP-07`, `WP-11`, `WP-12`, `WP-13` | Measured-input and retrieval source semantics. |
| `src/model/InverseProblem.zig` | `WP-01`, `WP-11`, `WP-12`, `WP-13` | Retrieval config typing. |
| `src/model/StateVector.zig` | `WP-01`, `WP-11`, `WP-12`, `WP-13` | State-target typing and transforms. |
| `src/model/Surface.zig` | `WP-01`, `WP-05`, `WP-06` | Surface config and interaction semantics. |
| `src/model/Bands.zig` | `WP-03`, `WP-04`, `WP-06` | Spectral-window support. |
| `src/model/Spectrum.zig` | `WP-06`, `WP-14` | Product spectrum representation. |
| `src/model/Binding.zig` | `WP-01`, `WP-07` | Binding semantics for external/measured data. |
| `src/model/LayoutRequirements.zig` | `WP-10`, `WP-15` | Performance/layout support later in the plan. |
| `src/model/hitran_partition_tables.zig` | `WP-03` | Supporting line-absorbing spectroscopy data. |
| `src/model/layout/Axes.zig` | `WP-10`, `WP-15` | Later performance/layout support. |
| `src/model/layout/AtmosphereSoA.zig` | `WP-10`, `WP-15` | Performance/layout support after scientific parity is real. |
| `src/model/layout/StateVectorSoA.zig` | `WP-10`, `WP-15` | Same. |
| `src/model/layout/TensorBlockAoSoA.zig` | `WP-10`, `WP-15` | Same. |

## Current Zig Forward / Optics / Spectra Files

| File | Assignment | Why |
| --- | --- | --- |
| `src/kernels/transport/common.zig` | `WP-01`, `WP-02` | Route and control typing. |
| `src/kernels/transport/dispatcher.zig` | `WP-02` | Forward route dispatch. |
| `src/kernels/transport/labos.zig` | `WP-02`, `WP-11` | Transport and later weighting-function parity hotspot. |
| `src/kernels/transport/adding.zig` | `WP-02` | Adding-route parity hotspot. |
| `src/kernels/transport/doubling.zig` | `WP-02` | Auxiliary propagation or removal decision. |
| `src/kernels/transport/derivatives.zig` | `WP-11` | Retrieval/weighting-function support. |
| `src/kernels/transport/measurement_space.zig` | `WP-02`, `WP-06`, `WP-07`, `WP-09`, `WP-11`, `WP-12`, `WP-13` | Central forward-model hotspot. |
| `src/kernels/optics/prepare.zig` | `WP-03`, `WP-04`, `WP-05`, `WP-08` | Prepared optics and layering bridge. |
| `src/kernels/optics/prepare/band_means.zig` | `WP-03`, `WP-04` | Band and mean treatment in spectroscopy pathways. |
| `src/kernels/optics/prepare/particle_profiles.zig` | `WP-05` | Particle vertical distributions. |
| `src/kernels/optics/prepare/phase_functions.zig` | `WP-02`, `WP-05` | Phase-function support. |
| `src/kernels/spectra/calibration.zig` | `WP-06`, `WP-07` | Calibration handling. |
| `src/kernels/spectra/convolution.zig` | `WP-06`, `WP-07`, `WP-12`, `WP-13` | Slit integration and spectral-fitting support. |
| `src/kernels/spectra/grid.zig` | `WP-06`, `WP-07`, `WP-08` | Grid handling for spectral and LUT paths. |
| `src/kernels/spectra/noise.zig` | `WP-06`, `WP-07`, `WP-11`, `WP-12`, `WP-13` | Noise and sigma semantics. |
| `src/kernels/quadrature/composite_trapezoid.zig` | `WP-03`, `WP-06` | Supporting integration utilities. |
| `src/kernels/quadrature/gauss_legendre.zig` | `WP-02`, `WP-03`, `WP-06` | Supporting transport/spectroscopy integration. |
| `src/kernels/quadrature/source_integration.zig` | `WP-02` | Transport-source integration support. |
| `src/kernels/interpolation/linear.zig` | `WP-03`, `WP-04`, `WP-06`, `WP-08` | Supporting interpolation. |
| `src/kernels/interpolation/resample.zig` | `WP-06`, `WP-07`, `WP-08` | Grid transformations. |
| `src/kernels/interpolation/spline.zig` | `WP-03`, `WP-06`, `WP-08` | Supporting interpolation. |
| `src/kernels/polarization/mueller.zig` | Preserve | Important later, but not the first scalar parity blocker. |
| `src/kernels/polarization/stokes.zig` | Preserve | Same. |
| `src/kernels/linalg/small_dense.zig` | `WP-10`, `WP-11`, `WP-12`, `WP-13` | Retrieval and benchmark support. |
| `src/kernels/linalg/cholesky.zig` | `WP-11` | OEM solver support. |
| `src/kernels/linalg/qr.zig` | `WP-11`, `WP-12`, `WP-13`, `WP-15` | Retrieval math and cleanup. |
| `src/kernels/linalg/svd_fallback.zig` | `WP-11`, `WP-12`, `WP-13`, `WP-15` | Retrieval math and cleanup. |
| `src/kernels/linalg/vector_ops.zig` | `WP-10`, `WP-11`, `WP-12`, `WP-13` | Shared numerical support. |

## Current Zig Retrieval Files

| File | Assignment | Why |
| --- | --- | --- |
| `src/retrieval/common/contracts.zig` | `WP-11`, `WP-12`, `WP-13`, `WP-14` | Retrieval-result semantics and later output parity. |
| `src/retrieval/common/covariance.zig` | `WP-11`, `WP-12`, `WP-13` | Sigma/covariance honesty. |
| `src/retrieval/common/diagnostics.zig` | `WP-11`, `WP-12`, `WP-13`, `WP-14` | Retrieval diagnostics output path. |
| `src/retrieval/common/forward_model.zig` | `WP-11`, `WP-12`, `WP-13` | Retrieval-facing forward model. |
| `src/retrieval/common/jacobian_chain.zig` | `WP-11` | Jacobian assembly. |
| `src/retrieval/common/priors.zig` | `WP-11` | OEM support. |
| `src/retrieval/common/transforms.zig` | `WP-11`, `WP-12`, `WP-13` | Shared transform support. |
| `src/retrieval/common/spectral_fit.zig` | `WP-12`, `WP-13` | Shared spectral-fitting path. |
| `src/retrieval/common/state_access.zig` | `WP-01`, `WP-11`, `WP-12`, `WP-13` | Typed state access is prerequisite for real retrievals. |
| `src/retrieval/common/surrogate_forward.zig` | `WP-11`, `WP-12`, `WP-13` | Must be retired or clearly kept non-parity. |
| `src/retrieval/oe/solver.zig` | `WP-11` | Real OEM implementation. |
| `src/retrieval/doas/solver.zig` | `WP-12` | Real DOAS implementation. |
| `src/retrieval/dismas/solver.zig` | `WP-13` | Real DISMAS implementation. |

## Current Zig Ingest / Export / Adapter / API Files

| File | Assignment | Why |
| --- | --- | --- |
| `src/adapters/canonical_config/Document.zig` | `WP-01`, `WP-15` | Main config-surface hotspot and later cleanup candidate. |
| `src/adapters/canonical_config/document_fields.zig` | `WP-01` | Stable vendor-key identity layer. |
| `src/adapters/canonical_config/document_yaml_helpers.zig` | `WP-01` | Helper extraction and strictness. |
| `src/adapters/canonical_config/execution.zig` | `WP-01` | Parse-to-runtime-honor compilation. |
| `src/adapters/canonical_config/yaml.zig` | `WP-01`, `WP-15` | YAML support and strictness. |
| `src/adapters/legacy_config/Adapter.zig` | `WP-01`, `WP-15` | Legacy-import compatibility boundary. |
| `src/adapters/legacy_config/config_in_importer.zig` | `WP-01`, `WP-15` | Legacy config import path. |
| `src/adapters/legacy_config/import_to_canonical.zig` | `WP-01`, `WP-15` | Legacy-to-canonical mapping. |
| `src/adapters/legacy_config/schema_mapper.zig` | `WP-01`, `WP-15` | Same. |
| `src/adapters/ingest/spectral_ascii.zig` | `WP-06`, `WP-07`, `WP-08` | Spectral ASCII and operational asset ingest. |
| `src/adapters/ingest/spectral_ascii_metadata.zig` | `WP-06`, `WP-07`, `WP-08` | Same. |
| `src/adapters/ingest/spectral_ascii_runtime.zig` | `WP-06`, `WP-07`, `WP-08` | Same. |
| `src/adapters/ingest/reference_assets.zig` | `WP-03`, `WP-04`, `WP-08` | Reference-asset ingest for spectroscopy and LUT work. |
| `src/adapters/ingest/reference_assets_formats.zig` | `WP-03`, `WP-04`, `WP-08` | Format-specific ingest support. |
| `src/adapters/missions/s5p/root.zig` | `WP-07`, `WP-14` | Mission-specific operational path. |
| `src/adapters/exporters/spec.zig` | `WP-14` | Export contract. |
| `src/adapters/exporters/diagnostic.zig` | `WP-14` | Diagnostic export path. |
| `src/adapters/exporters/format.zig` | `WP-14` | Export format support. |
| `src/adapters/exporters/io.zig` | `WP-14` | Export file I/O. |
| `src/adapters/exporters/writer.zig` | `WP-14` | Export writing support. |
| `src/adapters/exporters/netcdf_cf.zig` | `WP-09`, `WP-14` | Required for comparison output and final export parity. |
| `src/adapters/exporters/zarr.zig` | `WP-14` | Secondary export path. |
| `src/adapters/cli/App.zig` | `WP-09`, `WP-14` | Validation harness and CLI-facing export flow. |
| `src/adapters/cli/main.zig` | `WP-09`, `WP-14` | Same. |
| `src/api/zig/root.zig` | `WP-15` | Public Zig API narrowing. |
| `src/api/zig/wrappers.zig` | `WP-15` | Wrapper cleanup and error-surface hardening. |
| `src/api/c/bridge.zig` | `WP-15` | C ABI cleanup after scientific parity. |
| `src/api/c/disamar.h` | `WP-15` | Same. |
| `src/root.zig` | `WP-15` | Public export-surface reduction. |

## Current Zig Plugins / Runtime Files

| File | Assignment | Why |
| --- | --- | --- |
| `src/plugins/providers/transport.zig` | `WP-02` | Typed transport-provider seam. |
| `src/plugins/providers/optics.zig` | `WP-03`, `WP-04`, `WP-08` | Optics provider seam. |
| `src/plugins/providers/instrument.zig` | `WP-06`, `WP-07`, `WP-08` | Instrument/integration provider seam. |
| `src/plugins/providers/noise.zig` | `WP-06`, `WP-07`, `WP-11`, `WP-12`, `WP-13` | Noise and measured-input semantics. |
| `src/plugins/providers/surface.zig` | `WP-05`, `WP-06` | Surface semantics. |
| `src/plugins/providers/retrieval.zig` | `WP-11`, `WP-12`, `WP-13`, `WP-15` | Retrieval-family exposure and later cleanup. |
| `src/plugins/providers/diagnostics.zig` | `WP-14`, `WP-15` | Diagnostic provider support. |
| `src/plugins/providers/exporter.zig` | `WP-14`, `WP-15` | Export-provider support. |
| `src/plugins/providers/root.zig` | `WP-15` | Provider surface narrowing after science parity. |
| `src/plugins/selection.zig` | `WP-01`, `WP-15` | Config-to-runtime selection typing. |
| `src/plugins/slots.zig` | `WP-01`, `WP-15` | Same. |
| `src/plugins/registry/CapabilityRegistry.zig` | `WP-15` | Native-plugin complexity is late-cleanup territory. |
| `src/plugins/loader/manifest.zig` | `WP-15` | Same. |
| `src/plugins/loader/dynlib.zig` | `WP-15` | Same. |
| `src/plugins/loader/resolver.zig` | `WP-15` | Same. |
| `src/plugins/loader/runtime.zig` | `WP-15` | Same. |
| `src/plugins/abi/abi_types.zig` | `WP-15` | Same. |
| `src/plugins/abi/host_api.zig` | `WP-15` | Same. |
| `src/plugins/abi/plugin.h` | `WP-15` | Same. |
| `src/plugins/builtin/root.zig` | `WP-15` | Builtin registration cleanup. |
| `src/plugins/builtin/transport/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/surfaces/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/retrieval/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/instruments/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/noise/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/diagnostics/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/reference/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/exporters/root.zig` | `WP-15` | Same. |
| `src/plugins/builtin/exporters/catalog.zig` | `WP-15` | Same. |
| `src/plugins/builtin/exporters/netcdf_cf.plugin.json` | `WP-15` | Same. |
| `src/plugins/builtin/exporters/zarr.plugin.json` | `WP-15` | Same. |
| `src/plugins/root.zig` | `WP-15` | Plugin public surface cleanup. |
| `src/runtime/reference/BundledOptics.zig` | `WP-03`, `WP-04`, `WP-08`, `WP-09` | Bundled science-data path and validation. |
| `src/runtime/cache/DatasetCache.zig` | `WP-08`, `WP-10`, `WP-15` | Dataset and LUT/cache support. |
| `src/runtime/cache/LUTCache.zig` | `WP-08`, `WP-10`, `WP-15` | LUT cache parity and later performance work. |
| `src/runtime/cache/PlanCache.zig` | `WP-10`, `WP-15` | Runtime cache/performance and later cleanup. |
| `src/runtime/cache/PreparedLayout.zig` | `WP-10`, `WP-15` | Layout/performance and naming cleanup. |
| `src/runtime/scheduler/ScratchArena.zig` | `WP-10`, `WP-15` | Execution scratch/perf support. |
| `src/runtime/scheduler/ThreadContext.zig` | `WP-10`, `WP-15` | Execution-context cleanup. |
| `src/runtime/scheduler/BatchRunner.zig` | `WP-10`, `WP-15` | Benchmark and later simplification. |

## Current Zig Validation Files

| File | Assignment | Why |
| --- | --- | --- |
| `tests/validation/main.zig` | `WP-03`, `WP-09` | Validation-suite entrypoint now includes the focused line-gas family lane. |
| `tests/validation/o2a_vendor_reflectance_support.zig` | `WP-02`, `WP-03`, `WP-09` | Shared O2A validation harness for vendor reference comparison plus line-gas control/adaptive execution toggles. |
| `tests/validation/o2a_forward_shape_test.zig` | `WP-02`, `WP-03`, `WP-09` | O2A morphology, RTM-control, adaptive sampling, and line-gas control/CIA sensitivity checks. |
| `tests/validation/line_gas_family_validation_test.zig` | `WP-03`, `WP-09` | Focused non-O2 staged line-gas validation through the real prepare and measurement-space path. |
| `tests/validation/disamar_compatibility_harness_test.zig` | `WP-01`, `WP-02`, `WP-03`, `WP-04`, `WP-07`, `WP-08`, `WP-09`, `WP-14` | Shared compatibility harness that still needs broader non-O2 vendor-corpus line-gas coverage. |

## Preserve / No Immediate Patch

| File or family | Assignment | Why |
| --- | --- | --- |
| `src/internal.zig` | Preserve | Internal umbrella only. |
| `src/*/AGENTS.md` and `src/AGENTS.md` | Preserve | Process docs, not shipping code. |
| `src/runtime/reference/root.zig`, `src/runtime/cache/root.zig`, `src/runtime/scheduler/root.zig`, `src/runtime/root.zig`, `src/model/layout/root.zig`, `src/kernels/*/root.zig`, `src/adapters/*/root.zig`, `src/retrieval/*/root.zig` | Preserve | Umbrella files only unless they need export cleanup under `WP-15`. |
| `src/kernels/polarization/*` | Preserve | Important later, but not on the first scalar parity critical path. |
| `src/plugins/builtin/*/.gitkeep` and `src/adapters/missions/s5p/.gitkeep` | Preserve | Placeholder files only. |
| `main_DISAMAR.f90` | Preserve | Top-level entry only. |

## What This Plan Covers That The Narrower O2A Plan Did Not

This broader plan adds explicit ownership for:

- the **full DISAMAR config surface**, not just the O2A YAML port
- **cross-section gas parity** as a separate scientific track
- **measured radiance/irradiance and S5P operational pathways**
- **LUT and XsecLUT creation plus runtime consumption**
- **multi-case validation** across O2, O2-O2, NO2, O3, SO2, HCHO/BrO, H2O/NH3, SWIR/NIR, cirrus, and pressure cases
- **additional outputs and exporter parity**, not just core forward/retrieval numerics

That is the difference between “repair the forcing case” and “build a fully capable zdisamar that can honestly claim DISAMAR parity.”
