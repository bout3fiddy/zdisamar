"""Low-level Zig binding handle for RTM calls."""

import copy
import ctypes
import math
from array import array
from numbers import Integral
from typing import Self

from .. import reference_data
from ..input.wavelength_band.o2a import O2AInput
from ..output.spectrum import (
    JACOBIAN_STATE_NAMES,
    DiagnosticReport,
    Irradiance,
    Radiance,
    RadianceJacobian,
    Reflectance,
    SpectralAxis,
    Spectrum,
)
from ..output.tables import (
    AtmosphericBudget,
    InstrumentResponseTable,
    O2LineContributions,
    OxygenCollisionInducedAbsorptionDiagnosticTable,
    RadiativeTransferDiagnosticTable,
)
from .loader import load_library
from .signatures import configure
from .structures import (
    CAtmosphericBudget,
    CDiagnosticReport,
    CInstrumentResponse,
    COptimalEstimationBatchRequest,
    COptimalEstimationBatchResult,
    COptimalEstimationControls,
    COptimalEstimationFastmodeBatchResult,
    COptimalEstimationRequest,
    COptimalEstimationResult,
    COptimalEstimationStateSpec,
    CRadiativeTransferDiagnostics,
    CSpectrum,
    O2LineContributionsRaw,
    OxygenCollisionInducedAbsorptionDiagnosticsRaw,
)

_MAX_OPTIMAL_ESTIMATION_ITERATIONS = 1000
_MAX_UINT32 = 2**32 - 1
_NATIVE_PRESSURE_STATE = "aerosol_layer_mid_pressure_hpa"
_BATCH_RUN_STATUS_NAMES = ("pending", "ok", "failed")


def contiguous_wavelengths(wavelengths_nm):
    """Prepare a one-dimensional wavelength grid for the zdisamar model."""

    return double_array(wavelengths_nm, "wavelengths_nm")


def channel_mask(channels: tuple[str, ...]) -> int:
    """Translate requested spectral channels into model channel selection."""

    masks = {"radiance": 1, "irradiance": 2}
    mask = 0

    for channel in channels:
        try:
            mask |= masks[channel]
        except KeyError as exc:
            raise ValueError(f"unsupported spectral channel: {channel}") from exc

    if mask == 0:
        raise ValueError("channels must not be empty")

    return mask


def jacobian_state_ids(state_names: tuple[str, ...]):
    """Translate retrieval names into model Jacobian selectors."""

    ids = []

    for state_name in state_names:
        try:
            ids.append(JACOBIAN_STATE_NAMES.index(state_name))
        except ValueError as exc:
            raise ValueError(f"unsupported Jacobian state: {state_name}") from exc

    return (ctypes.c_uint8 * len(ids))(*ids)


def batch_run_status(value: int) -> str:
    """Translate native per-start batch status into a stable Python label."""

    try:
        return _BATCH_RUN_STATUS_NAMES[int(value)]
    except IndexError:
        return f"unknown:{int(value)}"


def double_array(values, name: str):
    """Copy a Python numeric sequence into a contiguous C double buffer."""

    copied = [float(value) for value in values]

    if not copied:
        raise ValueError(f"{name} must not be empty")

    if any(not math.isfinite(value) for value in copied):
        raise ValueError(f"{name} values must be finite")

    return (ctypes.c_double * len(copied))(*copied)


def flattened_state_rows(rows, state_count: int, name: str) -> tuple[list[float], int]:
    """Copy a two-dimensional state table into row-major native input."""

    copied = []
    run_count = 0

    for row in rows:
        values = [float(value) for value in row]

        if len(values) != state_count:
            raise ValueError(f"{name} rows must have {state_count} values")

        copied.extend(values)
        run_count += 1

    if run_count == 0:
        raise ValueError(f"{name} must not be empty")

    if any(not math.isfinite(value) for value in copied):
        raise ValueError(f"{name} values must be finite")

    return copied, run_count


