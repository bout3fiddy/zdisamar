import math
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import patch

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.native]


def test_native_oe_loads_requested_scene_into_supplied_cache() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.optimal_estimation import o2a as o2a_oe
    from zdisamar.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    events: list[tuple[str, object, object]] = []
    requested_scene = SimpleNamespace(scene_id="requested")
    measurement = Measurement((760.0,), (0.2,), signal_to_noise=100.0)
    state_vector = SimpleNamespace(
        parameters=(
            SimpleNamespace(name="aerosol_optical_depth"),
            SimpleNamespace(name="aerosol_layer_mid_pressure_hpa"),
        ),
        jacobian_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
    )
    controls = RetrievalControls(max_iterations=1)
    native_result = Result((), (), 0, True, (), (), ())

    class Handle:
        def optimal_estimation(self, *, measurement, state_vector, controls):

            events.append(("optimal_estimation", measurement, controls))

            return {"state_count": 0}

    class Cache:
        _handle = Handle()

        def has_loaded_scene(self, scene) -> bool:

            events.append(("has_loaded_case", scene, None))

            return False

        def load(self, scene, *, copy_scene: bool = True) -> None:

            events.append(("load", scene, copy_scene))

        def warm_optimal_estimation(self, state_names: tuple[str, ...]) -> None:

            events.append(("warm_oe", state_names, None))

    with (
        patch.object(o2a_oe, "_result_from_native", return_value=native_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
    ):
        result = o2a_oe.run_native_retrieval(
            scene=cast(Scene, requested_scene),
            measurement=measurement,
            state_vector=cast(StateVector, state_vector),
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert result is native_result
    assert events == [
        ("has_loaded_case", requested_scene, None),
        ("load", requested_scene, False),
        ("warm_oe", ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"), None),
        ("optimal_estimation", measurement, controls),
    ]


def test_native_oe_reuses_matching_supplied_cache() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.optimal_estimation import o2a as o2a_oe
    from zdisamar.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    events: list[tuple[str, object, object]] = []
    requested_scene = SimpleNamespace(scene_id="requested")
    measurement = Measurement((760.0,), (0.2,), signal_to_noise=100.0)
    state_vector = SimpleNamespace(
        parameters=(
            SimpleNamespace(name="aerosol_optical_depth"),
            SimpleNamespace(name="aerosol_layer_mid_pressure_hpa"),
        ),
        jacobian_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
    )
    controls = RetrievalControls(max_iterations=1)
    native_result = Result((), (), 0, True, (), (), ())

    class Handle:
        def optimal_estimation(self, *, measurement, state_vector, controls):

            events.append(("optimal_estimation", measurement, controls))

            return {"state_count": 0}

    class Cache:
        _handle = Handle()

        def has_loaded_scene(self, scene) -> bool:

            events.append(("has_loaded_case", scene, None))

            return True

        def load(self, scene, *, copy_scene: bool = True) -> None:

            raise AssertionError("matching OE cache reloaded its prepared scene")

        def warm_optimal_estimation(self, state_names: tuple[str, ...]) -> None:

            events.append(("warm_oe", state_names, None))

    with (
        patch.object(o2a_oe, "_result_from_native", return_value=native_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
    ):
        result = o2a_oe.run_native_retrieval(
            scene=cast(Scene, requested_scene),
            measurement=measurement,
            state_vector=cast(StateVector, state_vector),
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert result is native_result
    assert events == [
        ("has_loaded_case", requested_scene, None),
        ("warm_oe", ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"), None),
        ("optimal_estimation", measurement, controls),
    ]


def test_native_oe_marshaling_bounds() -> None:

    from zdisamar import optimal_estimation
    from zdisamar.bindings.handles import RtmHandle

    handle = object.__new__(RtmHandle)
    measurement = optimal_estimation.Measurement(
        wavelength_nm=[760.0],
        reflectance=[0.2],
        signal_to_noise=100.0,
    )
    pressure_profile = SimpleNamespace(
        altitude_km=(0.0, 1.0),
        pressure_hpa=(900.0, 800.0),
    )
    state_vector = SimpleNamespace(
        parameters=[
            SimpleNamespace(
                name="aerosol_optical_depth",
                initial=0.3,
                prior=0.3,
                prior_uncertainty=math.sqrt(0.8),
                lower=None,
                upper=None,
                interval_index_1based=0,
            ),
            SimpleNamespace(
                name="aerosol_layer_mid_pressure_hpa",
                initial=850.0,
                prior=850.0,
                prior_uncertainty=100.0,
                lower=600.0,
                upper=1000.0,
                interval_index_1based=2,
                thickness_hpa=10.0,
                pressure_altitude_profile=pressure_profile,
            ),
        ]
    )

    for max_iterations in (-1, 0, 1001):
        try:
            handle.optimal_estimation(
                measurement=measurement,
                state_vector=state_vector,
                controls=optimal_estimation.RetrievalControls(max_iterations=max_iterations),
            )
        except ValueError as error:
            assert "max_iterations" in str(error)
        else:
            raise AssertionError("invalid max_iterations reached native OE marshaling")

    try:
        handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=cast(Any, 1.9)),
        )
    except ValueError as error:
        assert "max_iterations" in str(error)
    else:
        raise AssertionError("non-integer max_iterations reached native OE marshaling")

    for invalid_signal_to_noise in (0.0, -1.0e-3, math.inf, math.nan):
        try:
            handle.optimal_estimation(
                measurement=optimal_estimation.Measurement(
                    wavelength_nm=[760.0],
                    reflectance=[0.2],
                    signal_to_noise=invalid_signal_to_noise,
                ),
                state_vector=state_vector,
                controls=optimal_estimation.RetrievalControls(max_iterations=1),
            )
        except ValueError as error:
            assert "signal-to-noise" in str(error)
        else:
            raise AssertionError("invalid measurement SNR reached native OE marshaling")

    state_vector.parameters[0].interval_index_1based = 2**32

    try:
        handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
    except ValueError as error:
        assert "interval_index_1based" in str(error)
    else:
        raise AssertionError("invalid interval index reached native OE marshaling")

    state_vector.parameters[0].interval_index_1based = 1.9

    try:
        handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
    except ValueError as error:
        assert "interval_index_1based" in str(error)
    else:
        raise AssertionError("non-integer interval index reached native OE marshaling")

    state_vector.parameters[0].interval_index_1based = 0
    state_vector.parameters[0].prior_uncertainty = -1.0

    try:
        handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
    except ValueError as error:
        assert "uncertainty" in str(error)
    else:
        raise AssertionError("negative uncertainty reached native OE marshaling")

    state_vector.parameters[0].prior_uncertainty = math.sqrt(0.8)
    state_vector.parameters[0].name = "log_aerosol_optical_depth"
    state_vector.parameters[0].jacobian_name = "aerosol_optical_depth"

    try:
        handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
    except ValueError as error:
        assert "transformed state-vector parameters" in str(error)
    else:
        raise AssertionError("transformed state vector reached native OE marshaling")

    state_vector.parameters[0].name = "aerosol_optical_depth"
    state_vector.parameters[0].jacobian_name = "aerosol_optical_depth"
    state_vector.parameters[0].jacobian_scale = lambda value: 2.0

    try:
        handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
    except ValueError as error:
        assert "jacobian_scale" in str(error)
    else:
        raise AssertionError("custom jacobian scale reached native OE marshaling")


def test_native_oe_runs_after_reference_scene_prepare() -> None:

    from rtm_scene import narrow
    from zdisamar import optimal_estimation
    from zdisamar.bindings.handles import RtmHandle
    from zdisamar.optimal_estimation import o2a as o2a_oe

    handle = RtmHandle()

    try:
        # Narrow representative band: this test asserts retrieval STRUCTURE (iteration and
        # state counts), not full-band physics values, so the band does not affect coverage.
        scene = narrow()
        measurement = optimal_estimation.simulate_measurement(
            scene,
            signal_to_noise=100.0,
        )
        state_vector = optimal_estimation.StateVector(
            (
                optimal_estimation.AerosolOpticalDepth(
                    initial=0.3,
                    prior=0.3,
                    prior_uncertainty=math.sqrt(0.8),
                ),
                optimal_estimation.AerosolLayerMidPressure(
                    initial=850.0,
                    prior=850.0,
                    prior_uncertainty=100.0,
                    lower=600.0,
                    upper=1000.0,
                ),
            )
        )
        state_vector = o2a_oe.resolved_state_vector_for_scene(scene, state_vector)
        handle.load_scene(scene)
        result = handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
        assert result["iteration_count"] == 1
        assert result["state_count"] == 2
        correction = handle.optimal_estimation_correction(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=10),
        )
        assert correction["iteration_count"] == 1
        assert correction["state_count"] == 2
    finally:
        handle.close()
