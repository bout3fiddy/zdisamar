"""O2 A wavelength-band helpers for optimal estimation."""

import copy
import math
from array import array
from collections.abc import Callable, Mapping, Sequence
from dataclasses import replace

from ... import rtm
from ...input.wavelength_band.o2a import O2AInput
from .measurement import require_matching_wavelength_grid
from .retrieval import FastCorrection, Iteration, Measurement, Result, RetrievalControls
from .rtm_evaluation import RtmEvaluation
from .state_vector import PressureAltitudeProfile, StateVector


def case_for_state(
    template: O2AInput,
    state: Sequence[float],
    state_vector: StateVector,
) -> O2AInput:
    """Create a wavelength-band case for one retrieval state."""

    case = copy.copy(template)
    case.aerosol = copy.copy(template.aerosol)
    case.aerosol.placement = copy.copy(template.aerosol.placement)
    case.atmosphere = copy.copy(template.atmosphere)
    case.atmosphere.intervals = [copy.copy(interval) for interval in template.atmosphere.intervals]
    case.surface = copy.copy(template.surface)
    state_vector.write_to(case, state)

    return case


def evaluate_state(
    template: O2AInput,
    state: Sequence[float],
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
                load_case=False,
            )

    return _disamar_oe(
        case=case,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        load_case=True,
    )


def disamar_oe_fast(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None = None,
    cache: rtm.SessionCache | None = None,
) -> Result:
    """Retrieve with fast-mode convergence followed by one full-physics correction."""

    fast_case = case.with_fast_mode()
    active_controls = controls or RetrievalControls.from_disamar_retrieval_specs()

    if cache is None:
        with rtm.SessionCache(fast_case) as local_cache:
            return run_fast_accurate_oe(
                case=case,
                fast_case=fast_case,
                measurement=measurement,
                state_vector=state_vector,
                controls=active_controls,
                cache=local_cache,
                fast_case_loaded=True,
            )

    return run_fast_accurate_oe(
        case=case,
        fast_case=fast_case,
        measurement=measurement,
        state_vector=state_vector,
        controls=active_controls,
        cache=cache,
        fast_case_loaded=False,
    )


def run_fast_accurate_oe(
    *,
    case: O2AInput,
    fast_case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls,
    cache: rtm.SessionCache,
    fast_case_loaded: bool,
) -> Result:
    """Run the two-stage fast-accurate O2 A retrieval in one cache."""

    fast_result = _disamar_oe(
        case=fast_case,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        load_case=not fast_case_loaded,
    )
    corrected_state_vector = state_vector_with_initial(state_vector, fast_result.state)
    full_result = _disamar_oe(
        case=case,
        measurement=measurement,
        state_vector=corrected_state_vector,
        controls=full_correction_controls(controls),
        cache=cache,
        load_case=True,
    )

    return combine_fast_accurate_result(fast_result, full_result)


def state_vector_with_initial(
    state_vector: StateVector,
    initial_state: Sequence[float],
) -> StateVector:
    """Use one retrieved state as the next solver initial state without moving the prior."""

    if len(initial_state) != len(state_vector.parameters):
        raise ValueError("initial state length does not match state vector")

    parameters = []

    for parameter, value in zip(state_vector.parameters, initial_state, strict=True):
        updated = copy.copy(parameter)
        object.__setattr__(updated, "initial", float(value))
        parameters.append(updated)

    return StateVector(tuple(parameters))


def full_correction_controls(controls: RetrievalControls) -> RetrievalControls:
    """Keep OE damping settings while limiting the full-physics stage to one update."""

    return replace(controls, max_iterations=1)


def combine_fast_accurate_result(fast_result: Result, full_result: Result) -> Result:
    """Expose the full-physics corrected state with fast-stage convergence semantics."""

    full_correction = None
    combined_history = fast_result.history

    if full_result.history:
        full_correction = replace(
            full_result.history[-1],
            index=fast_result.iterations + full_result.history[-1].index,
        )
        combined_history = (*fast_result.history, full_correction)

    correction_convergence = (
        math.nan if full_correction is None else float(full_correction.state_vector_convergence)
    )
    diagnostics = FastCorrection(
        fast_iterations=fast_result.iterations,
        fast_converged=fast_result.converged,
        fast_state=tuple(float(value) for value in fast_result.state),
        full_correction=full_correction,
        full_correction_converged=full_result.converged,
        full_correction_state_vector_convergence=correction_convergence,
    )

    return Result(
        state_names=full_result.state_names,
        state=full_result.state,
        iterations=fast_result.iterations + full_result.iterations,
        converged=fast_result.converged,
        history=combined_history,
        posterior_covariance=full_result.posterior_covariance,
        averaging_kernel=full_result.averaging_kernel,
        measurement=full_result.measurement,
        final_evaluation=object.__getattribute__(full_result, "final_evaluation"),
        last_evaluated_state=full_result.last_evaluated_state,
        last_evaluation=full_result.last_evaluation,
        initial_state=fast_result.initial_state,
        fast_correction=diagnostics,
        _final_evaluation_factory=object.__getattribute__(
            full_result,
            "_final_evaluation_factory",
        ),
    )


