# `spectrum/` — from fine-grid radiance to the instrument spectrum

This is the fifth stage of the forward pass, and the one that turns the radiative
transfer into the spectrum an instrument would record. The instrument reports
radiance at a fixed set of product wavelengths, each one an average over a band set
by its slit. The model works at a much finer resolution, because oxygen absorption
swings sharply across the A band and a coarse grid would miss the line shapes.
`spectrum/` picks the fine wavelengths to evaluate, runs the per-wavelength radiance
there through `optics/` and `rtm/`, and averages the result back down through the
slit. `rtm/` computes the radiance one wavelength at a time, and `spectrum/` is the
loop around it that turns those single wavelengths into a band.

Oxygen absorption varies fast near a strong line and slowly between lines, so the
model places its sample points densely around the strong lines and sparsely
elsewhere. It then evaluates far fewer wavelengths than a uniform grid would, and a
slit average over those points still reproduces what the instrument records.

```
   +----------------------+
   |    sampling_table    |   choose the fine wavelengths, dense near O2 lines
   +----------------------+
              |
              v
   +----------------------+
   | radiance_wavelengths |   reduce to the unique wavelengths, run each once
   +----------------------+
              |
              v
   +----------------------+
   |     spectrum_run     |   radiance at each wavelength via optics/ and rtm/, parallel
   +----------------------+
              |
              v
   +----------------------+
   |   radiance_results   |   gather the fine grid onto the product wavelengths
   +----------------------+
              |
              v
   +----------------------+
   |  instrument_average  |   slit average, calibration, reflectance
   +----------------------+
              |
              v
      product spectrum  ->  output/, retrieval/
```

## Choosing where to evaluate (`sampling_table.zig`, `radiance_wavelengths.zig`)

`sampling_table.zig` builds the fine wavelength grid. It starts from the product
wavelengths and the instrument slit width, widens the span to catch the line wings,
and then splits it into intervals cut at the strong O2 line positions. Each interval
carries a set of Gauss-Legendre quadrature points: wide intervals far from any line
get few, narrow intervals near a line center get many. For each product wavelength it
stores the offsets and weights that say which fine samples average into that product
wavelength and how much each one counts. The table depends on the spectral grid, the
instrument, and the line positions, none of which change during a retrieval, so it is
built once and reused.

`radiance_wavelengths.zig` collects the unique fine wavelengths those weights refer
to. Two product wavelengths near each other share many of the same fine samples, and
the model should evaluate each one only once. The wavelength's exact f64 bit pattern
is the key, with no rounding or tolerance, so a sample shared between two product
wavelengths collapses to one entry. The result, `RadianceWavelengthList`, is the list
of wavelengths the per-wavelength loop runs over, plus the index map from each product
wavelength back to its samples in that list.

## Evaluating one wavelength (`spectrum_run.zig`)

`spectrum_run.zig` is the orchestrator, and `radianceAtWavelength` is its core. For
one fine wavelength it reads the cached O2 line cross-section, fills the support and
layer optical depths through `optics/` (gas absorption, Rayleigh, the O2-O2 continuum,
aerosol), builds the source levels and curved sun-path samples when the route asks for
them, then calls `rtm/`'s `solveReflectance` and scales the returned reflectance into a
radiance.

`runForwardSpectrum` runs the whole stage: it fills the dense radiance grid, gathers
it onto the product wavelengths, then hands off to the slit average. The dense grid is
the expensive part, so it is split across worker threads, each writing its own slice
of the output; Performance covers how that stays race-free.

## O2 line spectroscopy (`line_physics.zig`)

`line_physics.zig` is the oxygen A-band line-by-line spectroscopy: given a
temperature, a pressure, and a wavelength, it returns the O2 absorption cross-section
per molecule. `cache/profile_line_memory.zig` sums it over the lines at every fine
wavelength and caches the result; the per-wavelength loop reads that cache rather than
calling this file, and `output/` calls it for per-line diagnostics. That is why it
sits in the folder but not in the dataflow above.

Each oxygen line absorbs in a profile around its center wavelength, and its width
comes from two effects. Thermal motion of the molecules spreads it into a Gaussian
(Doppler broadening); collisions with other molecules spread it into a Lorentzian
(pressure broadening). The true profile is the convolution of the two, the Voigt
profile, evaluated here through a complex-probability-function approximation. On top
of the shape, three things scale a line:

1. Strength with temperature. A line's strength is set by how many molecules sit in
   its lower energy state, which follows the Boltzmann population and the partition
   function, so the reference strength at 296 K is rescaled to the layer temperature.
2. Pressure shift. The center moves slightly with pressure.
3. Cutoff. Past a set distance in wavenumber from the center, a line is dropped.

