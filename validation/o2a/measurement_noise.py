"""Retained O2 A baseline measurement-noise helpers."""

from dataclasses import dataclass
from functools import cache

import numpy as np
from zdisamar import reference_data, rtm
from zdisamar.inverse_method import optimal_estimation

from validation.o2a import baseline

S5_REFERENCE_RADIANCE_PATH = "noise/o2a_s5_reference_radiance_755_775.csv"
MIN_REFLECTANCE_NOISE = 1.0e-12


@dataclass(frozen=True)
class O2ANoiseComponents:
    """Wavelength-dependent SNR and reflectance uncertainty terms."""

    wavelength_nm: np.ndarray
    radiance_snr: np.ndarray
    irradiance_snr: np.ndarray
    reflectance_snr: np.ndarray
    reflectance_noise: np.ndarray

    def snr_table(self) -> tuple[list[float], list[float]]:

        return (
            self.wavelength_nm.astype(float).tolist(),
            self.reflectance_snr.astype(float).tolist(),
        )


def measurement_from_o2a_baseline_noise(case) -> optimal_estimation.Measurement:
    """Build a reflectance measurement with retained O2 A baseline SNR semantics."""

    spectrum = rtm.spectrum(case)
    wavelength_nm = np.asarray(spectrum.wavelength_nm, dtype=np.float64).copy()
    radiance = np.asarray(spectrum.radiance, dtype=np.float64).copy()
    irradiance = np.asarray(spectrum.irradiance, dtype=np.float64).copy()
    reflectance = np.asarray(spectrum.reflectance, dtype=np.float64).copy()

    noise = components_from_spectrum(
        wavelength_nm=wavelength_nm,
        radiance=radiance,
        irradiance=irradiance,
        reflectance=reflectance,
    )

    return optimal_estimation.Measurement(
        wavelength_nm=wavelength_nm.tolist(),
        reflectance=reflectance.tolist(),
        signal_to_noise=noise.reflectance_snr.tolist(),
    )


def components_from_spectrum(
    *,
    wavelength_nm,
    radiance,
    irradiance,
    reflectance,
) -> O2ANoiseComponents:
    """Return SNR components for one O2 A spectrum."""

    wavelength = _one_dimensional_array("wavelength_nm", wavelength_nm)
    radiance_values = _positive_array("radiance", radiance, wavelength.size)
    irradiance_values = _positive_array("irradiance", irradiance, wavelength.size)
    reflectance_values = _one_dimensional_array("reflectance", reflectance)

    if reflectance_values.size != wavelength.size:
        raise ValueError("reflectance must match wavelength_nm length")

    reference_radiance = instrument_mapped_s5_reference_radiance(wavelength)
    reference_anchor = instrument_mapped_s5_reference_radiance(
        np.array([baseline.RADIANCE_SNR_WAVELENGTH_NM], dtype=np.float64)
    )[0]
    current_irradiance_anchor = float(
        np.interp(
            baseline.IRRADIANCE_SNR_WAVELENGTH_NM,
            wavelength,
            irradiance_values,
        )
    )

    reference_snr = baseline.RADIANCE_REFERENCE_SNR * np.sqrt(reference_radiance / reference_anchor)
    radiance_snr = (
        reference_snr
        * np.sqrt(radiance_values / reference_radiance)
        * np.sqrt(baseline.WAVELENGTH_STEP_NM / baseline.RADIANCE_REFERENCE_BIN_WIDTH_NM)
    )
    radiance_snr = np.minimum(radiance_snr, baseline.RADIANCE_SNR_MAX)

    irradiance_snr = baseline.IRRADIANCE_REFERENCE_SNR * np.sqrt(
        irradiance_values / current_irradiance_anchor
    )
    irradiance_snr = np.minimum(irradiance_snr, baseline.IRRADIANCE_SNR_MAX)

    reflectance_snr = 1.0 / np.sqrt(radiance_snr**-2 + irradiance_snr**-2)
    reflectance_noise = np.maximum(
        np.abs(reflectance_values) / reflectance_snr,
        MIN_REFLECTANCE_NOISE,
    )

    return O2ANoiseComponents(
        wavelength_nm=wavelength,
        radiance_snr=radiance_snr,
        irradiance_snr=irradiance_snr,
        reflectance_snr=reflectance_snr,
        reflectance_noise=reflectance_noise,
    )


