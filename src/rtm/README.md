# `rtm/` — radiative transfer for one wavelength

This is the fourth stage of the forward pass and the core of the model. For one
wavelength, `optics/` gives it a column of layers, each with an optical depth and a
single-scatter albedo. Alongside the layers it gets the viewing and solar geometry,
the solar source, and the curved sun-path samples. `rtm/` turns all of that into the
one number the spectrum stage wants — the top-of-atmosphere reflectance at this
wavelength — and, when a retrieval asks, the derivatives of that reflectance with
respect to the aerosol state. The forward model calls `solveReflectance` once per
dense wavelength sample.

Sunlight enters the top of the atmosphere along the solar direction, scattered by
air molecules and aerosol and absorbed by oxygen; the scattered light travels on
and scatters again; some of it leaves the top along the viewing direction. The
reflectance is the ratio of that outgoing radiance to the incoming
solar flux. There is no closed form for it once light scatters more than once, so
the stage builds the answer numerically with the LABOS scheme that zdisamar
reproduces from the DISAMAR reference model. Four nested physical ideas turn the
problem into arithmetic:

- Azimuth in Fourier space. The dependence on the sun-to-view azimuth is expanded
  as a cosine series, so the two-dimensional angular problem becomes a set of
  independent one-dimensional problems, one per Fourier term `m`.
- Discrete streams. Each one-dimensional problem is integrated over a fixed set of
  Gauss-Legendre angles (the streams), plus the exact solar and viewing
  directions.
- Layer reflection and transmission. Every layer is reduced to two stream-to-stream
  operators — what it reflects, what it transmits — building thick layers up from
  thin ones by doubling.
- Orders of scattering. The radiation field is accumulated one scattering event at
  a time: the direct beam scatters once, that field scatters again, and so on
  until the contributions die out.

```
        per wavelength: layer optics + geometry + source + curved path
                                  |
                                  v
                    +--------------------------+
                    |     solveReflectance     |  scattering == none ->  direct surface
                    +--------------------------+      albedo * exp(-tau/mu0 - tau/muv)
                                  |  multiple scattering
                                  v
              geometry (gauss_angles)  +  direct beam (attenuation)
                                  |
                                  v
        +----------- loop over retained Fourier terms m -------------+
        |                                                            |
        |   phase_basis      ->  Z+ / Z- stream-coupling matrices    |
        |   layer_reflect_transmit (+ matrix_12x10) ->  R, T rows    |
        |   scattering_orders  ->  up/down fields, order by order    |
        |   reflectance        ->  rho_m  (top or integrated source) |
        |                                                            |
        +-----------------------+------------------------------------+
                                |  weighted Fourier sum, tail stop
                                v
                  reflectance + aerosol Jacobian vector  ->  spectrum/
```

## The radiative transfer and its routes (`solve.zig`, `controls.zig`)

`solveReflectance` is the entry point and the dispatcher. `controls.zig` holds the
validated knobs it reads — stream count, scattering mode, the source-integration
and spherical-correction flags, the convergence and truncation thresholds, and
which Jacobians are wanted — prepared once by `prepareSolveConfig` so the
per-wavelength work never re-validates them.

There are two routes. When scattering is off (`scattering == .none`) the answer is
the direct surface term alone: the solar beam attenuates down the column, reflects
off a Lambertian surface — one that reflects equally in all directions — and
attenuates back up, `albedo * exp(-tau/mu0) * exp(-tau/muv)`, where `mu0` and `muv`
are the cosines of the solar and viewing angles. The other route is `.multiple`,
the layer-resolved radiative transfer in `solveLayerResolvedScattering`, which runs
the Fourier loop above.

Within that route the source can be handled two ways, chosen by
`integrate_source_function`. The top route reads the upward field at the top
level. The integrated-source route instead integrates the scattering source over
the source-level quadrature optics built in `optics/`; it is the default, and it
is the only route that can produce the aerosol-layer-pressure Jacobian. The O2 A
reference case runs multiple scattering with the integrated source on a flat
atmosphere, and because its viewing geometry is nadir, the near-normal gate
collapses the Fourier loop to the single `m = 0` term.

## Directions and the direct beam (`gauss_angles.zig`, `attenuation.zig`)

The radiation field is tracked along a fixed set of directions, the streams from
the list above. `gauss_angles.zig` chooses them for one pair of sun and view
angles: a handful of angles spread over the hemisphere — the points a numerical
integration over direction evaluates at — plus the two directions the measurement
actually cares about, where the sun is and where the instrument looks. For each
direction it keeps a cosine and an integration weight, and for each pair of
directions a factor the scattering step reuses, since one scattering event sends
light from every direction into every other. None of this depends on wavelength,
only on the two angles and how many streams were asked for, so it is built once for
a sun/view pair and reused; when the pair changes, the phase-function rows of the
next section are rebuilt against the new directions.

