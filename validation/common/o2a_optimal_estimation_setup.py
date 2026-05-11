"""Shared O2 A optimal-estimation validation setup."""

import copy
import math
from typing import Any

import numpy as np
from zdisamar.inverse_method import optimal_estimation

from validation.common import o2a_retrieval_baseline as oe_baseline


def uniform_lhs(rng: np.random.Generator, low: float, high: float, count: int) -> np.ndarray:
    values = (np.arange(count, dtype=np.float64) + rng.random(count)) / count
    rng.shuffle(values)
    return low + values * (high - low)


def sampled_scenes(count: int, seed: int) -> list[dict[str, float]]:
    rng = np.random.default_rng(seed)
    solar = uniform_lhs(rng, 25.0, 65.0, count)
    view = uniform_lhs(rng, 0.0, 50.0, count)
    azimuth = uniform_lhs(rng, 0.0, 180.0, count)
    surface_pressure = uniform_lhs(rng, 820.0, 1040.0, count)
    surface_albedo = uniform_lhs(rng, 0.05, 0.55, count)
    aerosol_optical_depth = np.exp(uniform_lhs(rng, math.log(0.10), math.log(2.0), count))
    mid_fraction = uniform_lhs(rng, 0.18, 0.78, count)
    scenes: list[dict[str, float]] = []
    for index in range(count):
        mid_min = 225.0
        mid_max = surface_pressure[index] - 100.0
        scenes.append(
            {
                "solar_zenith_deg": float(solar[index]),
                "viewing_zenith_deg": float(view[index]),
                "relative_azimuth_deg": float(azimuth[index]),
                "surface_pressure_hpa": float(surface_pressure[index]),
                "surface_albedo": float(surface_albedo[index]),
                "aerosol_optical_depth": float(aerosol_optical_depth[index]),
                "aerosol_mid_pressure_hpa": float(
                    mid_min + mid_fraction[index] * (mid_max - mid_min)
                ),
            }
        )
    return scenes


def initial_aod(truth: float, index: int) -> float:
    factor = 1.12 if index % 2 == 0 else 0.88
    return min(5.0, max(0.02, truth * factor + 0.01))


def initial_mid_pressure(truth: float, surface_pressure: float, index: int) -> float:
    offset = [-25.0, -15.0, 15.0, 25.0][index % 4]
    return min(surface_pressure - 75.0, max(100.0, truth + offset))


def initial_state(index: int, scene: dict[str, float]) -> dict[str, float]:
    return {
        "aerosol_optical_depth": initial_aod(scene["aerosol_optical_depth"], index),
        "aerosol_mid_pressure_hpa": initial_mid_pressure(
            scene["aerosol_mid_pressure_hpa"],
            scene["surface_pressure_hpa"],
            index,
        ),
    }


def layer_bounds(
    mid_pressure_hpa: float,
    *,
    thickness_hpa: float = oe_baseline.LAYER_THICKNESS_HPA,
) -> tuple[float, float]:
    return (
        mid_pressure_hpa - 0.5 * thickness_hpa,
        mid_pressure_hpa + 0.5 * thickness_hpa,
    )


def update_layer_pressures(
    case: Any,
    mid_pressure_hpa: float,
    *,
    thickness_hpa: float = oe_baseline.LAYER_THICKNESS_HPA,
) -> None:
    top_pressure, bottom_pressure = layer_bounds(
        mid_pressure_hpa,
        thickness_hpa=thickness_hpa,
    )
    case.aerosol.placement.top_pressure_hpa = top_pressure
    case.aerosol.placement.bottom_pressure_hpa = bottom_pressure
    for interval in case.atmosphere.intervals:
        if interval.index_1based == 1:
            interval.bottom_pressure_hpa = top_pressure
        elif interval.index_1based == 2:
            interval.top_pressure_hpa = top_pressure
            interval.bottom_pressure_hpa = bottom_pressure
        elif interval.index_1based == 3:
            interval.top_pressure_hpa = bottom_pressure
            interval.bottom_pressure_hpa = case.surface.pressure_hpa