def _disamar_oe(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache,
    load_case: bool = True,
) -> Result:
    """Bind the O2 A RTM relation to the generic OE solver."""

    final_evaluate_state = _lazy_final_evaluator(case, state_vector)
    active_controls = controls or RetrievalControls.from_disamar_retrieval_specs()

    if load_case and not cache.has_loaded_case(case):
        cache.load(case, copy_case=False)

    raw = cache._handle.optimal_estimation(  # noqa: SLF001
        measurement=measurement,
        state_vector=state_vector,
        controls=active_controls,
    )
    result = _result_from_native(raw, state_vector, measurement)

    return attach_final_evaluation(
        result,
        final_evaluate_state,
    )


def _lazy_final_evaluator(
    case: O2AInput,
    state_vector: StateVector,
) -> Callable[[Sequence[float]], RtmEvaluation]:
    """Keep a way to evaluate the final retrieval state after the run ends."""

    template = copy.deepcopy(case)

    def evaluate_with_fresh_cache(state: Sequence[float]) -> RtmEvaluation:

        return evaluate_state(template, state, state_vector)

    return evaluate_with_fresh_cache


def attach_final_evaluation(
    result: Result,
    evaluate_state: Callable[[Sequence[float]], RtmEvaluation],
) -> Result:
    """Attach the final-state spectrum needed by OE result plots.

    If the last iteration already evaluated the accepted state, reuse that
    spectrum.  Otherwise store the final state and evaluate it only if a caller
    asks for plots or residuals.
    """

    if (
        result.last_evaluation is not None
        and result.last_evaluated_state is not None
        and tuple(result.state) == tuple(result.last_evaluated_state)
    ):
        return replace(
            result,
            final_evaluation=result.last_evaluation,
            _final_evaluation_factory=None,
        )

    final_state = tuple(result.state)

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
        include_case=False,
    )
    wavelength_nm = spectrum.wavelength_nm
    reflectance = spectrum.reflectance
    radiance_jacobian = spectrum.radiance_jacobian
    irradiance = spectrum.irradiance
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
    scales: Sequence[float],
) -> RtmEvaluation:
    """Scale reflectance Jacobians into the retrieval variables."""

    scale_values = tuple(float(value) for value in scales)
    scaled_rows = []

    for row in evaluation.reflectance_jacobian:
        if len(row) != len(scale_values):
            raise ValueError("Jacobian scale count does not match state vector dimension")

        scaled_rows.append(
            array(
                "d",
                (float(value) * scale for value, scale in zip(row, scale_values, strict=True)),
            )
        )

    return RtmEvaluation(
        wavelength_nm=evaluation.wavelength_nm,
        reflectance=evaluation.reflectance,
        reflectance_jacobian=tuple(scaled_rows),
    )


def measurement_from_case(
    case: O2AInput,
    *,
    reflectance_variance: float,
) -> Measurement:
    """Build a synthetic reflectance measurement from a truth case."""

    spectrum = rtm.spectrum(case)

    return Measurement(
        wavelength_nm=array("d", spectrum.wavelength_nm),
        reflectance=array("d", spectrum.reflectance),
        variance=array("d", (float(reflectance_variance) for _ in spectrum.wavelength_nm)),
    )


def pressure_altitude_profile_from_case(case: O2AInput) -> PressureAltitudeProfile:
    """Read the pressure-altitude relation from the RTM atmospheric grid."""

    budget = rtm.atmospheric_budget(
        case,
        [case.spectral_grid.start_nm],
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
        altitude_km=tuple(altitude for altitude, _pressure in levels),
        pressure_hpa=tuple(pressure for _altitude, pressure in levels),
    )


