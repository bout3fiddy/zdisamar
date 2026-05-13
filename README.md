# zdisamar

`zdisamar` is a Zig implementation of the oxygen A-band forward model used in
DISAMAR aerosol-layer-height retrieval studies. It calculates
top-of-atmosphere reflectance and reflectance derivatives for scenes in which
oxygen absorption, aerosol scattering, surface reflection, and instrument
spectral response all affect the measured spectrum.

The Fortran DISAMAR code family is the scientific reference for this work.
`zdisamar` keeps the same radiative-transfer problem and reorganizes the
repeated oxygen A-band calculations so validation cases can be run, timed, and
inspected through generated spectra and timing files.

The Python wrapper is demonstrated in executable notebooks under
[`scripts/demo/`](./scripts/demo/). Build the native library first:

```bash
zig build
```

Then open the notebooks:

```bash
uv run --with jupyterlab --with ipykernel python -m jupyter lab scripts/demo
```

The two demos are
[`o2a_plot_bundle.ipynb`](./scripts/demo/o2a_plot_bundle.ipynb), which shows the
Python-facing O2 A output and plotting accessors, and
[`optimal_estimation_demo.ipynb`](./scripts/demo/optimal_estimation_demo.ipynb),
which shows a two-state O2 A optimal-estimation flow.

## Why The Oxygen A Band

The oxygen A band near 758-770 nm is a strong molecular oxygen absorption band
used by passive satellite retrievals to infer information about the vertical
placement of scattering layers. Oxygen is well mixed in the atmosphere, so the
absorption structure in a measured top-of-atmosphere spectrum carries
information about photon path length. Photons scattered by a lower aerosol or
cloud layer travel through more oxygen than photons scattered by a higher layer.

This makes the band useful for aerosol-layer-height and cloud-height retrievals.
The oxygen absorption signal is also sensitive to surface brightness, geometry,
aerosol optical thickness, and the balance between atmospheric and surface
contributions to the measured reflectance. Aerosols scatter less strongly than
clouds, so aerosol retrievals need a detailed forward model.

![Aerosol scene and oxygen A-band reflectance](./docs/assets/o2a-aerosol-spectrum-context.png)

The figure links a visible aerosol scene to the O2 A reflectance spectrum seen
by the instrument: the aerosol contribution changes both the absolute
reflectance and the structure inside the absorption band. Aerosol optical
thickness, aerosol vertical distribution, and surface reflection all affect the
oxygen A-band retrieval.

That spectral change can be used to retrieve atmospheric properties. Light that
travels deeper into the atmosphere passes through more oxygen and therefore has
deeper absorption-band structure. If photons meet an aerosol or cloud layer
higher in the atmosphere, they scatter back toward the instrument earlier and
travel through less oxygen. The absorption profile then carries information
about where the scattering happened. A forward model makes this usable: for a
given atmosphere, surface, viewing geometry, and instrument response, it
calculates the reflectance spectrum and the derivatives needed by the retrieval
to update the atmospheric state.

## What Changed Relative To Fortran DISAMAR

