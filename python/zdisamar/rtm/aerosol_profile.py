"""Aerosol-profile forward-spectrum inputs."""

from dataclasses import dataclass


@dataclass(frozen=True)
class AerosolProfileLayer:
    """One pressure-bounded aerosol component used for forward truth spectra."""

    top_pressure_hpa: float
    bottom_pressure_hpa: float
    optical_depth: float
    single_scatter_albedo: float = 0.93
    asymmetry_factor: float = 0.65
    angstrom_exponent: float = 1.3
    reference_wavelength_nm: float = 550.0
