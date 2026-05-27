"""O2 A wavelength-band helpers for optimal estimation."""

import copy
import math
from array import array
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, replace

from ... import rtm
from ...input.instrument import SpectralGrid
from ...input.wavelength_band.o2a import O2AInput
from ...input.wavelength_band.optimisation import (
    FastModeFastStageSampling,
    measurement_indices_for_wavelengths,
)
from ...output.tables import AtmosphericBudget
from .measurement import require_matching_wavelength_grid
from .retrieval import FastCorrection, Iteration, Measurement, Result, RetrievalControls
from .rtm_evaluation import RtmEvaluation
from .state_vector import StateName, StateVector
from .state_vector.pressure_altitude_profile import PressureAltitudeProfile

FULL_CORRECTION_WINDOW_NM = (762.0, 768.0)


@dataclass(frozen=True)
class BatchResult:
    """Final-state summaries from a native batch of OE starts."""

    state_names: tuple[str, ...]
    state: tuple[tuple[float, ...], ...]
    iterations: tuple[int, ...]
    converged: tuple[bool, ...]
    measurement: Measurement
    fast_stage_iterations: tuple[int, ...] | None = None
    fast_stage_converged: tuple[bool, ...] | None = None
    full_correction_iterations: tuple[int, ...] | None = None
    full_correction_converged: tuple[bool, ...] | None = None

    def value(self, name: str) -> tuple[float, ...]:
        """Return one retrieved state column by name."""

        try:
            index = self.state_names.index(name)
        except ValueError as exc:
            raise KeyError(f"unknown state variable: {name}") from exc

        return tuple(row[index] for row in self.state)


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

    resolved_state_vector = resolved_state_vector_for_case(template, state_vector)
    case = case_for_state(template, state, resolved_state_vector)
    evaluation = evaluate_reflectance(
        case,
        resolved_state_vector.jacobian_names,
        cache=cache,
    )

    return scale_reflectance_jacobian(evaluation, resolved_state_vector.jacobian_scales(state))


def retrieve(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None = None,
    cache: rtm.SessionCache | None = None,
) -> Result:
    """Retrieve O2 A state-vector parameters."""

    _require_aerosol_retrieval_compatible(case)
    active_controls = retrieval_controls_for_case(case, controls)

    if case.optimisation.fastmode.enabled:
        fast_case, fast_measurement = fast_stage_retrieval_inputs(case, measurement)

        if cache is None:
            with rtm.SessionCache() as local_cache:
                local_cache.load(fast_case, copy_case=False)
                resolved_state_vector = resolved_state_vector_for_loaded_case(
                    fast_case,
                    state_vector,
                    local_cache,
                )

                result = run_fastmode_oe(
                    case=case,
                    measurement=measurement,
                    fast_case=fast_case,
                    fast_measurement=fast_measurement,
                    state_vector=resolved_state_vector,
                    controls=active_controls,
                    cache=local_cache,
                    fast_case_loaded=True,
                    preserve_fast_cache=False,
                )

                return attach_diagnosis(
                    result,
                    case=case,
                    measurement=measurement,
                    state_vector=state_vector,
                    controls=active_controls,
                )

        if not cache.has_loaded_case(fast_case):
            cache.load(fast_case, copy_case=False)

        resolved_state_vector = resolved_state_vector_for_loaded_case(
            fast_case,
            state_vector,
            cache,
        )

        result = run_fastmode_oe(
            case=case,
            measurement=measurement,
            fast_case=fast_case,
            fast_measurement=fast_measurement,
            state_vector=resolved_state_vector,
            controls=active_controls,
            cache=cache,
            fast_case_loaded=True,
            preserve_fast_cache=True,
        )

        return attach_diagnosis(
            result,
            case=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=active_controls,
        )

    resolved_state_vector = resolved_state_vector_for_case(case, state_vector)

    if cache is None:
        with rtm.SessionCache() as local_cache:
            local_cache.load(case, copy_case=False)
            resolved_state_vector = resolved_state_vector_for_loaded_case(
                case,
                state_vector,
                local_cache,
            )
            result = run_native_retrieval(
                case=case,
                measurement=measurement,
                state_vector=resolved_state_vector,
                controls=active_controls,
                cache=local_cache,
                load_case=False,
            )

            return attach_diagnosis(
                result,
                case=case,
                measurement=measurement,
                state_vector=state_vector,
                controls=active_controls,
            )

    result = run_native_retrieval(
        case=case,
        measurement=measurement,
        state_vector=resolved_state_vector,
        controls=active_controls,
        cache=cache,
        load_case=True,
    )

    return attach_diagnosis(
        result,
        case=case,
        measurement=measurement,
        state_vector=state_vector,
        controls=active_controls,
    )


