# Performance Research

This folder tracks durable performance findings for zdisamar. The current scope is one O2 A forward spectrum. Retrieval-loop reuse and `prepare_o2a` are separate topics.

## Documents

- [O2 A per-spectrum wall](o2a-per-spectrum-wall.md): measured wall, code path, and timing decomposition.
- [Why zdisamar is faster than DISAMAR](why-zdisamar-is-faster/): plain explanation of why the current O2 A run is faster, split by mechanism with code excerpts and source links.
- [LABOS matrix calculations](labos-matrix-calculations.md): why the LABOS math remains expensive even after each small calculation is fast.
- [Where is the bottleneck?](where-is-the-bottleneck/): layered trace evidence from spectrum wall to LABOS primitives, retained with generated artifacts.
- [O2 A calculation demo](o2a-calculation-demo.ipynb): Jupyter notebook that isolates the measured O2 A counts and the small LABOS matrix calculations behind the wall.

## Run the notebook

From the repo root:

```sh
uvx --from jupyterlab jupyter lab research/performance/o2a-calculation-demo.ipynb
```

`uvx` runs JupyterLab in a temporary tool environment, so contributors do not need to install Jupyter into the repo environment first.

## Current finding

The forward run is dominated by the high-resolution radiance calculations needed before the 701 output wavelengths can be produced. The current O2 A summary is in the expected band: `prepare_o2a` is about 200 ms, and the forward model is about 1.9-2.0 s.

The important count is not 701. Each output wavelength represents an instrument-weighted measurement, so the model first calculates radiance at 3,874 high-resolution wavelengths and then averages those values back to the 701 output wavelengths.

The concise model is:

```text
one spectrum
  = choose high-resolution wavelengths for the instrument response
  + calculate radiance at those 3,874 wavelengths
  + average the radiance and irradiance back to 701 output wavelengths
```

The expensive product is:

```text
3,874 high-resolution wavelengths
* about 31 Fourier terms per wavelength
* active atmospheric layers
* repeated layer-doubling and scattering-order calculations
```

That product is the current per-spectrum wall.
