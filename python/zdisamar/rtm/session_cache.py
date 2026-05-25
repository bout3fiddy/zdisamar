"""Reusable RTM work-array cache."""

from dataclasses import dataclass, field
from typing import Self

from ..bindings.handles import RtmHandle
from ..input.wavelength_band.o2a import O2AInput


@dataclass(eq=False)
class SessionCache:
    """Cache reusable RTM storage across repeated wavelength-band cases."""

    case: O2AInput | None = None
    _handle: RtmHandle = field(init=False, repr=False)
    _loaded: bool = field(default=False, init=False, repr=False)

    def __post_init__(self) -> None:

        self._handle = RtmHandle()
        initial_case = self.case
        self.case = None

        if initial_case is not None:
            self.load(initial_case, copy_case=False)
            self._handle.warm_cache()

    def load(self, case: O2AInput, *, copy_case: bool = True) -> None:
        """Load a wavelength-band case into the cached RTM storage."""

        self._handle.load_o2a_case(case, copy_case=copy_case)
        self._loaded = True

    def has_loaded_case(self, case: O2AInput) -> bool:
        """Return whether this cache already owns the prepared native case."""

        return self._loaded and self._handle.loaded_o2a_case_matches(case)

    def spectrum(
        self,
        case: O2AInput | None = None,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
        include_case: bool = False,
    ):
        """Run the RTM using cached storage."""

        if case is not None and (include_case or not self.has_loaded_case(case)):
            self.load(case, copy_case=include_case)
        elif not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.spectrum(
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
            include_case=include_case,
        )

    def atmospheric_budget(self, wavelengths_nm):
        """Return atmospheric optical-depth budget rows for the loaded case."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.atmospheric_budget(wavelengths_nm)

    def instrument_response(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ):
        """Return instrument response rows for the loaded case."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.instrument_response_sampling(wavelengths_nm, channels=channels)

    def collision_induced_absorption(self, wavelengths_nm):
        """Return O2-O2 collision-induced absorption rows for the loaded case."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.collision_induced_absorption(wavelengths_nm)

    def close(self) -> None:
        """Release cached RTM storage."""

        self._handle.close()
        self._loaded = False

    def __enter__(self) -> Self:

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()