def retrieve_many(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vectors: Sequence[StateVector],
    controls: RetrievalControls | None = None,
    cache: rtm.SessionCache | None = None,
    batch_workers: int = 1,
) -> BatchResult:
    """Retrieve many O2 A starts while reusing one native prepared session."""

    _require_aerosol_retrieval_compatible(case)
    active_controls = retrieval_controls_for_case(case, controls)
    state_vector_batch = tuple(state_vectors)

    if not state_vector_batch:
        raise ValueError("state_vectors must not be empty")

    if case.optimisation.fastmode.enabled:
        final_correction = case.optimisation.fastmode.oe.final_correction
        fast_case, fast_measurement = fast_stage_retrieval_inputs(case, measurement)

        if cache is None:
            with rtm.SessionCache() as local_cache:
                local_cache.load(fast_case, copy_case=False)

                resolved_template = resolved_state_vector_for_loaded_case(
                    fast_case,
                    state_vector_batch[0],
                    local_cache,
                )

                if not final_correction.enabled:
                    return run_native_retrieval_batch(
                        case=fast_case,
                        measurement=fast_measurement,
                        state_vectors=state_vector_batch,
                        resolved_template=resolved_template,
                        controls=active_controls,
                        cache=local_cache,
                        load_case=False,
                        batch_workers=batch_workers,
                    )

                return run_native_fastmode_retrieval_batch(
                    case=case,
                    measurement=measurement,
                    fast_measurement=fast_measurement,
                    state_vectors=state_vector_batch,
                    resolved_template=resolved_template,
                    controls=active_controls,
                    cache=local_cache,
                    batch_workers=batch_workers,
                )

        if not cache.has_loaded_case(fast_case):
            cache.load(fast_case, copy_case=False)

        resolved_template = resolved_state_vector_for_loaded_case(
            fast_case,
            state_vector_batch[0],
            cache,
        )

        if not final_correction.enabled:
            return run_native_retrieval_batch(
                case=fast_case,
                measurement=fast_measurement,
                state_vectors=state_vector_batch,
                resolved_template=resolved_template,
                controls=active_controls,
                cache=cache,
                load_case=False,
                batch_workers=batch_workers,
            )

        return run_native_fastmode_retrieval_batch(
            case=case,
            measurement=measurement,
            fast_measurement=fast_measurement,
            state_vectors=state_vector_batch,
            resolved_template=resolved_template,
            controls=active_controls,
            cache=cache,
            batch_workers=batch_workers,
        )

    if cache is None:
        with rtm.SessionCache() as local_cache:
            local_cache.load(case, copy_case=False)
            resolved_template = resolved_state_vector_for_loaded_case(
                case,
                state_vector_batch[0],
                local_cache,
            )

            return run_native_retrieval_batch(
                case=case,
                measurement=measurement,
                state_vectors=state_vector_batch,
                resolved_template=resolved_template,
                controls=active_controls,
                cache=local_cache,
                load_case=False,
                batch_workers=batch_workers,
            )

    resolved_template = resolved_state_vector_for_case(case, state_vector_batch[0])

    return run_native_retrieval_batch(
        case=case,
        measurement=measurement,
        state_vectors=state_vector_batch,
        resolved_template=resolved_template,
        controls=active_controls,
        cache=cache,
        load_case=True,
        batch_workers=batch_workers,
    )