def measurement_from_sun_normalized_radiance_noise(
    case: O2AInput,
    *,
    wavelength_nm: Sequence[float],
    sun_normalized_radiance_noise: Sequence[float],
) -> Measurement:
    """Put measurement noise in the same reflectance space as the retrieval."""

    source_wavelength = array("d", (float(value) for value in wavelength_nm))
    source_noise = array("d", (float(value) for value in sun_normalized_radiance_noise))

    if len(source_wavelength) != len(source_noise):
        raise ValueError("noise wavelength and values must have the same length")

    if not source_wavelength:
        raise ValueError("noise reference must contain at least one sample")

    if any(not math.isfinite(value) for value in source_wavelength) or any(
        not math.isfinite(value) for value in source_noise
    ):
        raise ValueError("noise wavelength and values must be finite")

    if any(value <= 0.0 for value in source_noise):
        raise ValueError("sun-normalized radiance noise must be positive")

    spectrum = rtm.spectrum(case)
    measurement_wavelength = array("d", spectrum.wavelength_nm)
    reflectance = array("d", spectrum.reflectance)

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
        variance=array("d", (value * value for value in reflectance_noise)),
    )


def _result_from_native(
    raw: Mapping[str, object],
    state_vector: StateVector,
    measurement: Measurement,
) -> Result:
    """Translate the native retrieval output without recreating Python algebra arrays."""

    state_count = _native_int(raw, "state_count")
    iteration_count = _native_int(raw, "iteration_count")
    history_state = _native_floats(raw, "history_state")
    history_chi2 = _native_floats(raw, "history_chi2")
    history_chi2_reflectance = _native_floats(raw, "history_chi2_reflectance")
    history_chi2_state_vector = _native_floats(raw, "history_chi2_state_vector")
    history_state_vector_convergence = _native_floats(
        raw,
        "history_state_vector_convergence",
    )
    history_snr_normal = _native_ints(raw, "history_snr_normal")
    state_names = state_vector.names

    if state_count != len(state_names):
        raise RuntimeError("native optimal-estimation state count does not match request")

    history = tuple(
        Iteration(
            index=index + 1,
            state=history_state[index * state_count : (index + 1) * state_count],
            chi2=history_chi2[index],
            chi2_reflectance=history_chi2_reflectance[index],
            chi2_state_vector=history_chi2_state_vector[index],
            state_vector_convergence=history_state_vector_convergence[index],
            snr_normal=bool(history_snr_normal[index]),
        )
        for index in range(iteration_count)
    )

    return Result(
        state_names=state_names,
        state=_native_floats(raw, "state"),
        iterations=iteration_count,
        converged=_native_bool(raw, "converged"),
        history=history,
        posterior_covariance=_matrix_rows(
            _native_floats(raw, "posterior_covariance"),
            state_count,
        ),
        averaging_kernel=_matrix_rows(_native_floats(raw, "averaging_kernel"), state_count),
        measurement=measurement,
        initial_state=_native_floats(raw, "initial_state"),
    )


def _native_int(raw: Mapping[str, object], key: str) -> int:

    value = raw[key]

    if not isinstance(value, int | float | str):
        raise RuntimeError(f"native optimal-estimation field is not an integer: {key}")

    return int(value)


def _native_bool(raw: Mapping[str, object], key: str) -> bool:

    return bool(raw[key])


def _native_sequence(raw: Mapping[str, object], key: str) -> Sequence[object]:

    values = raw[key]

    if not isinstance(values, Sequence):
        raise RuntimeError(f"native optimal-estimation field is not a sequence: {key}")

    return values


def _native_floats(raw: Mapping[str, object], key: str) -> tuple[float, ...]:

    return tuple(float(_native_number(value, key)) for value in _native_sequence(raw, key))


def _native_ints(raw: Mapping[str, object], key: str) -> tuple[int, ...]:

    return tuple(int(_native_number(value, key)) for value in _native_sequence(raw, key))


def _native_number(value: object, key: str) -> int | float | str:

    if not isinstance(value, int | float | str):
        raise RuntimeError(f"native optimal-estimation field is not numeric: {key}")

    return value


def _matrix_rows(
    flat: tuple[float, ...],
    state_count: int,
) -> tuple[tuple[float, ...], ...]:

    return tuple(
        flat[index * state_count : (index + 1) * state_count] for index in range(state_count)
    )
