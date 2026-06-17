# `input/` — scene definition and validation

This is the first stage of the forward pass. Everything downstream — `setup/`,
`optics/`, `rtm/` — reads one typed value, `Scene`, and trusts that it is already
valid. This directory defines that type, parses the Python-native JSON boundary,
and checks the scene before setup or compute sees it.

```
+----------------+         +----------------------+
| Python    |  JSON   |    parseSceneJson    |
| factory/scene  +-------->| buildScene+normalize |
+----------------+         +----------+-----------+
                                      |
                                      v
                              +---------------+
                              | sceneControls |
                              +-------+-------+
                                      |
                                      v
                                      Scene  -------->  setup/
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

- A `Scene` borrows all its strings and slices from storage someone else holds,
  such as a JSON parser arena. It is valid only as long as that storage lives.
- The asset paths are already resolved. `input/` never opens files; it receives
  `Asset` descriptors, and `src/assets/` later opens and parses them.

## Where a `Scene` comes from

A `Scene` enters the model through caller-provided typed data or through
`parseSceneJson`; both end at the same validator. The packaged DISAMAR-family
reference scene lives in
`python/zdisamar/input/wavelength_band/o2a_default.py` as
`default_o2a_scene()`. Python assembles the dataclass scene, resolves
reference-data paths before preparation, and passes the native JSON shape over
`zds_prepare_o2a_json`. Zig receives the packaged reference scene as an ordinary
caller-provided scene; there is no built-in Zig default scene or zero-JSON
default preparation path.

`json.zig` is the C and Python boundary. `parseSceneJson` takes the JSON that
Python's `Scene.to_native_json_bytes()` emits and produces a typed `Scene`. A
few things to know here:

- The JSON shape (`NativeSceneJson`) carries Python bookkeeping and some fields
  that have no effect on this forward-only route. `buildScene` maps the
  fields the model uses across to `Scene`, and rejects unsupported route changes
  (a different scattering mode, a Jacobian request, finite altitude bounds)
  instead of accepting them silently.
- A small number of route-owned controls are constants in `json.zig`: the
  supported stream count and route Fourier term limit. Scene-specific science
  controls still come from Python input.
- `ParsedSceneJson` owns the parser arena; the `Scene` it returns borrows from
  it. Call `deinit` only after the model has finished reading the scene.
- Python's native JSON encoder maps optional placeholder `NaN` values to `null`.
  The parser still rewrites bare `NaN` to `null` as a boundary guard before
  parsing (`normalizePythonJson`).

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

## Performance

This stage is cheap, and stays that way by avoiding extra copies and extra memory.

- The scene points straight at the text the JSON parser already holds, so its
  strings and lists are reused in place instead of copied again. That memory is
  freed once, when the parsed result is done with.
- The JSON cleanup only makes a fresh copy when it has to. It looks for a stray
  `NaN` first; if there is none it uses the original text untouched, and even when
  it does scan, it keeps the original unless it actually changed something.
- Validation is only simple number checks (is this finite, is it in range), so it
  is cheap to run again on every retrieval step.

## Where to start

- `scene.zig` — read this first; it is the type every other stage consumes.
- `json.zig` — the Python boundary and what the model refuses to run.
- `validate.zig` — the invariants a scene must satisfy, in one place.
