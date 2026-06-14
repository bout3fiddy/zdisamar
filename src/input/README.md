# `input/` — scene definition, defaulting, and validation

This is the first stage of the forward pass. Everything downstream — `setup/`,
`optics/`, `rtm/` — reads one typed value, `Scene`, and trusts that it is already
valid. This directory defines that type, builds it, and checks it.

```
+---------------+         +----------------+
| defaultScene  |         | parseSceneJson |   the two ways a Scene is built
| (built-in)    |         | (Python JSON)  |
+-------+-------+         +--------+-------+
        |                          |
        |  referenceScene()        |  buildScene() + normalize
        v                          v
            +----------------------+
            |   sceneControls()    |   validate
            +----------+-----------+
                       |
                       v
                     Scene  -------->  setup/ and the rest of the forward pass
```

## The `Scene` (`scene.zig`)

`Scene` is the value the whole model reads. It is a flat record of typed controls
grouped by physical concern, each a small sub-struct:

- `SpectralGrid` — the exact output wavelength route (start, end, sample count).
- `AtmosphereControls` and `VerticalInterval` — the pressure-layer profile, the
  surface pressure, and which interval the fit targets.
- `GeometryControls` — solar and viewing angles and the pseudo-spherical flag.
- `AerosolControls` and `AerosolProfileLayer` — optical depth and where the
  aerosol sits, as scalar placement or explicit per-layer rows.
- `ObservationControls` — instrument line shape and the high-resolution support
  grid the spectrum step samples on.
- `LineGasControls` and `CiaControls` — the O2 line list and O2–O2 continuum,
  given as `Asset` descriptors (id, path, format) plus runtime filter thresholds.
- `RtmControls` — stream count, Fourier limit, and the transport performance
  thresholds.

Two things hold for every `Scene`:

- A `Scene` borrows all its strings and slices from storage someone else holds —
  static defaults, or a JSON parser arena. It is valid only as long as that
  storage lives.
- The asset paths are already resolved. `input/` never opens files; it receives
  `Asset` descriptors, and `src/assets/` later opens and parses them.

## Where a `Scene` comes from

A `Scene` enters the model through one of two paths, and both end at the same
validator.

`defaults.zig` holds the built-in reference scene. `referenceScene()` returns the
DISAMAR O2 A reference case: the 755–776 nm grid, the three-layer atmosphere, the
default aerosol layer, and the packaged HITRAN, solar, and CIA assets. It is
exposed publicly as `root.defaultScene`, and it is the scene validation runs use
and the template the Python side renders.

`json.zig` is the C and Python boundary. `parseSceneJson` takes the JSON that
Python's `Scene.to_native_json_bytes()` emits and produces a typed `Scene`;
`renderDefaultSceneJson` goes the other way for the default case. A few things to
know here:

- The JSON shape (`NativeSceneJson`) carries Python bookkeeping and some fields
  that have no effect on this forward-only O2 A route. `buildScene` maps the
  fields the model uses across to `Scene`, and rejects unsupported route changes
  (a different scattering mode, a Jacobian request, finite altitude bounds)
  instead of accepting them silently.
- `ParsedSceneJson` owns the parser arena; the `Scene` it returns borrows from
  it. Call `deinit` only after the model has finished reading the scene.
- Python's JSON encoder writes bare `NaN` for optional placeholders, which Zig's
  scanner rejects, so the parser rewrites bare `NaN` to `null` before parsing
  (`normalizePythonJson`).

## Validation (`validate.zig`)

`sceneControls(scene)` is the gate every scene passes through. It checks physical
and structural bounds: the grid is increasing and finite, albedo is in [0, 1],
the pressure intervals tile without gaps, the aerosol layer sits inside its
declared interval, profile layers agree on spectral scaling, and so on. It
returns two errors:

- `InvalidControl` — a malformed or out-of-range control (a bad number, a wrong
  count).
- `InvalidRequest` — a control that is well formed but physically inconsistent,
  such as an aerosol layer outside the atmosphere it claims to live in.

It runs in two places. Once inside `parseSceneJson` at load time. And again on
every retrieval iteration: the Rodgers loop writes the updated state vector back
into a scene and re-validates it before running the forward model, so a retrieval
step can never reach an invalid scene.

## Where to start

- `scene.zig` — read this first; it is the type every other stage consumes.
- `defaults.zig` — the reference scene, with concrete values for every control.
- `json.zig` — the Python boundary and what the model refuses to run.
- `validate.zig` — the invariants a scene must satisfy, in one place.
