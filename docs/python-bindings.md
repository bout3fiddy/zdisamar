# Python Bindings

Python research bindings are being added incrementally. The interface should
continue to follow [`python-research-wrapper.md`](./python-research-wrapper.md)
and use DISAMAR-facing language.

The existing low-level C interface in `src/api/c.zig` is the native boundary.
The native library owns contexts and spectrum arrays until the matching free or
destroy call.

Build the shared library:

```bash
zig build
```

Use the wrapper from the repo:

```python
import zdisamar as zd

case = zd.o2a_disamar_reference_input()
case.spectral_grid.sample_count = 701
case.geometry.solar_zenith_deg = 60.0
case.aerosol.optical_depth_550_nm = 0.3
case.radiative_transfer.n_streams = 20

with zd.prepare(case) as prepared:
    with prepared.forward_model() as spectrum:
        report = spectrum.diagnostic_report
        print(spectrum.wavelength_nm)
        print(spectrum.reflectance)
        print(report.mean_reflectance)

    wavelengths = [755.0, 760.76, 776.0]
    with prepared.atmosphere.budget(wavelengths_nm=wavelengths) as budget:
        table = budget.table
        print(table["interval_index_1based"])
        print(table["aerosol_optical_depth"])

    with prepared.o2_lines.contributions(wavelengths_nm=[760.76], max_rows=100_000) as lines:
        table = lines.table
        print(table["center_wavelength_nm"])
        print(table["total_sigma_cm2_per_molecule"])
        print(lines.truncated)

    cia = prepared.o2_o2_cia.diagnostics(wavelengths_nm=wavelengths)
    print(cia.table["cia_share_of_total_absorption"])

    response = prepared.instrument_response.sampling_table(wavelengths_nm=[760.76])
    print(response.table["support_wavelength_nm"])
    print(response.table["weight"])

    rt = prepared.radiative_transfer.diagnostics(wavelengths_nm=[760.76])
    print(rt.table["atmospheric_scattering_source_proxy"])

    delta = prepared.perturbations.spectrum_delta(
        "aerosol.optical_depth_550_nm",
        case.aerosol.optical_depth_550_nm * 1.1,
    )
    print(delta.summary.max_abs_delta_reflectance)
```

`zd.prepare_default_o2a()` remains available and prepares the same DISAMAR O2 A
reference setup as `zd.prepare(zd.o2a_disamar_reference_input())`.

The Python API exposes full-array operations. It does not provide scalar
per-wavelength calls because the native boundary is meant to stay coarse.

## Plotting

The plotting surface lives under `zdisamar.plot` and uses Altair as the core
chart engine. Plotting dependencies are regular project dependencies rather than
an optional extra, so generated plots can be produced from the same `uv run ...`
environment as the other Python helpers.

Demo notebooks display plots inline in JupyterLab. The O2 A plotting bundle
notebook keeps the tracked validation bundle untouched and does not write PNG
artifacts.

Run the Python setup contract check:

```bash
zig build python-o2a-setup-roundtrip
```

Open the explanatory demo notebooks from the repository root:

```bash
uvx --from jupyterlab jupyter lab scripts/demo
```

See [`scripts/demo/README.md`](../scripts/demo/README.md) for the notebook inventory.
