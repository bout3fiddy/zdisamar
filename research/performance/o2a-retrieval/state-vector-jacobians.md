# State-Vector Jacobians

The aerosol-only retrieval state vector has two dimensions:

```text
aerosol optical depth
aerosol layer mid pressure
```

The forward model should therefore return a two-column reflectance Jacobian for
this retrieval. If surface albedo is not in the state vector, the retrieval path
must not request the surface-albedo Jacobian column.

The relevant Python call is:

```python
prepared.forward_model(jacobian=True, jacobian_state_names=state_names)
```

`state_names` comes from the actual `StateVector`. The C ABI maps those names to
requested state IDs, runs the Jacobian calculation with a derivative-state mask,
and compacts the returned Jacobian to the requested columns.

Some Zig layers still use fixed internal Jacobian storage, but the
retrieval-facing result is state-vector sized. This keeps the Python optimal
estimation matrices aligned with the retrieval state and avoids carrying unused
surface-albedo columns through aerosol-only retrievals.

Future surface-albedo retrievals should add surface albedo to the state vector
and then request the corresponding Jacobian column explicitly.
