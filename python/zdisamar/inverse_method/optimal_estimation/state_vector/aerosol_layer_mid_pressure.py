"""Aerosol layer pressure-placement retrieval parameter."""

from dataclasses import dataclass

from .pressure_altitude_profile import PressureAltitudeProfile

AEROSOL_LAYER_MID_PRESSURE_HPA = "aerosol_layer_mid_pressure_hpa"


@dataclass(frozen=True)
class AerosolLayerMidPressure:
    """State-vector coordinate for fixed-thickness aerosol layer placement."""

    initial: float
    prior: float
    variance: float
    thickness_hpa: float
    interval_index_1based: int
    pressure_altitude_profile: PressureAltitudeProfile
    lower: float | None = None
    upper: float | None = None
    name: str = AEROSOL_LAYER_MID_PRESSURE_HPA
    jacobian_name: str = AEROSOL_LAYER_MID_PRESSURE_HPA

    def write_to(self, target, value: float) -> None:
        """Move the aerosol layer while preserving neighboring layer boundaries."""

        if not self.thickness_hpa > 0.0:
            raise ValueError("aerosol layer pressure thickness must be positive")

        half_thickness = 0.5 * self.thickness_hpa
        top_pressure = value - half_thickness
        bottom_pressure = value + half_thickness

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

    def jacobian_scale(self, value: float) -> float:
        """Convert altitude sensitivity into pressure sensitivity."""

        return self.pressure_altitude_profile.altitude_derivative_at_pressure(value)
