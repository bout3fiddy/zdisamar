# 02. Keep Jacobians State-Vector Sized

The aerosol-only retrieval state vector has two dimensions:

```text
aerosol optical depth
aerosol layer mid pressure
```

The forward model should therefore return a two-column reflectance Jacobian for
this retrieval. If surface albedo is not in the state vector, the surface-albedo
Jacobian column is not requested by the Python optimal-estimation path.

The relevant Python call is:

```python
prepared.forward_model(jacobian=True, jacobian_state_names=state_names)
```

`state_names` comes from the actual `StateVector`. The C ABI path maps those
names to requested state IDs, runs the Jacobian calculation with a derivative
state mask, and compacts the returned Jacobian to the requested columns.

The forward model still has a fixed internal Jacobian representation in some
Zig layers, but the public retrieval-facing result is state-vector sized. That
keeps the Python optimal-estimation matrices aligned with the retrieval state
and avoids carrying unused surface-albedo columns through this aerosol-only
retrieval.
