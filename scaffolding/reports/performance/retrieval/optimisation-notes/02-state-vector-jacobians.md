# 02. Keep Jacobians State-Vector Sized

Current aerosol-only state vector:

```text
aerosol optical depth
aerosol layer mid pressure
```

In short: request only the Jacobian columns required by the active state vector.

Source links:

- DISAMAR
  - No direct Fortran source link is needed for this zdisamar API rule. The point is that the Python retrieval state vector controls which zdisamar derivative columns are requested.
- zdisamar
  - `python/zdisamar/inverse_method/optimal_estimation/o2a.py`: passes the actual state-vector Jacobian names into the RTM call.
  - `python/zdisamar/bindings/handles.py`: maps requested names to backend state IDs.
  - [C ABI state mask](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/src/api/c.zig#L459-L488): turns requested state IDs into a derivative-state mask.
  - [LABOS derivative checks](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/src/forward_model/radiative_transfer/labos/execute.zig#L207-L216): computes derivative paths only for states included in the mask.

The optimal-estimation matrix dimension is the state-vector dimension. If
surface albedo is not in the retrieval state, the RTM should not return or carry
a surface-albedo Jacobian column for that retrieval.

```python
# Broad route: always calculate every supported derivative.
all_names = ["aod", "mid_pressure", "surface_albedo"]
y, jacobian = evaluate_rtm(jacobian=True, jacobian_state_names=all_names)
k = jacobian[:, [0, 1]]  # retrieval only uses two columns

# State-vector route: request exactly the active state.
state_names = state_vector.jacobian_names
y, k = evaluate_rtm(jacobian=True, jacobian_state_names=state_names)
assert k.shape[1] == len(state_vector)
```

Some internal storage can still be fixed shape, but the retrieval-facing result
must be state-vector sized. Future surface-albedo retrievals should add surface
albedo to the `StateVector`, then request that column explicitly.
