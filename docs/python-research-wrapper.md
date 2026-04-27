# Python Research Wrapper Ideas

This note records ideas for a future Python interface to the O2 A-band
forward calculation. It is intentionally not an implementation plan for the
current code. Before building this, the repository should first align its
public names and documentation more closely with DISAMAR terminology.

## Goal

The Python interface should let a researcher run an O2 A-band simulation and
inspect the scientific calculation in stages. It should be useful both for a
simple forward run and for detailed investigation of why a spectrum has a
particular shape.

The interface should expose data in bulk, not one scalar at a time. Python
should ask for tables or arrays such as a spectrum, atmospheric layers,
absorption contributions, instrument response samples, or radiative-transfer
trace outputs. The expensive calculations should remain in Zig.

## Preferred User Language

Use DISAMAR-facing scientific names in the Python API and docs. Avoid exposing
project-internal terms when a clearer DISAMAR-style term exists.

Prefer:

- `forward_model`
- `atmosphere`
- `atmospheric_layers`
- `absorbers`
- `o2_lines`
- `o2_o2_cia`
- `aerosol`
- `surface`
- `geometry`
- `instrument_response`
- `high_resolution_wavelengths`
- `radiative_transfer`
- `source_function`
- `spherical_correction`
- `reflectance`
- `radiance`
- `irradiance`

Avoid making users learn internal terms such as `kernel`, `transport`, or
`sample_plan` unless they are explicitly documented as implementation details.

## Example Python Shape

```python
import zdisamar as zd

case = zd.o2a_case(
    wavelength_range_nm=(755.0, 776.0),
    sample_count=701,
    geometry={
        "solar_zenith_deg": 60.0,
        "viewing_zenith_deg": 30.0,
        "relative_azimuth_deg": 120.0,
    },
    aerosol={
        "optical_depth_550_nm": 0.3,
        "single_scatter_albedo": 1.0,
        "asymmetry_factor": 0.7,
        "layer_center_km": 5.4,
        "layer_width_km": 0.4,
    },
)

with zd.prepare(case) as run:
    spectrum = run.forward_model()
    absorption = run.atmosphere.absorption_budget(
        wavelengths_nm=spectrum.wavelength_nm,
    )
    lines = run.o2_lines.contributions(
        wavelengths_nm=[761.75],
        max_rows=50_000,
    )
```

In this example, `forward_model()` performs the full simulated spectrum run.
The later calls inspect prepared scientific state or evaluate selected
diagnostic quantities. They should not rerun the full forward model unless the
user explicitly asks for radiative-transfer tracing or parameter sensitivity.

## Data To Expose

### Case And Inputs

- wavelength range and sample count
- solar/viewing geometry
- surface albedo and surface pressure
- aerosol optical depth, placement, single-scatter albedo, and phase parameters
- atmospheric pressure, temperature, altitude, and density profile
- absorber setup, especially O2 and O2-O2 CIA controls
- line-mixing factor, isotope selection, line threshold, and cutoff settings
- instrument spectral response shape, FWHM, and high-resolution sampling rules
- reference data identifiers and file provenance

### Atmospheric State

- layer and sublayer index
- altitude, pressure, temperature, air number density
- oxygen number density
- path length
- interval identity
- aerosol and cloud fractions when enabled

### Absorption And Scattering Budget

- O2 line absorption optical depth
- O2 line-mixing contribution
- O2-O2 CIA contribution
- gas scattering optical depth
- aerosol optical depth
- aerosol scattering optical depth
- cloud optical depth if enabled
- total absorption optical depth
- total scattering optical depth
- total optical depth
- single-scatter albedo
- selected phase-function coefficients

### O2 Line Details

- line center
- isotope number
- line strength
- pressure shift
- lower-state energy
- air-broadened half width
- weak-line contribution
- strong-line contribution
- line-mixing contribution
- whether a weak line was included or excluded
- matched strong-line sidecar, when present

### O2-O2 CIA Details

- CIA cross section by wavelength and temperature
- CIA optical depth by layer or sublayer
- share of total absorption due to CIA
- wavelengths where CIA contribution is largest

### Instrument Response

- nominal wavelength
- high-resolution wavelengths used for that nominal sample
- response weights
- radiance and irradiance response samples
- integrated radiance and irradiance before final reflectance
- whether adaptive high-resolution sampling was used

### Radiative-Transfer Trace

This should be explicit and opt-in because it can be large.

