"""Prepared diagnostic accessors that still have first-class plot users."""

from typing import Any


class OxygenCollisionInducedAbsorptionDiagnostics:
    """O2-O2 collision-induced absorption diagnostics from the native core."""

    def __init__(self, prepared: Any):

        self._prepared = prepared

    def diagnostics(self, wavelengths_nm):

        return self._prepared.collision_induced_absorption_diagnostics(wavelengths_nm)


class InstrumentResponseDiagnostics:
    """Instrument response and high-resolution wavelength sampling diagnostics."""

    def __init__(self, prepared: Any):

        self._prepared = prepared

    def sampling_table(
        self,
        wavelengths_nm=None,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ):

        import numpy as np

        case = self._prepared.input
        nominal = (
            _nominal_wavelengths(case)
            if wavelengths_nm is None
            else np.asarray(wavelengths_nm, dtype=np.float64)
        )

        return self._prepared.instrument_response_sampling(nominal, channels=channels)


def _nominal_wavelengths(case):

    import numpy as np

    return np.linspace(
        case.spectral_grid.start_nm,
        case.spectral_grid.end_nm,
        case.spectral_grid.sample_count,
        dtype=np.float64,
    )
