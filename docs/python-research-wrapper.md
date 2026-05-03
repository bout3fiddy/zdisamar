# Python Research Interface

This note records the intended shape of the Python research interface for the
O2 A-band forward model. The first spectrum/report slice is implemented; the
larger diagnostic interface remains a design target for later work.

The interface should use DISAMAR and atmospheric remote-sensing language. It
should not expose private implementation wording unless the user explicitly
asks for implementation details.

## Current Public Model

The repository now presents the O2 A path as:

```text
input -> forward model -> output
```

The public Zig surface is:

- `Input`
- `PreparedInput`
- `ReferenceData`
- `OpticalProperties`
- `CalculationStorage`
- `RadiativeTransferControls`
- `Output`
- `DiagnosticReport`

The Python research interface should follow that shape. It should feel like a
thin scientific interface over DISAMAR-style forward-model stages, not like a
mirror of internal file names.

## Goal

The Python interface should let a researcher:

1. configure an O2 A-band input;
2. run the forward model;
3. inspect the resulting spectrum;
4. inspect selected scientific diagnostics without rerunning the full forward
   model unless explicitly requested;
5. run controlled parameter perturbations for sensitivity studies.

The expensive calculation stays in Zig. Python receives bulk arrays and tables
that can be viewed as NumPy, Pandas, or xarray data.

## Naming Principles

Use these terms in Python-facing APIs and docs:

- `input`
- `forward_model`
- `reference_data`
- `optical_properties`
- `atmosphere`
- `atmospheric_layers`
- `absorbers`
- `o2_lines`
- `o2_o2_cia`
- `aerosol`
- `cloud`
- `surface`
- `geometry`
- `instrument_response`
- `instrument_grid`
- `wavelength_sampling`
- `high_resolution_wavelengths`
- `radiative_transfer`
- `doubling_adding`
- `labos`
- `source_function`
- `pseudo_spherical_correction`
- `reflectance`
- `radiance`
- `irradiance`
- `diagnostic_report`
- `diagnostics`

Avoid exposing these as user-facing terms:

- `kernel`
- `sample_plan`
- `workspace`
- `engine`
- `planner`
- `plugin`
- `provider`
- `ABI`
- `trace`

When these appear in source paths or private implementation modules, document
them only as implementation details.

## Example Python Shape

```python
import zdisamar as zd

input = zd.o2a_disamar_reference_input()
input.spectral_grid.sample_count = 701
input.geometry.solar_zenith_deg = 60.0
input.aerosol.optical_depth_550_nm = 0.3
input.radiative_transfer.n_streams = 20

with zd.prepare(input) as prepared:
    output = prepared.forward_model()
    budget = prepared.atmosphere.absorption_budget(
        wavelengths_nm=output.wavelength_nm,
    )
    lines = prepared.o2_lines.contributions(
        wavelengths_nm=[761.75],
        max_rows=50_000,
    )
```

In this example:

- `forward_model()` runs the full spectrum calculation.
- `absorption_budget()` inspects prepared optical properties.
- `o2_lines.contributions()` evaluates selected spectroscopy diagnostics.
- Neither diagnostic call should rerun the full forward model.

Radiative-transfer diagnostics are different. They may need selected
radiative-transfer evaluations, so they should be explicit:

```python
diagnostics = prepared.radiative_transfer.diagnostics(
    wavelengths_nm=[761.75],
    include=["source_function", "pseudo_spherical_correction"],
    max_rows=100_000,
)
```

## Output Checkpoints

Each output checkpoint records what Python should expose, where the feature
lives when implemented, and how to test it. Pending rows intentionally name the
future test command so progress can be tracked as the wrapper grows.