- selected wavelength
- selected high-resolution sample wavelength
- layer optical properties passed to radiative transfer
- source-function terms
- multiple-scattering order or Fourier contribution where available
- attenuation terms
- spherical-correction path samples
- final contribution to radiance and reflectance

## Research Questions The Wrapper Should Help Answer

### Aerosol Questions

- Which wavelengths have the largest aerosol share of total optical depth?
- Which wavelengths have the largest aerosol share of scattering optical depth?
- Which wavelengths are most sensitive to aerosol optical depth?
- Does aerosol sensitivity change more with solar zenith angle or viewing zenith angle?
- Which atmospheric interval contributes most to the aerosol signal?
- How much does aerosol layer placement inside the O2 A-band absorption region matter?
- Does spherical correction change the aerosol contribution for long slant paths?

Example:

```python
with zd.prepare(case) as run:
    spectrum = run.forward_model()
    budget = run.atmosphere.absorption_budget(spectrum.wavelength_nm)

    budget["aerosol_fraction"] = (
        budget.aerosol_optical_depth / budget.total_optical_depth
    )
    strongest = budget.groupby("wavelength_nm").aerosol_fraction.sum().idxmax()
```

For observed reflectance impact, use a parameter perturbation:

```python
with zd.prepare(case) as run:
    sensitivity = run.sensitivity(
        parameter="aerosol.optical_depth_550_nm",
        delta=0.01,
    )
    strongest = sensitivity.reflectance_delta.abs().idxmax()
```

### O2 Spectroscopy Questions

- Which O2 lines dominate a reflectance trough?
- Which weak lines are included, excluded, or replaced by strong-line handling?
- Which isotope contributes most in a selected wavelength region?
- How much of the cross section comes from weak lines, strong lines, and line mixing?
- Which wavelengths are most sensitive to the line-mixing factor?
- Are residuals concentrated in line cores, line wings, or continuum regions?

### O2-O2 CIA Questions

- Where does O2-O2 CIA contribute most to total absorption?
- How does the CIA contribution change with temperature?
- Which layers dominate CIA optical depth?
- Does CIA change the apparent continuum or specific O2 A-band structures?

### Instrument Questions

- Which nominal channels use the broadest high-resolution wavelength support?
- Which response samples dominate a nominal channel?
- Does a spectral residual come from line physics or from instrument response integration?
- How does changing FWHM change the apparent O2 A-band depth?
- Which channels are most sensitive to wavelength shift?

### Radiative-Transfer Questions

- Which layers dominate the final radiance for a selected wavelength?
- How much of the signal is direct surface reflection versus atmospheric scattering?
- Which source-function terms matter most?
- Does multiple scattering materially change the reflectance in a selected band?
- How much does spherical correction change the path through each layer?

### Parity And Debugging Questions

- At a wavelength where DISAMAR and this implementation differ, which scientific stage first diverges?
- Is a difference caused by line absorption, line mixing, CIA, aerosol placement, instrument response, solar irradiance, or radiative transfer?
- Which intermediate table should be compared against DISAMAR for a focused parity check?

## Runtime Expectations

A full forward model run should remain a single coarse native call. Additional
diagnostic calls should reuse the prepared state.

Expected cost pattern:

- final spectrum: full forward-model cost
- atmospheric budget: moderate, scales with wavelengths and layers
- O2 line contribution trace: potentially high, scales with wavelengths,
  thermodynamic states, and relevant line count
- instrument response table: low to moderate
- radiative-transfer trace: high, should be filtered and row-limited
- parameter sensitivity: usually one extra forward run per perturbation unless
  an analytical derivative is available

The API should make expensive tracing explicit:

```python
trace = run.radiative_transfer.trace(
    wavelengths_nm=[761.75],
    include=["source_function", "spherical_correction"],
    max_rows=100_000,
)
```

## Implementation Direction

The first useful slice should be an atmospheric absorption/scattering budget,
because it answers real research questions without rerunning full radiative
transfer.

Suggested staged order:

1. expose final spectrum and current profile output cleanly;
2. expose atmospheric layer and absorption/scattering budget tables;
3. expose O2 line contribution tables;
4. expose instrument response samples;
5. expose selected radiative-transfer traces;
6. expose parameter perturbation helpers.

Each stage should return versioned table schemas so Python can convert them to
NumPy, Pandas, or xarray without knowing Zig's internal struct layout.
