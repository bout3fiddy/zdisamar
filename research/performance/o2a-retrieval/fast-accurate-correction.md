# Fast-Accurate Retrieval Correction

This note describes the `disamar_oe_fast` retrieval mode: a fast-mode
optimal-estimation solve followed by one targeted full-physics correction.

The mode is a multi-fidelity retrieval. Fast mode is used to find the retrieval
basin. Full physics is then used only for the final local state-vector update,
not for every iteration and not over the full O2 A band.

## Algorithm

The retained implementation uses this sequence:

```text
1. Run O2AInput.with_fast_mode() retrieval to convergence on the full measurement vector.
2. Use the fast-mode retrieved state as the initial state for one correction.
3. Retain the 762-768 nm correction window from the measured spectrum.
4. Load a matching full-physics O2 A case whose spectral grid is that window.
5. Run one exact full-physics forward model and Jacobian on the correction grid.
6. Assemble and solve one OE normal-system update in state space.
7. Return the corrected state with the fast-stage history and correction diagnostics.
```

The correction window is currently:

```text
FULL_CORRECTION_WINDOW_NM = 762.0-768.0
```

That window was chosen because a full-band exact correction removed too much of
the fast-mode latency gain, while a narrower retained window failed the 100-case
AOD delta gate. The current window is an empirical retained-validation choice,
not a claim that this is the only physically informative region.

## Dimension Shape

The correction solve clips the measurement and the full-physics simulation to
the same wavelength grid. The dimensions therefore match inside the correction
boundary:

```text
y_window          n_window
F_full(x)_window  n_window
K_window          n_window x n_state
S_e_window        n_window diagonal
```

The wavelength dimension is reduced away when the normal equations are formed:

```text
K_window^T S_e_window^-1 K_window       n_state x n_state
K_window^T S_e_window^-1 (y - F(x))     n_state
```

The solve is still a state-vector solve. For the retained two-state O2 A
retrieval, `n_state = 2` for aerosol optical depth and aerosol layer mid
pressure. A clipped or sparse wavelength set changes the number of rows in the
Jacobian, not the number of retrieved state dimensions.

The correction measurement scales the retained variances by the retained
fraction of wavelengths. This keeps the window from being underweighted only
because it has fewer rows. It is an empirical normalization and should be
revisited if the correction becomes sparse rather than one continuous window.

## Timing Boundary

The retained sweep records `retrieval_s` around the public retrieval call. It
does not include scene construction, measurement construction, plotting, or the
lazy final-state spectrum evaluation. It does include:

- the fast-mode retrieval call;
- native case load/prepare for the correction window;
- one exact full-physics forward model and Jacobian on that window;
- one native OE correction solve;
- copying the result back through the Python binding.

The final full-band spectrum is lazy. It is attached to the result so plotting
and residual inspection can ask for it later, but it is not part of
`retrieval_s` unless a caller reads `result.final_evaluation`.

## Retained Evidence

The retained 100-case fast-mode sweep was regenerated with:

```sh
uv run validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py
```

Summary from
[`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json):

```text
reference:      100/100 converged, median 1.887 s, mean 1.951 s
fast:           100/100 converged, median 0.998 s, mean 1.019 s
fast-accurate:  100/100 converged, median 1.408 s, mean 1.472 s
```

Paired deltas:

```text
fast-accurate speedup vs reference: median +0.508 s, mean +0.479 s
fast-accurate extra vs fast:       median +0.396 s, mean +0.453 s
latency position:                  0.461
```

`latency position` places fast mode at `0.0` and full reference mode at `1.0`.
Values below `0.5` are closer to fast mode than to full reference mode.

Accuracy against the full-physics reference retrieval stayed inside the retained
gate:

```text
fast-accurate max AOD delta vs reference:          4.149e-04
fast-accurate max mid-pressure delta vs reference: 0.272 hPa
```

Fast mode alone has larger retained errors:

```text
fast max AOD error:          7.392e-03
fast max mid-pressure error: 5.553 hPa
```

Fast-accurate reduces those to:

```text
fast-accurate max AOD error:          4.129e-04
fast-accurate max mid-pressure error: 0.283 hPa
```

The retained plots are:

- [`validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png`](../../../validation/outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png)
- [`validation/outputs/optimal_estimation/paired_oe_latency.png`](../../../validation/outputs/optimal_estimation/paired_oe_latency.png)

## Why This Works

Fast mode and full mode are not doing different inverse problems. They use the
same state vector and measurement concept, but fast mode uses cheaper RTM
settings. Once fast mode has converged, the remaining error is largely a local
model-bias correction in the state vector.

The clipped full-physics correction gives the OE solve a higher-fidelity
Jacobian and residual near the converged fast state. That update can move the
state toward the full-physics solution without paying for exact full-band RTM
and Jacobians at every iteration.

The useful design split is:

```text
cheap global search + targeted exact local correction
```

## Tradeoffs And Next Questions

The correction window can become a real design parameter. Current evidence only
proves the retained `762-768 nm` continuous window. Plausible next steps are:

- select sparse wavelengths or small windows around high-information R/P branch
  features instead of using one continuous window;
- rank candidate wavelengths by Jacobian information for the retrieved state
  dimensions;
- keep a held-out validation set so the correction window does not overfit the
  retained 100 cases;
- measure correction-only timing separately from fast-stage timing;
- test whether variance weighting should use retained-fraction scaling,
  information-content scaling, or direct noise-model covariance for sparse
  windows.

The failure mode is also clear: if the clipped or sparse full-physics window no
longer constrains both aerosol optical depth and aerosol layer pressure, the
state update can look fast while drifting away from the full-physics retrieval.
The retained gate should therefore require both latency and state-error checks.
