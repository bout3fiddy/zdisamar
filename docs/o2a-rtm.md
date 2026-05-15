# O2 A RTM

The Python package keeps wavelength-band cases separate from radiative-transfer
execution:

```python
from zdisamar import rtm
from zdisamar.wavelength_bands import o2a

case = o2a.reference_case()
spectrum = rtm.spectrum(case, jacobian=True)
```

Repeated inverse-method evaluations can reuse RTM storage explicitly:

```python
from zdisamar import rtm

with rtm.SessionCache(case) as cache:
    spectrum = rtm.spectrum(case, cache=cache, jacobian=True)
```

The public Python runtime surface is:

- `zdisamar.wavelength_bands.o2a` for O2 A case data classes and reference-case
  construction,
- `zdisamar.rtm` for radiance, reflectance, atmospheric-budget, instrument
  response, and collision-induced-absorption execution helpers,
- `zdisamar.inverse_method.optimal_estimation` for inverse-method data classes
  and the Rodgers-style optimal-estimation implementation.

The Python package loads the Rust-built binding and reference data from packaged
resources. Runtime callers do not pass shared-library paths and do not depend on
the source tree layout.