class RtmHandle:
    """Own the opaque Zig RTM handle used by the C ABI."""

    def __init__(self):

        self._lib = configure(load_library())
        self._ctx = self._lib.zds_context_create()
        self._case: O2AInput | None = None
        self._case_fingerprint: bytes | None = None
        self._loaded_has_multi_layer_aerosol_profile = False
        self._solar_mu0: float | None = None

        if not self._ctx:
            raise RuntimeError("failed to start zdisamar RTM handle")

    @property
    def input(self) -> O2AInput | None:
        """Return the wavelength-band case loaded into this handle."""

        return None if self._case is None else copy.deepcopy(self._case)

    def default_o2a_case(self) -> O2AInput:
        """Read the packaged O2 A reference case from the Zig binding."""

        size = ctypes.c_size_t()
        self._check(self._lib.zds_default_o2a_input_json(self._ctx, None, 0, ctypes.byref(size)))
        buffer = ctypes.create_string_buffer(size.value + 1)
        self._check(
            self._lib.zds_default_o2a_input_json(
                self._ctx,
                ctypes.cast(buffer, ctypes.c_void_p),
                ctypes.sizeof(buffer),
                ctypes.byref(size),
            )
        )

        return O2AInput.from_json(buffer.value[: size.value])

    def load_o2a_case(self, case: O2AInput, *, copy_case: bool = True) -> None:
        """Load one O2 A wavelength-band case into the RTM handle."""

        rtm_case = case.with_rtm_optimisation_applied()
        resolved = rtm_case.with_resolved_asset_resolver(reference_data.resolve_asset_path)
        payload = resolved.to_native_json_bytes()
        self._check(
            self._lib.zds_prepare_o2a_json(
                self._ctx,
                ctypes.c_char_p(payload),
                len(payload),
            )
        )
        self._case = copy.deepcopy(rtm_case) if copy_case else None
        self._case_fingerprint = payload
        self._loaded_has_multi_layer_aerosol_profile = len(rtm_case.aerosol.profile) > 1
        self._solar_mu0 = rtm_case.geometry.solar_mu0

    def loaded_o2a_case_matches(self, case: O2AInput) -> bool:
        """Return whether the native handle already owns this prepared case.

        The fingerprint uses the resolved deterministic payload passed to Zig.
        That lets session users avoid a duplicate prepare without retaining a
        Python case copy solely for invalidation.
        """

        if self._case_fingerprint is None:
            return False

        rtm_case = case.with_rtm_optimisation_applied()
        resolved = rtm_case.with_resolved_asset_resolver(reference_data.resolve_asset_path)

        return resolved.to_native_json_bytes() == self._case_fingerprint

    def warm_cache(self) -> None:
        """Build reusable RTM work arrays for repeated runs."""

        self._check(self._lib.zds_warm_o2a_session(self._ctx))

    def warm_optimal_estimation_cache(self, state_names: tuple[str, ...]) -> None:
        """Build reusable RTM work arrays for the OE Jacobian route."""

        state_ids = jacobian_state_ids(state_names)
        self._check(
            self._lib.zds_warm_o2a_optimal_estimation(
                self._ctx,
                state_ids,
                len(state_ids),
            )
        )

    def spectrum(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
        include_case: bool = False,
    ) -> Spectrum:
        """Run the loaded wavelength-band case and return copied spectral arrays."""

        raw = CSpectrum()

        if jacobian_state_names is not None and not jacobian:
            raise ValueError("jacobian_state_names requires jacobian=True")

        if jacobian and self._loaded_has_multi_layer_aerosol_profile:
            raise ValueError("multi-layer aerosol profile Jacobians are not supported")

        if jacobian_state_names is not None:
            if len(jacobian_state_names) == 0:
                raise ValueError("jacobian_state_names must not be empty")

            state_ids = jacobian_state_ids(jacobian_state_names)
            self._check(
                self._lib.zds_run_spectrum_jacobian_for_states(
                    self._ctx,
                    ctypes.byref(raw),
                    state_ids,
                    len(state_ids),
                )
            )

            return self._copied_spectrum(
                raw,
                jacobian_state_names=jacobian_state_names,
                include_case=include_case,
            )

        runner = self._lib.zds_run_spectrum_jacobian if jacobian else self._lib.zds_run_spectrum
        self._check(runner(self._ctx, ctypes.byref(raw)))

        return self._copied_spectrum(raw, include_case=include_case)

    def atmospheric_budget(self, wavelengths_nm) -> AtmosphericBudget:
        """Return copied atmospheric optical-depth rows."""

        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = CAtmosphericBudget()
        self._check(
            self._lib.zds_atmospheric_budget(
                self._ctx,
                wavelengths,
                len(wavelengths),
                ctypes.byref(raw),
            )
        )

        return AtmosphericBudget(self._copied_rows(raw, self._lib.zds_atmospheric_budget_free))

    def o2_line_contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        """Return copied line-by-line O2 evidence rows."""

        wavelengths = contiguous_wavelengths(wavelengths_nm)

        if max_rows <= 0:
            raise ValueError("max_rows must be positive")

        raw = O2LineContributionsRaw()
        self._check(
            self._lib.zds_o2_line_contributions(
                self._ctx,
                wavelengths,
                len(wavelengths),
                max_rows,
                ctypes.byref(raw),
            )
        )
        total_row_count = int(raw.total_row_count)
        truncated = bool(raw.truncated)
        rows = self._copied_rows(raw, self._lib.zds_o2_line_contributions_free)

        return O2LineContributions(
            rows,
            total_row_count=total_row_count,
            truncated=truncated,
        )

    def instrument_response_sampling(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ) -> InstrumentResponseTable:
        """Return copied instrument response support rows."""

        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = CInstrumentResponse()
        self._check(
            self._lib.zds_instrument_response_sampling(
                self._ctx,
                wavelengths,
                len(wavelengths),
                channel_mask(channels),
                ctypes.byref(raw),
            )
        )

        return InstrumentResponseTable(
            self._copied_rows(raw, self._lib.zds_instrument_response_free)
        )

    def collision_induced_absorption(
        self,
        wavelengths_nm,
    ) -> OxygenCollisionInducedAbsorptionDiagnosticTable:
        """Return copied O2-O2 CIA rows on the atmospheric layer grid."""

        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = OxygenCollisionInducedAbsorptionDiagnosticsRaw()
        self._check(
            self._lib.zds_o2_o2_cia_diagnostics(
                self._ctx,
                wavelengths,
                len(wavelengths),
                ctypes.byref(raw),
            )
        )

        return OxygenCollisionInducedAbsorptionDiagnosticTable(
            self._copied_rows(raw, self._lib.zds_o2_o2_cia_diagnostics_free)
        )

    def radiative_transfer_diagnostics(self, wavelengths_nm) -> RadiativeTransferDiagnosticTable:
        """Return copied bounded radiative-transfer evidence rows."""

        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = CRadiativeTransferDiagnostics()
        self._check(
            self._lib.zds_radiative_transfer_diagnostics(
                self._ctx,
                wavelengths,
                len(wavelengths),
                None,
                ctypes.byref(raw),
            )
        )

        return RadiativeTransferDiagnosticTable(
            self._copied_rows(raw, self._lib.zds_radiative_transfer_diagnostics_free)
        )

    def optimal_estimation(self, *, measurement, state_vector, controls):
        """Run native O2 A optimal estimation for the loaded case."""

        return self._run_optimal_estimation(
            "zds_run_o2a_optimal_estimation",
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )

    def optimal_estimation_correction(self, *, measurement, state_vector, controls):
        """Run one native OE correction for the loaded prepared O2 A case."""

        return self._run_optimal_estimation(
            "zds_run_o2a_optimal_estimation_correction",
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )

    def optimal_estimation_batch(
        self,
        *,
        measurement,
        state_vector,
        initial_states,
        prior_states,
        controls,
        batch_workers=1,
    ):
        """Run many native O2 A retrievals against one loaded case and measurement."""

        request, buffers = self._optimal_estimation_batch_request(
            measurement=measurement,
            state_vector=state_vector,
            initial_states=initial_states,
            prior_states=prior_states,
            controls=controls,
            batch_workers=batch_workers,
        )
        raw = COptimalEstimationBatchResult()
        self._check(
            self._lib.zds_run_o2a_optimal_estimation_batch(
                self._ctx,
                ctypes.byref(request),
                ctypes.byref(raw),
            )
        )

        try:
            return self._copied_optimal_estimation_batch_result(raw)
        finally:
            del buffers
            self._lib.zds_optimal_estimation_batch_result_free(self._ctx, ctypes.byref(raw))

    def optimal_estimation_fastmode_batch(
        self,
        *,
        correction_handle,
        measurement,
        correction_measurement,
        state_vector,
        correction_state_vector,
        initial_states,
        prior_states,
        controls,
        correction_controls,
        batch_workers=1,
    ):
        """Run fast-stage and sparse correction batches inside one native boundary."""

        fast_request, fast_buffers = self._optimal_estimation_batch_request(
            measurement=measurement,
            state_vector=state_vector,
            initial_states=initial_states,
            prior_states=prior_states,
            controls=controls,
            batch_workers=batch_workers,
        )
        correction_request, correction_buffers = (
            correction_handle._optimal_estimation_batch_request(
                measurement=correction_measurement,
                state_vector=correction_state_vector,
                initial_states=initial_states,
                prior_states=prior_states,
                controls=correction_controls,
                batch_workers=batch_workers,
            )
        )
        raw = COptimalEstimationFastmodeBatchResult()
        self._check(
            self._lib.zds_run_o2a_fastmode_optimal_estimation_batch(
                self._ctx,
                correction_handle._ctx,
                ctypes.byref(fast_request),
                ctypes.byref(correction_request),
                ctypes.byref(raw),
            )
        )

        try:
            return self._copied_optimal_estimation_fastmode_batch_result(raw)
        finally:
            del fast_buffers
            del correction_buffers
            self._lib.zds_optimal_estimation_fastmode_batch_result_free(
                self._ctx,
                ctypes.byref(raw),
            )

    def _run_optimal_estimation(self, runner_name: str, *, measurement, state_vector, controls):

        request, buffers = self._optimal_estimation_request(
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )
        raw = COptimalEstimationResult()
        runner = getattr(self._lib, runner_name)
        self._check(
            runner(
                self._ctx,
                ctypes.byref(request),
                ctypes.byref(raw),
            )
        )

        try:
            return self._copied_optimal_estimation_result(raw)
        finally:
            del buffers
            self._lib.zds_optimal_estimation_result_free(self._ctx, ctypes.byref(raw))

    def _optimal_estimation_request(self, *, measurement, state_vector, controls):

        wavelength = double_array(measurement.wavelength_nm, "measurement wavelengths")
        reflectance = double_array(measurement.reflectance, "measurement reflectance")
        uncertainty = double_array(
            measurement.reflectance_uncertainty,
            "measurement reflectance uncertainty",
        )

        if len(wavelength) != len(reflectance) or len(wavelength) != len(uncertainty):
            raise ValueError("measurement arrays must have the same length")

        if any(not math.isfinite(value) or value <= 0.0 for value in uncertainty):
            raise ValueError("measurement uncertainty values must be finite and positive")

        measurement_covariance = (ctypes.c_double * len(uncertainty))(
            *(value * value for value in uncertainty)
        )

        state_buffers = []
        state_specs = []
        raw_max_iterations = controls.max_iterations

        if not isinstance(raw_max_iterations, Integral) or isinstance(raw_max_iterations, bool):
            raise ValueError("optimal-estimation max_iterations must be an integer")

        max_iterations = int(raw_max_iterations)

        if max_iterations <= 0 or max_iterations > _MAX_OPTIMAL_ESTIMATION_ITERATIONS:
            raise ValueError(
                "optimal-estimation max_iterations must be between "
                f"1 and {_MAX_OPTIMAL_ESTIMATION_ITERATIONS}"
            )

        for parameter in state_vector.parameters:
            parameter_name = parameter.name
            state_name = getattr(parameter, "jacobian_name", parameter_name)

            if state_name != parameter_name:
                raise ValueError(
                    "native optimal estimation requires direct state parameters; "
                    "transformed state-vector parameters are not supported"
                )

            if (
                getattr(parameter, "jacobian_scale", None) is not None
                and state_name != _NATIVE_PRESSURE_STATE
            ):
                raise ValueError(
                    "native optimal estimation does not support custom jacobian_scale transforms"
                )

            try:
                state_id = JACOBIAN_STATE_NAMES.index(state_name)
            except ValueError as exc:
                raise ValueError(f"unsupported optimal-estimation state: {state_name}") from exc

            profile = getattr(parameter, "pressure_altitude_profile", None)
            profile_altitude = None
            profile_pressure = None
            profile_count = 0

            if profile is not None:
                profile_altitude = double_array(profile.altitude_km, "pressure-profile altitude")
                profile_pressure = double_array(profile.pressure_hpa, "pressure-profile pressure")

                if len(profile_altitude) != len(profile_pressure):
                    raise ValueError("pressure-profile arrays must have the same length")

                profile_count = len(profile_altitude)
                state_buffers.extend([profile_altitude, profile_pressure])

            lower = getattr(parameter, "lower", None)
            upper = getattr(parameter, "upper", None)
            raw_interval_index = getattr(parameter, "interval_index_1based", 0)

            if not isinstance(raw_interval_index, Integral) or isinstance(raw_interval_index, bool):
                raise ValueError("optimal-estimation interval_index_1based must be an integer")

            interval_index_1based = int(raw_interval_index)

            if interval_index_1based < 0 or interval_index_1based > _MAX_UINT32:
                raise ValueError("optimal-estimation interval_index_1based is out of uint32 range")

            uncertainty = float(parameter.prior_uncertainty)

            if not math.isfinite(uncertainty) or uncertainty <= 0.0:
                raise ValueError(
                    "optimal-estimation state prior_uncertainty values must be finite and positive"
                )

            state_specs.append(
                COptimalEstimationStateSpec(
                    state_id=state_id,
                    has_lower=0 if lower is None else 1,
                    has_upper=0 if upper is None else 1,
                    interval_index_1based=interval_index_1based,
                    initial=float(parameter.initial),
                    prior=float(parameter.prior),
                    variance=uncertainty * uncertainty,
                    lower=0.0 if lower is None else float(lower),
                    upper=0.0 if upper is None else float(upper),
                    thickness_hpa=float(getattr(parameter, "thickness_hpa", 0.0)),
                    pressure_profile_count=profile_count,
                    pressure_profile_altitude_km=profile_altitude,
                    pressure_profile_pressure_hpa=profile_pressure,
                )
            )

        if not state_specs:
            raise ValueError("state vector must contain at least one parameter")

        state_spec_array = (COptimalEstimationStateSpec * len(state_specs))(*state_specs)
        request = COptimalEstimationRequest(
            sample_count=len(wavelength),
            wavelength_nm=wavelength,
            reflectance=reflectance,
            variance=measurement_covariance,
            state_count=len(state_specs),
            states=state_spec_array,
            controls=COptimalEstimationControls(
                max_iterations=max_iterations,
                state_vector_convergence_threshold=float(
                    controls.state_vector_convergence_threshold
                ),
                max_change_transformed_state=float(controls.max_change_transformed_state),
            ),
        )
        buffers = (
            wavelength,
            reflectance,
            measurement_covariance,
            state_spec_array,
            *state_buffers,
        )

        return request, buffers

    def _optimal_estimation_batch_request(
        self,
        *,
        measurement,
        state_vector,
        initial_states,
        prior_states,
        controls,
        batch_workers,
    ):

        template_request, template_buffers = self._optimal_estimation_request(
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
        )
        state_count = len(state_vector.parameters)
        initial_values, run_count = flattened_state_rows(
            initial_states,
            state_count,
            "batch initial states",
        )
        prior_values, prior_run_count = flattened_state_rows(
            prior_states,
            state_count,
            "batch prior states",
        )

        if prior_run_count != run_count:
            raise ValueError("batch initial and prior states must have the same row count")

        if not isinstance(batch_workers, Integral) or isinstance(batch_workers, bool):
            raise ValueError("optimal-estimation batch_workers must be an integer")

        batch_worker_count = int(batch_workers)

        if batch_worker_count <= 0:
            raise ValueError("optimal-estimation batch_workers must be positive")

        initial = double_array(initial_values, "batch initial states")
        prior = double_array(prior_values, "batch prior states")
        request = COptimalEstimationBatchRequest(
            sample_count=template_request.sample_count,
            wavelength_nm=template_request.wavelength_nm,
            reflectance=template_request.reflectance,
            variance=template_request.variance,
            state_count=template_request.state_count,
            state_template=template_request.states,
            run_count=run_count,
            initial=initial,
            prior=prior,
            controls=template_request.controls,
            batch_worker_count=batch_worker_count,
        )
        buffers = (*template_buffers, initial, prior)

        return request, buffers

    def close(self) -> None:
        """Release the opaque Zig RTM handle."""

        if self._ctx:
            self._lib.zds_context_destroy(self._ctx)
            self._ctx = None
            self._case = None
            self._case_fingerprint = None
            self._loaded_has_multi_layer_aerosol_profile = False
            self._solar_mu0 = None

    def _copied_spectrum(
        self,
        raw: CSpectrum,
        *,
        jacobian_state_names: tuple[str, ...] | None = None,
        include_case: bool = True,
    ) -> Spectrum:

        try:
            length = int(raw.len)
            wavelength_nm = self._copied_double_array(raw.wavelength_nm, length)
            radiance = self._copied_double_array(raw.radiance, length)
            irradiance = self._copied_double_array(raw.irradiance, length)
            reflectance = self._copied_double_array(raw.reflectance, length)
            state_names = self._jacobian_names(raw, jacobian_state_names)
            radiance_jacobian = None

            if raw.jacobian and raw.jacobian_state_count != 0:
                state_count = int(raw.jacobian_state_count)
                radiance_jacobian = tuple(
                    array(
                        "d",
                        (
                            float(raw.jacobian[sample_index * state_count + state_index])
                            for state_index in range(state_count)
                        ),
                    )
                    for sample_index in range(length)
                )

            report = self._spectrum_report(raw)
        finally:
            self._free_spectrum(raw)

        return Spectrum(
            axis=SpectralAxis(wavelength_nm=wavelength_nm),
            radiance_quantity=Radiance(radiance),
            irradiance_quantity=Irradiance(irradiance),
            reflectance_quantity=Reflectance(reflectance),
            case=self.input if include_case else None,
            solar_mu0_value=self._solar_mu0,
            diagnostic_report=report,
            radiance_jacobian_quantity=(
                None
                if radiance_jacobian is None
                else RadianceJacobian(radiance_jacobian, state_names)
            ),
        )

    def _copied_double_array(self, pointer, count: int) -> array:

        return array("d", (float(pointer[index]) for index in range(count)))

    def _jacobian_names(
        self,
        raw: CSpectrum,
        requested: tuple[str, ...] | None,
    ) -> tuple[str, ...]:

        if raw.jacobian_state_count == 0:
            return ()

        if requested is not None:
            if len(requested) != raw.jacobian_state_count:
                raise RuntimeError("spectrum Jacobian state names do not match model output")

            return requested

        return JACOBIAN_STATE_NAMES[0 : raw.jacobian_state_count]

    def _spectrum_report(self, raw: CSpectrum) -> DiagnosticReport:

        report = CDiagnosticReport()
        self._check(
            self._lib.zds_spectrum_report(self._ctx, ctypes.byref(raw), ctypes.byref(report))
        )

        return DiagnosticReport(
            sample_count=report.sample_count,
            wavelength_start_nm=report.wavelength_start_nm,
            wavelength_end_nm=report.wavelength_end_nm,
            mean_radiance=report.mean_radiance,
            mean_irradiance=report.mean_irradiance,
            mean_reflectance=report.mean_reflectance,
        )

    def _copied_rows(self, raw, free):

        try:
            rows = []

            for row_index in range(int(raw.len)):
                source = raw.rows[row_index]
                rows.append({name: getattr(source, name) for name, _ctype in type(source)._fields_})

            return tuple(rows)
        finally:
            free(self._ctx, ctypes.byref(raw))

    def _free_spectrum(self, raw: CSpectrum) -> None:

        self._lib.zds_spectrum_free(self._ctx, ctypes.byref(raw))

    def _copied_optimal_estimation_result(self, raw: COptimalEstimationResult):

        state_count = int(raw.state_count)
        iteration_count = int(raw.iteration_count)
        matrix_count = state_count * state_count
        history_count = iteration_count * state_count

        def doubles(pointer, count: int) -> list[float]:

            return [float(pointer[index]) for index in range(count)]

        def uint8s(pointer, count: int) -> list[int]:

            return [int(pointer[index]) for index in range(count)]

        return {
            "state_count": state_count,
            "iteration_count": iteration_count,
            "converged": bool(raw.converged),
            "state_ids": uint8s(raw.state_ids, state_count),
            "state": doubles(raw.state, state_count),
            "initial_state": doubles(raw.initial_state, state_count),
            "posterior_covariance": doubles(raw.posterior_covariance, matrix_count),
            "averaging_kernel": doubles(raw.averaging_kernel, matrix_count),
            "history_state": doubles(raw.history_state, history_count),
            "history_chi2": doubles(raw.history_chi2, iteration_count),
            "history_chi2_reflectance": doubles(raw.history_chi2_reflectance, iteration_count),
            "history_chi2_state_vector": doubles(raw.history_chi2_state_vector, iteration_count),
            "history_state_vector_convergence": doubles(
                raw.history_state_vector_convergence,
                iteration_count,
            ),
            "history_snr_normal": uint8s(raw.history_snr_normal, iteration_count),
        }

    def _copied_optimal_estimation_batch_result(self, raw: COptimalEstimationBatchResult):

        run_count = int(raw.run_count)
        state_count = int(raw.state_count)
        history_capacity = int(raw.history_capacity)
        value_count = run_count * state_count
        history_value_count = run_count * history_capacity * state_count
        status = tuple(batch_run_status(raw.status[index]) for index in range(run_count))

        return {
            "run_count": run_count,
            "state_count": state_count,
            "history_capacity": history_capacity,
            "iteration_count": tuple(int(raw.iteration_count[index]) for index in range(run_count)),
            "converged": tuple(bool(raw.converged[index]) for index in range(run_count)),
            "status": status,
            "state": tuple(float(raw.state[index]) for index in range(value_count)),
            "history_state": tuple(
                float(raw.history_state[index]) for index in range(history_value_count)
            ),
        }

    def _copied_optimal_estimation_fastmode_batch_result(
        self,
        raw: COptimalEstimationFastmodeBatchResult,
    ):

        run_count = int(raw.run_count)
        state_count = int(raw.state_count)
        history_capacity = int(raw.history_capacity)
        value_count = run_count * state_count
        history_value_count = run_count * history_capacity * state_count
        status = tuple(batch_run_status(raw.status[index]) for index in range(run_count))

        return {
            "run_count": run_count,
            "state_count": state_count,
            "history_capacity": history_capacity,
            "iteration_count": tuple(int(raw.iteration_count[index]) for index in range(run_count)),
            "converged": tuple(bool(raw.converged[index]) for index in range(run_count)),
            "status": status,
            "state": tuple(float(raw.state[index]) for index in range(value_count)),
            "history_state": tuple(
                float(raw.history_state[index]) for index in range(history_value_count)
            ),
            "fast_stage_iteration_count": tuple(
                int(raw.fast_stage_iteration_count[index]) for index in range(run_count)
            ),
            "fast_stage_converged": tuple(
                bool(raw.fast_stage_converged[index]) for index in range(run_count)
            ),
            "full_correction_iteration_count": tuple(
                int(raw.full_correction_iteration_count[index]) for index in range(run_count)
            ),
            "full_correction_converged": tuple(
                bool(raw.full_correction_converged[index]) for index in range(run_count)
            ),
        }

    def _check(self, status: int) -> None:

        if status == 0:
            return

        message = self._lib.zds_last_error(self._ctx)
        raise RuntimeError((message or b"zdisamar error").decode("utf-8", errors="replace"))

    def __enter__(self) -> Self:

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()