| Status | Output | Created In | Test |
| --- | --- | --- | --- |
| [x] | Final spectrum arrays: `wavelength_nm`, `radiance`, `irradiance`, `reflectance` | `ZdsSpectrum` in `src/api/c.zig`; `Spectrum` in `python/zdisamar/ffi.py` | `zig build python-forward-summary` or `uv run scripts/testing_harness/python_forward_summary.py`; writes `out/ci/python_forward_summary_plot.png` |
| [x] | Current `DiagnosticReport`: sample count, wavelength range, mean radiance, mean irradiance, mean reflectance | `ZdsDiagnosticReport` and `zds_spectrum_report` in `src/api/c.zig`; `Spectrum.diagnostic_report` in `python/zdisamar/ffi.py` | Same as above; the script checks report-vs-array agreement, validation sampling, timing, and closed-spectrum failure |
| [x] | Typed DISAMAR O2 A setup: wavelength grid, atmosphere intervals, geometry, surface, aerosol, O2 line controls, O2-O2 CIA, instrument response, reference assets, radiative-transfer controls | Shared native O2 A setup in `src/input/o2a_reference/`; JSON C boundary in `src/api/c.zig`; Python dataclasses in `python/zdisamar/types.py` | `zig build python-o2a-setup-roundtrip`; verifies typed setup matches `prepare_default_o2a()` |
| [ ] | Input summary: compact read-only summary of the prepared setup | Pending input-summary table | Pending `zig build python-input-summary` |
| [ ] | Reference-data summary: atmosphere profile, O2 line list, O2 strong-line sidecars, O2 line-mixing data, O2-O2 CIA table, solar irradiance data, air-mass-factor tables, aerosol/cloud phase data, asset provenance | Pending reference-data diagnostic table | Pending `zig build python-reference-data-summary` |
| [x] | Atmospheric layer and optical-property budget: layer/sublayer index, altitude, pressure, temperature, number densities, interval identity, absorber/scatterer optical depths, total optical depths, single-scatter albedo | `AtmosphericBudgetRow` in `src/output/atmospheric_budget.zig`; `zds_atmospheric_budget` in `src/api/c.zig`; `AtmosphericBudget` and `PreparedO2A.atmosphere.budget(...)` in `python/zdisamar/ffi.py` | `zig build python-atmosphere-budget`; writes `out/ci/python_atmosphere_budget.csv` and science-question answers in `out/ci/python_atmosphere_budget_questions.json` |
| [x] | O2 line diagnostics: wavelength, spectroscopy profile node, altitude, pressure, temperature, line center, isotope, strength, pressure shift, lower-state energy, half width, weak/strong/line-mixing contributions, inclusion status, matched strong-line sidecar | `O2LineContributionRow` in `src/output/o2_line_contributions.zig`; `zds_o2_line_contributions` in `src/api/c.zig`; `O2LineContributions` and `PreparedO2A.o2_lines.contributions(...)` in `python/zdisamar/ffi.py` | `zig build python-o2-line-diagnostics`; writes `out/ci/python_o2_line_contributions.csv` and science-question answers in `out/ci/python_o2_line_questions.json` |
| [x] | O2-O2 CIA diagnostics: cross sections, layer optical depths, share of total absorption, largest-contribution wavelengths | `O2O2CIADiagnostics` in `python/zdisamar/diagnostics.py`; exposed as `PreparedO2A.o2_o2_cia.diagnostics(...)` | `zig build python-o2-o2-cia-diagnostics`; writes `out/ci/python_o2_o2_cia_diagnostics.csv` and answers in `out/ci/python_o2_o2_cia_questions.json` |
| [x] | Instrument response and instrument grid: nominal wavelengths, high-resolution wavelengths, response weights, high-resolution support width, adaptive sampling controls | `InstrumentResponseDiagnostics` in `python/zdisamar/diagnostics.py`; exposed as `PreparedO2A.instrument_response.sampling_table(...)` | `zig build python-instrument-response`; writes `out/ci/python_instrument_response.csv` and answers in `out/ci/python_instrument_response_questions.json` |
| [x] | Radiative-transfer diagnostics: selected wavelengths, layer optical properties, bounded source/attenuation proxy terms, pseudo-spherical path proxy, final radiance/reflectance | `RadiativeTransferDiagnostics` in `python/zdisamar/diagnostics.py`; exposed as `PreparedO2A.radiative_transfer.diagnostics(...)` | `zig build python-radiative-transfer-diagnostics`; writes `out/ci/python_radiative_transfer_diagnostics.csv` and answers in `out/ci/python_radiative_transfer_questions.json` |
| [x] | Parameter perturbation output: perturbed parameter, delta, baseline spectrum, perturbed spectrum, reflectance delta, sensitivity ranking | `PerturbationDiagnostics` and `PerturbationResult` in `python/zdisamar/diagnostics.py`; exposed as `PreparedO2A.perturbations` | `zig build python-parameter-perturbation`; writes `out/ci/python_parameter_perturbation.csv` and answers in `out/ci/python_parameter_perturbation_questions.json` |