def retrieval_controls_for_case(
    case: O2AInput,
    controls: RetrievalControls | None,
) -> RetrievalControls:
    """Return caller controls or the active case-owned OE defaults."""

    if controls is not None:
        return controls

    if not case.optimisation.fastmode.enabled:
        return RetrievalControls.from_disamar_retrieval_specs()

    fastmode_controls = case.optimisation.fastmode.oe.controls

    return RetrievalControls(
        max_iterations=fastmode_controls.max_iterations,
        state_vector_convergence_threshold=fastmode_controls.state_vector_convergence_threshold,
        max_change_transformed_state=fastmode_controls.max_change_transformed_state,
    )


def run_fastmode_oe(
    *,
    case: O2AInput,
    measurement: Measurement,
    fast_case: O2AInput,
    fast_measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls,
    cache: rtm.SessionCache,
    fast_case_loaded: bool,
    preserve_fast_cache: bool = False,
) -> Result:
    """Run an O2 A fastmode retrieval in one session cache."""

    fast_result = run_native_retrieval(
        case=fast_case,
        measurement=fast_measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        load_case=not fast_case_loaded,
    )

    final_correction = case.optimisation.fastmode.oe.final_correction

    if not final_correction.enabled:
        return fast_result

    corrected_state_vector = state_vector_with_initial(state_vector, fast_result.state)
    full_case = full_physics_case(case)
    full_state_case = case_for_state(full_case, fast_result.state, state_vector)
    correction_wavelengths_nm = final_correction.resolved_wavelengths(measurement.wavelength_nm)
    correction_measurement = full_correction_measurement(
        measurement,
        wavelengths_nm=correction_wavelengths_nm,
        uncertainty_scale=final_correction.uncertainty_scale,
    )
    correction_case = full_correction_case(full_state_case, correction_measurement)

    if preserve_fast_cache:
        full_result = run_full_physics_correction_in_temporary_cache(
            case=correction_case,
            measurement=correction_measurement,
            state_vector=corrected_state_vector,
            controls=controls,
            result_measurement=measurement,
            final_evaluation_case=full_case,
        )
    else:
        full_result = run_full_physics_correction(
            case=correction_case,
            measurement=correction_measurement,
            state_vector=corrected_state_vector,
            controls=controls,
            cache=cache,
            result_measurement=measurement,
            final_evaluation_case=full_case,
        )

    return combine_fastmode_correction_result(fast_result, full_result)


def run_native_fastmode_retrieval_batch(
    *,
    case: O2AInput,
    measurement: Measurement,
    fast_measurement: Measurement,
    state_vectors: Sequence[StateVector],
    resolved_template: StateVector,
    controls: RetrievalControls,
    cache: rtm.SessionCache,
    batch_workers: int,
) -> BatchResult:
    """Run fast-stage and sparse correction starts inside one native handoff."""

    final_correction = case.optimisation.fastmode.oe.final_correction
    full_case = full_physics_case(case)
    correction_wavelengths_nm = final_correction.resolved_wavelengths(measurement.wavelength_nm)
    correction_measurement = full_correction_measurement(
        measurement,
        wavelengths_nm=correction_wavelengths_nm,
        uncertainty_scale=final_correction.uncertainty_scale,
    )
    correction_case = full_correction_case(full_case, correction_measurement)
    correction_controls = replace(controls, max_iterations=1)
    initial_rows, prior_rows = batch_state_rows(resolved_template, state_vectors)

    with rtm.SessionCache() as correction_cache:
        correction_cache.load(correction_case, copy_case=False)

        correction_template = resolved_state_vector_for_loaded_case(
            correction_case,
            state_vectors[0],
            correction_cache,
        )

        if batch_workers == 1:
            cache.warm_optimal_estimation(resolved_template.jacobian_names)
            correction_cache.warm_optimal_estimation(correction_template.jacobian_names)

        raw = cache._handle.optimal_estimation_fastmode_batch(  # noqa: SLF001
            correction_handle=correction_cache._handle,  # noqa: SLF001
            measurement=fast_measurement,
            correction_measurement=correction_measurement,
            state_vector=resolved_template,
            correction_state_vector=correction_template,
            initial_states=initial_rows,
            prior_states=prior_rows,
            controls=controls,
            correction_controls=correction_controls,
            batch_workers=batch_workers,
        )

    state_count = int(raw["state_count"])
    states = tuple(
        tuple(float(value) for value in raw["state"][offset : offset + state_count])
        for offset in range(0, len(raw["state"]), state_count)
    )

    return BatchResult(
        state_names=resolved_template.names,
        state=states,
        iterations=tuple(int(value) for value in raw["iteration_count"]),
        converged=tuple(bool(value) for value in raw["converged"]),
        measurement=measurement,
        fast_stage_iterations=tuple(int(value) for value in raw["fast_stage_iteration_count"]),
        fast_stage_converged=tuple(bool(value) for value in raw["fast_stage_converged"]),
        full_correction_iterations=tuple(
            int(value) for value in raw["full_correction_iteration_count"]
        ),
        full_correction_converged=tuple(bool(value) for value in raw["full_correction_converged"]),
    )


