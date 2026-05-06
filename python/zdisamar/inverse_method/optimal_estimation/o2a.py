"""O2 A inverse forward-model adapter for optimal estimation."""

from __future__ import annotations

import copy
import math

import numpy as np

from ...prepared import PreparedO2ABase, prepare
from ...types import O2AInput
from .core import retrieve
from .forward_evaluation import ForwardEvaluation
from .retrieval import Measurement, RetrievalControls, Result
from .state_vector import StateVector


class O2AInverseForwardModel:
    """Evaluates O2 A spectra at state-vector points.

    The public contract is already the optimized inverse-model shape:
    `evaluate(x, state_vector)` mutates model settings conceptually, then runs
    the spectrum and Jacobian.  The current backend materializes that settings
    target as a copied `O2AInput`; a future native mutable backend can replace
    that implementation without changing the optimal-estimation loop.
    """

    def __init__(self, template: O2AInput, library_path: str | None = None):
        self._template = copy.deepcopy(template)
        self._library_path = library_path

    def settings_for_state(
        self,
        state: np.ndarray,
        state_vector: StateVector,
    ) -> O2AInput:
        settings = copy.deepcopy(self._template)
        state_vector.write_to(settings, state)
        return settings

    def evaluate(
        self,
        state: np.ndarray,
        state_vector: StateVector,
    ) -> ForwardEvaluation:
        with prepare(
            self.settings_for_state(state, state_vector),
            library_path=self._library_path,
        ) as prepared:
            return evaluate_prepared_reflectance(prepared, state_vector.jacobian_names)


def disamar_oe(
    *,
    inverse_model: O2AInverseForwardModel,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None = None,
) -> Result:
    """Retrieve O2 A state-vector parameters with the DISAMAR optimal estimation controls."""

    return retrieve(
        lambda state: inverse_model.evaluate(state, state_vector),
        measurement,
        state_vector,
        controls=controls or RetrievalControls.from_disamar_retrieval_specs(),
    )


def evaluate_prepared_reflectance(
    prepared: PreparedO2ABase,
    state_names: tuple[str, ...],
) -> ForwardEvaluation:
    """Evaluate reflectance and selected reflectance Jacobian columns."""

    with prepared.forward_model(jacobian=True) as spectrum:
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
        radiance_jacobian = spectrum.radiance_jacobian.copy()
        irradiance = spectrum.irradiance.copy()
        available_state_names = spectrum.jacobian_state_names

    # zdisamar returns radiance Jacobians.  Optimal estimation here operates on
    # reflectance, so K must be scaled by the same sun-normalization as the
    # spectrum:
    #
    #     R = pi * I / (mu0 * E0)
    #     dR/dx = dI/dx / (mu0 * E0 / pi).
    mu0 = math.cos(math.radians(prepared.input.geometry.solar_zenith_deg))
    reflectance_jacobian_all = (
        radiance_jacobian / ((mu0 * irradiance / math.pi)[:, None])
    )
    columns = [available_state_names.index(name) for name in state_names]
    return ForwardEvaluation(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        reflectance_jacobian=reflectance_jacobian_all[:, columns],
    )


def measurement_from_prepared(
    prepared: PreparedO2ABase,
    *,
    reflectance_variance: float,
) -> Measurement:
    """Build a synthetic reflectance measurement from a prepared truth scene."""

    with prepared.forward_model() as spectrum:
        wavelength_nm = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()
    return Measurement(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        variance=np.full(wavelength_nm.shape, reflectance_variance, dtype=np.float64),
    )
