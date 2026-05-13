"""Optimal-estimation update machinery.

The core solver knows only about the inverse problem

    y = F(x) + e

and a callback that returns F(x) and K = dF/dx.  It deliberately has no O2 A
settings knowledge; model mutation belongs to the inverse forward-model layer.
That separation keeps inverse-method experiments from spreading scene-specific
write logic into the numerical solver.
"""

from collections.abc import Callable
from dataclasses import dataclass

import numpy as np

from .covariance_space import (
    SolverWorkspace,
    build_covariance_space_from_workspace,
    build_solver_workspace,
)
from .diagnostics import final_diagnostics
from .forward_evaluation import ForwardEvaluation
from .gauss_newton import gauss_newton_step
from .measurement import (
    MeasurementArrays,
    measurement_arrays,
    require_matching_wavelength_grid,
)
from .retrieval import (
    Iteration,
    IterationTiming,
    Measurement,
    Result,
    RetrievalControls,
)
from .state_vector import StateVector
from .timing import IterationTimer, NoopIterationTimer


@dataclass(frozen=True)
class IterationForward:
    previous: np.ndarray
    evaluation: ForwardEvaluation


@dataclass(frozen=True)
class IterationEvaluation:
    previous: np.ndarray
    evaluation: ForwardEvaluation
    reflectance: np.ndarray
    jacobian: np.ndarray
    residual: np.ndarray


@dataclass(frozen=True)
class IterationUpdate:
    state: np.ndarray
    history_entry: Iteration
    posterior_precision: np.ndarray
    jacobian: np.ndarray
    converged: bool


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
        iteration_forward = evaluate_iteration(
            forward_model,
            previous,
            iteration_timer,
        )
        last_evaluated_state = np.array(iteration_forward.previous, copy=True)
        last_evaluation = iteration_forward.evaluation
        iteration_timer.start_solver()
        iteration_evaluation = prepare_iteration_evaluation(
            iteration_forward,
            measured,
            state_count,
        )
        iteration_update = solve_iteration(
            iteration_evaluation,
            workspace,
            state_vector,
            xa,
            controls,
            iteration_index,
            state_count,
        )
        x = iteration_update.state
        history.append(iteration_update.history_entry)
        iteration_timer.stop_solver()
        if controls.collect_timing:
            timing.append(iteration_timer.finish())
        final_posterior_precision = iteration_update.posterior_precision
        final_jacobian = iteration_update.jacobian
        if iteration_update.converged:
            converged = True
            break

    if final_jacobian is not None:
        posterior, averaging_kernel = final_posterior_products(
            final_posterior_precision,
            final_jacobian,
            measured.variance,
        )

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


def evaluate_iteration(
    forward_model: Callable[[np.ndarray], ForwardEvaluation],
    previous: np.ndarray,
    iteration_timer: IterationTimer | NoopIterationTimer,
) -> IterationForward:
    # The expensive part of optimal estimation is here: every iteration asks
    # the forward model for both F(x_i) and K_i. `prior` is not used to generate
    # this spectrum unless the caller deliberately chose `initial == prior`.
    evaluation = iteration_timer.forward(lambda state=previous: forward_model(state))
    return IterationForward(previous=previous, evaluation=evaluation)


def prepare_iteration_evaluation(
    iteration_forward: IterationForward,
    measured: MeasurementArrays,
    state_count: int,
) -> IterationEvaluation:
    evaluation = iteration_forward.evaluation
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
    return IterationEvaluation(
        previous=iteration_forward.previous,
        evaluation=evaluation,
        reflectance=reflectance,
        jacobian=jacobian,
        residual=measured.reflectance - reflectance,
    )


def solve_iteration(
    iteration_evaluation: IterationEvaluation,
    workspace: SolverWorkspace,
    state_vector: StateVector,
    prior: np.ndarray,
    controls: RetrievalControls,
    iteration_index: int,
    state_count: int,
) -> IterationUpdate:
    # The retrieval loop owns the expensive model evaluation and bookkeeping,
    # while the covariance-space and Gauss-Newton modules own the math that can
    # be swapped for LM or other inverse-method experiments.
    covariance_space = build_covariance_space_from_workspace(
        workspace=workspace,
        previous=iteration_evaluation.previous,
        residual=iteration_evaluation.residual,
        jacobian=iteration_evaluation.jacobian,
    )
    step = gauss_newton_step(
        covariance_space,
        prior=prior,
        max_change_transformed_state=controls.max_change_transformed_state,
    )
    state = state_vector.clip_to_bounds(step.state)
    dx_iter = state - iteration_evaluation.previous
    chi2_reflectance = float(
        iteration_evaluation.residual @ workspace.inv_se @ iteration_evaluation.residual
    )
    chi2_state = float(dx_iter @ workspace.inv_prior_covariance @ dx_iter)
    state_conv = float(dx_iter @ step.posterior_precision @ dx_iter / state_count)
    # Convergence requires both a small accepted state movement and a normal
    # signal-to-noise step. Without the second condition an artificially reduced
    # spectral signal could make a too-large proposed move look harmless.
    converged = state_conv < controls.state_vector_convergence_threshold and step.snr_normal
    return IterationUpdate(
        state=state,
        history_entry=Iteration(
            index=iteration_index,
            state=np.array(state, copy=True),
            chi2=chi2_reflectance + chi2_state,
            chi2_reflectance=chi2_reflectance,
            chi2_state_vector=chi2_state,
            state_vector_convergence=state_conv,
            snr_normal=step.snr_normal,
        ),
        posterior_precision=step.posterior_precision,
        jacobian=iteration_evaluation.jacobian,
        converged=converged,
    )


def final_posterior_products(
    posterior_precision: np.ndarray,
    jacobian: np.ndarray,
    measurement_variance: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    diagnostics = final_diagnostics(
        posterior_precision=posterior_precision,
        jacobian=jacobian,
        measurement_variance=measurement_variance,
    )
    return diagnostics.posterior_covariance, diagnostics.averaging_kernel
