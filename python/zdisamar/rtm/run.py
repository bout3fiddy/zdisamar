"""Functional RTM execution helpers."""

from array import array
from collections.abc import Generator
from contextlib import contextmanager

from ..bindings.handles import RtmHandle
from ..input.wavelength_band.o2a import O2AInput
from .session_cache import SessionCache


@contextmanager
def _temporary_cache(case: O2AInput, *, copy_case: bool = False) -> Generator[SessionCache]:

    cache = SessionCache()

    try:
        cache.load(case, copy_case=copy_case)
        yield cache
    finally:
        cache.close()


def spectrum(
    case: O2AInput,
    *,
    cache: SessionCache | None = None,
    jacobian: bool = False,
    jacobian_state_names: tuple[str, ...] | None = None,
    include_case: bool = False,
):
    """Run radiative transfer for one wavelength-band case."""

    if cache is not None:
        return cache.spectrum(
            case,
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
            include_case=include_case,
        )

    with _temporary_cache(case, copy_case=include_case) as temporary:
        return temporary.spectrum(
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
            include_case=include_case,
        )


def aerosol_profile_spectrum(
    case: O2AInput,
    layers,
    *,
    cache: SessionCache | None = None,
    include_case: bool = False,
):
    """Run a forward spectrum with multiple pressure-bounded aerosol layers."""

    if cache is not None:
        if cache.has_loaded_case(case) and not include_case:
            return cache.aerosol_profile_spectrum(
                layers,
                include_case=include_case,
            )

        return cache.aerosol_profile_spectrum(
            layers,
            case,
            include_case=include_case,
        )

    with _temporary_cache(case, copy_case=include_case) as temporary:
        return temporary.aerosol_profile_spectrum(
            layers,
            include_case=include_case,
        )


def atmospheric_budget(
    case: O2AInput,
    wavelengths_nm,
    *,
    cache: SessionCache | None = None,
):
    """Return atmospheric optical-depth budget rows."""

    if cache is not None:
        cache.load(case)

        return cache.atmospheric_budget(wavelengths_nm)

    with _temporary_cache(case) as temporary:
        return temporary.atmospheric_budget(wavelengths_nm)


def instrument_response(
    case: O2AInput,
    wavelengths_nm=None,
    *,
    channels: tuple[str, ...] = ("radiance", "irradiance"),
    cache: SessionCache | None = None,
):
    """Return instrument response support rows."""

    grid = nominal_wavelengths(case) if wavelengths_nm is None else wavelengths_nm

    if cache is not None:
        cache.load(case)

        return cache.instrument_response(grid, channels=channels)

    with _temporary_cache(case) as temporary:
        return temporary.instrument_response(grid, channels=channels)


def collision_induced_absorption(
    case: O2AInput,
    wavelengths_nm,
    *,
    cache: SessionCache | None = None,
):
    """Return O2-O2 collision-induced absorption rows."""

    if cache is not None:
        cache.load(case)

        return cache.collision_induced_absorption(wavelengths_nm)

    with _temporary_cache(case) as temporary:
        return temporary.collision_induced_absorption(wavelengths_nm)


def o2_line_contributions(
    case: O2AInput,
    wavelengths_nm,
    *,
    max_rows: int = 50_000,
    cache: SessionCache | None = None,
):
    """Return line-by-line O2 evidence rows."""

    if cache is not None:
        cache.load(case)

        return cache._handle.o2_line_contributions(wavelengths_nm, max_rows=max_rows)

    with _temporary_cache(case) as temporary:
        return temporary._handle.o2_line_contributions(wavelengths_nm, max_rows=max_rows)


def nominal_wavelengths(case: O2AInput):
    """Recreate the nominal spectrum grid from a wavelength-band case."""

    count = int(case.spectral_grid.sample_count)

    if count < 0:
        raise ValueError("nominal spectral sample_count must be non-negative")

    if count == 0:
        return array("d")

    if count == 1:
        return array("d", [float(case.spectral_grid.start_nm)])

    start = float(case.spectral_grid.start_nm)
    end = float(case.spectral_grid.end_nm)
    step = (end - start) / float(count - 1)
    wavelengths = array("d", (start + step * index for index in range(count)))
    wavelengths[-1] = end

    return wavelengths


def o2a_reference_case() -> O2AInput:
    """Return the packaged O2 A reference case."""

    with RtmHandle() as handle:
        return handle.default_o2a_case()
