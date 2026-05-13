"""Gauss-Newton optimal estimation step in transformed covariance space."""

from dataclasses import dataclass

import numpy as np

from .covariance_space import CovarianceSpace


@dataclass(frozen=True)
class StepResult:
    """Result of one modified Gauss-Newton state-vector update."""

    state: np.ndarray
    posterior_precision: np.ndarray
    snr_normal: bool


def gauss_newton_step(
    problem: CovarianceSpace,
    *,
    prior: np.ndarray,
    max_change_transformed_state: float,
) -> StepResult:
    """Compute one modified Gauss-Newton update.

    In the SVD basis K_white = U W V^T, each singular direction is independent:

        dx_new_t = w * (dR_t + w * dx_t) / (w^2 + 1).

    The formula is the optimal estimation normal-equation update written in transformed
    coordinates.  The SVD form is useful because weak spectral information
    appears as small singular values, so the prior naturally dominates those
    directions instead of requiring a hand-written rule per state variable.

    The S/N safeguard lives here because it changes the accepted step.  It is
    kept out of the retrieval loop so convergence accounting can stay about
    "what step was accepted" rather than "how that step was solved."
    """

    # Kwhite carries the observation sensitivity after both covariance
    # penalties have been normalized.  Its singular vectors are therefore the
    # directions where the measurement can actually constrain the state.
    u, singular_values, vt = np.linalg.svd(problem.k_white, full_matrices=False)
    v = vt.T
    dx_trans = vt @ problem.dx_white
    d_r_trans = u.T @ problem.d_r_white
    dx_trans_new = _transformed_state(singular_values, d_r_trans, dx_trans)

    change = float(np.max(np.abs(dx_trans_new - dx_trans)))
    max_change = max(max_change_transformed_state, float(np.max(np.abs(dx_trans))))
    snr_normal = True

    if change > 1.01 * max_change:
        # This is step-size safeguarding, not Levenberg-Marquardt curvature
        # damping.  Scaling the residual and singular values lowers the
        # effective spectral signal while preserving the same covariance
        # geometry, which prevents a single very informative spectrum mismatch
        # from launching the next forward-model call far outside the local
        # linearization.
        snr_normal = False
        factor_total = 1.0
        factor = 0.75
        reduced_w = np.array(singular_values, copy=True)

        for _ in range(10):
            factor_total *= factor
            reduced_d_r = factor_total * d_r_trans
            reduced_w = factor_total * singular_values
            dx_trans_new = _transformed_state(reduced_w, reduced_d_r, dx_trans)

            if float(np.max(np.abs(dx_trans_new - dx_trans))) < max_change:
                singular_values = reduced_w
                break

    # The solve happened in normalized SVD coordinates; the forward model needs
    # physical state units.  Multiplying by S_a^1/2 makes the accepted move mean
    # "this many prior standard deviations" before returning to AOD and hPa.
    dx_new = problem.sqrt_sa @ v @ dx_trans_new
    state = prior + dx_new
    state_count = problem.k_white.shape[1]
    posterior_precision_white = np.eye(state_count, dtype=np.float64)
    posterior_precision_white += v @ np.diag(singular_values**2) @ vt
    posterior_precision = problem.sqrt_inv_sa.T @ posterior_precision_white @ problem.sqrt_inv_sa

    return StepResult(
        state=state,
        posterior_precision=posterior_precision,
        snr_normal=snr_normal,
    )


def _transformed_state(
    singular_values: np.ndarray,
    residual: np.ndarray,
    dx: np.ndarray,
) -> np.ndarray:
    """Apply the scalar optimal estimation update in SVD-transformed coordinates."""

    return singular_values * (residual + singular_values * dx) / (singular_values**2 + 1.0)