def instrument_mapped_s5_reference_radiance(
    wavelength_nm,
) -> np.ndarray:
    """Map the S5 reference radiance spectrum onto the O2 A instrument grid."""

    target = _one_dimensional_array("wavelength_nm", wavelength_nm)
    reference_wavelength, reference_radiance = _load_s5_reference_radiance()
    half_span_nm = 3.0 * baseline.INSTRUMENT_LINE_FWHM_NM
    lower = reference_wavelength[0] + half_span_nm
    upper = reference_wavelength[-1] - half_span_nm

    if np.min(target) < lower or np.max(target) > upper:
        raise ValueError(
            "wavelength_nm extends beyond the S5 reference support needed for instrument mapping"
        )

    mapped = np.empty(target.shape, dtype=np.float64)

    for index, wavelength in enumerate(target):
        mapped[index] = _integrate_reference_radiance(
            wavelength,
            reference_wavelength,
            reference_radiance,
        )

    return mapped


def _integrate_reference_radiance(
    wavelength_nm: float,
    reference_wavelength: np.ndarray,
    reference_radiance: np.ndarray,
) -> float:

    half_span_nm = 3.0 * baseline.INSTRUMENT_LINE_FWHM_NM
    lower = wavelength_nm - half_span_nm
    upper = wavelength_nm + half_span_nm
    mask = (reference_wavelength >= lower) & (reference_wavelength <= upper)

    if not np.any(mask):
        raise ValueError("no S5 reference samples available for instrument mapping")

    offsets = reference_wavelength[mask] - wavelength_nm
    weights = _flat_top_n4_weights(offsets, baseline.INSTRUMENT_LINE_FWHM_NM)

    return float(np.sum(weights * reference_radiance[mask]) / np.sum(weights))


def _flat_top_n4_weights(offset_nm: np.ndarray, fwhm_nm: float) -> np.ndarray:

    width_nm = fwhm_nm / 1.681793

    return np.power(2.0, -2.0 * np.power(offset_nm / width_nm, 4.0))


@cache
def _load_s5_reference_radiance() -> tuple[np.ndarray, np.ndarray]:

    data = np.genfromtxt(
        reference_data.path(S5_REFERENCE_RADIANCE_PATH),
        delimiter=",",
        names=True,
    )
    wavelength = np.asarray(data["wavelength_nm"], dtype=np.float64)
    radiance = np.asarray(data["reference_radiance_photons_cm2_s_sr_nm"], dtype=np.float64)

    if wavelength.ndim != 1 or radiance.ndim != 1 or wavelength.size == 0:
        raise ValueError("S5 reference radiance asset must contain one-dimensional arrays")

    if wavelength.size != radiance.size:
        raise ValueError("S5 reference wavelength and radiance columns must match")

    if not np.all(np.diff(wavelength) > 0.0):
        raise ValueError("S5 reference wavelengths must be strictly increasing")

    if np.any(radiance <= 0.0):
        raise ValueError("S5 reference radiance values must be positive")

    return wavelength, radiance


def _one_dimensional_array(name: str, values) -> np.ndarray:

    array = np.asarray(values, dtype=np.float64)

    if array.ndim != 1 or array.size == 0:
        raise ValueError(f"{name} must be a non-empty one-dimensional array")

    if not np.all(np.isfinite(array)):
        raise ValueError(f"{name} must contain finite values")

    return array


def _positive_array(name: str, values, expected_size: int) -> np.ndarray:

    array = _one_dimensional_array(name, values)

    if array.size != expected_size:
        raise ValueError(f"{name} must match wavelength_nm length")

    if np.any(array <= 0.0):
        raise ValueError(f"{name} must contain positive values")

    return array
