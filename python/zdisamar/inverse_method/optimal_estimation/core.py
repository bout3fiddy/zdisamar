"""Optimal-estimation update machinery.

The core solver knows only about the inverse problem

    y = F(x) + e

and a callback that returns F(x) and K = dF/dx.  It deliberately has no O2 A
settings knowledge; model mutation belongs to the inverse forward-model layer.
That separation keeps inverse-method experiments from spreading scene-specific
write logic into the numerical solver.
"""

from __future__ import annotations

import time
from collections.abc import Callable, Iterable

import numpy as np

from .covariance_space import build_covariance_space
from .forward_evaluation import ForwardEvaluation
from .gauss_newton import gauss_newton_step
from .retrieval import (
    Iteration,
    IterationTiming,
    Measurement,
    Result,
    RetrievalControls,
    StateName,
)
from .state_vector import StateVector


def retrieve(
    forward_model: Callable[[np.ndarray], ForwardEvaluation],
    measurement: Measurement,
    state_vector: StateVector,
    *,
    controls: RetrievalControls,
) -> Result:
    """Run a modified Gauss-Newton optimal-estimation retrieval.

    The cost function is the standard optimal estimation objective

        J(x) = (y - F(x))^T S_e^-1 (y - F(x))
             + (x - x_a)^T S_a^-1 (x - x_a),

    with a diagonal measurement covariance S_e in this first API slice.  The
    update policy is factored into `gauss_newton_step` so future LM,
    line-search, or alternative regularization experiments can reuse the same
    state history and diagnostics.
    """

    state_names = state_vector.names
    x = state_vector.initial_state()
    xa = state_vector.prior_state()
    sa = state_vector.prior_covariance()
    se_variance = np.asarray(measurement.variance, dtype=np.float64)
    if np.any(se_variance <= 0.0):
        raise ValueError("measurement variance must be positive")

    inv_se = np.diag(1.0 / se_variance)
    history: list[Iteration] = []
    posterior = np.array(sa, copy=True)
    state_count = len(state_names)
    averaging_kernel = np.eye(state_count, dtype=np.float64)
    converged = False
    timing: list[IterationTiming] = []

    for iteration_index in range(1, controls.max_iterations + 1):
        iteration_start = time.perf_counter()
        previous = np.array(x, copy=True)
        # The expensive part of optimal estimation is here: every iteration
        # asks the forward model for both F(x_i) and K_i.  `prior` is not used
        # to generate this spectrum unless the caller deliberately chose
        # `initial == prior`.
        forward_start = time.perf_counter()
        evaluation = forward_model(previous)
        forward_seconds = time.perf_counter() - forward_start

        solver_start = time.perf_counter()
        reflectance = _interpolate(
            measurement.wavelength_nm, evaluation.wavelength_nm, evaluation.reflectance
        )
        jacobian = _interpolate_columns(
            measurement.wavelength_nm,
            evaluation.wavelength_nm,
            evaluation.reflectance_jacobian,
            state_names,
        )
        residual = np.asarray(measurement.reflectance, dtype=np.float64) - reflectance

        # The solver is deliberately split at this point.  The retrieval loop
        # owns the expensive model evaluation and bookkeeping, while the
        # covariance-space and Gauss-Newton modules own the math that can be
        # swapped for LM or other inverse-method experiments.
        covariance_space = build_covariance_space(
            previous=previous,
            prior=xa,
            residual=residual,
            jacobian=jacobian,
            prior_covariance=sa,
            measurement_variance=se_variance,
        )
        step = gauss_newton_step(
            covariance_space,
            prior=xa,
            jacobian=jacobian,
            measurement_variance=se_variance,
            max_change_transformed_state=controls.max_change_transformed_state,
        )
        x = state_vector.clip_to_bounds(step.state)

        dx_iter = x - previous
        chi2_reflectance = float(residual @ inv_se @ residual)
        chi2_state = float(dx_iter @ np.linalg.inv(sa) @ dx_iter)
        state_conv = float(dx_iter @ step.posterior_precision @ dx_iter / state_count)
        history.append(
            Iteration(
                index=iteration_index,
                state=np.array(x, copy=True),
                chi2=chi2_reflectance + chi2_state,
                chi2_reflectance=chi2_reflectance,
                chi2_state_vector=chi2_state,
                state_vector_convergence=state_conv,
                snr_normal=step.snr_normal,
            )
        )
        solver_seconds = time.perf_counter() - solver_start
        timing.append(
            IterationTiming(
                index=iteration_index,
                forward_model_and_jacobian_s=forward_seconds,
                solver_update_s=solver_seconds,
                total_iteration_s=time.perf_counter() - iteration_start,
            )
        )
        posterior = step.posterior_covariance
        averaging_kernel = step.averaging_kernel
        # Convergence requires both a small accepted state movement and a normal
        # signal-to-noise step.  Without the second condition an artificially
        # reduced spectral signal could make a too-large proposed move look
        # harmless, ending the retrieval before the real forward model has been
        # evaluated near the solution.
        if state_conv < controls.state_vector_convergence_threshold and step.snr_normal:
            converged = True
            break

    return Result(
        state_names=state_names,
        state=x,
        iterations=len(history),
        converged=converged,
        history=tuple(history),
        posterior_covariance=posterior,
        averaging_kernel=averaging_kernel,
        timing=tuple(timing),
    )


def _interpolate(target: np.ndarray, source: np.ndarray, values: np.ndarray) -> np.ndarray:
    if np.array_equal(target, source):
        return np.asarray(values, dtype=np.float64)
    return np.interp(target, source, values)


def _interpolate_columns(
    target: np.ndarray,
    source: np.ndarray,
    values: np.ndarray,
    state_names: Iterable[StateName],
) -> np.ndarray:
    columns = tuple(state_names)
    if np.array_equal(target, source):
        return np.asarray(values, dtype=np.float64)
    interpolated = np.empty((target.size, len(columns)), dtype=np.float64)
    for column_index in range(len(columns)):
        interpolated[:, column_index] = np.interp(target, source, values[:, column_index])
    return interpolated