The comparisons use the Fortran DISAMAR code family. Source links in the
performance notes point to the KNMI GitLab snapshot
[`d17c52884a875cb87b98e4c4ea7f722659e685ac`](https://gitlab.com/KNMI-OSS/disamar/disamar/-/tree/d17c52884a875cb87b98e4c4ea7f722659e685ac).

Fortran DISAMAR is the grandfather of this implementation. It is a mature
radiative-transfer and retrieval model for passive atmospheric remote sensing:
it reads a retrieval configuration, prepares atmospheric and surface inputs,
calculates spectra and Jacobians, and runs inverse methods such as optimal
estimation. Its strength is breadth. It supports many retrieval families,
spectral ranges, configuration options, and operational/research use cases. That
breadth also makes focused O2 A benchmarking difficult: a single aerosol-height
case still passes through general setup, broad configuration handling, and
general numerical routines built for a much wider set of retrieval problems.

Both implementations target the same O2 A retrieval forward model: line-by-line
oxygen absorption, multiple scattering, instrument-grid convolution, and
reflectance derivatives for optimal estimation. The performance improvements
come from reducing repeated setup around that calculation:

- scene, spectroscopy, geometry, and reference data are prepared once and reused
  across repeated forward-model calls;
- optimal-estimation retrievals call the forward model several times while the
  scene, instrument grid, spectroscopy, and many optical inputs stay the same.
  Each iteration reuses that O2 A calculation state in memory;
- retrieval Jacobians are calculated for the active state-vector columns;
- common O2 A LABOS matrix shapes for the 20-stream case use specialized
  implementations in the repeated layer-doubling calculations;
- validation and benchmark evidence is stored under
  [`validation/outputs/`](./validation/outputs/).

The benchmark cases use `nstreamsSim = 20` and `nstreamsRetr = 20`. Streams are
the angular quadrature directions used by the multiple-scattering
radiative-transfer solver; more streams resolve the angular radiation field more
finely, but each forward-model call costs more. The production DISAMAR O2 A
setup usually uses 16 streams, so these retained 20-stream timings are
deliberately slower than a production-tuned Fortran run.

The DISAMAR baseline configuration also keeps `aerosolLayerHeight = 0`. We do
not use the Fortran `aerosolLayerHeight = 1` flag to speed the comparison up,
because that flag activates an older shortcut path. The timings below therefore
compare `zdisamar` against the normal physical inverse problem, not against a
shortcut-accelerated DISAMAR run.

## Benchmarks

The benchmark evidence covers forward-model timing and
optimal-estimation retrieval timing.

### Forward Model

The forward-model benchmark calculates one O2 A spectrum over 755-776 nm. The
reported spectrum has 701 instrument-grid wavelengths, but each instrument
channel is an average over sharper oxygen absorption structure at higher
spectral resolution:

```text
low-overhead prepare_o2a       0.057692 s
low-overhead forward elapsed   1.328534 s
ztracy forward elapsed         2.443697 s
output wavelengths                  701
high-resolution radiance samples  3,874
LABOS Fourier terms             120,390
LABOS layer visits            5,417,550
doubling steps                8,389,666
```

The low-overhead evidence is
[`research/performance/tracing/output/lauka-forward/forward-run/summary.json`](./research/performance/tracing/output/lauka-forward/forward-run/summary.json).
The timeline trace summary is
[`research/performance/tracing/output/labos-bottleneck/summary.json`](./research/performance/tracing/output/labos-bottleneck/summary.json).
The detailed performance notes live in
[`research/performance/o2a-forward/`](./research/performance/o2a-forward/).

### Retrieval

The paired optimal-estimation sweep compares DISAMAR Fortran and `zdisamar`
using the same scene and a-priori sampling. Each system retrieves its own
synthetic spectrum, which keeps the retrieval problem aligned while measuring
the two systems separately.

```text
DISAMAR Fortran: 100/100 converged, median 1228.826 s, mean 1189.862 s
zdisamar:        100/100 converged, median    3.624 s, mean    3.667 s
```

![Paired optimal-estimation retrieval comparison](./validation/outputs/optimal_estimation/paired_oe_retrieved_scatter.png)

The lower row shows the paired retrieved-state difference for each scene,
computed as `zdisamar` retrieved value minus DISAMAR Fortran retrieved value:

```text
aerosol optical depth:       median +1.688e-08, mean -3.025e-07, range -3.703e-05 to +5.423e-06
aerosol mid pressure [hPa]:  median -0.0016,    mean -0.0020,    range -0.0522 to +0.0821
```

The tracked summary is
[`validation/outputs/optimal_estimation/paired_oe_plot_manifest.json`](./validation/outputs/optimal_estimation/paired_oe_plot_manifest.json).
The retrieval notes live in
[`research/performance/o2a-retrieval/`](./research/performance/o2a-retrieval/).

## Bottlenecks

The oxygen A band contains narrow absorption lines. To model an instrument
measurement, `zdisamar` calculates radiance at high-resolution wavelengths and
then applies the instrument spectral response to form the 701 reported
wavelengths.

The benchmark expands one spectrum as follows:

```text
701 output wavelengths
-> 3,874 high-resolution radiance samples
-> 120,390 LABOS Fourier terms
-> millions of layer, doubling, and scattering-order operations
```

The main remaining costs are the repeated LABOS radiative-transfer calculations:
Fourier transport, RT-layer construction, layer doubling, scattering-order
accumulation, and phase-matrix construction. The detailed timing and operation
counts are in
[`research/performance/o2a-forward/remaining-bottlenecks.md`](./research/performance/o2a-forward/remaining-bottlenecks.md).

## Production Status And Next Work

The stable implementation today is the O2 A forward model: typed inputs, bundled
reference data, the Zig library and CLI helpers, Python wrapper demos, spectra
validation, and benchmark artifacts.

The optimal-estimation retrieval code currently supports the aerosol-only
two-state retrieval case used by the benchmark evidence. The stable API remains
centered on the forward model.

The next work is to reduce the cost of repeated reflectance and derivative
calculations during retrievals, while preserving the full O2 A result, and to
decide which retrieval functions should become part of the stable API.

[Nanda et al. (2019)](https://doi.org/10.5194/amt-12-6619-2019) describes an
operational neural-network approach that uses a trained replacement for repeated
online radiative-transfer calculations. `zdisamar` keeps the online full-physics
calculation explicit, measurable, and available for validation and further
optimization.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `src/input/` | atmosphere, geometry, surface, spectroscopy, instrument, and reference-data inputs |
| `src/forward_model/` | optical properties, radiative transfer, instrument-grid calculation, and implementations |
| `src/output/` | diagnostic reports and spectrum serialization |
| `src/common/` | shared units, errors, interpolation, quadrature, and linear algebra |
| `data/` | tracked O2 A bundles and reference assets |
| `tests/` | O2 A executable checks |
| `validation/` | O2 A compatibility, benchmark, and reference evidence |
| `research/performance/` | performance provenance, current benchmark notes, and bottleneck analysis |
| `scripts/demo/` | executable Python-facing demo notebooks |
| `docs/` | DISAMAR context, O2 A runtime, and reference-data boundary |

## Build And Verification

Prerequisites:

- Zig `0.15.2` or newer. The repo declares `minimum_zig_version = "0.15.2"` in
  [`build.zig.zon`](./build.zig.zon).
- [`uv`](https://docs.astral.sh/uv/) for Python-based helpers.

Build the library and CLI:

```bash
zig build
```

This produces the CLI helpers at `./zig-out/bin/zdisamar` and
`./zig-out/bin/zdisamar-o2a-plot-spectrum`.

Run the fast local verification loop:

```bash
zig build check
```

Run the broader fast presubmit:

```bash
zig build test-fast
```

Run the full verification baseline:

```bash
zig build test
```

Regenerate the tracked O2 A comparison bundle after changing the O2 A
forward-model or Jacobian validation outputs. These Python validation scripts
load the native library from `./zig-out/lib/`, so run `zig build` first on a
clean checkout:

```bash
uv run validation/spectra/validate_spectra.py
```

For temporary Zig caches, use the ephemeral wrapper:

```bash
./scripts/zig-build-ephemeral.sh check
./scripts/zig-build-ephemeral.sh test-fast --summary all
```

To reclaim space from prior runs:

```bash
./scripts/clean-zig-caches.sh
```

## Recommended Reading

- [`docs/disamar-overview.md`](./docs/disamar-overview.md)
- [`docs/o2a-forward.md`](./docs/o2a-forward.md)
- [`docs/reference-data-and-bundles.md`](./docs/reference-data-and-bundles.md)
- [`research/performance/README.md`](./research/performance/README.md)
- [`validation/README.md`](./validation/README.md)
