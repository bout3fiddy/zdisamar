"""Covariance-space preparation for optimal-estimation updates."""

from __future__ import annotations

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

    # S_a^1/2 maps a unit move in normalized state space back to physical state
    # units.  Cholesky gives the same role for diagonal and future full prior
    # covariances, so this code path will not need to change once correlated
    # priors are introduced.
    sqrt_sa = np.linalg.cholesky(prior_covariance)
    sqrt_inv_sa = np.linalg.inv(sqrt_sa)

    # The current public Measurement stores only the diagonal of S_e.  Keeping
    # the covariance conversion here isolates that interface decision from the
    # step solver, so a future full covariance changes one boundary instead of
    # every inverse-method experiment.
    sqrt_inv_se = np.diag(1.0 / np.sqrt(measurement_variance))

    # dx is measured from the a-priori state, not the previous iteration delta,
    # because optimal estimation regularizes absolute distance from x_a.  Using x_i - x_{i-1}
    # here would remove the prior penalty from the linearized update.
    dx = previous - prior
    return CovarianceSpace(
        dx_white=sqrt_inv_sa @ dx,
        d_r_white=sqrt_inv_se @ residual,
        k_white=sqrt_inv_se @ jacobian @ sqrt_sa,
        sqrt_sa=sqrt_sa,
        sqrt_inv_sa=sqrt_inv_sa,
    )
