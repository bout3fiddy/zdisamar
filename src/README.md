# `src/` — forward model and retrieval

`zdisamar` fits a measured spectrum of the oxygen A band (about 755-775 nm) for
two aerosol properties: the aerosol optical thickness, how much aerosol is in the
air, and the height of the aerosol layer, given as its mid-layer pressure. Oxygen
is evenly mixed through the atmosphere at a known concentration, so its absorption
near 760 nm measures how far light travelled before it reached the instrument.
Aerosol shortens that path by scattering light back out at its own altitude, so
the depth and shape of the band in a measured spectrum pin down how much aerosol
there is and how high it sits.

The model has two halves. The forward pass takes a described scene and computes
the top-of-atmosphere reflectance spectrum it would produce. The retrieval runs
that forward pass over and over, adjusting the aerosol state until the computed
spectrum matches a measured one. This directory holds both.

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

- A caller-provided or parsed JSON scene gives a `Scene`: atmosphere, geometry,
  surface, spectroscopy, instrument, aerosol.
- `prepare` builds the physics tables that stay fixed across runs of the same
  scene.
- `warmSessionMemory` sets up the memory a run reuses.
- `runForwardWithSessionMemory` runs one spectrum and returns the arrays:
  radiance, reflectance, irradiance, and the Jacobian. `runForward` does the same
  with throwaway memory, for a one-off run.

## The forward pass

One forward pass is six stages, numbered the way each subdirectory README refers
to itself. Data flows one way through them:

1. [`input/`](input/README.md) reads and validates the scene into a `Scene`.
2. [`setup/`](setup/README.md) builds the physics tables fixed for that scene:
   absorption lines, CIA, aerosol, solar, phase, layers.
3. [`optics/`](optics/README.md) turns those tables into per-layer optical depths
   at one wavelength: Rayleigh, gas absorption, the O2-O2 continuum, aerosol.
4. [`rtm/`](rtm/README.md) does the radiative transfer for one wavelength and
   returns its reflectance and aerosol Jacobian.
5. [`spectrum/`](spectrum/README.md) picks the wavelengths to evaluate, loops
   `optics/` and `rtm/` over them, and averages the result through the instrument
   slit.
6. [`output/`](output) writes the spectrum and the diagnostics.

`input/` and `setup/` run once per scene. Then `spectrum/` drives the rest: it
loops the dense wavelength grid, calls `optics/` and `rtm/` at each wavelength,
and gathers the per-wavelength results into the band.

```
+----------+      +----------+
|  input/  |  ->  |  setup/  |   once per scene: validate the Scene
+----------+      +----------+   and build the fixed physics tables
                       |
                       v
+------------------------------------------------------+
|  spectrum/   loop the dense wavelength grid          |
|                                                      |
|     optics/  ->  per-layer optical depths            |
|     rtm/     ->  reflectance + aerosol Jacobian      |
|                                                      |
+--------------------------+---------------------------+
                           |
                           v
gather onto the product grid  ->  slit average  ->  output/
```

`rtm/` works one wavelength at a time and has no notion of the band; `spectrum/`
is the loop that turns those single wavelengths into a spectrum.

## The retrieval loop

A retrieval inverts a measured spectrum. It is the Rodgers optimal-estimation
loop in [`retrieval/`](retrieval), driven from `runOptimalEstimation` in
`root.zig`. Each iteration runs one forward pass, compares the computed
reflectance to the measurement, and updates the aerosol state from that mismatch
and the Jacobian, then feeds the new state back in.

```
measurement  +  prior aerosol state
   |
   v
repeat until converged:
   |
   |   forward pass    ->  reflectance + Jacobian
   |   compare to the measurement
   |   Rodgers update  ->  new aerosol state
   |   write the state into the Scene, re-validate
   |
   v
retrieved aerosol optical depth + layer pressure,
with posterior uncertainty
```

The state vector is fixed at two elements, the aerosol optical depth and the
aerosol layer's mid-pressure, set in `rtm/jacobian_states.zig` and shared by
every stage. Each iteration writes the updated state back into the `Scene` and
re-runs the same validation as the first, so a retrieval step can never run an
invalid scene.

## Reused memory across iterations

Between iterations only the aerosol state changes. Everything that does not depend
on it, the wavelength grid, the gas spectroscopy, the solar spectrum, is built
once and passed back in, so each iteration stays cheap. `SessionMemory`
([`cache/session_memory.zig`](cache/session_memory.zig)) holds these:

- [`SpectrumSamplingTable`](cache/spectrum_memory.zig) — the high-resolution
  wavelengths to evaluate, dense around strong O2 lines and sparse elsewhere, with
  the offsets and weights that average them down to each product wavelength.
- [`RadianceWavelengthList`](cache/radiance_memory.zig) — the dense grid `rtm/`
  loops over, the radiance at each entry, and the Jacobian column.
- [`ProfileLineValues`](cache/profile_line_memory.zig) — the O2 absorption summed
  from every line at each wavelength, the most expensive part of setup and the
  largest table.
- [`SolarIrradianceMemory`](cache/solar_irradiance_memory.zig) — the incoming
  solar flux at each wavelength, needed to turn radiance into reflectance.
- [`TransportWorkArrays`](cache/transport_worker_memory.zig) — per-worker scratch
  for the radiative transfer: layer matrices, scattering orders, Fourier terms,
  sized once per thread.

Each table is rebuilt only when the inputs it depends on change; `prepareSessionRows`
in `root.zig` hashes those inputs per table and reuses the table on a match.
[`cache/`](cache/README.md) covers where each buffer lives and when it is touched.

Because the tables are reused, the per-wavelength stages allocate nothing. A
function in `optics/`, `rtm/`, `spectrum/`, or `retrieval/` takes the arrays it
reads and the one it writes as arguments, so its inputs and outputs are visible in
its signature.

## Supporting directories

- [`common/`](common) — shared helpers: errors, hashing, math, units, memory,
  worker partition.
- [`assets/`](assets) — readers for the packaged reference data: HITRAN O2 line
  lists, O2-O2 CIA tables, solar spectra, atmosphere profiles.
- [`api/`](api) — the C entry points the Python package calls.
- [`validation/`](validation) — band metrics.
- [`instrumentation/`](instrumentation) — tracing and telemetry hooks, off by
  default.

## Where to start

- `root.zig` — the public functions, in call order.
- `rtm/solve.zig` — the radiative transfer, the core of the model.
- `setup/run_tables.zig` — how a scene turns into physics tables.
- `runOptimalEstimation` in `root.zig` — the retrieval loop.

Tests reach internal symbols through `internal.zig`.