def run_fastmode_correction_batch(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vectors: Sequence[StateVector],
    fast_batch: BatchResult,
    controls: RetrievalControls,
    batch_workers: int,
) -> BatchResult:
    """Apply the sparse full-physics correction to a native fast-stage batch."""

    final_correction = case.optimisation.fastmode.oe.final_correction
    full_case = full_physics_case(case)
    correction_wavelengths_nm = final_correction.resolved_wavelengths(measurement.wavelength_nm)
    correction_measurement = full_correction_measurement(
        measurement,
        wavelengths_nm=correction_wavelengths_nm,
        uncertainty_scale=final_correction.uncertainty_scale,
    )
    correction_case = full_correction_case(full_case, correction_measurement)
    corrected_state_vectors = tuple(
        state_vector_with_initial(state_vector, fast_state)
        for state_vector, fast_state in zip(state_vectors, fast_batch.state, strict=True)
    )
    correction_controls = replace(controls, max_iterations=1)

    with rtm.SessionCache() as correction_cache:
        correction_cache.load(correction_case, copy_case=False)

        correction_template = resolved_state_vector_for_loaded_case(
            correction_case,
            corrected_state_vectors[0],
            correction_cache,
        )
        correction_batch = run_native_retrieval_batch(
            case=correction_case,
            measurement=correction_measurement,
            state_vectors=corrected_state_vectors,
            resolved_template=correction_template,
            controls=correction_controls,
            cache=correction_cache,
            load_case=False,
            batch_workers=batch_workers,
        )

    return BatchResult(
        state_names=correction_batch.state_names,
        state=correction_batch.state,
        iterations=tuple(
            fast_iterations + correction_iterations
            for fast_iterations, correction_iterations in zip(
                fast_batch.iterations,
                correction_batch.iterations,
                strict=True,
            )
        ),
        converged=fast_batch.converged,
        measurement=measurement,
        fast_stage_iterations=fast_batch.iterations,
        fast_stage_converged=fast_batch.converged,
        full_correction_iterations=correction_batch.iterations,
        full_correction_converged=correction_batch.converged,
    )


def fast_stage_retrieval_inputs(
    case: O2AInput,
    measurement: Measurement,
) -> tuple[O2AInput, Measurement]:
    """Return the case and measurement used by the fast OE stage."""

    sampling = case.optimisation.fastmode.oe.fast_stage_sampling

    if not sampling.enabled:
        return case, measurement

    fast_measurement = fast_stage_measurement(measurement, sampling=sampling)
    fast_case = case_on_measurement_grid(case, fast_measurement)

    return fast_case, fast_measurement


def fast_stage_measurement(
    measurement: Measurement,
    *,
    sampling: FastModeFastStageSampling,
) -> Measurement:
    """Apply the case-owned sparse wavelength selection to the fast OE vector."""

    wavelengths_nm = sampling.resolved_wavelengths(measurement.wavelength_nm)

    return measurement_on_wavelengths(
        measurement,
        wavelengths_nm=wavelengths_nm,
        uncertainty_scale=sampling.uncertainty_scale,
        label="fastmode fast-stage wavelengths",
    )


def run_full_physics_correction(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls,
    cache: rtm.SessionCache,
    result_measurement: Measurement | None = None,
    final_evaluation_case: O2AInput | None = None,
) -> Result:
    """Apply one full-physics native correction for an already converged fast state."""

    cache.load(case, copy_case=False)
    raw = cache._handle.optimal_estimation_correction(  # noqa: SLF001
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
    )

    return attach_final_evaluation(
        _result_from_native(raw, state_vector, result_measurement or measurement),
        _lazy_final_evaluator(final_evaluation_case or case, state_vector),
    )


