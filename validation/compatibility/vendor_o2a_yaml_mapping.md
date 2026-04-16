# O2A Vendor YAML Mapping

This note records the live YAML mapping for the retained O2A parity case.

Reference policy:

- Semantic source for parse/default intent: `readConfigFileModule::readConfigFile`
- Semantic source for compatibility checks: `verifyConfigFileModule::verifyConfigFile`
- Executable YAML entrypoint: `data/examples/vendor_o2a_parity.yaml`
- Typed parity support layer: `src/o2a/data/vendor_parity_yaml.zig`

The current YAML surface is intentionally narrow. Every field below is either
consumed by the resolved runtime or rejected explicitly by the adapter.

| DISAMAR concept | YAML path | Zig runtime consumer | Status |
| --- | --- | --- | --- |
| `wavelength_start`, `wavelength_end`, coarsened band sampling | `templates.vendor_o2a_base.scene.bands.o2a.*` | `ResolvedVendorO2ACase.spectral_grid` via `vendor_parity_runtime.buildResolvedVendorO2AScene()` | Consumed |
| `slit_index_* = 1`, `FWHM_* = 0.38` | `templates.vendor_o2a_base.scene.measurement_model.spectral_response.*` | `ResolvedVendorO2ACase.observation` | Consumed |
| `SolarZenithAngle`, `ViewingZenithAngle`, `RelativeAzimuthAngle` | `templates.vendor_o2a_base.scene.geometry.*` | `ResolvedVendorO2ACase.geometry` | Consumed |
| `surfPressure*`, explicit pressure intervals, `numIntervalFit` | `templates.vendor_o2a_base.scene.atmosphere.boundary` and `.interval_grid` | `ResolvedVendorO2ACase.surface_pressure_hpa`, `.intervals`, `.fit_interval_index_1based` | Consumed |
| Aerosol optical thickness, SSA, asymmetry, fit-interval placement | `templates.vendor_o2a_base.scene.aerosols.plume.*` | `ResolvedVendorO2ACase.aerosol` | Consumed |
| `factorLMSim`, `cutoffSim`, isotope selection | `templates.vendor_o2a_base.scene.absorbers.o2.spectroscopy.*` | `ResolvedVendorO2ACase.o2` | Consumed |
| `SECTION O2-O2` CIA enablement | `templates.vendor_o2a_base.scene.absorbers.o2o2.spectroscopy.*` | `ResolvedVendorO2ACase.o2o2` | Consumed |
| `numDivPointsFWHMSim`, adaptive strong-line bounds | `templates.vendor_o2a_base.scene.measurement_model.sampling.adaptive_reference_grid.*` | `ResolvedVendorO2ACase.observation.adaptive_reference_grid` | Consumed |
| `atmosphericScatteringSim`, `nstreamsSim`, source integration, renorm | `templates.vendor_o2a_base.scene.rtm.*` | `ResolvedVendorO2ACase.rtm_controls` | Consumed |
| Asset file references instead of inline scientific tables | `inputs.assets.*` | `vendor_parity_runtime.loadResolvedVendorO2AInputs()` | Consumed |
| Unsupported broader canonical-config surface | any field outside the retained subset | `adapters/o2a_parity_config.zig` strict field checks | Rejected |

Notable translation decisions:

- The executable YAML is anchored to the retained O2A parity lane, not the full
  historical canonical-config project.
- The YAML keeps data external through tracked asset references instead of
  embedding scientific arrays inline.
- The current vendor trend baseline in
  `validation/compatibility/o2a_vendor_forward_reflectance_baseline.json` is not
  a passing baseline today. The YAML lane preserves the current retained parity
  runtime behavior and therefore preserves the current baseline outcome as
  well.
