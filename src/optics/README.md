# `optics/` — per-wavelength optical properties

This is the third stage of the forward pass, and the first one that runs per
wavelength. Setup built tables that are fixed for a scene. Optics evaluates them
at one wavelength and turns them into the per-layer optical depths `rtm/`
reads: gas absorption, gas (Rayleigh) scattering, the O2-O2 continuum, and
aerosol. The forward model loops the dense radiance grid and calls this stage at
every sample.

```
                one wavelength sample
                          |
                          v
              +-----------------------+
              |   fillSupportOptics   |   <- rayleigh.zig + cia_absorption.zig
              +-----------+-----------+      supply per-wavelength cross sections
                          |
                          v
                 support optics rows
               (fine, quadrature nodes)
                          |
                          v
              +-----------------------+
              |   reduceLayerOptics   |
              +-----------+-----------+
                          |
                          v
                  layer optics rows
                 (coarse, RTM layers)
                          |
                          v
      source_levels + curved_sun_path  -->  rtm/ radiative transfer
```

## The core (`layer_depths.zig`)

This module turns the setup tables into optical depths. It runs in two steps that
match setup's two resolutions.

`fillSupportOpticsAtWavelength` evaluates each support row (the fine quadrature
node). At every node it adds up four contributions per unit path: gas absorption
from the O2 lines, gas scattering from Rayleigh, the O2-O2 continuum, and aerosol,
then multiplies by the node path length to get optical depths. The result is one
`SupportOptics` row per node, carrying the components, the total, and the single
scatter albedo.

`reduceLayerOpticsFromSupportRows` then sums the active support rows inside each
layer into one `LayerOptics` row per RTM layer. That coarse row is what `rtm/`
reads.

The O2 line cross-sections come in as an argument, already worked out in
`cache/profile_line_memory.zig`, so the slow line-by-line summation happens once
upstream and this loop just reads the result. Both `SupportOptics` and
`LayerOptics` also carry Jacobian vectors, and `fillLayerAerosolJacobians` fills
the aerosol derivative lanes the retrieval needs.

## Cross sections (`rayleigh.zig`, `cia_absorption.zig`)

These compute the cross sections the core needs at each wavelength.

`rayleigh.zig` computes dry-air Rayleigh scattering from a wavelength: the King
depolarization factor, the refractive index fit, and the resulting cross-section
and second phase coefficient. The values depend only on wavelength.

`cia_absorption.zig` handles the O2-O2 collision-induced continuum. It
interpolates the BIRA coefficient table to the wavelength, then evaluates the
cross-section from a temperature polynomial at each layer's temperature.

## Transport inputs (`source_levels.zig`, `curved_sun_path.zig`)

Both read the filled optics rows and build inputs `rtm/` needs before it
integrates the column.

`source_levels.zig` builds the source-integration levels for the integrated
source transport route: the altitude quadrature levels, their weights, and the
aerosol and Rayleigh phase weights used when the scattering source is integrated
through the column.

`curved_sun_path.zig` expands each layer's support rows into pseudo-spherical
direct-beam attenuation samples. It maps the already-computed support optical
depths onto the curved solar-path grid; the path geometry factors themselves are
applied later in `rtm/` attenuation.

## Performance

Optics runs at every high-resolution wavelength, so the goal here is to keep that
loop cheap.

- It never sets aside new memory. Every function writes into arrays it is handed,
  reused from `cache/`. Over thousands of wavelengths, nothing new is set aside.
- Anything that depends only on the wavelength is worked out once, before the loop
  over layers. For each wavelength the Rayleigh cross-section, the CIA
  coefficients, and the aerosol scaling are computed a single time, and then the
  layer loop just multiplies and adds.
- The slow O2 line sum is done once further upstream and passed in, so it never
  repeats inside this loop.
- The fill loop is told that its output and its inputs sit in separate memory,
  which lets it run faster.
- Its scratch space is small and fixed in size, so setting it up costs nothing.
  The O2-O2 density profile in particular is built once and reused for every
  wavelength.
- The curved sun-path step reuses the optical depths already computed and just
  copies them onto its own grid, instead of working them out again.

## Where to start

- `layer_depths.zig` — the core; read `fillSupportOpticsAtWavelength` and
  `reduceLayerOpticsFromSupportRows` first.
- `rayleigh.zig` and `cia_absorption.zig` — the cross-section physics it calls.
- the parent `src/README.md` for how these optical depths feed `rtm/` and how the
  reused line sigma reaches this stage.
