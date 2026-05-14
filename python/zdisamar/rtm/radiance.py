"""Radiance-space helper functions."""

import numpy as np
from numpy.typing import ArrayLike, NDArray


def sun_normalized_radiance(
    radiance: ArrayLike,
    irradiance: ArrayLike,
) -> NDArray[np.float64]:
    """Return radiance divided by irradiance."""

    return np.asarray(radiance, dtype=np.float64) / np.asarray(irradiance, dtype=np.float64)