## Research Question Checkpoints

### Implemented Starter Question

- [x] Which sampled wavelength has the minimum reflectance for the Python-defined DISAMAR O2 A input? Output: final spectrum arrays, `DiagnosticReport`, one-line timing/residual summary, and `out/ci/python_forward_summary_plot.png`. Created in `scripts/testing_harness/python_forward_summary.py`, `scripts/testing_harness/o2a_spectrum_plot.py`, `python/zdisamar/ffi.py`, and `src/api/c.zig`. Test: `zig build python-forward-summary`.
- [x] Can Python directly reproduce the DISAMAR O2 A reference setup? Output: typed setup JSON roundtrip, default-vs-typed array agreement, and diagnostic-report checks. Created in `src/input/o2a_reference/`, `python/zdisamar/types.py`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_o2a_setup_roundtrip.py`. Test: `zig build python-o2a-setup-roundtrip`.

### Aerosol

- [x] Which wavelengths have the largest aerosol share of total optical depth? Output: atmospheric budget table plus ranked wavelength answer. Created in `src/output/atmospheric_budget.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_atmosphere_budget.py`. Test: `zig build python-atmosphere-budget`.
- [x] Which wavelengths have the largest aerosol share of scattering optical depth? Output: atmospheric budget table plus ranked wavelength answer. Created in `src/output/atmospheric_budget.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_atmosphere_budget.py`. Test: `zig build python-atmosphere-budget`.
- [x] Which wavelengths are most sensitive to aerosol optical depth? Output: parameter perturbation reflectance-delta table for aerosol optical depth. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_parameter_perturbation.py`. Test: `zig build python-parameter-perturbation`.
- [ ] Does aerosol sensitivity change more with solar zenith angle or viewing zenith angle? Output needed: input builder plus perturbation output across geometry changes. Checkpoint: pending input builder and perturbation helper.
- [x] Which atmospheric interval contributes most to the aerosol signal? Output: interval-resolved aerosol optical-depth aggregation from the atmospheric budget table. Created in `src/output/atmospheric_budget.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_atmosphere_budget.py`. Test: `zig build python-atmosphere-budget`.
- [ ] How much does aerosol placement inside the O2 A-band absorption region matter? Output needed: input builder plus aerosol placement perturbation output. Checkpoint: pending input builder and perturbation helper.
- [ ] Does pseudo-spherical correction change the aerosol contribution for long slant paths? Output needed: radiative-transfer diagnostics plus aerosol budget. Checkpoint: pending radiative-transfer diagnostic slice.

### O2 Spectroscopy

