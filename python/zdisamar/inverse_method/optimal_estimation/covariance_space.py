"""Covariance-space preparation for optimal-estimation updates."""

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class CovarianceSpace:
    """Linearized optimal estimation problem expressed in normalized variables.

    State-vector elements and spectral samples live in different units and on
    different numerical scales.  This object stores the dimensionless problem
    where the prior and measurement covariance matrices define comparable unit
    moves for the Gauss-Newton solve.
    """

    dx_white: np.ndarray
    d_r_white: np.ndarray
    k_white: np.ndarray
    sqrt_sa: np.ndarray
    sqrt_inv_sa: np.ndarray


@dataclass(frozen=True)
class SolverWorkspace:
    """Static covariance terms reused across retrieval iterations."""

    prior: np.ndarray
    prior_covariance: np.ndarray
    inv_prior_covariance: np.ndarray
    sqrt_sa: np.ndarray
    sqrt_inv_sa: np.ndarray
    measurement_variance: np.ndarray
    sqrt_inv_se: np.ndarray
    inv_se: np.ndarray


def build_solver_workspace(
    *,
    prior: np.ndarray,
    prior_covariance: np.ndarray,
    measurement_variance: np.ndarray,
) -> SolverWorkspace:
    """Precompute covariance transforms that do not change between iterations."""

    prior_values = np.asarray(prior, dtype=np.float64)
    prior_covariance_values = np.asarray(prior_covariance, dtype=np.float64)
    measurement_variance_values = np.asarray(measurement_variance, dtype=np.float64)
    sqrt_sa = np.linalg.cholesky(prior_covariance_values)
    sqrt_inv_sa = np.linalg.inv(sqrt_sa)

    return SolverWorkspace(
        prior=prior_values,
        prior_covariance=prior_covariance_values,
        inv_prior_covariance=np.linalg.inv(prior_covariance_values),
        sqrt_sa=sqrt_sa,
        sqrt_inv_sa=sqrt_inv_sa,
        measurement_variance=measurement_variance_values,
        sqrt_inv_se=np.diag(1.0 / np.sqrt(measurement_variance_values)),
        inv_se=np.diag(1.0 / measurement_variance_values),
    )


def build_covariance_space(
    *,
    previous: np.ndarray,
    prior: np.ndarray,
    residual: np.ndarray,
    jacobian: np.ndarray,
    prior_covariance: np.ndarray,
    measurement_variance: np.ndarray,
) -> CovarianceSpace:
    """Return the normalized linear problem for one optimal estimation iteration.

    The linearized cost has two quadratic penalties,

        (y - F(x))^T S_e^-1 (y - F(x))
        + (x - x_a)^T S_a^-1 (x - x_a).

    Applying S_e^-1/2 to the residual side and S_a^+/-1/2 to the state side
    turns both penalties into unit-covariance coordinates before the SVD.  The
    retrieval should not move pressure more or less aggressively just because
    hPa has larger raw numbers than AOD; the covariance matrices, not the
    display units, should define what a large move means.
    """

    workspace = build_solver_workspace(
        prior=prior,
        prior_covariance=prior_covariance,
        measurement_variance=measurement_variance,
    )

    return build_covariance_space_from_workspace(
        workspace=workspace,
        previous=previous,
        residual=residual,
        jacobian=jacobian,
    )


def build_covariance_space_from_workspace(
    *,
    workspace: SolverWorkspace,
    previous: np.ndarray,
    residual: np.ndarray,
    jacobian: np.ndarray,
) -> CovarianceSpace:
    """Return the normalized linear problem using cached covariance transforms."""

    # dx is measured from the a-priori state, not the previous iteration delta,
    # because optimal estimation regularizes absolute distance from x_a.  Using x_i - x_{i-1}
    # here would remove the prior penalty from the linearized update.
    dx = previous - workspace.prior

    return CovarianceSpace(
        dx_white=workspace.sqrt_inv_sa @ dx,
        d_r_white=workspace.sqrt_inv_se @ residual,
        k_white=workspace.sqrt_inv_se @ jacobian @ workspace.sqrt_sa,
        sqrt_sa=workspace.sqrt_sa,
        sqrt_inv_sa=workspace.sqrt_inv_sa,
    )
