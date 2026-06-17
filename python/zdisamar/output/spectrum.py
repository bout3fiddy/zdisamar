"""Dataclass outputs for RTM spectra."""

from array import array
from collections.abc import Sequence
from dataclasses import dataclass

from ..input.wavelength_band.o2a import Scene

JACOBIAN_STATE_NAMES = (
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
class RadianceJacobian:
    """Radiance Jacobian columns returned by the RTM."""

    values: tuple[array, ...]
    state_names: tuple[str, ...]


@dataclass(frozen=True)
class ReflectanceJacobian:
    """Reflectance Jacobian columns used by inverse methods."""

    values: tuple[array, ...]
    state_names: tuple[str, ...]


@dataclass(frozen=True)
class Spectrum:
    """Copied RTM spectrum arrays."""

    wavelength_nm: array
    radiance: array
    irradiance: array
    reflectance: array
    scene: Scene | None = None
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
    def input(self) -> Scene | None:
        """Return the wavelength-band scene associated with this spectrum."""

        return self.scene

    @property
    def solar_mu0(self) -> float | None:

        if self.scene is None:
            return self.solar_mu0_value

        return self.scene.geometry.solar_mu0

    @property
    def sun_normalized_radiance(self) -> array:
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
    def radiance_jacobian(self) -> tuple[array, ...]:
        """Return d(radiance)/d(state) before reflectance scaling."""

        if self.radiance_jacobian_quantity is None:
            raise RuntimeError("spectrum does not include a radiance Jacobian")

        return self.radiance_jacobian_quantity.values

    def reflectance_jacobian(self, state: str) -> array:
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