def run_full_physics_correction_in_temporary_cache(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls,
    result_measurement: Measurement | None = None,
    final_evaluation_case: O2AInput | None = None,
) -> Result:
    """Run final correction without replacing a caller-owned fast-stage cache."""

    with rtm.SessionCache() as correction_cache:
        return run_full_physics_correction(
            case=case,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=correction_cache,
            result_measurement=result_measurement,
            final_evaluation_case=final_evaluation_case,
        )


def full_physics_case(case: O2AInput) -> O2AInput:
    """Return the same physical case with fastmode disabled."""

    full_case = copy.deepcopy(case)
    full_case.optimisation.fastmode.enabled = False

    return full_case


def full_correction_measurement(
    measurement: Measurement,
    window_nm: tuple[float, float] = FULL_CORRECTION_WINDOW_NM,
    wavelengths_nm: Sequence[float] | None = None,
    uncertainty_scale: float | None = None,
) -> Measurement:
    """Retain the O2 A wavelengths used by the final full-physics correction."""

    if wavelengths_nm is None:
        start_nm, end_nm = window_nm
        wavelengths_nm = tuple(
            float(wavelength_nm)
            for wavelength_nm in measurement.wavelength_nm
            if start_nm <= float(wavelength_nm) <= end_nm
        )

    return measurement_on_wavelengths(
        measurement,
        wavelengths_nm=wavelengths_nm,
        uncertainty_scale=uncertainty_scale,
        label="full-physics correction wavelengths",
    )


def measurement_on_wavelengths(
    measurement: Measurement,
    *,
    wavelengths_nm: Sequence[float],
    uncertainty_scale: float | None,
    label: str,
) -> Measurement:
    """Retain selected wavelengths and scale SNR for sparse OE vectors."""

    retained_indices = measurement_indices_for_wavelengths(
        measurement.wavelength_nm,
        wavelengths_nm,
        label=label,
    )

    if len(retained_indices) < 2:
        raise ValueError(f"{label} retained fewer than two wavelengths")

    retained_uncertainty_scale = (
        math.sqrt(len(retained_indices) / len(measurement.wavelength_nm))
        if uncertainty_scale is None
        else float(uncertainty_scale)
    )

    if not math.isfinite(retained_uncertainty_scale) or retained_uncertainty_scale <= 0.0:
        raise ValueError(f"{label} uncertainty scale must be finite and positive")

    return Measurement(
        wavelength_nm=array("d", (measurement.wavelength_nm[index] for index in retained_indices)),
        reflectance=array("d", (measurement.reflectance[index] for index in retained_indices)),
        signal_to_noise=array(
            "d",
            (
                float(measurement.signal_to_noise[index]) / retained_uncertainty_scale
                for index in retained_indices
            ),
        ),
    )


def full_correction_case(case: O2AInput, measurement: Measurement) -> O2AInput:
    """Use full physics on the correction window instead of the whole O2 A band."""

    return case_on_measurement_grid(case, measurement)


def case_on_measurement_grid(case: O2AInput, measurement: Measurement) -> O2AInput:
    """Return the same case sampled on a selected measured wavelength grid."""

    correction_case = copy.copy(case)
    correction_case.instrument_response = copy.copy(case.instrument_response)
    correction_case.spectral_grid = SpectralGrid(
        start_nm=float(measurement.wavelength_nm[0]),
        end_nm=float(measurement.wavelength_nm[-1]),
        sample_count=len(measurement.wavelength_nm),
    )
    correction_case.instrument_response.measured_wavelengths_nm = tuple(
        float(wavelength_nm) for wavelength_nm in measurement.wavelength_nm
    )

    return correction_case


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


def combine_fastmode_correction_result(fast_result: Result, full_result: Result) -> Result:
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


