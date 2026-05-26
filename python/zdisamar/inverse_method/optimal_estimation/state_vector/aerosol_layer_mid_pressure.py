"""Aerosol layer pressure-placement retrieval parameter."""

from dataclasses import dataclass

from .pressure_altitude_profile import PressureAltitudeProfile

AEROSOL_LAYER_MID_PRESSURE_HPA = "aerosol_layer_mid_pressure_hpa"


def aerosol_layer_metadata(target) -> tuple[float, int]:
    """Read the case-owned layer thickness and fit interval used by ALH retrievals."""

    placement = target.aerosol.placement
    thickness_hpa = placement.bottom_pressure_hpa - placement.top_pressure_hpa

    if not thickness_hpa > 0.0:
        raise ValueError("aerosol layer pressure thickness must be positive")

    return thickness_hpa, placement.interval_index_1based


def write_aerosol_layer_mid_pressure(
    target,
    value: float,
    *,
    thickness_hpa: float,
    interval_index_1based: int,
) -> None:
    """Move the aerosol layer while preserving neighboring layer boundaries."""

    target.aerosol.require_retrieval_compatible()

    if not thickness_hpa > 0.0:
        raise ValueError("aerosol layer pressure thickness must be positive")

    half_thickness = 0.5 * thickness_hpa
    top_pressure = value - half_thickness
    bottom_pressure = value + half_thickness

    target.aerosol.placement.top_pressure_hpa = top_pressure
    target.aerosol.placement.bottom_pressure_hpa = bottom_pressure
    target.aerosol.replace_single_profile_layer(
        top_pressure_hpa=top_pressure,
        bottom_pressure_hpa=bottom_pressure,
    )

    updated_fit_interval = False

    for interval in target.atmosphere.intervals:
        if interval.index_1based == interval_index_1based:
            interval.top_pressure_hpa = top_pressure
            interval.bottom_pressure_hpa = bottom_pressure
            updated_fit_interval = True
        elif interval.index_1based == interval_index_1based - 1:
            interval.bottom_pressure_hpa = top_pressure
        elif interval.index_1based == interval_index_1based + 1:
            interval.top_pressure_hpa = bottom_pressure

    if not updated_fit_interval:
        raise ValueError("aerosol fit interval is not present in the atmosphere")


@dataclass(frozen=True)
class ResolvedAerosolLayerMidPressure:
    """ALH state with case metadata for native OE and Jacobian scaling."""

    initial: float
    prior: float
    prior_uncertainty: float
    thickness_hpa: float
    interval_index_1based: int
    pressure_altitude_profile: PressureAltitudeProfile
    lower: float | None = None
    upper: float | None = None
    name: str = AEROSOL_LAYER_MID_PRESSURE_HPA
    jacobian_name: str = AEROSOL_LAYER_MID_PRESSURE_HPA

    def write_to(self, target, value: float) -> None:
        """Move the aerosol layer using the metadata resolved for this retrieval."""

        write_aerosol_layer_mid_pressure(
            target,
            value,
            thickness_hpa=self.thickness_hpa,
            interval_index_1based=self.interval_index_1based,
        )

    def jacobian_scale(self, value: float) -> float:
        """Convert altitude sensitivity into pressure sensitivity."""

        return self.pressure_altitude_profile.altitude_derivative_at_pressure(value)


@dataclass(frozen=True)
class AerosolLayerMidPressure:
    """State-vector coordinate for fixed-thickness aerosol layer placement."""

    initial: float
    prior: float
    prior_uncertainty: float
    lower: float | None = None
    upper: float | None = None
    name: str = AEROSOL_LAYER_MID_PRESSURE_HPA
    jacobian_name: str = AEROSOL_LAYER_MID_PRESSURE_HPA

    def write_to(self, target, value: float) -> None:
        """Move the aerosol layer while preserving neighboring layer boundaries."""

        thickness_hpa, interval_index_1based = aerosol_layer_metadata(target)
        write_aerosol_layer_mid_pressure(
            target,
            value,
            thickness_hpa=thickness_hpa,
            interval_index_1based=interval_index_1based,
        )

    def resolve_for_case(
        self,
        target,
        pressure_altitude_profile: PressureAltitudeProfile,
    ) -> ResolvedAerosolLayerMidPressure:
        """Attach case-derived metadata required by native OE and Jacobian scaling."""

        thickness_hpa, interval_index_1based = aerosol_layer_metadata(target)

        return ResolvedAerosolLayerMidPressure(
            initial=self.initial,
            prior=self.prior,
            prior_uncertainty=self.prior_uncertainty,
            thickness_hpa=thickness_hpa,
            interval_index_1based=interval_index_1based,
            pressure_altitude_profile=pressure_altitude_profile,
            lower=self.lower,
            upper=self.upper,
            name=self.name,
            jacobian_name=self.jacobian_name,
        )
