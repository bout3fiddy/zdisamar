# Fastmode Final Correction

Fastmode is a case-owned optimisation mode, not a separate retrieval API.  A
normal O2 A case remains the full-physics reference case.  Fastmode is enabled
on that same case:

```python
case.optimisation.fastmode.enabled = True
```

The case keeps the optimisation settings visible.  The execution path resolves
those settings before loading the native RTM case, so callers can inspect the
actual knobs and final-correction wavelengths:

```python
case.resolved_optimisation()["fastmode"]
```

The default fastmode configuration changes:

- RTM performance thresholds: Fourier cap, aerosol tangent cap, Fourier-tail
  threshold, and layer-doubling threshold.
- Adaptive reference-grid controls: points per FWHM and strong-line
  subdivisions.
- OE controls: iteration and state-vector convergence settings.
- OE final correction: one full-physics state update after fastmode
  convergence.

## Algorithm

The retained OE path uses one public `disamar_oe` call:

```text
1. The input case has fastmode enabled.
2. The native session loads the same case with fastmode RTM controls resolved.
3. OE runs to convergence on the full measurement vector.
4. If final correction is enabled, zdisamar disables fastmode on a case copy.
5. The correction keeps explicit sparse wavelengths on the measurement grid.
6. The same session handle loads that sparse full-physics correction case.
7. Native OE computes one full-physics forward model, Jacobian, and update.
8. The result returns the corrected state plus fast-stage correction diagnostics.
```

There is no public correction case and no public spectral-branch object.  The
default sparse selector is just a window and count that resolves to concrete
wavelengths on the case sampling:

```text
wavelength_window_nm = 765.2-768.0
wavelength_count = 12
```

Users can replace the default by assigning explicit wavelengths:

```python
case.optimisation.fastmode.oe.final_correction.wavelengths_nm = (
    765.2,
    765.44,
    765.71,
    ...
)
```

## Dimension Shape

The correction solve clips the measurement and the full-physics simulation to
the same explicit wavelength grid.  The dimensions therefore match inside the
correction boundary:

```text
y_sparse          n_sparse
F_full(x)_sparse  n_sparse
K_sparse          n_sparse x n_state
S_e_sparse        n_sparse diagonal
```

The wavelength dimension is reduced away when the normal equations are formed:

```text
K_sparse^T S_e_sparse^-1 K_sparse       n_state x n_state
K_sparse^T S_e_sparse^-1 (y - F(x))     n_state
```

The solve is still a state-vector solve.  For the retained two-state O2 A
retrieval, `n_state = 2` for aerosol optical depth and aerosol layer mid
pressure.  Sparse wavelengths change the number of Jacobian rows, not the
number of retrieved state dimensions.

## Timing Boundary

The retained sweep records `retrieval_s` around the public retrieval call.  It
does not include scene construction, measurement construction, plotting, or the
lazy final-state spectrum evaluation.  It does include:

- the fastmode OE retrieval call;
- native case load/prepare for the sparse full-physics correction;
- one exact full-physics forward model and Jacobian on that sparse grid;
- one native OE correction solve;
- copying the result back through the Python binding.

The final full-band spectrum is lazy.  It is attached to the result so plotting
and residual inspection can ask for it later, but it is not part of
`retrieval_s` unless a caller reads `result.final_evaluation`.

## Retained Evidence

Regenerate the retained 100-case fastmode sweep with:

```sh
uv run validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py
```

Summary from
[`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json):

```text
reference:          100/100 converged, median 1.790 s, mean 1.741 s
fast:               100/100 converged, median 0.954 s, mean 0.919 s
fastmode corrected: 100/100 converged, median 1.140 s, mean 1.115 s
```

Corrected fastmode stays closer to fastmode latency than full-reference latency:

```text
corrected speedup vs reference: median +0.653 s, mean +0.626 s
corrected extra vs fastmode:    median +0.194 s, mean +0.196 s
latency position:               0.222
```

`latency position` places fastmode at `0.0` and full reference mode at `1.0`.
Values below `0.5` are closer to fastmode than to full reference mode.

Accuracy against the full-physics reference retrieval stayed inside the retained
gate:

```text
corrected max AOD delta vs reference:          4.864e-04
corrected max mid-pressure delta vs reference: 0.215 hPa
```

The sweep compares:

- `reference`: normal full-physics zdisamar OE;
- `fast`: case-owned fastmode with final correction disabled;
- `fast_corrected`: case-owned fastmode with the default sparse full-physics
  final correction.

The tracked outputs are:

- [`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png)
- [`validation/outputs/optimal_estimation/paired_oe_latency.png`](../../../validation/outputs/optimal_estimation/paired_oe_latency.png)
- [`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json)

The validation gate requires the corrected mode to beat full-reference median
latency and improve the fastmode retrieved-state errors while staying inside
the retained AOD and aerosol-pressure delta limits.

## Why This Works

Fastmode and full mode are not different inverse problems.  They use the same
state vector and measurement concept, but fastmode uses cheaper RTM settings.
Once fastmode has converged, the remaining error is largely a local model-bias
correction in the state vector.

The sparse full-physics correction gives the OE solve a higher-fidelity
Jacobian and residual near the converged fast state.  That update can move the
state toward the full-physics solution without paying for exact full-band RTM
and Jacobians at every iteration.

The useful design split is:

```text
cheap global search + targeted exact local correction
```

## Tradeoffs And Next Questions

The correction wavelengths are sampling-dependent.  That is why the public
configuration stores either explicit `wavelengths_nm` or a simple window/count
selector that resolves to explicit wavelengths before execution.  The tuned
default is empirical retained-validation evidence, not a claim that this is the
only physically informative region.

Open questions:

- test whether narrower windows keep both AOD and pressure constrained;
- rank candidate wavelengths by Jacobian information for the retrieved state
  dimensions;
- keep a held-out validation set so sparse defaults do not overfit the retained
  100 cases;
- measure correction-only timing separately from fast-stage timing;
- revisit variance scaling for sparse windows.
