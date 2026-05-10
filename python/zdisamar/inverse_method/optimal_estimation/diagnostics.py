"""Final optimal-estimation diagnostics."""

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class FinalDiagnostics:
    """Diagnostics that are report outputs, not inputs to the next iteration."""

    posterior_covariance: np.ndarray
    averaging_kernel: np.ndarray


def final_diagnostics(
    *,
    posterior_precision: np.ndarray,
    jacobian: np.ndarray,
    measurement_variance: np.ndarray,
) -> FinalDiagnostics:
    """Compute final posterior diagnostics from the accepted linearized problem."""

    posterior_covariance = np.linalg.inv(posterior_precision)
    averaging_kernel = (
        posterior_covariance @ jacobian.T @ np.diag(1.0 / measurement_variance) @ jacobian
    )
    return FinalDiagnostics(
        posterior_covariance=posterior_covariance,
        averaging_kernel=averaging_kernel,
    )
