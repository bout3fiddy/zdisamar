"""Shared physical quantity conversions for O2 A spectra."""

import math
from typing import Any


def solar_mu0_from_zenith_deg(solar_zenith_deg: float) -> float:
    """Return cos(solar zenith angle)."""

    return math.cos(math.radians(float(solar_zenith_deg)))


def solar_mu0(geometry: Any) -> float:
    """Return cos(solar zenith angle) from a geometry object."""

    return solar_mu0_from_zenith_deg(float(geometry.solar_zenith_deg))


def sun_normalized_radiance(radiance: Any, irradiance: Any):
    """Return radiance divided by irradiance."""

    import numpy as np

    return np.asarray(radiance, dtype=np.float64) / np.asarray(irradiance, dtype=np.float64)


def reflectance_from_radiance(radiance: Any, irradiance: Any, mu0: float):
    """Return reflectance from radiance, irradiance, and solar cosine."""

    import numpy as np

    return (
        np.asarray(radiance, dtype=np.float64)
        * np.pi
        / (float(mu0) * np.asarray(irradiance, dtype=np.float64))
    )


def reflectance_jacobian_from_radiance_jacobian(
    radiance_jacobian: Any,
    irradiance: Any,
    mu0: float,
):
    """Convert dL/dx to dR/dx for R = pi * L / (mu0 * E0)."""

    import numpy as np

    jacobian = np.asarray(radiance_jacobian, dtype=np.float64)
    scale = float(mu0) * np.asarray(irradiance, dtype=np.float64) / np.pi

    if jacobian.ndim == 1:
        return jacobian / scale

    return jacobian / scale[..., None]


def reflectance_noise_from_sun_normalized_radiance_noise(noise: Any, mu0: float):
    """Convert sun-normalized radiance noise to reflectance noise."""

    import numpy as np

    return np.asarray(noise, dtype=np.float64) * (np.pi / float(mu0))
