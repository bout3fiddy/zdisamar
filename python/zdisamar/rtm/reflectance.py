"""Reflectance-space helper functions."""

import math

import numpy as np
from numpy.typing import ArrayLike, NDArray


def reflectance_from_radiance(
    radiance: ArrayLike,
    irradiance: ArrayLike,
    solar_zenith_cosine: float,
) -> NDArray[np.float64]:
    """Return reflectance from radiance, irradiance, and solar zenith cosine."""

    return (
        np.asarray(radiance, dtype=np.float64)
        * np.pi
        / (float(solar_zenith_cosine) * np.asarray(irradiance, dtype=np.float64))
    )


def reflectance_jacobian_from_radiance_jacobian(
    radiance_jacobian: ArrayLike,
    irradiance: ArrayLike,
    solar_zenith_cosine: float,
) -> NDArray[np.float64]:
    """Convert dL/dx to dR/dx for R = pi * L / (mu0 * E0)."""

    jacobian = np.asarray(radiance_jacobian, dtype=np.float64)
    scale = float(solar_zenith_cosine) * np.asarray(irradiance, dtype=np.float64) / math.pi

    if jacobian.ndim == 1:
        return jacobian / scale

    return jacobian / scale[..., None]


def reflectance_noise_from_sun_normalized_radiance_noise(
    noise: ArrayLike,
    solar_zenith_cosine: float,
) -> NDArray[np.float64]:
    """Convert sun-normalized radiance noise to reflectance noise."""

    return np.asarray(noise, dtype=np.float64) * (math.pi / float(solar_zenith_cosine))
