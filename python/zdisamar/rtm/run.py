"""Functional RTM execution helpers."""

from array import array
from collections.abc import Generator
from contextlib import contextmanager

from ..input.wavelength_band.o2a import Scene
from ..input.wavelength_band.o2a_default import default_o2a_scene
from .session_cache import SessionCache


@contextmanager
def _temporary_cache(scene: Scene, *, copy_scene: bool = False) -> Generator[SessionCache]:

    cache = SessionCache()

    try:
        cache.load(scene, copy_scene=copy_scene)
        yield cache
    finally:
        cache.close()


def spectrum(
    scene: Scene,
    *,
    cache: SessionCache | None = None,
    jacobian: bool = False,
    include_scene: bool = False,
):
    """Run radiative transfer for one wavelength-band scene."""

    if cache is not None:
        return cache.spectrum(
            scene,
            jacobian=jacobian,
            include_scene=include_scene,
        )

    with _temporary_cache(scene, copy_scene=include_scene) as temporary:
        return temporary.spectrum(
            jacobian=jacobian,
            include_scene=include_scene,
        )


def atmospheric_budget(
    scene: Scene,
    wavelengths_nm,
    *,
    cache: SessionCache | None = None,
):
    """Return atmospheric optical-depth budget rows."""

    if cache is not None:
        cache.load(scene)

        return cache.atmospheric_budget(wavelengths_nm)

    with _temporary_cache(scene) as temporary:
        return temporary.atmospheric_budget(wavelengths_nm)


def nominal_wavelengths(scene: Scene):
    """Recreate the nominal spectrum grid from a wavelength-band scene."""

    count = int(scene.spectral_grid.sample_count)

    if count < 0:
        raise ValueError("nominal spectral sample_count must be non-negative")

    if count == 0:
        return array("d")

    if count == 1:
        return array("d", [float(scene.spectral_grid.start_nm)])

    start = float(scene.spectral_grid.start_nm)
    end = float(scene.spectral_grid.end_nm)
    step = (end - start) / float(count - 1)
    wavelengths = array("d", (start + step * index for index in range(count)))
    wavelengths[-1] = end

    return wavelengths


def reference_scene() -> Scene:
    """Return the packaged reference scene."""

    return default_o2a_scene()
