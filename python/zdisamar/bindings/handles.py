"""Low-level Zig binding handle for RTM calls."""

import copy
import ctypes
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
    CRadiativeTransferDiagnostics,
    CSpectrum,
    O2LineContributionsRaw,
    OxygenCollisionInducedAbsorptionDiagnosticsRaw,
)


def contiguous_wavelengths(wavelengths_nm):
    """Prepare a one-dimensional wavelength grid for the zdisamar model."""

    import numpy as np

    wavelengths = np.ascontiguousarray(wavelengths_nm, dtype=np.float64)

    if wavelengths.ndim != 1:
        raise ValueError("wavelengths_nm must be one-dimensional")

    if wavelengths.size == 0:
        raise ValueError("wavelengths_nm must not be empty")

    return wavelengths


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


class RtmHandle:
    """Own the opaque Zig RTM handle used by the C ABI."""

    def __init__(self):

        self._lib = configure(load_library())
        self._ctx = self._lib.zds_context_create()
        self._case: O2AInput | None = None

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

        resolved = case.with_resolved_asset_resolver(reference_data.resolve_asset_path)
        payload = resolved.to_json_bytes()
        self._check(
            self._lib.zds_prepare_o2a_json(
                self._ctx,
                ctypes.c_char_p(payload),
                len(payload),
            )
        )
        self._case = copy.deepcopy(case) if copy_case else case

    def warm_cache(self) -> None:
        """Build reusable RTM work arrays for repeated runs."""

        self._check(self._lib.zds_warm_o2a_session(self._ctx))

    def spectrum(
        self,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
        include_case: bool = True,
    ) -> Spectrum:
        """Run the loaded wavelength-band case and return copied spectral arrays."""

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
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
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
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
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
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
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
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
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
                wavelengths.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                wavelengths.size,
                None,
                ctypes.byref(raw),
            )
        )

        return RadiativeTransferDiagnosticTable(
            self._copied_rows(raw, self._lib.zds_radiative_transfer_diagnostics_free)
        )

    def close(self) -> None:
        """Release the opaque Zig RTM handle."""

        if self._ctx:
            self._lib.zds_context_destroy(self._ctx)
            self._ctx = None
            self._case = None

    def _copied_spectrum(
        self,
        raw: CSpectrum,
        *,
        jacobian_state_names: tuple[str, ...] | None = None,
        include_case: bool = True,
    ) -> Spectrum:

        import numpy as np

        try:
            wavelength_nm = np.ctypeslib.as_array(raw.wavelength_nm, shape=(raw.len,)).copy()
            radiance = np.ctypeslib.as_array(raw.radiance, shape=(raw.len,)).copy()
            irradiance = np.ctypeslib.as_array(raw.irradiance, shape=(raw.len,)).copy()
            reflectance = np.ctypeslib.as_array(raw.reflectance, shape=(raw.len,)).copy()
            state_names = self._jacobian_names(raw, jacobian_state_names)
            radiance_jacobian = None

            if raw.jacobian and raw.jacobian_state_count != 0:
                flat = np.ctypeslib.as_array(
                    raw.jacobian,
                    shape=(raw.len * raw.jacobian_state_count,),
                )
                radiance_jacobian = flat.reshape((raw.len, raw.jacobian_state_count)).copy()

            report = self._spectrum_report(raw)
        finally:
            self._free_spectrum(raw)

        return Spectrum(
            axis=SpectralAxis(wavelength_nm=wavelength_nm),
            radiance_quantity=Radiance(radiance),
            irradiance_quantity=Irradiance(irradiance),
            reflectance_quantity=Reflectance(reflectance),
            case=self.input if include_case else None,
            diagnostic_report=report,
            radiance_jacobian_quantity=(
                None
                if radiance_jacobian is None
                else RadianceJacobian(radiance_jacobian, state_names)
            ),
        )

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

        import numpy as np

        try:
            return np.ctypeslib.as_array(raw.rows, shape=(raw.len,)).copy()
        finally:
            free(self._ctx, ctypes.byref(raw))

    def _free_spectrum(self, raw: CSpectrum) -> None:

        self._lib.zds_spectrum_free(self._ctx, ctypes.byref(raw))

    def _check(self, status: int) -> None:

        if status == 0:
            return

        message = self._lib.zds_last_error(self._ctx)
        raise RuntimeError((message or b"zdisamar error").decode("utf-8", errors="replace"))

    def __enter__(self) -> Self:

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()
