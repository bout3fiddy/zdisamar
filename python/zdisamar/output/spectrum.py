"""Spectrum result wrappers for zdisamar O2 A model output."""

from dataclasses import dataclass
from typing import Any

from ..bindings.structures import CSpectrum
from ..input.wavelength_band.o2a import O2AInput

JACOBIAN_STATE_NAMES = (
    "surface_albedo",
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)


@dataclass(frozen=True)
class DiagnosticReport:
    """Small spectrum summary that remains valid after arrays are closed."""

    sample_count: int
    wavelength_start_nm: float
    wavelength_end_nm: float
    mean_radiance: float
    mean_irradiance: float
    mean_reflectance: float


class Spectrum:
    """Radiance, irradiance, reflectance, and Jacobians from one O2 A run."""

    def __init__(
        self,
        owner: Any,
        raw: CSpectrum,
        close_owner: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ):

        self._owner = owner
        self._raw = raw
        self._close_owner = close_owner
        self._jacobian_state_names = jacobian_state_names
        self._diagnostic_report: DiagnosticReport | None = None

    def _array(self, pointer: object) -> Any:
        """Expose model-owned spectrum memory as an array while it is open."""

        self._require_open()
        import numpy as np

        return np.ctypeslib.as_array(pointer, shape=(self._raw.len,))

    def _require_open(self) -> Any:

        owner = self._owner

        if owner is None or owner._ctx is None:
            raise RuntimeError("spectrum is closed")

        return owner

    @property
    def input(self) -> O2AInput | None:
        """Return the O2 A scene associated with this spectrum."""

        owner = self._require_open()

        return owner.input

    @property
    def solar_mu0(self) -> float | None:

        input = self.input

        if input is None:
            return None

        return input.geometry.solar_mu0

    @property
    def wavelength_nm(self) -> Any:

        return self._array(self._raw.wavelength_nm)

    @property
    def radiance(self) -> Any:

        return self._array(self._raw.radiance)

    @property
    def irradiance(self) -> Any:

        return self._array(self._raw.irradiance)

    @property
    def reflectance(self) -> Any:

        return self._array(self._raw.reflectance)

    @property
    def sun_normalized_radiance(self) -> Any:
        """Use the same radiance normalization as the validation analysis."""

        from ..quantities import sun_normalized_radiance

        return sun_normalized_radiance(self.radiance, self.irradiance)

    def reflectance_jacobian(self, state: str) -> Any:
        """Return d(reflectance)/d(state) for one retrieval variable."""

        names = self.jacobian_state_names

        if state not in names:
            raise ValueError(f"unknown Jacobian state: {state}")

        mu0 = self.solar_mu0

        if mu0 is None:
            raise RuntimeError("spectrum input geometry is unavailable")

        from ..quantities import reflectance_jacobian_from_radiance_jacobian

        index = names.index(state)

        return reflectance_jacobian_from_radiance_jacobian(
            self.radiance_jacobian[:, index],
            self.irradiance,
            mu0,
        )

    @property
    def jacobian_state_names(self) -> tuple[str, ...]:
        """Name Jacobian columns so retrieval code can request them explicitly."""

        if self._raw.jacobian_state_count == 0:
            return ()

        if self._jacobian_state_names is not None:
            if len(self._jacobian_state_names) != self._raw.jacobian_state_count:
                raise RuntimeError("spectrum Jacobian state names do not match model output")

            return self._jacobian_state_names

        return JACOBIAN_STATE_NAMES[0 : self._raw.jacobian_state_count]

    @property
    def radiance_jacobian(self) -> Any:
        """Return d(radiance)/d(state) before reflectance scaling."""

        self._require_open()

        if not self._raw.jacobian or self._raw.jacobian_state_count == 0:
            raise RuntimeError("spectrum does not include a Jacobian")

        import numpy as np

        flat = np.ctypeslib.as_array(
            self._raw.jacobian,
            shape=(self._raw.len * self._raw.jacobian_state_count,),
        )

        return flat.reshape((self._raw.len, self._raw.jacobian_state_count))

    @property
    def plot(self):
        """Import plotting only when a caller asks for spectrum figures."""

        from ..plot.spectrum import SpectrumPlot

        return SpectrumPlot(self)

    @property
    def diagnostic_report(self) -> DiagnosticReport:
        """Ask for the compact spectrum summary only when needed."""

        owner = self._require_open()

        if self._diagnostic_report is None:
            self._diagnostic_report = owner._spectrum_report(self._raw)

        report = self._diagnostic_report

        if report is None:
            raise RuntimeError("spectrum diagnostic report is unavailable")

        return report

    def close(self) -> None:
        """Release spectrum arrays held by the zdisamar model."""

        if self._owner is not None:
            owner = self._owner
            owner._free_spectrum(self._raw)

            if self._close_owner:
                owner.close()

            self._owner = None
            self._raw = CSpectrum()
            self._close_owner = False

    def __enter__(self) -> Spectrum:

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()