In the A band the strong lines sit close enough that they do not absorb
independently: a collision can move a molecule between two lines, so their shapes
couple. Summing isolated Voigt profiles would be wrong there. zdisamar instead
uses a line-mixing treatment for the strong lines, built from the LISA relaxation
matrix for up to 128 of them, and sums the remaining weaker lines as independent Voigt
profiles. The cross-section it returns is what `optics/` multiplies by the O2 number
density and the path length to get the gas absorption optical depth of a layer.

## Solar irradiance (`solar_lookup.zig`)

Reflectance is radiance divided by the incoming solar flux, so the model needs the
solar irradiance at each wavelength. `solar_lookup.zig` reads it from the solar spline
table that `setup/` prepared, keyed on the exact wavelength bits through the cached
`SolarIrradianceMemory`, and integrates it with the same offsets and weights as the
radiance so the two share a sampling. A positive floor on the source value
keeps the later division from blowing up.

## Gathering and the instrument slit (`radiance_results.zig`, `instrument_average.zig`)

`radiance_results.zig` holds the dense radiance grid and gathers it. The `rtm/` stage
returns a reflectance, which this module scales into a radiance with
`L = reflectance * mu0 * E0 / pi`, because radiance is the physical quantity the slit
averages. Gathering then applies each product wavelength's offsets and weights exactly
once, summing the fine radiances (and the aerosol Jacobian lanes alongside them) into
one product radiance.

`instrument_average.zig` builds the product rows. When the sampling already folded the
slit into those weights, the product radiance is the convolved value directly;
otherwise it applies the slit weighting here. It then calibrates each channel
(gain, offset, wavelength shift, stray light) and forms reflectance from the
calibrated radiance and the averaged solar irradiance, `rho = pi * L / (mu0 * E0)`,
with a floor on the denominator. The aerosol Jacobian columns ride through the same
convolution and calibration, and because the fitted states perturb the radiance but
not the solar flux or geometry, the reflectance derivative is just the radiance
derivative over the same denominator.

## Performance

The spectrum stage runs the per-wavelength loop that dominates the whole forward
model, so the cost lives in how many wavelengths it evaluates and how much each one
costs. Two properties hold the rest down.

- It allocates no memory. The dense grid, the product rows, and each worker's optics
  scratch are caller-owned, sized once in `cache/` and reused across every wavelength
  and every retrieval iteration.
- The fine grid is concurrent and race-free by construction. Each worker is handed
  its own `TransportWorkerMemory` by index, so no worker touches another's scratch,
  and the output is partitioned into disjoint wavelength ranges (static ranges, or
  disjoint chunks pulled from a shared queue). The only shared mutable state is the
  chunk queue's atomic claim and a first-worker-wins error slot; the per-wavelength
  work touches neither. Shared inputs (the tables, the cached line sigma, the solar
  memory) are read-only while the workers run.

### Where the time goes

Listed from most to least expensive, each with what it costs and the gate that keeps
it down.

1. The dense radiance loop (`radianceAtWavelength`, once per unique fine wavelength)
   is the bulk of forward time. Each call fills the optical depths and runs `rtm/`'s
   `solveReflectance`, whose own cost is the subject of the `rtm/` README. The number
   of calls is set by the sampling table, and the adaptive grid is the gate: by
   sampling densely only where absorption varies fast, it keeps that count far below a
   uniform fine grid.
2. The O2 line summation (`line_physics.zig`, through `cache/profile_line_memory.zig`)
   is the most expensive single build. For every fine wavelength and every profile
   node it sums the contribution of every nearby line, each one a Voigt evaluation,
   and the strong-line line-mixing prep builds a relaxation matrix once per node,
   which grows with the square of the strong-line count. It is done once per scene and
   reused across retrieval iterations, since the gas spectroscopy does not depend on
   the aerosol state. Within the build, work is skipped four ways: a binary-search
   window narrows to the lines near each wavelength, the weak and strong lines are
   split, the wavenumber cutoff drops distant lines, and the temperature- and
   pressure-dependent terms are prepared once per node and reused across all its
   wavelengths.
3. Building the sampling table (`sampling_table.zig`) is a one-time per-scene cost. It
   places the adaptive quadrature points, parallelized across product rows, and is
   cached and rebuilt only when the spectral grid or the instrument changes.
4. The gather and the slit average (`radiance_results.zig`, `instrument_average.zig`)
   are cheap. Each product wavelength is a handful of weighted sums over its samples,
   and the slit convolution is short, so neither is a bottleneck next to the
   per-wavelength loop.

## Where to start

1. `spectrum_run.zig`: `runForwardSpectrum` for the whole stage in order, and
   `radianceAtWavelength` for the per-wavelength work that drives `optics/` and
   `rtm/`.
2. `sampling_table.zig`: how the fine grid is placed around the O2 lines.
3. `line_physics.zig`: the line-by-line O2 spectroscopy, read with
   `cache/profile_line_memory.zig`, which is where it is summed and cached.
4. `instrument_average.zig`: the slit average, calibration, and reflectance.
5. the parent `src/README.md` for how this stage sits between `optics/`, `rtm/`, and
   the retrieval.
