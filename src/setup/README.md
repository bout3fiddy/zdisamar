# `setup/` — physics tables built from a scene

This is the second stage of the forward pass. To compute a top-of-atmosphere
reflectance `rtm/` needs, for every layer and every wavelength: a
vertical grid to integrate over, gas absorption, scattering with a phase
function, and the solar source. Most of those inputs depend on the scene but not
on the wavelength, and not on the retrieval iteration. `setup/` computes them
once, so the per-wavelength work only does the wavelength-specific arithmetic.
`root.prepare` runs this stage once per scene and the tables are reused across
every forward run.

```
                          Scene (validated)
                                  |
                                  v
                         +----------------+
                         | buildRunTables |
                         +----------------+
                                  |
                                  v   RunTables
+----------------+----------------+----------------+----------------+
| vertical grid  | gas absorption |  scattering    | source + slit  |
+----------------+----------------+----------------+----------------+
|  atmosphere    |  O2 line list  |   aerosol      |   solar        |
|  layer grid    |  O2-O2 CIA     |   phase fn     |   instrument   |
+----------------+----------------+----------------+----------------+
                                  |
                                  v
       optics/ combines these per wavelength, rtm/ does the radiative transfer
```

## Orchestrator (`run_tables.zig`)

`buildRunTables(scene)` is the entry point. It validates the scene once more,
builds each table, and returns them grouped as `RunTables`. The grouping is for
this stage only; downstream optics and transport code receives the narrow slices
it needs, not the whole bundle. `layers`, `quadrature`, `lines`, `cia`, and
`solar` own heap arrays freed by `RunTables.deinit`; `aerosol`, `phase`, and
`instrument` are inline value rows with nothing to free.

## Vertical grid (`atmosphere_layers.zig`)

This is the heaviest part of setup and the discretization the whole model runs
on. It starts from a coarse climatology profile (pressure, temperature, and
altitude at a handful of vendor levels), densifies it with a spline, then divides
the column the way the scene asks: each pressure interval is split into layers,
and each layer carries a set of Gauss-Legendre support nodes used as integration
points.

At every node it computes the thermodynamic state the transport needs: pressure
interpolated in log-pressure against altitude, temperature splined against
altitude, air number density from the ideal gas law (n = P / kT), O2 number
density as air density times the 0.20946 oxygen mixing ratio, and geometric path
lengths from the layer thickness. The result, `LayerGrid`, holds two resolutions:
the coarse output layers, and the finer support grid `rtm/` integrates over.
It also keeps the densified profile, which the line and CIA absorption use later
when they evaluate per-layer gas absorption.

The build is split so retrieval stays cheap. `buildLayerQuadrature` computes the
quadrature roots and weights, which depend only on the division counts, never on
pressure. A retrieval moves pressure bounds but not those counts, so the
quadrature is built once. Each iteration then calls `refillFromPreparedProfiles`,
which recomputes the layer and node thermodynamics in place, with no file read
and no reallocation.

## Gas absorption (`line_tables.zig`, `cia_table.zig`)

These hold the spectroscopy of the O2A band. `line_tables.zig` loads the HITRAN
line parameters together with the LISA line-mixing relaxation matrix and the
strong-line sidecar, and carries the runtime line-filter controls (isotopes,
strength threshold, wavenumber cutoff, mixing factor). It does not compute
absorption here; the per-wavelength cross-section summation over every line is
the expensive step and lives downstream in `cache/profile_line_build.zig`. This
module's job is to load and organize the rows that summation reads.

`cia_table.zig` loads the O2-O2 collision-induced absorption coefficients from
the BIRA table, plus the scale factor applied when the continuum is added per
wavelength.

## Scattering (`aerosol_tables.zig`, `phase_table.zig`)

`aerosol_tables.zig` copies the aerosol optical controls (optical depth, single
scatter albedo, asymmetry factor, Angstrom exponent, placement) into table form;
there is no file and no computation, just a shaped view of the scene controls.

`phase_table.zig` computes the aerosol angular scattering distribution as a
Henyey-Greenstein phase function expanded in Legendre coefficients from the
asymmetry factor (coefficient[l] = (2l + 1) g^l, truncated once the normalized
tail falls below threshold). It is stored as one fixed 151-term row the transport
can read without recomputing the series.

## Source and slit (`solar_table.zig`, `instrument_tables.zig`)

`solar_table.zig` loads the solar irradiance spectrum and prepares spline second
derivatives once, so later lookups of solar flux at a model wavelength are cheap.
This is the incident flux that turns computed radiance into reflectance.

`instrument_tables.zig` copies the instrument line shape (FWHM) and the
high-resolution support-grid controls that the spectrum stage uses to average the
high-resolution radiance down through the slit to the product wavelengths.

## Performance

Setup does the slow, scene-wide work once. Everything that does not change from
one wavelength to the next, or from one retrieval step to the next, is worked out
here and then reused, so the rest of the model stays fast.

- A retrieval keeps moving the aerosol up and down, which shifts the pressure
  boundaries. The vertical sampling pattern does not depend on those pressures,
  only on how many layers were asked for, so it is built once and kept. Each step
  only refreshes the per-layer values, reusing the same storage and reading no
  files.
- The solar spectrum and the aerosol phase function are each prepared once, so the
  per-wavelength code just looks them up instead of recomputing them.
- The big reference tables (layers, lines, CIA, solar) hold real data; the small
  control tables are only a few numbers and cost nothing to carry.
- Each table can quickly check whether its own inputs changed, so the model can
  skip rebuilding anything that stayed the same.

## Where to start

- `run_tables.zig` — the entry point and the full list of tables setup builds.
- `atmosphere_layers.zig` — the vertical discretization, the core of this stage.
- `line_tables.zig` with `cache/profile_line_build.zig` — where the line data is
  loaded and where it is later turned into absorption.
- the parent `src/README.md` for how these tables feed optics, rtm, and the
  reused session memory.
