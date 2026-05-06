"""O2 A inverse forward-model adapter for optimal estimation."""

from __future__ import annotations

import copy
import math

import numpy as np

from ...prepared import PreparedO2ABase, prepare
from ...types import O2AInput
from .core import retrieve
from .forward_evaluation import ForwardEvaluation
from .retrieval import Measurement, Result, RetrievalControls
from .state_vector import PressureAltitudeProfile, StateVector


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
    reflectance_jacobian_all = radiance_jacobian / ((mu0 * irradiance / math.pi)[:, None])
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


def pressure_altitude_profile_from_prepared_grid(
    case: O2AInput,
    *,
    library_path: str | None = None,
) -> PressureAltitudeProfile:
    """Use the prepared grid as the state-vector pressure/altitude contract."""

    with prepare(case, library_path=library_path) as prepared:
        budget = prepared.atmospheric_budget(
            np.array([case.spectral_grid.start_nm], dtype=np.float64)
        )
        table = budget.table

    levels_by_pressure: dict[float, float] = {}
    for row in table:
        levels_by_pressure[round(float(row["top_pressure_hpa"]), 12)] = float(
            row["top_altitude_km"]
        )
        levels_by_pressure[round(float(row["bottom_pressure_hpa"]), 12)] = float(
            row["bottom_altitude_km"]
        )
    levels = sorted((altitude, pressure) for pressure, altitude in levels_by_pressure.items())
    return PressureAltitudeProfile(
        altitude_km=np.array([altitude for altitude, _pressure in levels]),
        pressure_hpa=np.array([pressure for _altitude, pressure in levels]),
    )


def measurement_from_sun_normalized_radiance_noise(
    prepared: PreparedO2ABase,
    *,
    wavelength_nm: np.ndarray,
    sun_normalized_radiance_noise: np.ndarray,
) -> Measurement:
    """Put measurement noise in the same reflectance space as the retrieval."""

    source_wavelength = np.asarray(wavelength_nm, dtype=np.float64)
    source_noise = np.asarray(sun_normalized_radiance_noise, dtype=np.float64)
    if source_wavelength.ndim != 1 or source_noise.ndim != 1:
        raise ValueError("noise wavelength and values must be one-dimensional")
    if source_wavelength.size != source_noise.size:
        raise ValueError("noise wavelength and values must have the same length")
    if source_wavelength.size == 0:
        raise ValueError("noise reference must contain at least one sample")
    if not np.all(np.isfinite(source_wavelength)) or not np.all(np.isfinite(source_noise)):
        raise ValueError("noise wavelength and values must be finite")
    if np.any(source_noise <= 0.0):
        raise ValueError("sun-normalized radiance noise must be positive")

    with prepared.forward_model() as spectrum:
        measurement_wavelength = spectrum.wavelength_nm.copy()
        reflectance = spectrum.reflectance.copy()

    # The retrieval vector is reflectance, so the measurement covariance must
    # live in the same units before it enters the inverse problem.
    mu0 = math.cos(math.radians(prepared.input.geometry.solar_zenith_deg))
    reflectance_noise = np.interp(
        measurement_wavelength,
        source_wavelength,
        source_noise,
    ) * (math.pi / mu0)
    return Measurement(
        wavelength_nm=measurement_wavelength,
        reflectance=reflectance,
        variance=reflectance_noise**2,
    )
