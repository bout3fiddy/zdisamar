# Fastmode Sampling And Final Correction

Fastmode is a case-owned optimisation mode, not a separate retrieval API.  A
normal O2 A case remains the full-physics reference case.  Fastmode is enabled
on that same case:

```python
case.optimisation.fastmode.enabled = True
```

The case keeps the optimisation settings visible.  The execution path resolves
those settings before loading the native RTM case, so callers can inspect the
actual knobs, fast-stage wavelengths, and final-correction wavelengths:

```python
case.resolved_optimisation()["fastmode"]
```

The default fastmode configuration changes:

- RTM performance thresholds: Fourier cap, aerosol tangent cap, Fourier-tail
  threshold, and layer-doubling threshold.
- Adaptive reference-grid controls: points per FWHM and strong-line
  subdivisions.
- OE controls: iteration and state-vector convergence settings.
- OE fast-stage sampling: the measured wavelengths used by the fast solve.
- OE final correction: one full-physics state update after fastmode
  convergence.

## API Knobs

Fastmode is configured by editing fields under `case.optimisation.fastmode`.
The defaults are intended to be usable directly, but the fields are ordinary case
data and can be changed before calling `disamar_oe`.

```python
from zdisamar.wavelength_bands import o2a

case.optimisation.fastmode.enabled = True
fastmode = case.optimisation.fastmode

fastmode.radiative_transfer.fourier_order_cap = 5
fastmode.radiative_transfer.aerosol_tangent_order_cap = 11
fastmode.radiative_transfer.fourier_tail_reflectance_epsilon = 1.0e-11
fastmode.radiative_transfer.threshold_doubl = 3.0e-5

fastmode.adaptive_reference_grid.points_per_fwhm = 28
fastmode.adaptive_reference_grid.strong_line_min_divisions = 6
fastmode.adaptive_reference_grid.strong_line_max_divisions = 22

fastmode.oe.controls.max_iterations = 10
fastmode.oe.controls.state_vector_convergence_threshold = 1.0
fastmode.oe.controls.max_change_transformed_state = 1.0

fastmode.oe.fast_stage_sampling.enabled = True
fastmode.oe.fast_stage_sampling.windows = (
    o2a.FastModeWavelengthWindow((755.0, 758.5), 16),
    o2a.FastModeWavelengthWindow((765.2, 768.0), 25),
)
fastmode.oe.fast_stage_sampling.variance_scale = None

fastmode.oe.final_correction.enabled = True
fastmode.oe.final_correction.wavelength_window_nm = (765.2, 768.0)
fastmode.oe.final_correction.wavelength_count = 12
```

The RTM fields reduce work in the native forward model.  Fourier caps skip high
azimuthal orders; the Fourier-tail threshold stops the series once the
reflectance tail is small; `threshold_doubl` relaxes layer-doubling work.  These
are speed/accuracy controls, not physical-scene controls.

The adaptive-reference-grid fields reduce high-resolution O2 line sampling
before instrument convolution.  Lower values are faster but can under-resolve
strong line cores.

The OE controls decide when the fast retrieval stage stops.  The fast-stage
sampling fields decide which measured wavelengths are passed to the fast solve.
The final-correction fields decide whether zdisamar performs one sparse
full-physics update, and which measured wavelengths are used for that update.
`variance_scale=None` applies retained-fraction variance scaling for sparse
measurement vectors.

## Algorithm

The retained OE path uses one public `disamar_oe` call:

```text
1. The input case has fastmode enabled.
2. Fastmode resolves sparse fast-stage wavelengths on the measurement grid.
3. The native session loads that sparse case with fastmode RTM controls resolved.
4. OE runs to convergence on the sparse fast-stage measurement vector.
5. If final correction is enabled, zdisamar disables fastmode on the original
   full measurement case copy.
6. The correction keeps explicit sparse wavelengths on the measurement grid.
7. The same session handle loads that sparse full-physics correction case.
8. Native OE computes one full-physics forward model, Jacobian, and update.
9. The result returns the corrected state plus fast-stage correction diagnostics.
```

There is no public correction case and no public spectral-branch object.  The
default sparse selectors are just windows and counts that resolve to concrete
wavelengths on the case sampling:

```text
fast stage:
  wavelength_window_nm = 755.0-758.5, wavelength_count = 16
  wavelength_window_nm = 765.2-768.0, wavelength_count = 25

final correction:
  wavelength_window_nm = 765.2-768.0, wavelength_count = 12
```

Users can replace the default by assigning explicit wavelengths:

```python
case.optimisation.fastmode.oe.fast_stage_sampling.wavelengths_nm = (
    758.0,
    758.04,
    758.08,
    ...
)
case.optimisation.fastmode.oe.final_correction.wavelengths_nm = (
    765.2,
    765.44,
    765.71,
    ...
)
```

## Dimension Shape

The fast solve and the correction solve each clip the measurement and RTM case
to their own explicit wavelength grid.  The dimensions therefore match inside
each OE boundary:

```text
y_sparse      n_sparse
F(x)_sparse   n_sparse
K_sparse      n_sparse x n_state
S_e_sparse    n_sparse diagonal
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

The retained sweep records `retrieval_s` as wall-clock time around the public
retrieval call.  It does not include scene construction, measurement
construction, plotting, or the lazy final-state spectrum evaluation.  It does
include:

- the fastmode OE retrieval call;
- native case load/prepare for the sparse fast-stage case;
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
fullmode: 100/100 converged, median 1.944 s, mean 1.899 s
fastmode: 100/100 converged, median 0.538 s, mean 0.528 s
```

The validation sweep resolves 38 fast-stage wavelengths and 12 final-correction
wavelengths for every scene.  Fastmode median speedup against the same-run
fullmode reference is `+1.416 s`; mean speedup is `+1.371 s`.

Accuracy against the full-physics reference retrieval stayed inside the retained
gate:

```text
fastmode max AOD delta vs fullmode:          5.285e-04
fastmode max mid-pressure delta vs fullmode: 0.668 hPa
```

The sweep compares:

- `reference`: normal full-physics zdisamar OE;
- `fastmode`: case-owned fastmode with sparse fast-stage sampling and the default
  sparse full-physics final correction.

The tracked outputs are:

- [`validation/outputs/optimal_estimation/paired_oe_retrieved_fast_scatter.png`](../../../validation/outputs/optimal_estimation/paired_oe_retrieved_fast_scatter.png)
- [`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png)
- [`validation/outputs/optimal_estimation/paired_oe_latency.png`](../../../validation/outputs/optimal_estimation/paired_oe_latency.png)
- [`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json)

The validation gate requires fastmode to beat full-reference median latency,
retain the 38/12 wavelength shape, and stay inside the retained AOD and
aerosol-pressure delta limits.

## Why This Works

Fastmode and full mode are not different inverse problems.  They use the same
state vector and measurement concept, but fastmode uses cheaper RTM settings and
a sparse measured wavelength subset.  Once fastmode has converged, the remaining
error is largely a local model-bias correction in the state vector.

The sparse full-physics correction gives the OE solve a higher-fidelity
Jacobian and residual near the converged fast state.  That update can move the
state toward the full-physics solution without paying for exact full-band RTM
and Jacobians at every iteration.

The useful design split is:

```text
cheap global search + targeted exact local correction
```

## Tradeoffs And Next Questions

The sparse wavelengths are sampling-dependent.  That is why the public
configuration stores either explicit `wavelengths_nm` or simple window/count
selectors that resolve to explicit wavelengths before execution.  The tuned
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