`attenuation.zig` computes how much of the direct solar beam survives down to each
level: Beer-Lambert extinction along the slanted solar path, `exp(-tau / mu0)`. On
a flat atmosphere the path stretches by the plain `1/mu0`; with the
pseudo-spherical correction it follows the curved sun-path samples from `optics/`,
`tau * r / sqrt(r^2 - r_level^2 sin^2(theta))`, which matters when the sun is low
and the rays bend noticeably through a round atmosphere. The two source routes want
this in different shapes — the integrated-source route keeps a compact
adjacent-layer-plus-top-to-level form, the top route a full level-to-level table —
and a separate tangent fill supplies the beam's derivative for the aerosol
Jacobian.

## The phase function in Fourier space (`phase_basis.zig`)

A scattering event redirects light by an angle whose probability is the phase
function. Here it is the sum of two pieces: Rayleigh scattering by air, which is a
single `l = 2` Legendre term, and aerosol scattering, a Henyey-Greenstein lobe
already expanded by `setup/` into a Legendre series. `phase_basis.zig` decomposes
that mixture into the azimuth Fourier terms the loop runs over.

It works in the associated Legendre polynomials `P_l^m`, built by recurrence for
each Fourier index `m` and each stream and weighted by the stream's integration
weight. From them it forms the stream-coupling matrices `Z+` and `Z-` — the
probability that light in one stream scatters into another, for the forward and
backward halves of the hemisphere. These rows are cached per Fourier term and
reused across layers and across wavelengths of the same geometry.

## Per-layer reflection and transmission (`layer_reflect_transmit.zig`, `matrix_12x10.zig`, `rows.zig`)

For each layer and each Fourier term, `layer_reflect_transmit.zig` builds the two
operators that say what the layer does to radiation: a reflection matrix `R` and a
transmission matrix `T`, stream to stream. For a thin layer these come straight
from one scattering event — the phase kernel scaled by the single-scatter albedo,
with the unscattered direct part removed. A thick layer cannot be treated as a
single scatter, so it is doubled: split into halves thin enough to scatter once,
then combined with the adding equations, which account for light bouncing back and
forth between the halves before it leaves. Whether and how many times to double
comes from the layer's effective scattering depth.

The adding step is matrix arithmetic on fixed-size matrices: `matrix_12x10.zig`
provides the products, the diagonal scalings, and the matrix inverse `(I - R*R)^-1`
that sums the endless reflections back and forth between the two halves. The
matrices are fixed at 12 directions (10 Gauss angles plus the sun and view), so the
compiler sees constant loop bounds and the inner loops unroll, and a cheap check on
each matrix skips a multiply when both factors are too weak to matter.
`rows.zig` defines the shared row types — `LayerRT` (the `R`/`T` pair), the
direction vectors, and the up/down field rows — none of which own heap memory.

Before the Fourier loop, the stage measures for each layer the highest Legendre
term that still carries weight and how much scattering strength its remaining terms
hold, so the loop can skip layer/term pairs that contribute nothing.

## Orders of scattering (`scattering_orders.zig`)

With every layer reduced to `R` and `T`, `scattering_orders.zig` assembles the
radiation field by counting scattering events. The first order is the direct beam
scattering once in each layer — reflected up, transmitted down. Each later order
takes the previous order's up and down fields and scatters them again, `R` and `T`
mixing the directions, and the result is carried between levels through the
direct-beam attenuation. The orders are accumulated into the up/down fields (the
`ud` arrays) until the newest order falls below the convergence threshold or the
order cap is hit; the cap scales with the column's scattering optical depth, since
optically thicker columns need more orders to converge.

Layers with no scattering signal are flagged and skipped, and the 12-stream
propagation is a specialized inlined path. For Jacobians the same recurrence runs in
tangent-linear form — every `R*U` becomes `dR*U + R*dU` — so the derivative field
propagates alongside the base field.

## Reflectance and the Fourier sum (`reflectance.zig`)

`reflectance.zig` turns the converged field into the reflectance coefficient
`rho_m` for the current Fourier term. The top route reads the upward field at the
top level for the solar column and viewing stream. The integrated-source route
sums the scattering source over the source levels from `optics/`, weighting each
by its phase coupling and direction cosines. The terms are then combined into the
azimuth series: term `m` carries weight `1` for `m = 0` and `2 * cos(m * dphi)`
otherwise, and a tail-break gate stops the loop once added terms are negligible.
The public reflectance is clamped to `[0, 2]` (it can exceed 1 under strong
forward scattering).

The same module computes the aerosol Jacobian weightings: the sensitivity of
reflectance to the aerosol optical depth and to the aerosol layer's mid-pressure,
the two states `jacobian_states.zig` defines. Those derivatives are integrated
over the aerosol layer the same way the source is, and accumulated per Fourier
term beside the reflectance.

## Jacobians (`jacobian_states.zig`)

