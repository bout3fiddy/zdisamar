# O2 A RTM

The Python package keeps wavelength-band scenes separate from radiative-transfer
execution:

```python
from zdisamar import rtm
from zdisamar.wavelength_bands import o2a

scene = o2a.reference_scene()
spectrum = rtm.spectrum(scene, jacobian=True)
```

Repeated inverse-method evaluations can reuse RTM storage explicitly:

```python
from zdisamar import rtm

with rtm.SessionCache(scene) as cache:
    spectrum = rtm.spectrum(scene, cache=cache, jacobian=True)
```

The public Python runtime surface is:

- `zdisamar.wavelength_bands.o2a` for O2 A scene data classes and reference-scene
  construction,
- `zdisamar.rtm` for radiance, reflectance, atmospheric-budget, instrument
  response, and collision-induced-absorption execution helpers,
- `zdisamar.inverse_method.optimal_estimation` for inverse-method data classes
  and the Rodgers-style optimal-estimation implementation.

The Python package loads the Zig-built binding and reference data from packaged
resources. Runtime callers do not pass shared-library paths and do not depend on
the source tree layout.
