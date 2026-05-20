"""RTM values used by inverse-method solvers."""

from collections.abc import Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class RtmEvaluation:
    """RTM result at one state-vector point.

    `reflectance_jacobian` has shape `(n_wavelength, n_state)` and represents
    K = dy/dx for the same retrieval quantity as `reflectance`.
    """

    wavelength_nm: Sequence[float]
    reflectance: Sequence[float]
    reflectance_jacobian: Sequence[Sequence[float]]