def build_scene(
    base: Any,
    *,
    index: int,
    id_prefix: str,
    scene: dict[str, float],
    id_width: int = 3,
) -> Any:
    case = copy.deepcopy(base)
    scene_id = f"{id_prefix}_{index:0{id_width}d}"
    case.metadata["id"] = scene_id
    case.scene_id = scene_id
    case.geometry.solar_zenith_deg = scene["solar_zenith_deg"]
    case.geometry.viewing_zenith_deg = scene["viewing_zenith_deg"]
    case.geometry.relative_azimuth_deg = scene["relative_azimuth_deg"]
    case.surface.pressure_hpa = scene["surface_pressure_hpa"]
    case.surface.albedo = scene["surface_albedo"]
    case.aerosol.optical_depth_550_nm = scene["aerosol_optical_depth"]
    case.aerosol.single_scatter_albedo = oe_baseline.AEROSOL_SINGLE_SCATTER_ALBEDO
    case.aerosol.asymmetry_factor = oe_baseline.AEROSOL_ASYMMETRY_FACTOR
    case.aerosol.angstrom_exponent = oe_baseline.AEROSOL_ANGSTROM_EXPONENT
    update_layer_pressures(case, scene["aerosol_mid_pressure_hpa"])
    return case


def retrieval_controls() -> optimal_estimation.RetrievalControls:
    return optimal_estimation.RetrievalControls(
        max_iterations=10,
        state_vector_convergence_threshold=1.0,
        max_change_transformed_state=1.0,
        collect_timing=True,
    )


def aerosol_two_state_vector(
    *,
    initial: dict[str, float],
    profile: optimal_estimation.PressureAltitudeProfile,
    surface_pressure_hpa: float,
    interval_index_1based: int = 2,
    thickness_hpa: float = oe_baseline.LAYER_THICKNESS_HPA,
    aod_variance: float = 0.8,
    aod_lower: float = 0.02,
    aod_upper: float | None = 5.0,
    mid_pressure_variance_hpa2: float = 150.0**2,
    mid_pressure_lower_hpa: float | None = 225.0,
    mid_pressure_upper_hpa: float | None = None,
) -> optimal_estimation.StateVector:
    upper = (
        surface_pressure_hpa - 100.0 if mid_pressure_upper_hpa is None else mid_pressure_upper_hpa
    )
    return optimal_estimation.StateVector(
        [
            optimal_estimation.AerosolOpticalDepth(
                initial=initial["aerosol_optical_depth"],
                prior=initial["aerosol_optical_depth"],
                variance=aod_variance,
                lower=aod_lower,
                upper=aod_upper,
            ),
            optimal_estimation.AerosolLayerMidPressure(
                initial=initial["aerosol_mid_pressure_hpa"],
                prior=initial["aerosol_mid_pressure_hpa"],
                variance=mid_pressure_variance_hpa2,
                thickness_hpa=thickness_hpa,
                interval_index_1based=interval_index_1based,
                pressure_altitude_profile=profile,
                lower=mid_pressure_lower_hpa,
                upper=upper,
            ),
        ]
    )


def reference_two_state_vector(
    *,
    case: Any,
    reference: dict[str, Any],
    profile: optimal_estimation.PressureAltitudeProfile,
) -> optimal_estimation.StateVector:
    prior = reference["a_priori"]
    layer_thickness = (
        case.aerosol.placement.bottom_pressure_hpa - case.aerosol.placement.top_pressure_hpa
    )
    return aerosol_two_state_vector(
        initial={
            "aerosol_optical_depth": float(prior["aerosol_optical_depth"]),
            "aerosol_mid_pressure_hpa": float(prior["aerosol_layer_mid_pressure_hpa"]),
        },
        profile=profile,
        surface_pressure_hpa=case.surface.pressure_hpa,
        interval_index_1based=case.aerosol.placement.interval_index_1based,
        thickness_hpa=layer_thickness,
        aod_variance=1.0,
        aod_lower=0.0,
        aod_upper=None,
        mid_pressure_variance_hpa2=float(prior["aerosol_layer_mid_pressure_variance_hpa2"]),
        mid_pressure_lower_hpa=None,
        mid_pressure_upper_hpa=None,
    )
