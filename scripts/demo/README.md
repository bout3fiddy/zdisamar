# Demo Notebooks

This directory contains executable, explanatory notebooks for Python-facing
tooling. They are demos, not CI harnesses and not tracked validation evidence.
The notebooks should explain the wrapper flow, display plots inline, and keep
demo state inside the notebook instead of depending on repository-local paths.

Open the notebooks from the repository root with:

```bash
uv run --with jupyterlab --with ipykernel python -m jupyter lab scripts/demo
```

Build the native shared library first when a notebook calls the Python wrapper:

```bash
zig build
```

## Notebooks

- `o2a_plot_bundle.ipynb`: demonstrates the supported `.plot` accessor surface
  on `Spectrum`, atmospheric budget, O2-O2 CIA diagnostics, and the instrument
  response table. Each chart has its own notebook cell, including SNR and the
  sun-normalized radiance noise envelope from the retained baseline
  measurement-noise model.
- `optimal_estimation_demo.ipynb`: demonstrates a two-state
  optimal-estimation flow using aerosol optical depth and aerosol layer
  mid-pressure, with convergence, measurement-fit, residual, and Jacobian plots in
  separate cells. The notebook also points to the scene-owned fastmode switch and
  the main fastmode control knobs for trying the fastmode OE lane and its sparse
  wavelength defaults.
