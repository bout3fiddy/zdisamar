# 01. Reuse The O2 A Forward Session

Current slow-case evidence:

```text
non-session retrieval elapsed time  5.354143 s
session reused elapsed time         4.098390 s
same retrieved state                true
```

In short: reuse one O2 A session across retrieval iterations for the same scene.

Source links:

- DISAMAR
  - No direct Fortran analogue is used here. The optimisation is zdisamar's in-process session reuse around repeated state-vector evaluations.
- zdisamar
  - [Inverse adapter](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/python/zdisamar/inverse_method/optimal_estimation/o2a.py#L32-L75): routes every retrieval state through either a fresh prepare or the reusable session.
  - [Session object](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/python/zdisamar/prepared.py#L210-L260): keeps the O2 A context alive and re-prepares only the changed case state.
  - [Paired sweep use](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/validation/optimal_estimation/paired_disamar_zdisamar_sweep.py#L200-L224): uses the session path in the current validation lane.

The retrieval loop evaluates nearby state-vector points for the same scene. For
the aerosol-only case, geometry, instrument grid, surface settings, fixed
aerosol parameters, and most atmosphere structure stay constant inside the
retrieval. Aerosol optical depth and layer mid pressure change.

```python
# Non-session shape: each state point creates a fresh prepared context.
for state in retrieval_states:
    case = write_state(template_case, state)
    with prepare(case) as prepared:
        y, k = forward_and_jacobian(prepared)
    update_solver(y, k)

# Session shape: keep the scene context and storage alive.
with o2a_forward_session(template_case) as session:
    for state in retrieval_states:
        case = write_state(template_case, state)
        prepared = session.prepare(case)
        y, k = forward_and_jacobian(prepared)
        update_solver(y, k)
```

The session does not remove the forward+jacobian call. It removes avoidable cold
scene setup and lets repeated iterations use the same session storage.
