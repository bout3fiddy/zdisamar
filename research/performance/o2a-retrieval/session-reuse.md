# Session Reuse

The retrieval loop evaluates the RTM many times for the same scene.
For aerosol-only retrievals, most scene data do not change inside the loop:

```text
geometry
instrument grid
wavelength plan
surface pressure
surface albedo
fixed aerosol optical properties
most atmospheric structure
```

Only the state vector changes:

```text
aerosol optical depth
aerosol layer mid pressure
```

The Python path passes a session cache into the inverse method:

```python
from zdisamar import rtm
from zdisamar.inverse_method import optimal_estimation

with rtm.SessionCache(case) as cache:
    result = o2a_oe.disamar_oe(
        case=case,
        measurement=measurement,
        state_vector=state_vector,
        controls=optimal_estimation.RetrievalControls(),
        cache=cache,
        ...
    )
```

The inverse method calls `cache.load(...)` for each state-vector point. That
keeps reusable RTM storage alive while the state-dependent aerosol values
change.

The session is not magic. It does not make a retrieval cheaper than one
RTM+jacobian call. It removes cold scene setup and lets repeated iterations
reuse scene-invariant storage.

Historical session-reuse benchmark:

```text
non-session retrieval elapsed time       5.354143 s
session reused retrieval elapsed time    4.098390 s
same retrieved state             true
```

Current slow-case benchmark after later Jacobian and lazy-final-evaluation work:

```text
session reused retrieval elapsed time    3.142969 s
RTM+jacobian time                        3.142008 s
lazy final evaluation when requested     1.311871 s
```
