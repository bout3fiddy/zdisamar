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

    def __post_init__(self) -> None:

        self._handle = RtmHandle()

        if self.case is not None:
            self.load(self.case)
            self._handle.warm_cache()

    def load(self, case: O2AInput) -> None:
        """Load a wavelength-band case into the cached RTM storage."""

        self._handle.load_o2a_case(case)
        self.case = case

    def spectrum(
        self,
        case: O2AInput | None = None,
        *,
        jacobian: bool = False,
        jacobian_state_names: tuple[str, ...] | None = None,
    ):
        """Run the RTM using cached storage."""

        if case is not None:
            self.load(case)
        elif self.case is None:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.spectrum(
            jacobian=jacobian,
            jacobian_state_names=jacobian_state_names,
        )

    def atmospheric_budget(self, wavelengths_nm):
        """Return atmospheric optical-depth budget rows for the loaded case."""

        if self.case is None:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.atmospheric_budget(wavelengths_nm)

    def instrument_response(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ):
        """Return instrument response rows for the loaded case."""

        if self.case is None:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.instrument_response_sampling(wavelengths_nm, channels=channels)

    def collision_induced_absorption(self, wavelengths_nm):
        """Return O2-O2 collision-induced absorption rows for the loaded case."""

        if self.case is None:
            raise RuntimeError("SessionCache has no loaded wavelength-band case")

        return self._handle.collision_induced_absorption(wavelengths_nm)

    def close(self) -> None:
        """Release cached RTM storage."""

        self._handle.close()

    def __enter__(self) -> Self:

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()
