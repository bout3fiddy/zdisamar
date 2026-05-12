# Performance Research

This folder tracks durable performance findings for zdisamar. The notes are
organized by question and by measurement provenance, so current retained
artifacts are not mixed with historical checkpoint numbers.

## Documents

- [O2 A forward performance](o2a-forward/): current forward elapsed time, historical optimization path, detailed optimisation notes, remaining LABOS bottlenecks, and rejected ideas.
- [O2 A retrieval performance](o2a-retrieval/): session reuse, state-vector Jacobians, paired DISAMAR/zdisamar validation, optimisation notes, and current retrieval elapsed time.
- [Performance cases](cases/): case provenance for original reference measurements, current baseline config, slow OE case, and paired sweep scenes.
- [O2 A calculation demo](o2a-calculation-demo.ipynb): Jupyter notebook that isolates the measured O2 A counts and the small LABOS matrix calculations behind the elapsed time.

## Run the notebook

From the repo root:

```sh
uvx --from jupyterlab jupyter lab research/performance/o2a-calculation-demo.ipynb
```

`uvx` runs JupyterLab in a temporary tool environment, so contributors do not need to install Jupyter into the repo environment first.

## Current finding

The forward run is dominated by the high-resolution radiance calculations needed
before the 701 output wavelengths can be produced. The current low-overhead
forward harness reports `prepare_o2a=0.057692 s` and
`forward elapsed time=1.328534 s`. The ztracy timeline run reports
`forward elapsed time=2.443697 s` because instrumentation is enabled.

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

That product is the current per-spectrum elapsed time.

## Artifacts

Performance trace outputs live under `research/performance/tracing/output/`.
Generated local scratch data lives under `out/` and is intentionally gitignored.

Current forward trace artifacts:

```text
research/performance/tracing/output/labos-bottleneck/summary.json
```

Current retrieval artifacts:

```text
validation/outputs/optimal_estimation/paired_oe_plot_manifest.json
validation/outputs/optimal_estimation/paired_oe_retrieved_scatter.png
validation/outputs/optimal_estimation/paired_oe_error_histograms.png
validation/outputs/optimal_estimation/paired_oe_latency.png
validation/outputs/optimal_estimation/zdisamar_o2a_slow_forward_jacobian_benchmark.json
```

Local generated retrieval data:

```text
out/validation/optimal_estimation/paired_disamar_zdisamar/
```

Do not cite `out/` as retained evidence unless the corresponding tracked
manifest, plot, or summary is also named.
