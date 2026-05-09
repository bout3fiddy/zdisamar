# Session Reuse

The retrieval loop evaluates the forward model many times for the same scene.
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

The Python path passes a session into the inverse model:

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

The inverse-model adapter calls `session.prepare(...)` for each state-vector
point. That keeps the context and reusable session storage alive while the
state-dependent aerosol values change.

The session is not magic. It does not make a retrieval cheaper than one
forward+jacobian call. It removes cold scene setup and lets repeated iterations
reuse scene-invariant storage.

Current slow-case benchmark:

```text
non-session retrieval elapsed time       5.354143 s
session reused retrieval elapsed time    4.098390 s
same retrieved state             true
```