- [x] Which O2 lines dominate a selected O2 A trough? Output: O2 line contribution table plus top rows ranked by absolute total cross section. Created in `src/output/o2_line_contributions.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_o2_line_diagnostics.py`. Test: `zig build python-o2-line-diagnostics`.
- [x] Which weak lines are included, excluded, or handled through strong-line data? Output: O2 line inclusion/status table with row-kind and status counts. Created in `src/output/o2_line_contributions.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_o2_line_diagnostics.py`. Test: `zig build python-o2-line-diagnostics`.
- [x] Which isotope contributes most in a selected wavelength region? Output: isotope-resolved O2 line contribution table ranked by absolute total cross-section sum. Created in `src/output/o2_line_contributions.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_o2_line_diagnostics.py`. Test: `zig build python-o2-line-diagnostics`.
- [x] How much of the cross section comes from weak lines, strong lines, and line mixing? Output: weak/strong/line-mixing contribution columns and summed shares. Created in `src/output/o2_line_contributions.zig`, `python/zdisamar/ffi.py`, and `scripts/testing_harness/python_o2_line_diagnostics.py`. Test: `zig build python-o2-line-diagnostics`.
- [x] Which wavelengths are most sensitive to the line-mixing factor? Output: parameter perturbation reflectance-delta table for line-mixing factor. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_parameter_perturbation.py`. Test: `zig build python-parameter-perturbation`.
- [ ] Are residuals concentrated in line cores, line wings, or continuum regions? Output needed: O2 line diagnostics plus DISAMAR reference comparison metrics. Checkpoint: pending O2 line diagnostics and comparison helper.

### O2-O2 CIA

- [x] Where does O2-O2 CIA contribute most to total absorption? Output: CIA share of total absorption by wavelength and layer. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_o2_o2_cia_diagnostics.py`. Test: `zig build python-o2-o2-cia-diagnostics`.
- [x] How does the CIA contribution change with temperature? Output: temperature-resolved CIA cross-section summary. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_o2_o2_cia_diagnostics.py`. Test: `zig build python-o2-o2-cia-diagnostics`.
- [x] Which layers dominate CIA optical depth? Output: interval/layer-resolved CIA optical-depth ranking. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_o2_o2_cia_diagnostics.py`. Test: `zig build python-o2-o2-cia-diagnostics`.
- [x] Does CIA change the apparent continuum or specific O2 A-band structures? Output: CIA-enabled/disabled reflectance perturbation table. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_parameter_perturbation.py`. Test: `zig build python-parameter-perturbation`.

### Instrument Response

- [x] Which nominal wavelengths use the broadest high-resolution support? Output: instrument response high-resolution sampling table. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_instrument_response.py`. Test: `zig build python-instrument-response`.
- [x] Which high-resolution wavelengths dominate a nominal wavelength? Output: response weights by nominal wavelength. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_instrument_response.py`. Test: `zig build python-instrument-response`.
- [ ] Does a residual come from line physics or instrument response integration? Output needed: O2 line diagnostics plus instrument response samples. Checkpoint: pending O2 line diagnostics and instrument response slice.
- [x] How does changing FWHM change the apparent O2 A-band depth? Output: instrument-FWHM reflectance perturbation table. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_parameter_perturbation.py`. Test: `zig build python-parameter-perturbation`.
- [ ] Which channels are most sensitive to wavelength shift? Output needed: wavelength-shift perturbation output. Checkpoint: pending perturbation helper.

### Radiative Transfer

- [x] Which layers dominate final radiance for a selected wavelength? Output: bounded radiative-transfer layer table with final radiance/reflectance and scattering proxy ranking. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_radiative_transfer_diagnostics.py`. Test: `zig build python-radiative-transfer-diagnostics`.
- [x] How much of the signal is direct surface reflection versus atmospheric scattering? Output: direct-surface and atmospheric-scattering proxy columns. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_radiative_transfer_diagnostics.py`. Test: `zig build python-radiative-transfer-diagnostics`.
- [x] Which source-function terms matter most? Output: bounded source proxy columns and ranked layer terms. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_radiative_transfer_diagnostics.py`. Test: `zig build python-radiative-transfer-diagnostics`.
- [x] Does multiple scattering materially change reflectance in a selected band? Output: multiple-vs-single scattering reflectance perturbation table. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_parameter_perturbation.py`. Test: `zig build python-parameter-perturbation`.
- [x] How much does pseudo-spherical correction change the path through each layer? Output: pseudo-spherical airmass/path proxy column. Created in `python/zdisamar/diagnostics.py` and `scripts/testing_harness/python_radiative_transfer_diagnostics.py`. Test: `zig build python-radiative-transfer-diagnostics`.

