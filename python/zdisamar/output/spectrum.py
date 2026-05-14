"""Dataclass outputs for RTM spectra."""

from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray

from ..input.wavelength_band.o2a import O2AInput

JACOBIAN_STATE_NAMES = (
    "surface_albedo",
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)


@dataclass(frozen=True)
class DiagnosticReport:
    """Compact spectrum summary."""

    sample_count: int
    wavelength_start_nm: float
    wavelength_end_nm: float
    mean_radiance: float
    mean_irradiance: float
    mean_reflectance: float


@dataclass(frozen=True)
class SpectralAxis:
    """Wavelength coordinates for one RTM spectrum."""

    wavelength_nm: NDArray[np.float64]


@dataclass(frozen=True)
class Radiance:
    """Radiance samples on a spectral axis."""

    values: NDArray[np.float64]


@dataclass(frozen=True)
class Irradiance:
    """Irradiance samples on a spectral axis."""

    values: NDArray[np.float64]


@dataclass(frozen=True)
class Reflectance:
    """Reflectance samples on a spectral axis."""

    values: NDArray[np.float64]


@dataclass(frozen=True)
class RadianceJacobian:
    """Radiance Jacobian columns returned by the RTM."""

    values: NDArray[np.float64]
    state_names: tuple[str, ...]


@dataclass(frozen=True)
class ReflectanceJacobian:
    """Reflectance Jacobian columns used by inverse methods."""

    values: NDArray[np.float64]
    state_names: tuple[str, ...]


@dataclass(frozen=True)
class Spectrum:
    """Copied RTM spectrum arrays."""

    axis: SpectralAxis
    radiance_quantity: Radiance
    irradiance_quantity: Irradiance
    reflectance_quantity: Reflectance
    case: O2AInput | None = None
    diagnostic_report: DiagnosticReport | None = None
    radiance_jacobian_quantity: RadianceJacobian | None = None
    reflectance_jacobian_quantity: ReflectanceJacobian | None = None

    @property
    def input(self) -> O2AInput | None:
        """Return the wavelength-band case associated with this spectrum."""

        return self.case

    @property
    def solar_mu0(self) -> float | None:

        if self.case is None:
            return None

        return self.case.geometry.solar_mu0

    @property
    def wavelength_nm(self) -> NDArray[np.float64]:

        return self.axis.wavelength_nm

    @property
    def radiance(self) -> NDArray[np.float64]:

        return self.radiance_quantity.values

    @property
    def irradiance(self) -> NDArray[np.float64]:

        return self.irradiance_quantity.values

    @property
    def reflectance(self) -> NDArray[np.float64]:

        return self.reflectance_quantity.values

    @property
    def sun_normalized_radiance(self) -> NDArray[np.float64]:
        """Use the same radiance normalization as validation analysis."""

        from ..rtm.radiance import sun_normalized_radiance

        return sun_normalized_radiance(self.radiance, self.irradiance)

    @property
    def jacobian_state_names(self) -> tuple[str, ...]:

        if self.radiance_jacobian_quantity is not None:
            return self.radiance_jacobian_quantity.state_names

        if self.reflectance_jacobian_quantity is not None:
            return self.reflectance_jacobian_quantity.state_names

        return ()

    @property
    def radiance_jacobian(self) -> NDArray[np.float64]:
        """Return d(radiance)/d(state) before reflectance scaling."""

        if self.radiance_jacobian_quantity is None:
            raise RuntimeError("spectrum does not include a radiance Jacobian")

        return self.radiance_jacobian_quantity.values

    def reflectance_jacobian(self, state: str) -> NDArray[np.float64]:
        """Return d(reflectance)/d(state) for one retrieval variable."""

        names = self.jacobian_state_names

        if state not in names:
            raise ValueError(f"unknown Jacobian state: {state}")

        index = names.index(state)

        if self.reflectance_jacobian_quantity is not None:
            return self.reflectance_jacobian_quantity.values[:, index]

        mu0 = self.solar_mu0

        if mu0 is None:
            raise RuntimeError("spectrum input geometry is unavailable")

        from ..rtm.reflectance import reflectance_jacobian_from_radiance_jacobian

        return reflectance_jacobian_from_radiance_jacobian(
            self.radiance_jacobian[:, index],
            self.irradiance,
            mu0,
        )

    @property
    def plot(self):
        """Import plotting only when a caller asks for spectrum figures."""

        from ..plot.spectrum import SpectrumPlot

        return SpectrumPlot(self)
