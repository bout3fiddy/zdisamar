# `output/` — results in the structures the caller reads

This is where computed results become the stable structures the Python package
reads across the C boundary. The radiative-transfer math is done upstream in
`optics/`, `spectrum/`, and `rtm/`; `output/` shapes those results and owns the
memory they sit in.

One forward run returns a product spectrum, the arrays `runForward` hands back.
Separately, one builder produces the atmospheric-budget diagnostic table on
demand by re-deriving part of a prepared scene at wavelengths the caller chooses
and laying it out as fixed rows. The diagnostic never runs during a forward pass;
it explains a scene after the fact.

```
the forward run
   |
   v
spectrum.zig  ->  the product arrays and an assembly summary
   |
   v
SpectrumRunResult  ->  C ABI  ->  Python


a prepared scene, at chosen wavelengths
   |
   v
atmospheric_budget   ->  per-support-row optical depths and state
   |
   v
fixed extern-struct rows  ->  C ABI  ->  Python
```

## The forward result (`spectrum.zig`)

`Spectrum` is the output of one forward run: five arrays of equal length, one
entry per product wavelength. They are the wavelength, the radiance, the
irradiance, the reflectance, and the Jacobian, a two-element vector per sample.
`SpectrumRunResult` pairs that with `SpectrumRunSummary`, a few scalars from the
reflectance assembly. The file holds no physics. `root.zig` allocates these
arrays, `spectrum/` fills them, and `Spectrum.deinit` frees them. The C layer
keeps the result alive behind a handle and hands Python borrowed pointers into
it.

The Jacobian here is the derivative of reflectance, `dR/dx`, in the two retrieval
lanes (aerosol optical depth, then aerosol layer mid-pressure in hPa). The
retrieval reads it directly. The C boundary rescales it to a radiance derivative
for the Python spectrum view, since reflectance is `pi * radiance / (mu0 * E0)`.

## The diagnostic table

The atmospheric-budget builder takes a prepared scene and a list of diagnostic
wavelengths, re-derives one slice of the model at those wavelengths, and returns
a flat table of `extern struct` rows whose byte layout is fixed and mirrored
field-for-field by the Python `ctypes` struct. Rows are wavelength-major: the
outer loop is the wavelength, then the support row. The table owns one heap
allocation, freed by its `deinit` or the matching C free hook.

These inspection paths re-derive from the setup tables rather than the warm
session caches, so calling one does not share the forward run's cached
spectroscopy, and they are meant to be called on demand rather than inside a loop.

### Atmospheric budget (`atmospheric_budget.zig`)

For each chosen wavelength and each support row of the column, one row carries the
full optical-depth breakdown and the local atmospheric state: gas absorption, gas
(Rayleigh) scattering, the O2-O2 continuum, aerosol scattering and absorption, the
totals and the single-scatter albedo, alongside altitude, pressure, temperature,
air and O2 number densities, and path length. It first builds a temporary line
cross-section table for the requested wavelengths, then runs the same support-row
optics build the forward model uses, `optics/`'s `fillSupportOpticsAtWavelength`,
and reshapes each `SupportOptics` into a row. The aerosol absorption is the
aerosol total minus its scattering, floored at zero. The absorbing gas is O2, so
the absorber density equals the O2 density.

## Where to start

- `spectrum.zig` — the forward run's output type, the shortest file here.
- `atmospheric_budget.zig` — the per-support-row diagnostic table.
- `src/api/c.zig` — the C export (`zds_atmospheric_budget`) and how the table is
  freed.
- the parent `src/README.md` for how a forward run produces the spectrum these
  types carry.