### DISAMAR Reference Comparison

- [ ] At a wavelength where this implementation differs from DISAMAR reference evidence, which scientific stage first diverges? Output needed: staged diagnostic tables plus comparison metrics. Checkpoint: pending comparison helper.
- [ ] Is a difference caused by line absorption, line mixing, CIA, aerosol placement, instrument response, solar irradiance, or radiative transfer? Output needed: staged diagnostic tables covering those terms. Checkpoint: pending staged diagnostics.
- [ ] Which intermediate diagnostic table should be compared against DISAMAR for a focused validation check? Output needed: versioned diagnostic table schemas and comparison metadata. Checkpoint: pending table-schema registry.

## Runtime Expectations

A full forward model run should remain one coarse native call. Additional
diagnostic calls should reuse `PreparedInput`.

Expected cost pattern:

- final spectrum: full forward-model cost
- atmospheric absorption and scattering budget: moderate, scales with
  wavelengths and layers
- O2 line contribution table: potentially high, scales with wavelengths,
  thermodynamic states, and relevant line count
- instrument response table: low to moderate
- radiative-transfer diagnostics: high, should be filtered and row-limited
- parameter sensitivity: usually one extra forward-model run per perturbation
  unless an analytical derivative is available

The Python API should make expensive diagnostics explicit and should avoid
scalar per-wavelength calls across the native boundary.

## Native Boundary

The existing low-level C interface is the native boundary for the coarse
spectrum path. A future research interface should extend that approach with
versioned table schemas instead of exposing Zig structs directly.

The native side should return column-oriented tables:

- table id
- schema version
- row count
- column names
- units
- data type
- array pointer
- ownership/free function

Python should convert those tables to:

- NumPy arrays for numerical work
- Pandas data frames for diagnostic tables
- xarray datasets for dimensioned wavelength/layer data

## Implementation Direction

After the spectrum/report foundation, the first larger research slice should be
an atmospheric absorption and scattering budget, because it answers real
research questions without rerunning full radiative transfer.

Suggested staged checklist:

- [x] Expose final spectrum and current diagnostic report cleanly.
- [x] Expose a typed Python DISAMAR O2 A setup that uses the same native reference route as validation.
- [x] Expose atmospheric layer and absorption/scattering budget tables.
- [x] Expose O2 line contribution tables.
- [x] Expose O2-O2 CIA diagnostics.
- [x] Expose instrument response and high-resolution wavelength sampling tables.
- [x] Expose selected radiative-transfer diagnostics.
- [x] Expose parameter perturbation helpers.

The implemented foundation exposes DISAMAR O2 A reference setup controls, final
spectrum arrays, a `DiagnosticReport` for the same native result, atmospheric
budget tables, O2 line contribution tables, O2-O2 CIA tables, instrument
response tables, bounded radiative-transfer diagnostics, and parameter
perturbation outputs. The report is reached through `Spectrum.diagnostic_report`,
so reading it does not run the forward model again. The forward-summary harness
defines the O2 A case directly in Python, writes a parity plot under `out/ci/`,
and emits one compact CLI line with timing and residual diagnostics. The
setup-roundtrip harness checks that the typed Python setup matches the default
parity entrypoint. The diagnostic harnesses write machine-readable tables plus
JSON answers to their checkpointed science questions:

```bash
zig build python-forward-summary
zig build python-o2a-setup-roundtrip
zig build python-atmosphere-budget
zig build python-o2-line-diagnostics
zig build python-o2-o2-cia-diagnostics
zig build python-instrument-response
zig build python-radiative-transfer-diagnostics
zig build python-parameter-perturbation
```

Implementation should stay consistent with the current source-tree rules:

- file loading and parsing stay outside forward-model routines;
- scientific routines stay free of hidden global state;
- no parsed control is silently ignored;
- every public diagnostic table gets a documented schema;
- expensive diagnostics are opt-in and bounded.
