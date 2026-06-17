"""Reusable RTM work-array cache."""

from dataclasses import dataclass, field
from typing import Self

from ..bindings.handles import RtmHandle
from ..input.wavelength_band.o2a import Scene

OPTIMAL_ESTIMATION_STATE_NAMES = (
    "aerosol_optical_depth",
    "aerosol_layer_mid_pressure_hpa",
)


@dataclass(eq=False)
class SessionCache:
    """Cache reusable RTM storage across repeated wavelength-band scenes."""

    scene: Scene | None = None
    _handle: RtmHandle = field(init=False, repr=False)
    _loaded: bool = field(default=False, init=False, repr=False)
    _oe_warm_state_names: tuple[str, ...] | None = field(default=None, init=False, repr=False)

    def __post_init__(self) -> None:

        self._handle = RtmHandle()
        initial_scene = self.scene
        self.scene = None

        if initial_scene is not None:
            self.load(initial_scene, copy_scene=False)
            self.warm()

    def load(self, scene: Scene, *, copy_scene: bool = True) -> None:
        """Load a wavelength-band scene into the cached RTM storage."""

        self._handle.load_scene(scene, copy_scene=copy_scene)
        self._loaded = True
        self._oe_warm_state_names = None

    def warm(self) -> None:
        """Prepare reusable native RTM work arrays for the loaded scene."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band scene")

        self._handle.warm_cache()

    def warm_optimal_estimation(self, state_names: tuple[str, ...]) -> None:
        """Prepare reusable native RTM work arrays for an OE Jacobian route."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band scene")

        if tuple(state_names) != OPTIMAL_ESTIMATION_STATE_NAMES:
            raise ValueError(
                "optimal-estimation cache warming requires aerosol_optical_depth "
                "and aerosol_layer_mid_pressure_hpa in that order"
            )

        if self._oe_warm_state_names == state_names:
            return

        self._handle.warm_optimal_estimation_cache(state_names)
        self._oe_warm_state_names = state_names

    def has_loaded_scene(self, scene: Scene) -> bool:
        """Return whether this cache already owns the prepared native scene."""

        return self._loaded and self._handle.loaded_scene_matches(scene)

    def spectrum(
        self,
        scene: Scene | None = None,
        *,
        jacobian: bool = False,
        include_scene: bool = False,
    ):
        """Run the RTM using cached storage."""

        if scene is not None and (include_scene or not self.has_loaded_scene(scene)):
            self.load(scene, copy_scene=include_scene)
        elif not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band scene")

        return self._handle.spectrum(
            jacobian=jacobian,
            include_scene=include_scene,
        )

    def atmospheric_budget(self, wavelengths_nm):
        """Return atmospheric optical-depth budget rows for the loaded scene."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band scene")

        return self._handle.atmospheric_budget(wavelengths_nm)

    def instrument_response(
        self,
        wavelengths_nm,
        channels: tuple[str, ...] = ("radiance", "irradiance"),
    ):
        """Return instrument response rows for the loaded scene."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band scene")

        return self._handle.instrument_response_sampling(wavelengths_nm, channels=channels)

    def collision_induced_absorption(self, wavelengths_nm):
        """Return O2-O2 collision-induced absorption rows for the loaded scene."""

        if not self._loaded:
            raise RuntimeError("SessionCache has no loaded wavelength-band scene")

        return self._handle.collision_induced_absorption(wavelengths_nm)

    def close(self) -> None:
        """Release cached RTM storage."""

        self._handle.close()
        self._loaded = False
        self._oe_warm_state_names = None

    def __enter__(self) -> Self:

        return self

    def __exit__(self, *_exc: object) -> None:

        self.close()
