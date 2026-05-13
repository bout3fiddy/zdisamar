# 01. Reuse The O2 A RTM Session Cache

Historical slow-case evidence from the session-reuse optimization:

```text
non-session retrieval elapsed time  5.354143 s
session reused elapsed time         4.098390 s
same retrieved state                true
```

In short: reuse one O2 A RTM session cache across retrieval iterations for the
same scene.

Current retained slow-case evidence after later Jacobian and lazy-final-state
work:

```text
session reused elapsed time         3.142969 s
RTM+jacobian time                    3.142008 s
lazy final evaluation on demand      1.311871 s
```

Source links:

- DISAMAR
  - No direct Fortran analogue is used here. The optimisation is zdisamar's in-process session reuse around repeated state-vector evaluations.
- zdisamar
  - `python/zdisamar/inverse_method/optimal_estimation/o2a.py`: routes every retrieval state through either a fresh RTM evaluation or the reusable session cache.
  - `python/zdisamar/rtm/session_cache.py`: keeps reusable RTM storage alive and reloads only the changed case state.
  - [Paired sweep use](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/validation/optimal_estimation/paired_disamar_zdisamar_sweep.py#L200-L224): uses the session path in the current validation lane.

The retrieval loop evaluates nearby state-vector points for the same scene. For
the aerosol-only case, geometry, instrument grid, surface settings, fixed
aerosol parameters, and most atmosphere structure stay constant inside the
retrieval. Aerosol optical depth and layer mid pressure change.

```python
# Non-session shape: each state point creates a fresh RTM handle.
for state in retrieval_states:
    case = write_state(template_case, state)
    y, k = evaluate_rtm_and_jacobian(case)
    update_solver(y, k)

# Session shape: keep the scene context and storage alive.
with rtm.SessionCache(template_case) as cache:
    for state in retrieval_states:
        case = write_state(template_case, state)
        cache.load(case)
        y, k = evaluate_rtm_and_jacobian(cache)
        update_solver(y, k)
```

The session cache does not remove the RTM+jacobian call. It removes avoidable cold
scene setup and lets repeated iterations use the same session storage.
