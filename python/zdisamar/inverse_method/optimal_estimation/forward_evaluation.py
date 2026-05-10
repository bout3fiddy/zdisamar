"""Forward-model values used by inverse-method solvers."""

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class ForwardEvaluation:
    """Forward model result at one state-vector point.

    `reflectance_jacobian` has shape `(n_wavelength, n_state)` and represents
    K = dy/dx for the same retrieval quantity as `reflectance`.
    """

    wavelength_nm: np.ndarray
    reflectance: np.ndarray
    reflectance_jacobian: np.ndarray