def run_native_retrieval(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache,
    load_case: bool = True,
) -> Result:
    """Bind the O2 A RTM relation to the generic OE solver."""

    _require_aerosol_retrieval_compatible(case)
    resolved_state_vector = resolved_state_vector_for_case(case, state_vector)
    final_evaluate_state = _lazy_final_evaluator(case, resolved_state_vector)
    active_controls = controls or RetrievalControls.from_disamar_retrieval_specs()

    if load_case and not cache.has_loaded_case(case):
        cache.load(case, copy_case=False)

    cache.warm_optimal_estimation(resolved_state_vector.jacobian_names)

    raw = cache._handle.optimal_estimation(  # noqa: SLF001
        measurement=measurement,
        state_vector=resolved_state_vector,
        controls=active_controls,
    )
    result = _result_from_native(raw, resolved_state_vector, measurement)

    return attach_final_evaluation(
        result,
        final_evaluate_state,
    )


def run_native_retrieval_batch(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vectors: Sequence[StateVector],
    resolved_template: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache,
    load_case: bool = True,
    batch_workers: int = 1,
) -> BatchResult:
    """Bind one prepared O2 A relation to many native OE starts."""

    _require_aerosol_retrieval_compatible(case)
    active_controls = controls or RetrievalControls.from_disamar_retrieval_specs()

    if load_case and not cache.has_loaded_case(case):
        cache.load(case, copy_case=False)

    if batch_workers == 1:
        cache.warm_optimal_estimation(resolved_template.jacobian_names)

    initial_rows, prior_rows = batch_state_rows(resolved_template, state_vectors)
    raw = cache._handle.optimal_estimation_batch(  # noqa: SLF001
        measurement=measurement,
        state_vector=resolved_template,
        initial_states=initial_rows,
        prior_states=prior_rows,
        controls=active_controls,
        batch_workers=batch_workers,
    )
    state_count = int(raw["state_count"])
    states = tuple(
        tuple(float(value) for value in raw["state"][offset : offset + state_count])
        for offset in range(0, len(raw["state"]), state_count)
    )

    return BatchResult(
        state_names=resolved_template.names,
        state=states,
        iterations=tuple(int(value) for value in raw["iteration_count"]),
        converged=tuple(bool(value) for value in raw["converged"]),
        measurement=measurement,
    )


def batch_state_rows(
    template: StateVector,
    state_vectors: Sequence[StateVector],
) -> tuple[tuple[tuple[float, ...], ...], tuple[tuple[float, ...], ...]]:
    """Return row-major initial/prior state tables compatible with one template."""

    initial_rows = []
    prior_rows = []

    for state_vector in state_vectors:
        if state_vector.names != template.names:
            raise ValueError("batched state vectors must use the same state order")

        initial_rows.append(state_vector.initial_state())
        prior_rows.append(state_vector.prior_state())

    return tuple(initial_rows), tuple(prior_rows)


def resolved_state_vector_for_case(
    case: O2AInput,
    state_vector: StateVector,
    *,
    cache: rtm.SessionCache | None = None,
) -> StateVector:
    """Attach case-owned pressure metadata before native OE sees the state vector."""

    return resolved_state_vector_from_profile(
        case,
        state_vector,
        lambda: pressure_altitude_profile_from_case(case, cache=cache),
    )


def resolved_state_vector_for_loaded_case(
    case: O2AInput,
    state_vector: StateVector,
    cache: rtm.SessionCache,
) -> StateVector:
    """Attach pressure metadata from a cache already matched to this case."""

    return resolved_state_vector_from_profile(
        case,
        state_vector,
        lambda: pressure_altitude_profile_from_loaded_cache(case, cache),
    )


def resolved_state_vector_from_profile(
    case: O2AInput,
    state_vector: StateVector,
    pressure_profile: Callable[[], PressureAltitudeProfile],
) -> StateVector:
    """Resolve state-vector parameters that need case-owned pressure metadata."""

    parameters = []
    pressure_altitude_profile = None
    changed = False

    for parameter in state_vector.parameters:
        resolver = getattr(parameter, "resolve_for_case", None)

        if resolver is None:
            parameters.append(parameter)

            continue

        if pressure_altitude_profile is None:
            pressure_altitude_profile = pressure_profile()

        parameters.append(resolver(case, pressure_altitude_profile))
        changed = True

    if not changed:
        return state_vector

    return StateVector(tuple(parameters))