A retrieval needs not just the reflectance but its derivative with respect to the
state it is fitting. `jacobian_states.zig` fixes that state vocabulary for the
whole model — `aerosol_optical_depth` and `aerosol_layer_mid_pressure_hpa` — as a
two-element vector with a mask saying which lanes are active. `optics/` writes
per-layer derivatives in this order, `rtm/` propagates the same vector through one
`solveReflectance` call via the tangent paths above, and `spectrum/` convolves the
active columns with the same instrument weights as the reflectance. The result of
one call is a reflectance plus this fixed-order Jacobian vector.

## Performance

`rtm/` runs at every dense wavelength of every retrieval iteration, so the whole
stage is built to allocate nothing and to reuse everything that does not change.

- It allocates no memory. Every large buffer — the RT layer rows, the
  scattering-order fields, the phase-basis and attenuation tables — is borrowed
  from `TransportWorkArrays`, sized once per worker thread in `cache/` and
  overwritten each wavelength.
- The stream geometry and the Fourier phase basis are cached on the geometry key
  (stream count and the two direction cosines). Across the dense grid the geometry
  rarely changes, so these are built once and reused for thousands of wavelengths.
- Work is skipped wherever the physics is negligible: the near-normal gate drops
  the Fourier loop to one term at nadir, per-layer Legendre limits cut layer/term
  pairs that cannot contribute, non-scattering layers are flagged out of the order
  recurrence, and the Fourier tail-break stops the azimuth sum early.
- The layer matrices are fixed at 12 directions so the inner loops unroll and
  vectorize, and a cheap per-matrix check skips products whose result is below the
  noise floor.
- The scattering-order count is capped from the column's scattering optical depth,
  so optically thin wavelengths converge in few orders.

### Where the time goes

The cost-timing labels in the code name the measured stages: `execute` splits into
`rt_layer_build`, `orders_total`, `attenuation_fill`, `plm_basis`, and
`reflectance_integral`. Three of them dominate, and each carries its own gate that
drops the work when the physics is thin.

Building the per-layer reflection and transmission rows
(`fillLayerReflectTransmitRowsWithBasis`, timed as `rt_layer_build`) is usually the
largest cost, in two parts. The first is the phase matrix
(`rt_layer_phase_matrix`): every entry of the 12-by-12 matrix of stream pairs is a
sum over the Legendre terms of the phase function, so a forward-peaked aerosol that
needs around 150 terms costs around 150 multiply-adds in each of 144 entries, for
every layer and every Fourier term. This is what the per-layer Legendre limits cut:
the sum runs only to the highest term that still carries weight, and a layer/term
pair whose scattering strength is below threshold is skipped before the matrix is
touched. The second part is doubling (`rt_layer_doubling`): a layer thick enough to
scatter many times is split into halves and rebuilt, and each split costs a
10-by-10 matrix inverse — the `(I - R*R)^-1` that sums the reflections between the
halves — plus a few 12-by-12 products. A layer enters this loop only when its
effective scattering depth clears `threshold_doubl`; thin layers keep their
single-scatter rows and pay nothing. Inside a split, a check on the reflection
matrix skips the inverse and the product updates when the reflection is too weak to
change the answer, which is what the `fixed_qseries_skipped` and `fixed_rd_skipped`
counters record.

The scattering-order recurrence (`solveOrdersWithActive`, timed as `orders_total`)
is the second cost. Each order multiplies every layer's `R` and `T` against the
previous order's fields to build new local sources, then sweeps that order up and
down the level grid; the work is roughly the order count times the number of
levels. The order count is capped from the column's scattering optical depth
(`tau_scatter + 15`), so an optically thick wavelength runs more orders than a thin
one — but the loop also stops the moment the newest order's strongest upward value
falls below the convergence threshold (`threshold_conv_first`, then
`threshold_conv_mult`), so most wavelengths finish in far fewer orders than the cap
allows. Layers with no scattering signal are flagged in `rt_active` and skipped in
both the source build and the sweeps.

The direct-beam fill (`attenuation_fill`) is cheap on a flat atmosphere: one
exponential per stream per level. It only grows expensive under the
pseudo-spherical correction, which integrates the curved sun-path samples for each
stream and level. The O2 A reference case runs flat, so this stays in the
background.

Two stages that look expensive usually are not. The Legendre basis (`plm_basis`)
is a recurrence over streams and terms, but it is cached on the geometry and reused
across every wavelength of the same sun/view pair, so it is built a handful of
times over the whole dense grid rather than once per wavelength. And the entire
Fourier loop collapses to its first term (`m = 0`) whenever either direction is
within `1e-5` of normal; the nadir reference case takes this path, so everything
above runs once per wavelength instead of once per Fourier term.

## Where to start

- `solve.zig` — `solveReflectance` and `solveLayerResolvedScattering`; the whole
  stage in call order, and the clearest map of the Fourier loop.
- `controls.zig` — the routes and thresholds that decide which path runs.
- `scattering_orders.zig` and `layer_reflect_transmit.zig` — the two pieces of the
  actual radiative transfer: building layer operators and accumulating orders.
- the parent `src/README.md` for how `optics/` feeds these inputs and how the
  reflectance flows on into `spectrum/` and the retrieval.
