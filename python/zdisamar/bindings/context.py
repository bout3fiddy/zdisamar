"""Native context runtime for O2A forward-model calls."""

import copy
import ctypes
import os

from .. import reference_data
from ..input.o2a import O2AInput
from ..output.spectrum import JACOBIAN_STATE_NAMES, DiagnosticReport, Spectrum
from ..output.tables import (
    AtmosphericBudget,
    InstrumentResponseTable,
    O2LineContributions,
    OxygenCollisionInducedAbsorptionDiagnosticTable,
    RadiativeTransferDiagnosticTable,
)
from .library import load_library
from .signatures import configure
from .structures import (
    CAtmosphericBudget,
    CDiagnosticReport,
    CInstrumentResponse,
    CRadiativeTransferDiagnostics,
    CSpectrum,
    O2LineContributionsRaw,
    OxygenCollisionInducedAbsorptionDiagnosticsRaw,
)

LibraryPath = str | os.PathLike[str] | None


def contiguous_wavelengths(wavelengths_nm):
    import numpy as np

    wavelengths = np.ascontiguousarray(wavelengths_nm, dtype=np.float64)
    if wavelengths.ndim != 1:
        raise ValueError("wavelengths_nm must be one-dimensional")
    if wavelengths.size == 0:
        raise ValueError("wavelengths_nm must not be empty")
    return wavelengths


def channel_mask(channels: tuple[str, ...]) -> int:
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
    ids = []
    for state_name in state_names:
        try:
            ids.append(JACOBIAN_STATE_NAMES.index(state_name))
        except ValueError as exc:
            raise ValueError(f"unsupported Jacobian state: {state_name}") from exc
    return (ctypes.c_uint8 * len(ids))(*ids)


class Context:
    """Native zdisamar context."""

    def __init__(self, library_path: LibraryPath = None):
        self._lib = configure(load_library(library_path))
        self._ctx = self._lib.zds_context_create()
        self._input: O2AInput | None = None
        if not self._ctx:
            raise RuntimeError("failed to create zdisamar context")

    def close(self) -> None:
        if self._ctx:
            self._lib.zds_context_destroy(self._ctx)
            self._ctx = None

    @property
    def input(self) -> O2AInput | None:
        return None if self._input is None else copy.deepcopy(self._input)

    def prepare_default_o2a(self) -> Context:
        self._input = self.default_o2a_input()
        self._check(self._lib.zds_prepare_default_o2a(self._ctx))
        return self

    def default_o2a_input(self) -> O2AInput:
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

    def prepare_o2a(self, input: O2AInput) -> Context:
        resolved = input.with_resolved_asset_resolver(reference_data.resolve_asset_path)
        payload = resolved.to_json_bytes()
        self._check(
            self._lib.zds_prepare_o2a_json(
                self._ctx,
                ctypes.c_char_p(payload),
                len(payload),
            )
        )
        self._input = copy.deepcopy(input)
        return self

    def warm_o2a_session(self) -> Context:
        self._check(self._lib.zds_warm_o2a_session(self._ctx))
        return self

    def run(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ) -> Spectrum:
        raw = CSpectrum()
        if jacobian_state_names is not None and not jacobian:
            raise ValueError("jacobian_state_names requires jacobian=True")
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
            return Spectrum(self, raw, jacobian_state_names=jacobian_state_names)
        runner = self._lib.zds_run_spectrum_jacobian if jacobian else self._lib.zds_run_spectrum
        self._check(runner(self._ctx, ctypes.byref(raw)))
        return Spectrum(self, raw)

    def forward_model(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ) -> Spectrum:
        return self.run(jacobian=jacobian, jacobian_state_names=jacobian_state_names)

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

    def atmospheric_budget(self, wavelengths_nm) -> AtmosphericBudget:
        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = CAtmosphericBudget()
        self._check(
            self._lib.zds_atmospheric_budget(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                ctypes.byref(raw),
            )
        )
        return AtmosphericBudget(self, raw)

    def o2_line_contributions(self, wavelengths_nm, max_rows: int = 50_000) -> O2LineContributions:
        wavelengths = contiguous_wavelengths(wavelengths_nm)
        if max_rows <= 0:
            raise ValueError("max_rows must be positive")
        raw = O2LineContributionsRaw()
        self._check(
            self._lib.zds_o2_line_contributions(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                max_rows,
                ctypes.byref(raw),
            )
        )
        return O2LineContributions(self, raw)

    def instrument_response_sampling(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ) -> InstrumentResponseTable:
        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = CInstrumentResponse()
        self._check(
            self._lib.zds_instrument_response_sampling(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                channel_mask(channels),
                ctypes.byref(raw),
            )
        )
        return InstrumentResponseTable(self, raw)

    def collision_induced_absorption_diagnostics(
        self, wavelengths_nm
    ) -> OxygenCollisionInducedAbsorptionDiagnosticTable:
        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = OxygenCollisionInducedAbsorptionDiagnosticsRaw()
        self._check(
            self._lib.zds_o2_o2_cia_diagnostics(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                ctypes.byref(raw),
            )
        )
        return OxygenCollisionInducedAbsorptionDiagnosticTable(self, raw)

    def radiative_transfer_diagnostics(
        self,
        wavelengths_nm,
        spectrum: Spectrum | None = None,
    ) -> RadiativeTransferDiagnosticTable:
        wavelengths = contiguous_wavelengths(wavelengths_nm)
        raw = CRadiativeTransferDiagnostics()
        spectrum_ptr = None
        if spectrum is not None:
            spectrum._require_open()
            spectrum_ptr = ctypes.byref(spectrum._raw)
        self._check(
            self._lib.zds_radiative_transfer_diagnostics(
                self._ctx,
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                spectrum_ptr,
                ctypes.byref(raw),
            )
        )
        return RadiativeTransferDiagnosticTable(self, raw)

    def _free_spectrum(self, raw: CSpectrum) -> None:
        self._lib.zds_spectrum_free(self._ctx, ctypes.byref(raw))

    def _free_atmospheric_budget(self, raw: CAtmosphericBudget) -> None:
        self._lib.zds_atmospheric_budget_free(self._ctx, ctypes.byref(raw))

    def _free_o2_line_contributions(self, raw: O2LineContributionsRaw) -> None:
        self._lib.zds_o2_line_contributions_free(self._ctx, ctypes.byref(raw))

    def _free_instrument_response(self, raw: CInstrumentResponse) -> None:
        self._lib.zds_instrument_response_free(self._ctx, ctypes.byref(raw))

    def _free_collision_induced_absorption_diagnostics(
        self, raw: OxygenCollisionInducedAbsorptionDiagnosticsRaw
    ) -> None:
        self._lib.zds_o2_o2_cia_diagnostics_free(self._ctx, ctypes.byref(raw))

    def _free_radiative_transfer_diagnostics(self, raw: CRadiativeTransferDiagnostics) -> None:
        self._lib.zds_radiative_transfer_diagnostics_free(self._ctx, ctypes.byref(raw))

    def _check(self, status: int) -> None:
        if status == 0:
            return
        message = self._lib.zds_last_error(self._ctx)
        raise RuntimeError((message or b"zdisamar error").decode("utf-8", errors="replace"))

    def __enter__(self) -> Context:
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()
