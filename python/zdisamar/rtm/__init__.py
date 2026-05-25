# pyright: reportUnsupportedDunderAll=false
"""Radiative-transfer model execution API."""

from importlib import import_module

_EXPORTS = {
    "AerosolProfileLayer": "..input.aerosol",
    "SessionCache": ".session_cache",
    "atmospheric_budget": ".run",
    "collision_induced_absorption": ".run",
    "instrument_response": ".run",
    "nominal_wavelengths": ".run",
    "o2_line_contributions": ".run",
    "o2a_reference_case": ".run",
    "reflectance_from_radiance": ".reflectance",
    "reflectance_jacobian_from_radiance_jacobian": ".reflectance",
    "reflectance_noise_from_sun_normalized_radiance_noise": ".reflectance",
    "solar_zenith_cosine": ".geometry",
    "solar_zenith_cosine_from_degrees": ".geometry",
    "spectrum": ".run",
    "sun_normalized_radiance": ".radiance",
}


def __getattr__(name: str):

    try:
        module_name = _EXPORTS[name]
    except KeyError as exc:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}") from exc

    value = getattr(import_module(module_name, __name__), name)
    globals()[name] = value

    return value


__all__ = [
    "AerosolProfileLayer",
    "SessionCache",
    "atmospheric_budget",
    "collision_induced_absorption",
    "instrument_response",
    "nominal_wavelengths",
    "o2_line_contributions",
    "o2a_reference_case",
    "reflectance_from_radiance",
    "reflectance_jacobian_from_radiance_jacobian",
    "reflectance_noise_from_sun_normalized_radiance_noise",
    "solar_zenith_cosine",
    "solar_zenith_cosine_from_degrees",
    "spectrum",
    "sun_normalized_radiance",
]
