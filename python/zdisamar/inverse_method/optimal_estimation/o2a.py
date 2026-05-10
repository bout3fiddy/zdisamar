"""O2 A inverse forward-model adapter for optimal estimation."""

import copy
from collections.abc import Callable
from dataclasses import replace
from typing import Protocol

import numpy as np

from ...forward_model.prepared import (
    O2AForwardSession,
    PreparedO2ABase,
    o2a_forward_session,
    prepare,
)
from ...output.spectrum import Spectrum
from ...quantities import (
    reflectance_jacobian_from_radiance_jacobian,
    reflectance_noise_from_sun_normalized_radiance_noise,
)
from ...types import O2AInput
from .core import retrieve
from .forward_evaluation import ForwardEvaluation
from .measurement import require_matching_wavelength_grid
from .retrieval import Measurement, Result, RetrievalControls
from .state_vector import PressureAltitudeProfile, StateVector


class PreparedForwardModel(Protocol):
    @property
    def input(self) -> O2AInput: ...

    def forward_model(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ) -> Spectrum: ...


class O2AInverseForwardModel:
    """Evaluates O2 A spectra at state-vector points.

    The public contract is already the optimized inverse-model shape:
    `evaluate(x, state_vector)` mutates model settings conceptually, then runs
    the spectrum and Jacobian.  The current backend materializes that settings
    target as a copied `O2AInput`; a future native mutable backend can replace
    that implementation without changing the optimal-estimation loop.
    """

    def __init__(
        self,
        template: O2AInput,
        library_path: str | None = None,
        forward_session: O2AForwardSession | None = None,
        use_forward_session: bool = True,
    ):
        if forward_session is not None and not use_forward_session:
            raise ValueError("forward_session requires use_forward_session=True")
        self._template = copy.deepcopy(template)
        self._library_path = library_path
        self._forward_session = forward_session
        self._use_forward_session = use_forward_session

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
        if self._forward_session is not None:
            prepared = self._forward_session.prepare(self.settings_for_state(state, state_vector))
            evaluation = evaluate_prepared_reflectance(prepared, state_vector.jacobian_names)
            return scale_reflectance_jacobian(evaluation, state_vector.jacobian_scales(state))
        with prepare(
            self.settings_for_state(state, state_vector),
            library_path=self._library_path,
        ) as prepared:
            evaluation = evaluate_prepared_reflectance(prepared, state_vector.jacobian_names)
            return scale_reflectance_jacobian(evaluation, state_vector.jacobian_scales(state))


def disamar_oe(
    *,
    inverse_model: O2AInverseForwardModel,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None = None,
) -> Result:
    """Retrieve O2 A state-vector parameters with the DISAMAR optimal estimation controls."""

    if inverse_model._forward_session is None and inverse_model._use_forward_session:
        with o2a_forward_session(
            inverse_model._template,
            library_path=inverse_model._library_path,
        ) as session:
            session_model = O2AInverseForwardModel(
                inverse_model._template,
                library_path=inverse_model._library_path,
                forward_session=session,
            )
            return _disamar_oe(
                inverse_model=session_model,
                measurement=measurement,
                state_vector=state_vector,
                controls=controls,
            )
    return _disamar_oe(
        inverse_model=inverse_model,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
    )


def _disamar_oe(
    *,
    inverse_model: O2AInverseForwardModel,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None = None,
) -> Result:
    result = retrieve(
        lambda state: inverse_model.evaluate(state, state_vector),
        measurement,
        state_vector,
        controls=controls or RetrievalControls.from_disamar_retrieval_specs(),
    )
    return attach_final_evaluation(
        replace(result, measurement=measurement),
        lambda state: inverse_model.evaluate(state, state_vector),
    )


def attach_final_evaluation(
    result: Result,
    evaluate_state: Callable[[np.ndarray], ForwardEvaluation],
) -> Result:
    """Attach the final-state model product required by OE result plots."""

    if (
        result.last_evaluation is not None
        and result.last_evaluated_state is not None
        and np.array_equal(result.state, result.last_evaluated_state)
    ):
        final_evaluation = result.last_evaluation
    else:
        final_evaluation = evaluate_state(result.state)
    return replace(
        result,
        final_evaluation=final_evaluation,
    )


def evaluate_prepared_reflectance(
    prepared: PreparedForwardModel,
    state_names: tuple[str, ...],
) -> ForwardEvaluation:
    """Evaluate reflectance and selected reflectance Jacobian columns."""

    with prepared.forward_model(jacobian=True, jacobian_state_names=state_names) as spectrum:
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
    reflectance_jacobian_all = reflectance_jacobian_from_radiance_jacobian(
        radiance_jacobian,
        irradiance,
        prepared.input.geometry.solar_mu0,
    )
    if available_state_names != state_names:
        raise ValueError("Native Jacobian state selection did not preserve requested state order")
    return ForwardEvaluation(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        reflectance_jacobian=reflectance_jacobian_all,
    )


def scale_reflectance_jacobian(
    evaluation: ForwardEvaluation,
    scales: np.ndarray,
) -> ForwardEvaluation:
    """Convert backend Jacobian columns into state-vector coordinates."""

    if evaluation.reflectance_jacobian.shape[1] != scales.size:
        raise ValueError("Jacobian scale count does not match state vector dimension")
    return ForwardEvaluation(
        wavelength_nm=evaluation.wavelength_nm,
        reflectance=evaluation.reflectance,
        reflectance_jacobian=evaluation.reflectance_jacobian * scales[None, :],
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


def pressure_altitude_profile_from_prepared(prepared: PreparedO2ABase) -> PressureAltitudeProfile:
    budget = prepared.atmospheric_budget(
        np.array([prepared.input.spectral_grid.start_nm], dtype=np.float64)
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


def pressure_altitude_profile_from_prepared_grid(
    case: O2AInput,
    *,
    library_path: str | None = None,
) -> PressureAltitudeProfile:
    """Use the prepared grid as the state-vector pressure/altitude contract."""

    with prepare(case, library_path=library_path) as prepared:
        return pressure_altitude_profile_from_prepared(prepared)


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

    require_matching_wavelength_grid(
        measurement_wavelength,
        source_wavelength,
        expected_name="measurement",
        actual_name="noise",
    )
    # The retrieval vector is reflectance, so the measurement covariance must
    # live in the same units before it enters the inverse problem.
    reflectance_noise = source_noise
    reflectance_noise = reflectance_noise_from_sun_normalized_radiance_noise(
        reflectance_noise,
        prepared.input.geometry.solar_mu0,
    )
    return Measurement(
        wavelength_nm=measurement_wavelength,
        reflectance=reflectance,
        variance=reflectance_noise**2,
    )
