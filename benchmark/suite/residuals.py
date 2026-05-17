"""Residual calculations used by the benchmark."""

import math
from pathlib import Path
from typing import Any

import numpy as np
from zdisamar.inverse_method.optimal_estimation import o2a as band_retrieval
from zdisamar.output.spectrum import Spectrum

from validation.o2a.measurement_noise import components_from_spectrum
from validation.spectra.residuals import residual_metrics

from . import config


def reference_spectrum_metrics(
    case: Any,
    spectrum: Spectrum,
) -> dict[str, Any]:

    pressure_scale = mid_pressure_jacobian_scale(case)
    radiance_reference = load_csv(config.RADIANCE_REFERENCE_PATH)
    jacobian_reference = load_csv(config.REFLECTANCE_JACOBIAN_REFERENCE_PATH)
    wavelength_nm = spectrum.wavelength_nm
    mu0 = math.cos(math.radians(case.geometry.solar_zenith_deg))
    series = {
        "RTM reflectance": (
            spectrum.reflectance,
            np.interp(
                wavelength_nm,
                radiance_reference["wavelength_nm"],
                radiance_reference["sun_normalized_radiance"],
            )
            * np.pi
            / mu0,
        )
    }

    for state_name in config.FORWARD_STATE_NAMES:
        label = {
            "aerosol_optical_depth": "dR/d aerosol optical depth",
            "aerosol_layer_mid_pressure_hpa": "dR/d aerosol layer mid pressure",
        }[state_name]
        reference_values = np.interp(
            wavelength_nm,
            jacobian_reference["wavelength_nm"],
            jacobian_reference[config.REFERENCE_COLUMNS[state_name]],
        )
        current_values = spectrum.reflectance_jacobian(state_name)

        if state_name == "aerosol_layer_mid_pressure_hpa":
            reference_values = reference_values * pressure_scale
            current_values = current_values * pressure_scale

        series[label] = (current_values, reference_values)

    return {
        label: metric_payload(wavelength_nm, current - reference)
        for label, (current, reference) in series.items()
    }


def spectrum_delta_metrics(reference: Spectrum, current: Spectrum) -> dict[str, float]:

    payload = {
        "radiance_max_abs": max_abs(current.radiance - reference.radiance),
        "irradiance_max_abs": max_abs(current.irradiance - reference.irradiance),
        "reflectance_max_abs": max_abs(current.reflectance - reference.reflectance),
    }

    for state_name in config.FORWARD_STATE_NAMES:
        key = f"reflectance_jacobian_{state_name}_max_abs"
        payload[key] = max_abs(
            current.reflectance_jacobian(state_name) - reference.reflectance_jacobian(state_name)
        )

    return payload


def fast_scene_metrics(label: str, reference: Spectrum, fast: Spectrum) -> dict[str, Any]:

    residual = fast.reflectance - reference.reflectance
    metric = residual_metrics(reference.wavelength_nm, residual)
    noise = components_from_spectrum(
        wavelength_nm=reference.wavelength_nm,
        radiance=reference.radiance,
        irradiance=reference.irradiance,
        reflectance=reference.reflectance,
    ).reflectance_noise
    normalized = residual / np.maximum(noise, np.finfo(np.float64).tiny)

    return {
        "scene": label,
        "max_abs_residual": metric["max_abs_residual"],
        "max_abs_residual_wavelength_nm": metric["max_abs_wavelength_nm"],
        "rmse": metric["rmse"],
        "max_abs_residual_over_noise": float(np.max(np.abs(normalized))),
        "median_abs_residual_over_noise": float(np.median(np.abs(normalized))),
    }


def truth_residual(
    reference: dict[str, Any],
    result: Any,
    layer_thickness: float,
) -> dict[str, float]:

    retrieved = reference.get("truth", reference["retrieved"])
    mid_pressure = result.value("aerosol_layer_mid_pressure_hpa")
    top_pressure = mid_pressure - 0.5 * layer_thickness

    return {
        "aerosol_optical_depth_abs_diff": abs(
            result.value("aerosol_optical_depth") - float(retrieved["aerosol_optical_depth"])
        ),
        "aerosol_layer_top_pressure_abs_diff_hpa": abs(
            top_pressure - float(retrieved["aerosol_layer_top_pressure_hpa"])
        ),
        "aerosol_layer_mid_pressure_abs_diff_hpa": abs(
            mid_pressure - float(retrieved["aerosol_layer_mid_pressure_hpa"])
        ),
    }


def result_delta(current: Any, reference: Any) -> dict[str, float]:

    return {
        "aerosol_optical_depth_delta": current.value("aerosol_optical_depth")
        - reference.value("aerosol_optical_depth"),
        "aerosol_layer_mid_pressure_delta_hpa": current.value("aerosol_layer_mid_pressure_hpa")
        - reference.value("aerosol_layer_mid_pressure_hpa"),
    }


def mid_pressure_jacobian_scale(case: Any) -> float:

    profile = band_retrieval.pressure_altitude_profile_from_case(case)
    aerosol_mid_pressure_hpa = 0.5 * (
        case.aerosol.placement.top_pressure_hpa + case.aerosol.placement.bottom_pressure_hpa
    )

    return profile.altitude_derivative_at_pressure(aerosol_mid_pressure_hpa)


def metric_payload(wavelength_nm: np.ndarray, residual: np.ndarray) -> dict[str, float]:

    interior = slice(
        config.SPECTRA_EDGE_EXCLUSION_COUNT,
        len(wavelength_nm) - config.SPECTRA_EDGE_EXCLUSION_COUNT,
    )
    metric = residual_metrics(wavelength_nm[interior], residual[interior])
    full = residual_metrics(wavelength_nm, residual)

    return {
        "max_abs_residual": metric["max_abs_residual"],
        "max_abs_wavelength_nm": metric["max_abs_wavelength_nm"],
        "rmse": metric["rmse"],
        "mean_signed": metric["mean_signed"],
        "full_grid_max_abs_residual": full["max_abs_residual"],
    }


def max_abs(values: np.ndarray) -> float:

    return float(np.max(np.abs(values)))


def load_csv(path: Path) -> np.ndarray:

    return np.genfromtxt(path, delimiter=",", names=True, dtype=np.float64)