def _require_aerosol_retrieval_compatible(case: object) -> None:

    aerosol = getattr(case, "aerosol", None)
    checker = getattr(aerosol, "require_retrieval_compatible", None)

    if checker is not None:
        checker()


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


def attach_diagnosis(
    result: Result,
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls,
) -> Result:
    """Attach a lazy multi-start diagnosis runner to one retrieval result."""

    diagnosis_case = copy.deepcopy(case)
    diagnosis_measurement = copy.deepcopy(measurement)
    diagnosis_state_vector = copy.deepcopy(state_vector)
    result_state = tuple(float(value) for value in result.state)
    result_initial_state = (
        None
        if result.initial_state is None
        else tuple(float(value) for value in result.initial_state)
    )

    def diagnose(
        *,
        start_count: int = 100,
        batch_workers: int | None = None,
        bounds: Mapping[StateName, tuple[float, float]] | None = None,
        cache: rtm.SessionCache | None = None,
    ) -> object:

        from .diagnosis import diagnose_retrieval

        return diagnose_retrieval(
            case=diagnosis_case,
            measurement=diagnosis_measurement,
            state_vector=diagnosis_state_vector,
            result_state=result_state,
            result_initial_state=result_initial_state,
            controls=controls,
            start_count=start_count,
            batch_workers=batch_workers,
            bounds=bounds,
            cache=cache,
        )

    object.__setattr__(result, "diagnosis_factory", diagnose)

    return result


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


def simulate_measurement(
    case: O2AInput,
    *,
    signal_to_noise: float | Sequence[float],
) -> Measurement:
    """Simulate a reflectance measurement from a truth case."""

    spectrum = rtm.spectrum(case)

    return Measurement(
        wavelength_nm=array("d", spectrum.wavelength_nm),
        reflectance=array("d", spectrum.reflectance),
        signal_to_noise=signal_to_noise,
    )


def pressure_altitude_profile_from_case(
    case: O2AInput,
    *,
    cache: rtm.SessionCache | None = None,
) -> PressureAltitudeProfile:
    """Read the pressure-altitude relation from the RTM atmospheric grid."""

    budget = (
        cache.atmospheric_budget([case.spectral_grid.start_nm])
        if cache is not None and cache.has_loaded_case(case)
        else rtm.atmospheric_budget(case, [case.spectral_grid.start_nm])
    )

    return pressure_altitude_profile_from_budget(budget)


def pressure_altitude_profile_from_loaded_cache(
    case: O2AInput,
    cache: rtm.SessionCache,
) -> PressureAltitudeProfile:
    """Read pressure-altitude metadata from a cache already matched to this case."""

    return pressure_altitude_profile_from_budget(
        cache.atmospheric_budget([case.spectral_grid.start_nm])
    )


def pressure_altitude_profile_from_budget(budget: AtmosphericBudget) -> PressureAltitudeProfile:
    """Build the pressure-altitude relation from RTM atmospheric budget rows."""

    table = budget.table
    levels_by_pressure: dict[float, float] = {}

    for row in table:
        levels_by_pressure[round(budget_row_float(row, "top_pressure_hpa"), 12)] = budget_row_float(
            row, "top_altitude_km"
        )
        levels_by_pressure[round(budget_row_float(row, "bottom_pressure_hpa"), 12)] = (
            budget_row_float(row, "bottom_altitude_km")
        )

    levels = sorted((altitude, pressure) for pressure, altitude in levels_by_pressure.items())

    return PressureAltitudeProfile(
        altitude_km=tuple(altitude for altitude, _pressure in levels),
        pressure_hpa=tuple(pressure for _altitude, pressure in levels),
    )


def budget_row_float(row: Mapping[str, object], key: str) -> float:
    """Read a numeric atmospheric-budget value from copied RTM table rows."""

    value = row[key]

    if not isinstance(value, int | float):
        raise TypeError(f"atmospheric budget field {key} is not numeric")

    return float(value)


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
        signal_to_noise=tuple(
            max(abs(reflectance_value), 1.0e-300) / noise
            for reflectance_value, noise in zip(reflectance, reflectance_noise, strict=True)
        ),
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
