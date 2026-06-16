# `src/` — forward model and retrieval

`zdisamar` computes the top-of-atmosphere reflectance spectrum across the oxygen
A band (about 755–775 nm) and fits it for aerosol parameters, specifically the
aerosol optical thickness and the aerosol layer height. This directory holds the
whole model.

Each subdirectory has its own README with the physics and the data flow for that
stage. This file shows how the stages fit together.

## Running the model

The public functions are in [`root.zig`](root.zig) and run in this order:

```
Scene  ->  prepare  ->  warmSessionMemory  ->  runForwardWithSessionMemory
              |                 |                          |
              v                 v                          v
          Prepared          SessionMemory            SpectrumRunResult
```

- A caller-provided or parsed JSON scene gives a `Scene` — atmosphere, geometry,
  surface, spectroscopy, instrument, aerosol.
- `prepare` builds the physics tables that stay fixed across runs of the same
  scene.
- `warmSessionMemory` sets up the memory a run reuses.
- `runForwardWithSessionMemory` runs one spectrum and returns the arrays: radiance,
  reflectance, irradiance, and the Jacobian. `runForward` does the same with
  throwaway memory, for a single run.

A retrieval runs this forward pass many times — see below.

## The forward pass

Inside one forward pass, data flows one way:

```
+-------+      +-------+      +--------+      +-----+      +----------+      +--------+
| input |  ->  | setup |  ->  | optics |  ->  | rtm |  ->  | spectrum |  ->  | output |
+-------+      +-------+      +--------+      +-----+      +----------+      +--------+
```

- `input/` — read and check the scene into a `Scene`.
- `setup/` — build the physics tables: absorption lines, CIA, aerosol, solar, phase, layers.
- `optics/` — optical properties at each wavelength sample: Rayleigh, CIA, curved
  sun path, source levels.
- `rtm/` — the radiative transfer for each wavelength sample, with Jacobians.
- `spectrum/` — combine samples into radiance, average through the instrument slit.
- `output/` — diagnostics and the written-out spectrum.

`input/` and `setup/` run once. Then `spectrum/` loops the wavelengths, calling
`optics/` and `rtm/` for each one, and averages the per-wavelength results into the
spectrum:

```
input  ->  setup        (once per scene)
   |
   v
spectrum/
   |
   |   for each wavelength:
   |       optics/  ->  layer optical depths
   |       rtm/     ->  reflectance at that wavelength
   |
   v
gather  ->  slit average  ->  product spectrum
   |
   v
output
```

`rtm/` works one wavelength at a time and has no notion of the band; `spectrum/` is
the loop that turns those single wavelengths into a spectrum.

A retrieval wraps the whole pass and repeats it. The rest of the directories support 
the flow:

- `cache/` — the reused memory (see below).
- `common/` — shared helpers: errors, hashing, math, units, memory, workers.
- `assets/` — readers for the packaged reference data: HITRAN O2 line lists,
  O2–O2 CIA tables, solar spectra, and atmosphere profiles.
- `api/` — the C entry points the Python package calls.
- `validation/` — band metrics.
- `instrumentation/` — tracing and telemetry hooks, off by default.

## Reused memory

A retrieval runs the forward model many times, and between runs only the aerosol
state changes. Everything that does not depend on that state — the wavelength
grid, the gas spectroscopy, the solar spectrum — is built once and passed back
in, so each iteration stays cheap. `SessionMemory`
(`cache/session_memory.zig`) holds these:

- `SpectrumSamplingTable` (`cache/spectrum_memory.zig`) — the high-resolution
  wavelengths the model evaluates, placed densely around strong O2 lines and
  sparsely elsewhere. It depends on the spectral grid, instrument, and line
  positions, none of which change during a retrieval, so it is built once.
- `RadianceWavelengthList` (`cache/radiance_memory.zig`) — the dense grid the
  radiative transfer loops over, derived from the sampling table. `rtm/`
  computes a radiance at each entry before the spectrum step gathers them onto
  the output grid.
- `ProfileLineValues` (`cache/profile_line_memory.zig`) — the O2 absorption from
  summing every line at each wavelength, the most expensive part of setup.
  Aerosol changes do not touch the gas spectroscopy, so this is reused across
  iterations as long as the wavelengths match, which is what makes retrieval fast.
- `SolarIrradianceMemory` (`cache/solar_irradiance_memory.zig`) — the incoming
  solar flux at each wavelength, needed to turn radiance into reflectance. It
  depends only on the grid, so it is looked up once and kept.
- `TransportWorkArrays` (`cache/transport_worker_memory.zig`) — scratch space for
  the radiative transfer: layer matrices, scattering orders, and Fourier terms.
  These are large and overwritten on every sample, so they are sized once per
  worker thread and reused instead of reallocated each sample.

A function in `optics/`, `rtm/`, `spectrum/`, or `retrieval/` takes the arrays it
reads and the one it writes as arguments, so its inputs and outputs are visible
in its signature.

## Where to start

- `root.zig` — the public functions, in call order.
- `rtm/solve.zig` — the radiative transfer, the core of the model.
- `setup/run_tables.zig` — how a scene turns into physics tables.
- `runOptimalEstimation` in `root.zig` — the retrieval loop.

Tests reach internal symbols through `internal.zig`.
