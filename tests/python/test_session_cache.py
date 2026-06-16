from types import SimpleNamespace
from typing import cast
from unittest.mock import patch


def test_session_cache_warms_optimal_estimation_route_once() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.rtm import session_cache

    calls: list[tuple[str, object]] = []
    scene = cast(Scene, SimpleNamespace(scene_id="cache-case"))

    class Handle:
        def load_scene(self, loaded_scene, *, copy_scene: bool = True) -> None:

            calls.append(("load", (loaded_scene, copy_scene)))

        def warm_optimal_estimation_cache(self, state_names: tuple[str, ...]) -> None:

            calls.append(("warm_oe", state_names))

        def close(self) -> None:

            calls.append(("close", None))

    with patch.object(session_cache, "RtmHandle", side_effect=Handle):
        cache = session_cache.SessionCache()

        try:
            try:
                cache.warm_optimal_estimation(("aerosol_optical_depth",))
            except RuntimeError as error:
                assert "no loaded wavelength-band case" in str(error)
            else:
                raise AssertionError("unloaded OE cache warm was accepted")

            cache.load(scene)
            try:
                cache.warm_optimal_estimation(("aerosol_optical_depth",))
            except ValueError as error:
                assert "aerosol_layer_mid_pressure_hpa" in str(error)
            else:
                raise AssertionError("one-state OE cache warm was accepted")

            cache.warm_optimal_estimation(
                ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")
            )
            cache.warm_optimal_estimation(
                ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")
            )
            cache.load(scene)
            cache.warm_optimal_estimation(
                ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")
            )
        finally:
            cache.close()

    assert calls == [
        ("load", (scene, True)),
        ("warm_oe", ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")),
        ("load", (scene, True)),
        ("warm_oe", ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")),
        ("close", None),
    ]
