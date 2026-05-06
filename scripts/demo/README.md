# Demo Notebooks

This directory contains executable, explanatory notebooks for Python-facing O2 A
research workflows. They are demos, not CI harnesses and not tracked validation
evidence. Plots are displayed inline in the notebook. Disposable
machine-readable tables or summaries may go under `out/demo/` when a notebook
intentionally writes them.

Open the notebooks from the repository root with:

```bash
uvx --from jupyterlab jupyter lab scripts/demo
```

Build the native shared library first when a notebook calls the Python wrapper:

```bash
zig build
```

## Notebooks

- `forward_summary.ipynb`: runs the Python-defined DISAMAR O2 A case, compares
  the spectrum against the committed DISAMAR reference CSV, and displays an
  inline reflectance/radiance/irradiance comparison plot.
- `atmosphere_budget.ipynb`: inspects atmospheric layer and optical-property
  budgets to answer aerosol optical-depth and scattering-share questions.
- `o2_line_diagnostics.ipynb`: ranks O2 line, isotope, weak-line, strong-line,
  and line-mixing contributions at selected O2 A wavelengths.
- `collision_induced_absorption_diagnostics.ipynb`: examines O2-O2 CIA optical
  depth, absorption share, interval totals, and temperature-resolved cross
  sections.
- `instrument_response.ipynb`: inspects nominal-wavelength support, response
  weights, and effective response width.
- `radiative_transfer_diagnostics.ipynb`: inspects bounded layer/source proxies
  and pseudo-spherical path stretch for selected wavelengths.
- `parameter_perturbation.ipynb`: compares reflectance deltas for aerosol,
  line-mixing, CIA, instrument-FWHM, and scattering-mode perturbations.
- `o2a_plot_bundle.ipynb`: generates core-backed plotting-package charts and
  displays them inline.
- `optimal_estimation_demo.ipynb`: demonstrates a two-state O2 A
  optimal-estimation flow using surface albedo and aerosol optical depth.
