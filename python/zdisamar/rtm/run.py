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
    jacobian_state_names: tuple[str, ...] | None = None,
    include_scene: bool = False,
):
    """Run radiative transfer for one wavelength-band case."""

    if cache is not None:
        return cache.spectrum(
            scene,
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
            include_scene=include_scene,
        )

    with _temporary_cache(scene, copy_scene=include_scene) as temporary:
        return temporary.spectrum(
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
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


def instrument_response(
    scene: Scene,
    wavelengths_nm=None,
    *,
    channels: tuple[str, ...] = ("radiance", "irradiance"),
    cache: SessionCache | None = None,
):
    """Return instrument response support rows."""

    grid = nominal_wavelengths(scene) if wavelengths_nm is None else wavelengths_nm

    if cache is not None:
        cache.load(scene)

        return cache.instrument_response(grid, channels=channels)

    with _temporary_cache(scene) as temporary:
        return temporary.instrument_response(grid, channels=channels)


def collision_induced_absorption(
    scene: Scene,
    wavelengths_nm,
    *,
    cache: SessionCache | None = None,
):
    """Return O2-O2 collision-induced absorption rows."""

    if cache is not None:
        cache.load(scene)

        return cache.collision_induced_absorption(wavelengths_nm)

    with _temporary_cache(scene) as temporary:
        return temporary.collision_induced_absorption(wavelengths_nm)


def o2_line_contributions(
    scene: Scene,
    wavelengths_nm,
    *,
    max_rows: int = 50_000,
    cache: SessionCache | None = None,
):
    """Return line-by-line O2 evidence rows."""

    if cache is not None:
        cache.load(scene)

        return cache._handle.o2_line_contributions(wavelengths_nm, max_rows=max_rows)

    with _temporary_cache(scene) as temporary:
        return temporary._handle.o2_line_contributions(wavelengths_nm, max_rows=max_rows)


def nominal_wavelengths(scene: Scene):
    """Recreate the nominal spectrum grid from a wavelength-band case."""

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
    """Return the packaged O2 A reference case."""

    return default_o2a_scene()
