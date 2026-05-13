"""Geometry helper functions used by RTM conversions."""

import math


def solar_zenith_cosine_from_degrees(solar_zenith_deg: float) -> float:
    """Return cos(solar zenith angle)."""

    return math.cos(math.radians(float(solar_zenith_deg)))


def solar_zenith_cosine(geometry) -> float:
    """Return cos(solar zenith angle) from a geometry object."""

    return solar_zenith_cosine_from_degrees(float(geometry.solar_zenith_deg))
