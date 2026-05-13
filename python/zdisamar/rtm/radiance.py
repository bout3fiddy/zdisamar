"""Radiance-space helper functions."""

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import numpy as np
    from numpy.typing import ArrayLike, NDArray


def sun_normalized_radiance(
    radiance: ArrayLike,
    irradiance: ArrayLike,
) -> NDArray[np.float64]:
    """Return radiance divided by irradiance."""

    import numpy as np

    return np.asarray(radiance, dtype=np.float64) / np.asarray(irradiance, dtype=np.float64)
