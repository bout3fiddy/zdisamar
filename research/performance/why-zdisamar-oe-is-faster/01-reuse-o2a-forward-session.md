# 01. Reuse the O2 A Forward Session

The retrieval loop evaluates the forward model many times for the same scene.
For aerosol-only retrievals, the geometry, instrument grid, wavelength plan,
surface pressure, surface albedo, aerosol optical properties other than optical
depth, and most atmospheric structure are unchanged across iterations.

zdisamar exposes that shape through `o2a_forward_session`. The paired validation
harness uses:

```python
with zd.o2a_forward_session(case) as session:
    result = o2a_oe.disamar_oe(
        inverse_model=optimal_estimation.O2AInverseForwardModel(
            case,
            forward_session=session,
        ),
        ...
    )
```

Inside the inverse forward-model adapter, the session path calls
`self._forward_session.prepare(...)` for each state-vector point. That keeps the
context and session storage alive while only the state-dependent aerosol values
change.

This is why zdisamar retrieval timing should be interpreted as a retrieval-loop
measurement, not as repeated cold program starts. The first use of a session
still has to warm the scene. Later iterations reuse the session storage that is
valid for the same O2 A case.
