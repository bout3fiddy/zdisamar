"""Radiance-space helper functions."""

from array import array
from collections.abc import Iterable


def sun_normalized_radiance(
    radiance: Iterable[float],
    irradiance: Iterable[float],
) -> array[float]:
    """Return radiance divided by irradiance."""

    return array(
        "d",
        (float(value) / float(scale) for value, scale in zip(radiance, irradiance, strict=True)),
    )
