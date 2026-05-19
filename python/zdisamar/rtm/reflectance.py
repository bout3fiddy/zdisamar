"""Reflectance-space helper functions."""

import math
from array import array
from collections.abc import Iterable, Sequence


def _is_row_sequence(values: Sequence[object]) -> bool:

    return (
        bool(values) and not isinstance(values[0], int | float) and hasattr(values[0], "__iter__")
    )


def reflectance_from_radiance(
    radiance: Iterable[float],
    irradiance: Iterable[float],
    solar_zenith_cosine: float,
) -> array[float]:
    """Return reflectance from radiance, irradiance, and solar zenith cosine."""

    factor = math.pi / float(solar_zenith_cosine)

    return array(
        "d",
        (
            float(value) * factor / float(scale)
            for value, scale in zip(radiance, irradiance, strict=True)
        ),
    )


def reflectance_jacobian_from_radiance_jacobian(
    radiance_jacobian,
    irradiance: Iterable[float],
    solar_zenith_cosine: float,
) -> array[float] | tuple[array[float], ...]:
    """Convert dL/dx to dR/dx for R = pi * L / (mu0 * E0)."""

    scales = array(
        "d",
        (float(solar_zenith_cosine) * float(value) / math.pi for value in irradiance),
    )
    jacobian = tuple(radiance_jacobian)

    if _is_row_sequence(jacobian):
        return tuple(
            array("d", (float(value) / scale for value in row))
            for row, scale in zip(jacobian, scales, strict=True)
        )

    return array(
        "d",
        (float(value) / scale for value, scale in zip(jacobian, scales, strict=True)),
    )


def reflectance_noise_from_sun_normalized_radiance_noise(
    noise: Iterable[float],
    solar_zenith_cosine: float,
) -> array[float]:
    """Convert sun-normalized radiance noise to reflectance noise."""

    factor = math.pi / float(solar_zenith_cosine)

    return array("d", (float(value) * factor for value in noise))
