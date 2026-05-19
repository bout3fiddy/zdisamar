"""Dataclass outputs for RTM spectra."""

from array import array
from collections.abc import Sequence
from dataclasses import dataclass

from ..display import NotebookDisplay
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

    wavelength_nm: array[float]


@dataclass(frozen=True)
class Radiance:
    """Radiance samples on a spectral axis."""

    values: array[float]


@dataclass(frozen=True)
class Irradiance:
    """Irradiance samples on a spectral axis."""

    values: array[float]


@dataclass(frozen=True)
class Reflectance:
    """Reflectance samples on a spectral axis."""

    values: array[float]


@dataclass(frozen=True)
class RadianceJacobian:
    """Radiance Jacobian columns returned by the RTM."""

    values: tuple[array[float], ...]
    state_names: tuple[str, ...]


@dataclass(frozen=True)
class ReflectanceJacobian:
    """Reflectance Jacobian columns used by inverse methods."""

    values: tuple[array[float], ...]
    state_names: tuple[str, ...]


@dataclass(frozen=True)
class Spectrum(NotebookDisplay):
    """Copied RTM spectrum arrays."""

    axis: SpectralAxis
    radiance_quantity: Radiance
    irradiance_quantity: Irradiance
    reflectance_quantity: Reflectance
    case: O2AInput | None = None
    solar_mu0_value: float | None = None
    diagnostic_report: DiagnosticReport | None = None
    radiance_jacobian_quantity: RadianceJacobian | None = None
    reflectance_jacobian_quantity: ReflectanceJacobian | None = None

    def __repr__(self) -> str:

        wavelength_range = _value_range(self.wavelength_nm, "nm")
        reflectance_range = _value_range(self.reflectance)
        jacobian = "yes" if self.radiance_jacobian_quantity is not None else "no"

        return (
            "Spectrum(\n"
            f"  samples={len(self.wavelength_nm)},\n"
            f"  wavelength={wavelength_range},\n"
            f"  reflectance={reflectance_range},\n"
            f"  jacobian={jacobian},\n"
            ")"
        )

    @property
    def input(self) -> O2AInput | None:
        """Return the wavelength-band case associated with this spectrum."""

        return self.case

    @property
    def solar_mu0(self) -> float | None:

        if self.case is None:
            return self.solar_mu0_value

        return self.case.geometry.solar_mu0

    @property
    def wavelength_nm(self) -> array[float]:

        return self.axis.wavelength_nm

    @property
    def radiance(self) -> array[float]:

        return self.radiance_quantity.values

    @property
    def irradiance(self) -> array[float]:

        return self.irradiance_quantity.values

    @property
    def reflectance(self) -> array[float]:

        return self.reflectance_quantity.values

    @property
    def sun_normalized_radiance(self) -> array[float]:
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
    def radiance_jacobian(self) -> tuple[array[float], ...]:
        """Return d(radiance)/d(state) before reflectance scaling."""

        if self.radiance_jacobian_quantity is None:
            raise RuntimeError("spectrum does not include a radiance Jacobian")

        return self.radiance_jacobian_quantity.values

    def reflectance_jacobian(self, state: str) -> array[float]:
        """Return d(reflectance)/d(state) for one retrieval variable."""

        names = self.jacobian_state_names

        if state not in names:
            raise ValueError(f"unknown Jacobian state: {state}")

        index = names.index(state)

        if self.reflectance_jacobian_quantity is not None:
            return array(
                "d",
                (row[index] for row in self.reflectance_jacobian_quantity.values),
            )

        mu0 = self.solar_mu0

        if mu0 is None:
            raise RuntimeError("spectrum input geometry is unavailable")

        from ..rtm.reflectance import reflectance_jacobian_from_radiance_jacobian

        jacobian = reflectance_jacobian_from_radiance_jacobian(
            (row[index] for row in self.radiance_jacobian),
            self.irradiance,
            mu0,
        )

        if isinstance(jacobian, tuple):
            raise RuntimeError("unexpected matrix-valued reflectance Jacobian")

        return jacobian

    @property
    def plot(self):
        """Import plotting only when a caller asks for spectrum figures."""

        from ..plot.spectrum import SpectrumPlot

        return SpectrumPlot(self)


def _value_range(values: Sequence[float], unit: str = "") -> str:

    if not values:
        return "empty"

    suffix = f" {unit}" if unit else ""
    finite_values = [float(value) for value in values if value == value]

    if not finite_values:
        return f"nan..nan{suffix}"

    return f"{min(finite_values):.6g}..{max(finite_values):.6g}{suffix}"
