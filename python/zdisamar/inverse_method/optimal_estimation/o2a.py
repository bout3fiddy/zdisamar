"""O2 A wavelength-band helpers for optimal estimation."""

import copy
from collections.abc import Callable
from dataclasses import replace

import numpy as np

from ... import rtm
from ...input.wavelength_band.o2a import O2AInput
from .core import retrieve
from .measurement import require_matching_wavelength_grid
from .retrieval import Measurement, Result, RetrievalControls
from .rtm_evaluation import RtmEvaluation
from .state_vector import PressureAltitudeProfile, StateVector


def case_for_state(
    template: O2AInput,
    state: np.ndarray,
    state_vector: StateVector,
) -> O2AInput:
    """Create a wavelength-band case for one retrieval state."""

    case = copy.deepcopy(template)
    state_vector.write_to(case, state)

    return case


def evaluate_state(
    template: O2AInput,
    state: np.ndarray,
    state_vector: StateVector,
    *,
    cache: rtm.SessionCache | None = None,
) -> RtmEvaluation:
    """Evaluate reflectance and Jacobians for one retrieval state."""

    case = case_for_state(template, state, state_vector)
    evaluation = evaluate_reflectance(
        case,
        state_vector.jacobian_names,
        cache=cache,
    )

    return scale_reflectance_jacobian(evaluation, state_vector.jacobian_scales(state))


def disamar_oe(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None = None,
    cache: rtm.SessionCache | None = None,
) -> Result:
    """Retrieve O2 A state-vector parameters with DISAMAR-style controls."""

    if cache is None:
        with rtm.SessionCache(case) as local_cache:
            return _disamar_oe(
                case=case,
                measurement=measurement,
                state_vector=state_vector,
                controls=controls,
                cache=local_cache,
            )

    return _disamar_oe(
        case=case,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
    )


def _disamar_oe(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache,
) -> Result:
    """Bind the O2 A RTM relation to the generic OE solver."""

    final_evaluate_state = _lazy_final_evaluator(case, state_vector)
    result = retrieve(
        lambda state: evaluate_state(case, state, state_vector, cache=cache),
        measurement,
        state_vector,
        controls=controls or RetrievalControls.from_disamar_retrieval_specs(),
    )
    result = replace(result, measurement=measurement)

    return attach_final_evaluation(
        result,
        final_evaluate_state,
    )


def _lazy_final_evaluator(
    case: O2AInput,
    state_vector: StateVector,
) -> Callable[[np.ndarray], RtmEvaluation]:
    """Keep a way to evaluate the final retrieval state after the run ends."""

    template = copy.deepcopy(case)

    def evaluate_with_fresh_cache(state: np.ndarray) -> RtmEvaluation:

        return evaluate_state(template, state, state_vector)

    return evaluate_with_fresh_cache


def attach_final_evaluation(
    result: Result,
    evaluate_state: Callable[[np.ndarray], RtmEvaluation],
) -> Result:
    """Attach the final-state spectrum needed by OE result plots.

    If the last iteration already evaluated the accepted state, reuse that
    spectrum.  Otherwise store the final state and evaluate it only if a caller
    asks for plots or residuals.
    """

    if (
        result.last_evaluation is not None
        and result.last_evaluated_state is not None
        and np.array_equal(result.state, result.last_evaluated_state)
    ):
        return replace(
            result,
            final_evaluation=result.last_evaluation,
            _final_evaluation_factory=None,
        )

    final_state = np.array(result.state, copy=True)

    return replace(
        result,
        final_evaluation=None,
        _final_evaluation_factory=lambda: evaluate_state(final_state),
    )


def evaluate_reflectance(
    case: O2AInput,
    state_names: tuple[str, ...],
    *,
    cache: rtm.SessionCache | None = None,
) -> RtmEvaluation:
    """Evaluate reflectance and selected reflectance Jacobian columns."""

    spectrum = rtm.spectrum(
        case,
        cache=cache,
        jacobian=True,
        jacobian_state_names=state_names,
    )
    wavelength_nm = spectrum.wavelength_nm.copy()
    reflectance = spectrum.reflectance.copy()
    radiance_jacobian = spectrum.radiance_jacobian.copy()
    irradiance = spectrum.irradiance.copy()
    available_state_names = spectrum.jacobian_state_names

    reflectance_jacobian_all = rtm.reflectance_jacobian_from_radiance_jacobian(
        radiance_jacobian,
        irradiance,
        case.geometry.solar_mu0,
    )

    if available_state_names != state_names:
        raise ValueError("RTM Jacobian state selection did not preserve requested state order")

    return RtmEvaluation(
        wavelength_nm=wavelength_nm,
        reflectance=reflectance,
        reflectance_jacobian=reflectance_jacobian_all,
    )


def scale_reflectance_jacobian(
    evaluation: RtmEvaluation,
    scales: np.ndarray,
) -> RtmEvaluation:
    """Scale reflectance Jacobians into the retrieval variables."""

    if evaluation.reflectance_jacobian.shape[1] != scales.size:
        raise ValueError("Jacobian scale count does not match state vector dimension")

    return RtmEvaluation(
        wavelength_nm=evaluation.wavelength_nm,
        reflectance=evaluation.reflectance,
        reflectance_jacobian=evaluation.reflectance_jacobian * scales[None, :],
    )


def measurement_from_case(
    case: O2AInput,
    *,
    reflectance_variance: float,
) -> Measurement:
    """Build a synthetic reflectance measurement from a truth case."""

    spectrum = rtm.spectrum(case)

    return Measurement(
        wavelength_nm=spectrum.wavelength_nm.copy(),
        reflectance=spectrum.reflectance.copy(),
        variance=np.full(spectrum.wavelength_nm.shape, reflectance_variance, dtype=np.float64),
    )


def pressure_altitude_profile_from_case(case: O2AInput) -> PressureAltitudeProfile:
    """Read the pressure-altitude relation from the RTM atmospheric grid."""

    budget = rtm.atmospheric_budget(
        case,
        np.array([case.spectral_grid.start_nm], dtype=np.float64),
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
    case: O2AInput,
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

    spectrum = rtm.spectrum(case)
    measurement_wavelength = spectrum.wavelength_nm.copy()
    reflectance = spectrum.reflectance.copy()

    require_matching_wavelength_grid(
        measurement_wavelength,
        source_wavelength,
        expected_name="measurement",
        actual_name="noise",
    )
    reflectance_noise = rtm.reflectance_noise_from_sun_normalized_radiance_noise(
        source_noise,
        case.geometry.solar_mu0,
    )

    return Measurement(
        wavelength_nm=measurement_wavelength,
        reflectance=reflectance,
        variance=reflectance_noise**2,
    )
