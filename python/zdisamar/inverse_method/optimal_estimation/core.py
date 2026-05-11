"""Optimal-estimation update machinery.

The core solver knows only about the inverse problem

    y = F(x) + e

and a callback that returns F(x) and K = dF/dx.  It deliberately has no O2 A
settings knowledge; model mutation belongs to the inverse forward-model layer.
That separation keeps inverse-method experiments from spreading scene-specific
write logic into the numerical solver.
"""

from collections.abc import Callable

import numpy as np

from .covariance_space import build_covariance_space_from_workspace, build_solver_workspace
from .diagnostics import final_diagnostics
from .forward_evaluation import ForwardEvaluation
from .gauss_newton import gauss_newton_step
from .measurement import measurement_arrays, require_matching_wavelength_grid
from .retrieval import (
    Iteration,
    IterationTiming,
    Measurement,
    Result,
    RetrievalControls,
)
from .state_vector import StateVector
from .timing import IterationTimer, NoopIterationTimer


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

    with a diagonal measurement covariance S_e in this first API slice. The
    update policy is factored into `gauss_newton_step` so future LM,
    line-search, or alternative regularization experiments can reuse the same
    state history and diagnostics.
    """

    state_names = state_vector.names
    x = state_vector.initial_state()
    xa = state_vector.prior_state()
    sa = state_vector.prior_covariance()
    measured = measurement_arrays(measurement)

    workspace = build_solver_workspace(
        prior=xa,
        prior_covariance=sa,
        measurement_variance=measured.variance,
    )
    history: list[Iteration] = []
    posterior = np.array(sa, copy=True)
    state_count = len(state_names)
    averaging_kernel = np.eye(state_count, dtype=np.float64)
    converged = False
    timing: list[IterationTiming] = []
    last_evaluated_state: np.ndarray | None = None
    last_evaluation: ForwardEvaluation | None = None
    final_posterior_precision = workspace.inv_prior_covariance
    final_jacobian: np.ndarray | None = None

    for iteration_index in range(1, controls.max_iterations + 1):
        iteration_timer = (
            IterationTimer(iteration_index)
            if controls.collect_timing
            else NoopIterationTimer(iteration_index)
        )
        previous = np.array(x, copy=True)
        # The expensive part of optimal estimation is here: every iteration
        # asks the forward model for both F(x_i) and K_i.  `prior` is not used
        # to generate this spectrum unless the caller deliberately chose
        # `initial == prior`.
        evaluation = iteration_timer.forward(lambda state=previous: forward_model(state))
        last_evaluated_state = np.array(previous, copy=True)
        last_evaluation = evaluation

        iteration_timer.start_solver()
        require_matching_wavelength_grid(
            measured.wavelength_nm,
            evaluation.wavelength_nm,
            expected_name="measurement",
            actual_name="forward evaluation",
        )
        reflectance = np.asarray(evaluation.reflectance, dtype=np.float64)
        jacobian = np.asarray(evaluation.reflectance_jacobian, dtype=np.float64)
        if jacobian.shape != (measured.wavelength_nm.size, state_count):
            raise ValueError("forward evaluation Jacobian shape does not match retrieval state")
        residual = measured.reflectance - reflectance

        # The solver is deliberately split at this point.  The retrieval loop
        # owns the expensive model evaluation and bookkeeping, while the
        # covariance-space and Gauss-Newton modules own the math that can be
        # swapped for LM or other inverse-method experiments.
        covariance_space = build_covariance_space_from_workspace(
            workspace=workspace,
            previous=previous,
            residual=residual,
            jacobian=jacobian,
        )
        step = gauss_newton_step(
            covariance_space,
            prior=xa,
            max_change_transformed_state=controls.max_change_transformed_state,
        )
        x = state_vector.clip_to_bounds(step.state)

        dx_iter = x - previous
        chi2_reflectance = float(residual @ workspace.inv_se @ residual)
        chi2_state = float(dx_iter @ workspace.inv_prior_covariance @ dx_iter)
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
        iteration_timer.stop_solver()
        if controls.collect_timing:
            timing.append(iteration_timer.finish())
        final_posterior_precision = step.posterior_precision
        final_jacobian = jacobian
        # Convergence requires both a small accepted state movement and a normal
        # signal-to-noise step.  Without the second condition an artificially
        # reduced spectral signal could make a too-large proposed move look
        # harmless, ending the retrieval before the real forward model has been
        # evaluated near the solution.
        if state_conv < controls.state_vector_convergence_threshold and step.snr_normal:
            converged = True
            break

    if final_jacobian is not None:
        diagnostics = final_diagnostics(
            posterior_precision=final_posterior_precision,
            jacobian=final_jacobian,
            measurement_variance=measured.variance,
        )
        posterior = diagnostics.posterior_covariance
        averaging_kernel = diagnostics.averaging_kernel

    return Result(
        state_names=state_names,
        state=x,
        iterations=len(history),
        converged=converged,
        history=tuple(history),
        posterior_covariance=posterior,
        averaging_kernel=averaging_kernel,
        timing=tuple(timing),
        last_evaluated_state=last_evaluated_state,
        last_evaluation=last_evaluation,
    )
