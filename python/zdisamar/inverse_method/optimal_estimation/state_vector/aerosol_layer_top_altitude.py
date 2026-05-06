"""Aerosol layer altitude-placement retrieval parameter."""

from __future__ import annotations

from dataclasses import dataclass

from .pressure_altitude_profile import PressureAltitudeProfile

AEROSOL_LAYER_TOP_ALTITUDE_KM = "aerosol_layer_top_altitude_km"


@dataclass(frozen=True)
class AerosolLayerTopAltitude:
    """State-vector coordinate for fixed-pressure-thickness aerosol layer placement."""

    initial: float
    prior: float
    variance: float
    pressure_thickness_hpa: float
    interval_index_1based: int
    pressure_altitude_profile: PressureAltitudeProfile
    lower: float | None = None
    upper: float | None = None
    name: str = AEROSOL_LAYER_TOP_ALTITUDE_KM
    jacobian_name: str = "aerosol_layer_mid_pressure_hpa"

    def pressure_bounds(self, value: float) -> tuple[float, float]:
        if not self.pressure_thickness_hpa > 0.0:
            raise ValueError("aerosol layer pressure thickness must be positive")
        top_pressure = self.pressure_altitude_profile.pressure_at_altitude(value)
        return top_pressure, top_pressure + self.pressure_thickness_hpa

    def write_to(self, target, value: float) -> None:
        top_pressure, bottom_pressure = self.pressure_bounds(value)

        target.aerosol.placement.top_pressure_hpa = top_pressure
        target.aerosol.placement.bottom_pressure_hpa = bottom_pressure

        updated_fit_interval = False
        for interval in target.atmosphere.intervals:
            if interval.index_1based == self.interval_index_1based:
                interval.top_pressure_hpa = top_pressure
                interval.bottom_pressure_hpa = bottom_pressure
                updated_fit_interval = True
            elif interval.index_1based == self.interval_index_1based - 1:
                interval.bottom_pressure_hpa = top_pressure
            elif interval.index_1based == self.interval_index_1based + 1:
                interval.top_pressure_hpa = bottom_pressure

        if not updated_fit_interval:
            raise ValueError("aerosol fit interval is not present in the atmosphere")
