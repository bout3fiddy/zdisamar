from dataclasses import dataclass
from types import SimpleNamespace
from typing import cast
from unittest.mock import patch


def test_fastmode_oe_runs_single_full_correction() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.input.wavelength_band.optimisation import Optimisation
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Iteration,
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    @dataclass(frozen=True)
    class Parameter:
        name: str
        initial: float
        prior: float
        prior_uncertainty: float
        lower: float | None = None
        upper: float | None = None

        def write_to(self, target: object, value: float) -> None:

            del target, value

    optimisation = Optimisation.defaults()
    optimisation.fastmode.enabled = True
    optimisation.fastmode.oe.fast_stage_sampling.enabled = False
    reference_scene = SimpleNamespace(scene_id="reference", optimisation=optimisation)
    full_scene = SimpleNamespace(scene_id="full")
    correction_scene = SimpleNamespace(scene_id="correction")
    correction_measurement = Measurement((760.0, 760.1), (0.1, 0.2), signal_to_noise=100.0)
    measurement = Measurement(
        (765.2, 766.0, 768.0),
        (0.1, 0.2, 0.3),
        signal_to_noise=100.0,
    )
    state_vector = StateVector(
        (
            Parameter("aerosol_optical_depth", 0.2, 0.3, 0.8),
            Parameter("aerosol_layer_mid_pressure_hpa", 800.0, 820.0, 100.0),
        )
    )
    controls = RetrievalControls(
        max_iterations=6,
        state_vector_convergence_threshold=0.7,
        max_change_transformed_state=0.4,
    )
    fast_result = Result(
        state_names=state_vector.names,
        state=(0.31, 760.0),
        iterations=4,
        converged=True,
        history=(
            Iteration(1, (0.25, 780.0), 4.0, 3.0, 1.0, 4.0, True),
            Iteration(4, (0.31, 760.0), 1.8, 1.0, 0.8, 0.4, True),
        ),
        posterior_covariance=((1.0, 0.0), (0.0, 1.0)),
        averaging_kernel=((1.0, 0.0), (0.0, 1.0)),
        measurement=measurement,
        initial_state=state_vector.initial_state(),
    )
    final_evaluation_calls = 0

    def unexpected_final_evaluation():

        nonlocal final_evaluation_calls
        final_evaluation_calls += 1

        raise AssertionError("fastmode correction combine forced lazy final evaluation")

    full_result = Result(
        state_names=state_vector.names,
        state=(0.305, 761.5),
        iterations=1,
        converged=False,
        history=(Iteration(1, (0.305, 761.5), 0.7, 0.4, 0.3, 1.4, True),),
        posterior_covariance=((0.2, 0.0), (0.0, 0.2)),
        averaging_kernel=((0.9, 0.0), (0.0, 0.9)),
        measurement=measurement,
        initial_state=(0.31, 760.0),
        _final_evaluation_factory=unexpected_final_evaluation,
    )
    calls: list[dict[str, object]] = []
    correction_calls: list[tuple[object, RetrievalControls]] = []
    loads: list[tuple[object, bool]] = []
    correction_loads: list[tuple[object, bool]] = []

    def fake_native_retrieval(**kwargs):

        calls.append(kwargs)

        return fast_result

    class Cache:
        class Handle:
            def optimal_estimation_correction(self, *, measurement, state_vector, controls):

                del measurement
                correction_calls.append((state_vector, controls))

                return {"state_count": len(state_vector.parameters)}

        _handle = Handle()

        def has_loaded_scene(self, scene) -> bool:

            assert scene is reference_scene

            return False

        def load(self, scene, *, copy_scene: bool = True) -> None:

            loads.append((scene, copy_scene))

        def warm(self) -> None:

            pass

    class CorrectionCache:
        _handle = Cache.Handle()

        def load(self, scene, *, copy_scene: bool = True) -> None:

            correction_loads.append((scene, copy_scene))

        def __enter__(self):

            return self

        def __exit__(self, *_exc: object) -> None:

            return None

    with (
        patch.object(o2a_oe, "run_native_retrieval", side_effect=fake_native_retrieval),
        patch.object(o2a_oe, "full_physics_scene", return_value=full_scene) as full_physics_scene,
        patch.object(o2a_oe, "scene_for_state", return_value=correction_scene) as scene_for_state,
        patch.object(
            o2a_oe,
            "full_correction_measurement",
            return_value=correction_measurement,
        ) as correction_measurement_builder,
        patch.object(
            o2a_oe,
            "full_correction_scene",
            return_value=correction_scene,
        ) as correction_scene_builder,
        patch.object(o2a_oe, "_result_from_native", return_value=full_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
        patch.object(o2a_oe.rtm, "SessionCache", side_effect=CorrectionCache) as session_cache,
    ):
        result = o2a_oe.retrieve(
            scene=cast(Scene, reference_scene),
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert calls[0]["scene"] is reference_scene
    assert calls[0]["controls"] is controls
    assert calls[0]["load_scene"] is False
    assert len(calls) == 1
    full_physics_scene.assert_called_once_with(reference_scene)
    scene_for_state.assert_called_once_with(full_scene, fast_result.state, state_vector)
    correction_measurement_builder.assert_called_once_with(
        measurement,
        wavelengths_nm=(765.2, 766.0, 768.0),
        uncertainty_scale=None,
    )
    correction_scene_builder.assert_called_once_with(correction_scene, correction_measurement)
    session_cache.assert_called_once_with()
    assert loads == [(reference_scene, False)]
    assert correction_loads == [(correction_scene, False)]
    assert len(correction_calls) == 1
    corrected_state_vector = cast(StateVector, correction_calls[0][0])
    correction_controls = correction_calls[0][1]
    assert correction_controls is controls
    assert corrected_state_vector.initial_state() == (0.31, 760.0)
    assert corrected_state_vector.prior_state() == (0.3, 820.0)
    assert result.state == full_result.state
    assert result.converged is True
    assert result.iterations == 5
    assert result.history[-1].index == 5
    assert result.posterior_covariance == full_result.posterior_covariance
    assert result.fast_correction is not None
    assert result.fast_correction.fast_iterations == 4
    assert result.fast_correction.fast_converged is True
    assert result.fast_correction.fast_state == fast_result.state
    assert result.fast_correction.full_correction_converged is False
    assert result.fast_correction.full_correction_state_vector_convergence == 1.4
    assert final_evaluation_calls == 0


def test_fastmode_oe_uses_sparse_fast_stage_sampling() -> None:

    from zdisamar.input.instrument import SpectralGrid
    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.input.wavelength_band.optimisation import (
        FastModeWavelengthWindow,
        Optimisation,
    )
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    optimisation = Optimisation.defaults()
    optimisation.fastmode.enabled = True
    optimisation.fastmode.oe.final_correction.enabled = False
    optimisation.fastmode.oe.controls.max_iterations = 3
    wavelengths = tuple(
        round(755.0 + index * 0.1, 10) for index in range(int(round((768.0 - 755.0) / 0.1)) + 1)
    )
    measurement = Measurement(
        wavelengths,
        tuple(0.1 + 0.001 * index for index in range(len(wavelengths))),
        signal_to_noise=100.0,
    )
    reference_scene = SimpleNamespace(
        scene_id="reference",
        optimisation=optimisation,
        spectral_grid=SpectralGrid(
            start_nm=wavelengths[0],
            end_nm=wavelengths[-1],
            sample_count=len(wavelengths),
        ),
        instrument_response=SimpleNamespace(measured_wavelengths_nm=wavelengths),
    )
    state_vector = cast(StateVector, SimpleNamespace(parameters=(), names=()))
    calls: list[dict[str, object]] = []
    loads: list[tuple[object, bool]] = []

    def fake_native_retrieval(**kwargs):

        calls.append(kwargs)

        return Result(
            state_names=(),
            state=(),
            iterations=1,
            converged=True,
            history=(),
            posterior_covariance=(),
            averaging_kernel=(),
            measurement=kwargs["measurement"],
            initial_state=(),
        )

    class Cache:
        _handle = SimpleNamespace()

        def has_loaded_scene(self, scene) -> bool:

            del scene

            return False

        def load(self, scene, *, copy_scene: bool = True) -> None:

            loads.append((scene, copy_scene))

        def warm(self) -> None:

            pass

    with patch.object(o2a_oe, "run_native_retrieval", side_effect=fake_native_retrieval):
        result = o2a_oe.retrieve(
            scene=cast(Scene, reference_scene),
            measurement=measurement,
            state_vector=state_vector,
            cache=cast(SessionCache, Cache()),
        )

    assert result is not None
    assert len(calls) == 1
    fast_scene = cast(Scene, calls[0]["scene"])
    fast_measurement = cast(Measurement, calls[0]["measurement"])
    expected_wavelengths = optimisation.fastmode.oe.fast_stage_sampling.resolved_wavelengths(
        measurement.wavelength_nm
    )
    assert tuple(fast_measurement.wavelength_nm) == expected_wavelengths
    assert len(fast_measurement.wavelength_nm) < len(measurement.wavelength_nm)
    assert fast_scene is loads[0][0]
    assert fast_scene is not reference_scene
    assert fast_scene.spectral_grid.sample_count == len(fast_measurement.wavelength_nm)
    assert tuple(fast_scene.instrument_response.measured_wavelengths_nm) == expected_wavelengths
    assert calls[0]["load_scene"] is False
    active_controls = cast(RetrievalControls, calls[0]["controls"])
    assert active_controls.max_iterations == 3
    assert loads == [(fast_scene, False)]

    optimisation.fastmode.oe.fast_stage_sampling.windows = (
        FastModeWavelengthWindow((755.0, 755.2), 1),
    )

    try:
        optimisation.fastmode.oe.fast_stage_sampling.resolved_wavelengths(measurement.wavelength_nm)
    except ValueError as error:
        assert "wavelength count must be at least two" in str(error)
    else:
        raise AssertionError("single-sample fast-stage window count was accepted")


def test_fastmode_batch_uses_native_fused_correction() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.input.wavelength_band.optimisation import Optimisation
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Measurement,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector

    @dataclass(frozen=True)
    class Parameter:
        name: str
        initial: float
        prior: float
        prior_uncertainty: float
        lower: float | None = None
        upper: float | None = None

        def write_to(self, target: object, value: float) -> None:

            del target, value

    optimisation = Optimisation.defaults()
    optimisation.fastmode.enabled = True
    reference_scene = SimpleNamespace(scene_id="reference", optimisation=optimisation)
    reference_scene = cast(Scene, reference_scene)
    full_scene = SimpleNamespace(scene_id="full")
    correction_scene = SimpleNamespace(scene_id="correction")
    measurement = Measurement((765.2, 766.0, 768.0), (0.1, 0.2, 0.3), signal_to_noise=100.0)
    fast_measurement = Measurement((765.2, 768.0), (0.1, 0.3), signal_to_noise=100.0)
    correction_measurement = Measurement((765.2, 766.0), (0.1, 0.2), signal_to_noise=100.0)
    state_vectors = (
        StateVector(
            (
                Parameter("aerosol_optical_depth", 0.2, 0.3, 0.8),
                Parameter("aerosol_layer_mid_pressure_hpa", 800.0, 820.0, 100.0),
            )
        ),
        StateVector(
            (
                Parameter("aerosol_optical_depth", 0.5, 0.6, 0.8),
                Parameter("aerosol_layer_mid_pressure_hpa", 700.0, 710.0, 100.0),
            )
        ),
    )
    controls = RetrievalControls(
        max_iterations=6,
        state_vector_convergence_threshold=0.7,
        max_change_transformed_state=0.4,
    )
    native_calls: list[dict[str, object]] = []
    correction_loads: list[tuple[object, bool]] = []
    correction_handle = object()

    class FastHandle:
        def optimal_estimation_fastmode_batch(self, **kwargs):

            native_calls.append(kwargs)

            return {
                "run_count": 2,
                "state_count": 2,
                "history_capacity": 7,
                "state": (0.305, 761.5, 0.415, 691.0),
                "history_state": (
                    0.1,
                    800.0,
                    0.2,
                    780.0,
                    0.3,
                    762.0,
                    0.305,
                    761.5,
                    0.305,
                    761.5,
                    0.305,
                    761.5,
                    0.305,
                    761.5,
                    0.5,
                    700.0,
                    0.45,
                    695.0,
                    0.42,
                    691.0,
                    0.415,
                    691.0,
                    0.415,
                    691.0,
                    0.415,
                    691.0,
                    0.415,
                    691.0,
                ),
                "iteration_count": (5, 6),
                "converged": (True, False),
                "status": ("ok", "failed"),
                "fast_stage_iteration_count": (4, 5),
                "fast_stage_converged": (True, False),
                "full_correction_iteration_count": (1, 1),
                "full_correction_converged": (False, True),
            }

    class FastCache:
        _handle = FastHandle()

    class CorrectionCache:
        _handle = correction_handle

        def load(self, scene, *, copy_scene: bool = True) -> None:

            correction_loads.append((scene, copy_scene))

        def __enter__(self):

            return self

        def __exit__(self, *_exc: object) -> None:

            return None

    with (
        patch.object(o2a_oe, "full_physics_scene", return_value=full_scene) as full_physics_scene,
        patch.object(
            o2a_oe,
            "full_correction_measurement",
            return_value=correction_measurement,
        ) as correction_measurement_builder,
        patch.object(
            o2a_oe,
            "full_correction_scene",
            return_value=correction_scene,
        ) as correction_scene_builder,
        patch.object(o2a_oe.rtm, "SessionCache", side_effect=CorrectionCache) as session_cache,
        patch.object(
            o2a_oe,
            "resolved_state_vector_for_loaded_scene",
            return_value=state_vectors[0],
        ) as resolved_template,
    ):
        result = o2a_oe.run_native_fastmode_retrieval_batch(
            scene=reference_scene,
            measurement=measurement,
            fast_measurement=fast_measurement,
            state_vector=state_vectors[0],
            resolved_template=state_vectors[0],
            controls=controls,
            cache=cast(o2a_oe.rtm.SessionCache, FastCache()),
            start_rows=tuple(vector.initial_state() for vector in state_vectors),
            batch_workers=3,
        )

    full_physics_scene.assert_called_once_with(reference_scene)
    correction_measurement_builder.assert_called_once_with(
        measurement,
        wavelengths_nm=(765.2, 766.0, 768.0),
        uncertainty_scale=None,
    )
    correction_scene_builder.assert_called_once_with(full_scene, correction_measurement)
    session_cache.assert_called_once_with()
    assert correction_loads == [(correction_scene, False)]
    resolved_template.assert_called_once()
    assert len(native_calls) == 1
    native_call = native_calls[0]
    correction_controls = cast(RetrievalControls, native_call["correction_controls"])
    assert native_call["correction_handle"] is correction_handle
    assert native_call["measurement"] is fast_measurement
    assert native_call["correction_measurement"] is correction_measurement
    assert native_call["state_vector"] is state_vectors[0]
    assert native_call["correction_state_vector"] is state_vectors[0]
    assert native_call["initial_states"] == tuple(
        vector.initial_state() for vector in state_vectors
    )
    assert native_call["prior_states"] == tuple(vector.initial_state() for vector in state_vectors)
    assert native_call["controls"] is controls
    assert correction_controls.max_iterations == 1
    assert correction_controls.state_vector_convergence_threshold == 0.7
    assert correction_controls.max_change_transformed_state == 0.4
    assert native_call["batch_workers"] == 3
    assert result.state == ((0.305, 761.5), (0.415, 691.0))
    assert result.iterations == (5, 6)
    assert result.converged == (True, False)
    assert result.status == ("ok", "failed")
    assert result.history_state[0][-1] == (0.305, 761.5)
    assert result.history_state[1][-1] == (0.415, 691.0)
    assert result.measurement is measurement
    assert result.fast_stage_iterations == (4, 5)
    assert result.fast_stage_converged == (True, False)
    assert result.full_correction_iterations == (1, 1)
    assert result.full_correction_converged == (False, True)


def test_fastmode_pressure_profile_uses_loaded_sparse_cache() -> None:

    from zdisamar.input.instrument import SpectralGrid
    from zdisamar.input.wavelength_band.o2a import Scene
    from zdisamar.input.wavelength_band.optimisation import Optimisation
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    @dataclass(frozen=True)
    class ResolvedParameter:
        name: str
        initial: float
        prior: float
        prior_uncertainty: float
        lower: float | None = None
        upper: float | None = None

        def write_to(self, target: object, value: float) -> None:

            del target, value

    @dataclass(frozen=True)
    class PressureParameter:
        name: str = "aerosol_layer_mid_pressure_hpa"
        initial: float = 800.0
        prior: float = 810.0
        prior_uncertainty: float = 90.0
        lower: float | None = None
        upper: float | None = None

        def resolve_for_scene(self, scene, pressure_altitude_profile) -> ResolvedParameter:

            del scene
            assert pressure_altitude_profile == "profile-from-loaded-fast-cache"

            return ResolvedParameter(
                name=self.name,
                initial=self.initial,
                prior=self.prior,
                prior_uncertainty=self.prior_uncertainty,
                lower=self.lower,
                upper=self.upper,
            )

        def write_to(self, target: object, value: float) -> None:

            del target, value

    optimisation = Optimisation.defaults()
    optimisation.fastmode.enabled = True
    optimisation.fastmode.oe.final_correction.enabled = False
    optimisation.fastmode.oe.controls.max_iterations = 4
    wavelengths = tuple(
        round(755.0 + index * 0.1, 10) for index in range(int(round((768.0 - 755.0) / 0.1)) + 1)
    )
    measurement = Measurement(
        wavelengths,
        tuple(0.1 + 0.001 * index for index in range(len(wavelengths))),
        signal_to_noise=100.0,
    )
    reference_scene = SimpleNamespace(
        scene_id="reference",
        optimisation=optimisation,
        spectral_grid=SpectralGrid(
            start_nm=wavelengths[0],
            end_nm=wavelengths[-1],
            sample_count=len(wavelengths),
        ),
        instrument_response=SimpleNamespace(measured_wavelengths_nm=wavelengths),
    )
    state_vector = StateVector((PressureParameter(),))
    loads: list[tuple[object, bool]] = []
    match_checks: list[object] = []
    profile_calls: list[tuple[object, object]] = []
    retrieval_calls: list[dict[str, object]] = []

    class Cache:
        _handle = SimpleNamespace()

        def has_loaded_scene(self, scene) -> bool:

            match_checks.append(scene)

            return bool(loads and loads[-1][0] is scene)

        def load(self, scene, *, copy_scene: bool = True) -> None:

            loads.append((scene, copy_scene))

        def warm(self) -> None:

            pass

    def fake_pressure_profile(scene, cache):

        profile_calls.append((scene, cache))

        return "profile-from-loaded-fast-cache"

    def fake_native_retrieval(**kwargs):

        retrieval_calls.append(kwargs)

        return Result(
            state_names=kwargs["state_vector"].names,
            state=(800.0,),
            iterations=1,
            converged=True,
            history=(),
            posterior_covariance=((1.0,),),
            averaging_kernel=((1.0,),),
            measurement=kwargs["measurement"],
            initial_state=kwargs["state_vector"].initial_state(),
        )

    cache = Cache()

    with (
        patch.object(
            o2a_oe,
            "pressure_altitude_profile_from_loaded_cache",
            side_effect=fake_pressure_profile,
        ),
        patch.object(o2a_oe, "run_native_retrieval", side_effect=fake_native_retrieval),
    ):
        result = o2a_oe.retrieve(
            scene=cast(Scene, reference_scene),
            measurement=measurement,
            state_vector=state_vector,
            cache=cast(SessionCache, cache),
        )

    assert result.converged
    assert len(loads) == 1
    fast_scene = cast(Scene, loads[0][0])
    assert fast_scene is not reference_scene
    assert fast_scene.spectral_grid.sample_count < reference_scene.spectral_grid.sample_count
    assert match_checks == [fast_scene]
    assert profile_calls == [(fast_scene, cache)]
    assert len(retrieval_calls) == 1
    active_controls = cast(RetrievalControls, retrieval_calls[0]["controls"])
    assert active_controls.max_iterations == 4
    resolved_state_vector = cast(StateVector, retrieval_calls[0]["state_vector"])
    assert isinstance(resolved_state_vector.parameters[0], ResolvedParameter)
