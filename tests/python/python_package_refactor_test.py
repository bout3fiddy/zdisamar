import copy
import importlib.util
import math
import os
import sys
import tempfile
from dataclasses import dataclass, fields, replace
from pathlib import Path
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import patch


def assert_import_laziness() -> None:

    import zdisamar as zd

    assert "numpy" not in sys.modules
    assert "pandas" not in sys.modules
    assert "altair" not in sys.modules
    assert zd.__all__ == ["reference_data", "rtm", "wavelength_bands"]
    assert not hasattr(zd, "prepare")
    assert not hasattr(zd, "forward")
    assert not hasattr(zd, "O2AInput")

    import zdisamar.api as api

    assert api.__all__ == ["reference_data", "rtm", "wavelength_bands"]


def assert_plot_package_boundary() -> None:

    assert importlib.util.find_spec("zdisamar.plot") is not None
    assert "zdisamar.plot" not in sys.modules

    from zdisamar.plot.properties import PLOT

    assert PLOT.width == 1311
    assert PLOT.height == 465
    assert PLOT.markers_nm == (755.0, 760.76, 776.0)
    assert "blue" in PLOT.colors


def assert_rtm_conversions() -> None:

    import numpy as np
    from zdisamar import rtm

    mu0 = rtm.solar_zenith_cosine_from_degrees(60.0)
    radiance = np.array([2.0, 3.0], dtype=np.float64)
    irradiance = np.array([10.0, 12.0], dtype=np.float64)
    assert np.allclose(rtm.sun_normalized_radiance(radiance, irradiance), radiance / irradiance)
    assert np.allclose(
        rtm.reflectance_from_radiance(radiance, irradiance, mu0),
        radiance * math.pi / (mu0 * irradiance),
    )

    radiance_jacobian = np.array([[0.2, 0.4], [0.3, 0.6]], dtype=np.float64)
    expected = radiance_jacobian / ((mu0 * irradiance / math.pi)[:, None])
    assert np.allclose(
        rtm.reflectance_jacobian_from_radiance_jacobian(
            radiance_jacobian,
            irradiance,
            mu0,
        ),
        expected,
    )
    assert np.allclose(
        rtm.reflectance_noise_from_sun_normalized_radiance_noise(np.array([1.0]), mu0),
        np.array([math.pi / mu0]),
    )


def assert_session_cache_warms_optimal_estimation_route_once() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.rtm import session_cache

    calls: list[tuple[str, object]] = []
    case = cast(O2AInput, SimpleNamespace(scene_id="cache-case"))

    class Handle:
        def load_o2a_case(self, loaded_case, *, copy_case: bool = True) -> None:

            calls.append(("load", (loaded_case, copy_case)))

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

            cache.load(case)
            cache.warm_optimal_estimation(("aerosol_optical_depth",))
            cache.warm_optimal_estimation(("aerosol_optical_depth",))
            cache.warm_optimal_estimation(
                ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")
            )
            cache.load(case)
            cache.warm_optimal_estimation(
                ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")
            )
        finally:
            cache.close()

    assert calls == [
        ("load", (case, True)),
        ("warm_oe", ("aerosol_optical_depth",)),
        ("warm_oe", ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")),
        ("load", (case, True)),
        ("warm_oe", ("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa")),
        ("close", None),
    ]


def assert_plot_jacobian_uses_rtm_conversion() -> None:

    import numpy as np
    from zdisamar import rtm
    from zdisamar.plot.jacobian import jacobian_frame

    class Spectrum:
        jacobian_state_names = ("aerosol_optical_depth",)
        wavelength_nm = np.array([755.0, 760.0], dtype=np.float64)
        irradiance = np.array([10.0, 12.0], dtype=np.float64)
        radiance_jacobian = np.array([[0.2], [0.3]], dtype=np.float64)

        def reflectance_jacobian(self, state: str):

            assert state == "aerosol_optical_depth"

            return rtm.reflectance_jacobian_from_radiance_jacobian(
                self.radiance_jacobian[:, 0],
                self.irradiance,
                0.5,
            )

    frame, field, _title = jacobian_frame(Spectrum(), "aerosol_optical_depth")
    assert field == "reflectance_jacobian"
    assert np.allclose(
        np.array([row[field] for row in frame], dtype=float),
        rtm.reflectance_jacobian_from_radiance_jacobian(
            Spectrum.radiance_jacobian[:, 0],
            Spectrum.irradiance,
            0.5,
        ),
    )


def assert_optimal_estimation_grid_mismatch_rejected() -> None:

    import numpy as np
    from zdisamar.inverse_method.optimal_estimation import (
        WavelengthGridMismatchError,
    )
    from zdisamar.inverse_method.optimal_estimation.measurement import (
        require_matching_wavelength_grid,
    )

    try:
        require_matching_wavelength_grid(
            np.array([758.0, 758.04], dtype=np.float64),
            np.array([758.0, 758.03], dtype=np.float64),
            expected_name="measurement",
            actual_name="noise",
        )
    except WavelengthGridMismatchError:
        return

    raise AssertionError("optimal-estimation wavelength grid mismatch was accepted")


def assert_optimal_estimation_result_dataclass() -> None:

    from zdisamar.inverse_method.optimal_estimation.retrieval import FastCorrection, Result
    from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation

    first = cast(RtmEvaluation, object())
    second = cast(RtmEvaluation, object())
    result = Result(
        state_names=(),
        state=(),
        iterations=0,
        converged=True,
        history=(),
        posterior_covariance=(),
        averaging_kernel=(),
        final_evaluation=first,
    )
    assert result.final_evaluation is first
    assert replace(result, final_evaluation=second).final_evaluation is second
    assert replace(result, final_evaluation=None).final_evaluation is None
    assert "final_evaluation" in {field.name for field in fields(result)}

    positional = Result(
        (),
        (),
        0,
        True,
        (),
        (),
        (),
    )
    assert positional.initial_state is None
    assert positional.fast_correction is None

    correction = FastCorrection(
        fast_iterations=2,
        fast_converged=True,
        fast_state=(0.4,),
        full_correction=None,
        full_correction_converged=False,
        full_correction_state_vector_convergence=1.5,
    )
    assert replace(positional, fast_correction=correction).fast_correction is correction


def assert_optimal_estimation_diagnosis_display() -> None:

    from zdisamar.inverse_method.optimal_estimation.diagnosis import RetrievalDiagnosis
    from zdisamar.inverse_method.optimal_estimation.retrieval import Result

    calls = 0

    def diagnosis_factory(*, n: int | None = None):

        nonlocal calls
        calls += 1

        return {"n": n}

    result = Result(
        state_names=("aerosol_optical_depth",),
        state=(0.1,),
        iterations=1,
        converged=True,
        history=(),
        posterior_covariance=((1.0,),),
        averaging_kernel=((1.0,),),
        diagnosis_factory=diagnosis_factory,
    )
    diagnosis = result.diagnose(n=3)
    assert diagnosis == {"n": 3}
    assert result.diagnosis is diagnosis
    assert result.diagnose() is diagnosis
    assert calls == 1

    sweep = RetrievalDiagnosis(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        start_state=((0.1, 225.0), (2.0, 825.0)),
        retrieved_state=((0.12, 340.0), (0.55, 670.0)),
        iterations=(4, 7),
        converged=(True, True),
        retrieval_paths=(
            ((0.12, 340.0),),
            ((0.8, 700.0), (0.55, 670.0)),
        ),
        start_bounds=((0.1, 2.0), (225.0, 825.0)),
        batch_workers=1,
        truth_state=(0.2, 600.0),
        start_status=("ok", "failed"),
    )
    payload = sweep.to_dict()
    assert payload["runs"] == 2
    assert payload["non_converged"] == 1
    assert payload["basin_count"] == 1
    basin_payloads = cast(list[dict[str, object]], payload["basins"])
    assert len(basin_payloads) == 1
    assert basin_payloads[0]["runs"] == 1
    assert basin_payloads[0]["start_indices"] == [1]
    assert payload["native_worker_limit"] is None
    basins = sweep.basins()
    assert len(basins) == 1
    assert basins[0].run_count == 1
    assert basins[0].value("aerosol_layer_mid_pressure_hpa") == 340.0
    assert repr(basins[0]) == (
        "RetrievalBasin(runs=1, aerosol_optical_depth=0.12, aerosol_layer_mid_pressure_hpa=340)"
    )
    figure = sweep.plot()
    figure_payload = figure.to_dict()
    assert figure_payload["runs"] == 2
    assert figure_payload["title"]["text"] == "Retrieval Paths"
    assert figure_payload["x_scale"] == "pseudo-log"
    assert figure_payload["non_converged"] == 1
    assert figure_payload["truth"] == [0.2, 600.0]
    diagnosis_svg = figure._repr_svg_()
    assert "Retrieval Paths" in diagnosis_svg
    assert "accepted result" not in diagnosis_svg
    assert 'class="legend"' not in diagnosis_svg
    assert "pseudo-log scale" not in diagnosis_svg
    assert ">AOD at 550 nm</text>" in diagnosis_svg
    assert ">0.01</text>" not in diagnosis_svg
    assert ">truth (0.2, 600 hPa)</text>" in diagnosis_svg
    assert 'class="cluster-label"' in diagnosis_svg
    assert diagnosis_svg.count('class="diagnosis-non-converged"') == 2
    assert 'r="3.8"' in diagnosis_svg

    basin_sweep = RetrievalDiagnosis(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        start_state=((0.1, 225.0), (0.11, 255.0), (0.8, 700.0)),
        retrieved_state=((0.1, 240.0), (0.105, 243.0), (0.6, 720.0)),
        iterations=(3, 4, 5),
        converged=(True, True, True),
        retrieval_paths=(
            ((0.1, 240.0),),
            ((0.105, 243.0),),
            ((0.6, 720.0),),
        ),
        start_bounds=((0.02, 2.0), (50.0, 1000.0)),
        batch_workers=1,
    )
    grouped_basins = basin_sweep.basins()
    assert len(grouped_basins) == 2
    assert [basin.run_count for basin in grouped_basins] == [2, 1]
    assert grouped_basins[0].start_indices == (1, 2)
    assert grouped_basins[1].start_indices == (3,)
    grouped_payload = basin_sweep.to_dict()
    assert grouped_payload["basin_count"] == 2

    no_truth = replace(sweep, truth_state=None)
    no_truth_figure = no_truth.plot()
    assert no_truth_figure.to_dict()["truth"] is None
    no_truth_svg = no_truth_figure._repr_svg_()
    assert ">truth" not in no_truth_svg
    assert 'class="diagnosis-truth"' not in no_truth_svg


def assert_optimal_estimation_diagnosis_auto_workers() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.inverse_method.optimal_estimation.diagnosis import diagnose_retrieval
    from zdisamar.inverse_method.optimal_estimation.o2a import BatchResult
    from zdisamar.inverse_method.optimal_estimation.retrieval import Measurement, RetrievalControls
    from zdisamar.inverse_method.optimal_estimation.state_vector import (
        AerosolLayerMidPressure,
        AerosolOpticalDepth,
        StateVector,
        StateVectorParameter,
    )

    state_vector = StateVector(
        cast(
            tuple[StateVectorParameter, ...],
            (
                AerosolOpticalDepth(
                    initial=0.2,
                    prior=0.2,
                    prior_uncertainty=0.5,
                ),
                AerosolLayerMidPressure(
                    initial=600.0,
                    prior=600.0,
                    prior_uncertainty=150.0,
                ),
            ),
        )
    )
    measurement = Measurement(
        wavelength_nm=(760.0, 761.0),
        reflectance=(0.1, 0.2),
        signal_to_noise=100.0,
    )
    batch = BatchResult(
        state_names=state_vector.names,
        state=((0.2, 600.0),) * 9,
        iterations=(1,) * 9,
        converged=(True,) * 9,
        measurement=measurement,
        status=("ok",) * 9,
    )
    calls: list[dict[str, object]] = []

    def diagnosis_batch(**kwargs):

        calls.append(kwargs)

        return batch

    from zdisamar.inverse_method import optimal_estimation
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe

    banned_batch_api = "retrieve" + "_many"
    assert not hasattr(optimal_estimation, banned_batch_api)
    assert not hasattr(o2a_oe, banned_batch_api)

    with (
        patch.dict(os.environ, {"ZDISAMAR_WORKER_LIMIT": "10"}),
        patch(
            "zdisamar.inverse_method.optimal_estimation.o2a.diagnosis_batch",
            side_effect=diagnosis_batch,
        ),
    ):
        diagnosis = diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=9,
        )

    assert diagnosis.batch_workers == 2
    assert diagnosis.native_worker_limit == 10
    assert calls[0]["batch_workers"] == 2
    assert calls[0]["state_vector"] is state_vector
    start_rows = cast(tuple[tuple[float, ...], ...], calls[0]["start_rows"])
    assert len(start_rows) == 9
    assert start_rows[0] == (0.02, 50.0)
    assert math.isclose(start_rows[-1][0], 2.0)
    assert start_rows[-1][1] == 900.0

    calls.clear()

    with patch(
        "zdisamar.inverse_method.optimal_estimation.o2a.diagnosis_batch",
        side_effect=diagnosis_batch,
    ):
        explicit = diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=9,
            batch_workers=2,
        )

    assert explicit.batch_workers == 2
    assert calls[0]["batch_workers"] == 2
    assert calls[0]["state_vector"] is state_vector
    assert len(cast(tuple[object, ...], calls[0]["start_rows"])) == 9

    calls.clear()

    explicit_rows = tuple((0.02 + index * 0.001, 50.0 + index) for index in range(100))

    def explicit_diagnosis_batch(**kwargs):

        calls.append(kwargs)
        rows = cast(tuple[tuple[float, ...], ...], kwargs["start_rows"])

        return BatchResult(
            state_names=state_vector.names,
            state=rows,
            iterations=(1,) * len(rows),
            converged=(True,) * len(rows),
            measurement=measurement,
            status=("ok",) * len(rows),
        )

    with patch(
        "zdisamar.inverse_method.optimal_estimation.o2a.diagnosis_batch",
        side_effect=explicit_diagnosis_batch,
    ):
        explicit_large = diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=len(explicit_rows),
            batch_workers=2,
            start_rows=explicit_rows,
        )

    assert len(explicit_large.start_state) == 100
    assert calls[0]["start_rows"] == explicit_rows


def assert_optimal_estimation_diagnosis_adaptive_grid() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.inverse_method.optimal_estimation.diagnosis import diagnose_retrieval
    from zdisamar.inverse_method.optimal_estimation.o2a import BatchResult
    from zdisamar.inverse_method.optimal_estimation.retrieval import Measurement, RetrievalControls
    from zdisamar.inverse_method.optimal_estimation.state_vector import (
        AerosolLayerMidPressure,
        AerosolOpticalDepth,
        StateVector,
        StateVectorParameter,
    )

    state_vector = StateVector(
        cast(
            tuple[StateVectorParameter, ...],
            (
                AerosolOpticalDepth(
                    initial=0.2,
                    prior=0.2,
                    prior_uncertainty=0.5,
                ),
                AerosolLayerMidPressure(
                    initial=600.0,
                    prior=600.0,
                    prior_uncertainty=150.0,
                ),
            ),
        )
    )
    measurement = Measurement(
        wavelength_nm=(760.0, 761.0),
        reflectance=(0.1, 0.2),
        signal_to_noise=100.0,
    )
    calls: list[tuple[tuple[float, ...], ...]] = []

    def diagnosis_batch(**kwargs):

        rows = cast(tuple[tuple[float, ...], ...], kwargs["start_rows"])
        calls.append(rows)
        states = []
        converged = []
        status = []

        for aod, pressure in rows:
            failed = aod > 1.6 and pressure > 650.0

            if failed:
                states.append((math.nan, math.nan))
                converged.append(False)
                status.append("failed")
            elif aod < 0.55:
                states.append((0.24, 620.0))
                converged.append(True)
                status.append("ok")
            else:
                states.append((1.28, 310.0))
                converged.append(True)
                status.append("ok")

        return BatchResult(
            state_names=state_vector.names,
            state=tuple(states),
            iterations=(3,) * len(rows),
            converged=tuple(converged),
            measurement=measurement,
            status=tuple(status),
        )

    with (
        patch.dict(os.environ, {"ZDISAMAR_WORKER_LIMIT": "10"}),
        patch(
            "zdisamar.inverse_method.optimal_estimation.o2a.diagnosis_batch",
            side_effect=diagnosis_batch,
        ),
    ):
        diagnosis = diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=25,
        )

    assert len(calls) == 2
    assert len(calls[0]) == 16
    assert len(calls[1]) == 9
    assert len(diagnosis.start_state) == 25
    assert diagnosis.start_state[:16] == calls[0]
    assert diagnosis.start_state[16:] == calls[1]
    assert any(row[0] not in {start[0] for start in calls[0]} for row in calls[1])
    assert cast(int, diagnosis.to_dict()["non_converged"]) >= 1

    calls.clear()

    with patch(
        "zdisamar.inverse_method.optimal_estimation.o2a.diagnosis_batch",
        side_effect=diagnosis_batch,
    ):
        dynamic = diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
        )

    assert len(calls) >= 3
    assert len(calls[0]) == 9
    assert len(calls[1]) == 10
    assert 9 < len(dynamic.start_state) <= 30
    first_refinement_rows = calls[1]
    dynamic_refinement_rows = dynamic.start_state[9:]
    assert any(0.46 <= row[0] <= 0.49 for row in first_refinement_rows)
    assert any(0.58 <= row[0] <= 0.60 for row in first_refinement_rows)
    assert any(0.45 <= row[0] <= 0.65 for row in dynamic_refinement_rows)
    assert any(0.37 <= row[0] <= 0.55 for row in dynamic_refinement_rows)

    calls.clear()
    from zdisamar.inverse_method.optimal_estimation.diagnosis import BoundaryBisectionStrategy

    strategy = BoundaryBisectionStrategy(
        refinement_batch_size=3,
        bracket_fractions=(0.125,),
    )

    with patch(
        "zdisamar.inverse_method.optimal_estimation.o2a.diagnosis_batch",
        side_effect=diagnosis_batch,
    ):
        custom = diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            seeding_strategy=strategy,
        )

    assert len(calls) >= 2
    assert len(calls[1]) == 3
    assert any(0.46 <= row[0] <= 0.49 for row in custom.start_state[9:])

    from zdisamar.inverse_method.optimal_estimation.diagnosis import DiagnosisBatchSummary

    def synthetic_boundary_batch(rows: tuple[tuple[float, ...], ...]) -> DiagnosisBatchSummary:

        states = tuple((0.24, 620.0) if aod < 0.43 else (1.28, 310.0) for aod, _ in rows)

        return DiagnosisBatchSummary(
            state=states,
            iterations=(3,) * len(rows),
            converged=(True,) * len(rows),
            status=("ok",) * len(rows),
            history_state=(),
            fast_stage_iterations=None,
            fast_stage_converged=None,
            full_correction_iterations=None,
            full_correction_converged=None,
        )

    strategy = BoundaryBisectionStrategy()
    rows = strategy.initial_rows(((0.02, 2.0), (50.0, 900.0)))
    summary = synthetic_boundary_batch(rows)

    while len(rows) < 30:
        next_rows = strategy.refinement_rows(
            axes=((0.02, 2.0), (50.0, 900.0)),
            start_rows=rows,
            batch=summary,
            count=min(strategy.refinement_batch_size, 30 - len(rows)),
        )

        if not next_rows:
            break

        next_summary = synthetic_boundary_batch(next_rows)
        rows += next_rows
        summary = DiagnosisBatchSummary(
            state=summary.state + next_summary.state,
            iterations=summary.iterations + next_summary.iterations,
            converged=summary.converged + next_summary.converged,
            status=summary.status + next_summary.status,
            history_state=(),
            fast_stage_iterations=None,
            fast_stage_converged=None,
            full_correction_iterations=None,
            full_correction_converged=None,
        )

    boundary_aod = [row[0] for row in rows if 0.38 <= row[0] <= 0.45]
    assert len(boundary_aod) >= 6
    assert any(0.421 <= value <= 0.422 for value in boundary_aod)
    assert any(0.433 <= value <= 0.434 for value in boundary_aod)

    try:
        diagnose_retrieval(
            case=cast(O2AInput, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=31,
        )
    except ValueError as error:
        assert "at most 30" in str(error)
    else:
        raise AssertionError("diagnosis accepted more than 30 starts")


def assert_final_evaluation_reuses_last_rtm_evaluation() -> None:

    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import Result
    from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation

    sentinel = cast(RtmEvaluation, object())
    calls = 0
    result = Result(
        state_names=("aerosol_optical_depth",),
        state=(1.0,),
        iterations=1,
        converged=True,
        history=(),
        posterior_covariance=((1.0,),),
        averaging_kernel=((1.0,),),
        last_evaluated_state=(1.0,),
        last_evaluation=sentinel,
    )

    def evaluate_state(_state):

        nonlocal calls
        calls += 1

        return cast(RtmEvaluation, object())

    attached = o2a_oe.attach_final_evaluation(result, evaluate_state)
    assert attached.final_evaluation is sentinel
    assert calls == 0


def assert_lazy_final_evaluator_snapshots_case() -> None:

    from zdisamar.inverse_method import optimal_estimation
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation
    from zdisamar.wavelength_bands import o2a

    sentinel = cast(RtmEvaluation, object())
    observed_solar_zenith: list[float] = []
    case = o2a.reference_case()
    original_solar_zenith = case.geometry.solar_zenith_deg

    def fake_evaluate_state(template, _state, _state_vector):

        observed_solar_zenith.append(template.geometry.solar_zenith_deg)

        return sentinel

    with patch.object(o2a_oe, "evaluate_state", fake_evaluate_state):
        evaluator = o2a_oe._lazy_final_evaluator(  # noqa: SLF001
            case,
            optimal_estimation.StateVector(
                [
                    optimal_estimation.AerosolOpticalDepth(
                        initial=0.3,
                        prior=0.3,
                        prior_uncertainty=math.sqrt(0.8),
                    )
                ]
            ),
        )
        case.geometry.solar_zenith_deg = 0.0

        assert evaluator([1.0]) is sentinel

    assert observed_solar_zenith == [original_solar_zenith]


def assert_state_vector_uncertainty_rejected() -> None:

    from zdisamar.inverse_method import optimal_estimation

    for uncertainty in (-1.0, 0.0, math.inf, math.nan):
        try:
            optimal_estimation.StateVector(
                (
                    optimal_estimation.AerosolOpticalDepth(
                        initial=0.3,
                        prior=0.3,
                        prior_uncertainty=uncertainty,
                    ),
                )
            )
        except ValueError as error:
            assert "uncertainty" in str(error)
        else:
            raise AssertionError("invalid state-vector uncertainty was accepted")


def assert_measurement_accepts_scientific_numeric_scalars() -> None:

    import numpy as np
    from zdisamar.inverse_method import optimal_estimation

    measurement = optimal_estimation.Measurement(
        wavelength_nm=(cast(float, np.float64(760.0)), cast(float, np.float64(760.1))),
        reflectance=(cast(float, np.float64(0.2)), cast(float, np.float64(0.21))),
        signal_to_noise=(cast(float, np.float64(1000.0)), cast(float, np.float64(900.0))),
    )

    assert measurement.signal_to_noise == (1000.0, 900.0)

    from_uncertainty = optimal_estimation.Measurement.from_reflectance_uncertainty(
        wavelength_nm=(cast(float, np.float64(760.0)),),
        reflectance=(cast(float, np.float64(0.0)),),
        reflectance_uncertainty=(cast(float, np.float64(1.0e-12)),),
    )

    assert math.isclose(from_uncertainty.reflectance_uncertainty[0], 1.0e-12)


def assert_o2a_case_aerosol_state_properties() -> None:

    from zdisamar.wavelength_bands import o2a

    case = o2a.reference_case()
    serialized_aerosol = case.aerosol.to_dict()
    assert "layer_center_km" not in serialized_aerosol
    assert "layer_width_km" not in serialized_aerosol

    case.aerosol_optical_depth_550_nm = 0.31
    case.aerosol_layer.thickness_hpa = 50.0
    case.aerosol_layer.mid_pressure_hpa = 900.0

    assert case.aerosol.optical_depth_550_nm == 0.31
    assert case.aerosol_layer.thickness_hpa == 50.0
    assert case.aerosol_layer.mid_pressure_hpa == 900.0
    assert case.aerosol.placement.top_pressure_hpa == 875.0
    assert case.aerosol.placement.bottom_pressure_hpa == 925.0
    assert case.atmosphere.intervals[0].bottom_pressure_hpa == 875.0
    assert case.atmosphere.intervals[1].top_pressure_hpa == 875.0
    assert case.atmosphere.intervals[1].bottom_pressure_hpa == 925.0
    assert case.atmosphere.intervals[2].top_pressure_hpa == 925.0

    legacy = copy.deepcopy(serialized_aerosol)
    legacy["layer_center_km"] = 5.4

    try:
        o2a.Aerosol.from_dict(legacy)
    except ValueError as error:
        assert "unsupported aerosol placement fields" in str(error)
    else:
        raise AssertionError("legacy aerosol placement fields were accepted")

    invalid_case = copy.deepcopy(case)
    invalid_case.aerosol.placement.semantics = "altitude_center_width_approximation"

    try:
        invalid_case.aerosol_layer.mid_pressure_hpa = 900.0
    except ValueError as error:
        assert "explicit interval bounds" in str(error)
    else:
        raise AssertionError("pressure setter accepted altitude placement semantics")

    invalid_case = copy.deepcopy(case)

    try:
        invalid_case.aerosol_layer.mid_pressure_hpa = math.nan
    except ValueError as error:
        assert "finite" in str(error)
    else:
        raise AssertionError("pressure setter accepted non-finite pressure")

    invalid_case = copy.deepcopy(case)
    original_top_pressure_hpa = invalid_case.aerosol.placement.top_pressure_hpa
    original_bottom_pressure_hpa = invalid_case.aerosol.placement.bottom_pressure_hpa

    try:
        invalid_case.aerosol_layer.thickness_hpa = 650.0
    except ValueError as error:
        assert "atmosphere ordering" in str(error)
    else:
        raise AssertionError("pressure setter accepted inverted neighboring intervals")

    assert invalid_case.aerosol.placement.top_pressure_hpa == original_top_pressure_hpa
    assert invalid_case.aerosol.placement.bottom_pressure_hpa == original_bottom_pressure_hpa


def assert_deprecated_python_input_fields_rejected() -> None:

    from zdisamar.wavelength_bands import o2a

    case = o2a.reference_case()

    observation = copy.deepcopy(case.instrument_response.to_dict())
    observation["noise_model"] = {"enabled": True}

    try:
        o2a.InstrumentResponse.from_dict(observation)
    except ValueError as error:
        assert "unsupported observation fields" in str(error)
    else:
        raise AssertionError("deprecated observation noise_model field was accepted")

    radiative_transfer = copy.deepcopy(case.radiative_transfer.to_dict())
    radiative_transfer["use_adding"] = True
    radiative_transfer["stokes_dimension"] = 1

    try:
        o2a.RadiativeTransferControls.from_dict(radiative_transfer)
    except ValueError as error:
        assert "unsupported radiative-transfer fields" in str(error)
    else:
        raise AssertionError("deprecated radiative-transfer fields were accepted")


def assert_native_oe_loads_requested_case_into_supplied_cache() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    events: list[tuple[str, object, object]] = []
    requested_case = SimpleNamespace(scene_id="requested")
    measurement = Measurement((760.0,), (0.2,), signal_to_noise=100.0)
    state_vector = SimpleNamespace(parameters=(), jacobian_names=("aerosol_optical_depth",))
    controls = RetrievalControls(max_iterations=1)
    native_result = Result((), (), 0, True, (), (), ())

    class Handle:
        def optimal_estimation(self, *, measurement, state_vector, controls):

            events.append(("optimal_estimation", measurement, controls))

            return {"state_count": 0}

    class Cache:
        _handle = Handle()

        def has_loaded_case(self, case) -> bool:

            events.append(("has_loaded_case", case, None))

            return False

        def load(self, case, *, copy_case: bool = True) -> None:

            events.append(("load", case, copy_case))

        def warm_optimal_estimation(self, state_names: tuple[str, ...]) -> None:

            events.append(("warm_oe", state_names, None))

    with (
        patch.object(o2a_oe, "_result_from_native", return_value=native_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
    ):
        result = o2a_oe.run_native_retrieval(
            case=cast(O2AInput, requested_case),
            measurement=measurement,
            state_vector=cast(StateVector, state_vector),
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert result is native_result
    assert events == [
        ("has_loaded_case", requested_case, None),
        ("load", requested_case, False),
        ("warm_oe", ("aerosol_optical_depth",), None),
        ("optimal_estimation", measurement, controls),
    ]


def assert_native_oe_reuses_matching_supplied_cache() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    events: list[tuple[str, object, object]] = []
    requested_case = SimpleNamespace(scene_id="requested")
    measurement = Measurement((760.0,), (0.2,), signal_to_noise=100.0)
    state_vector = SimpleNamespace(parameters=(), jacobian_names=("aerosol_optical_depth",))
    controls = RetrievalControls(max_iterations=1)
    native_result = Result((), (), 0, True, (), (), ())

    class Handle:
        def optimal_estimation(self, *, measurement, state_vector, controls):

            events.append(("optimal_estimation", measurement, controls))

            return {"state_count": 0}

    class Cache:
        _handle = Handle()

        def has_loaded_case(self, case) -> bool:

            events.append(("has_loaded_case", case, None))

            return True

        def load(self, case, *, copy_case: bool = True) -> None:

            raise AssertionError("matching OE cache reloaded its prepared case")

        def warm_optimal_estimation(self, state_names: tuple[str, ...]) -> None:

            events.append(("warm_oe", state_names, None))

    with (
        patch.object(o2a_oe, "_result_from_native", return_value=native_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
    ):
        result = o2a_oe.run_native_retrieval(
            case=cast(O2AInput, requested_case),
            measurement=measurement,
            state_vector=cast(StateVector, state_vector),
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert result is native_result
    assert events == [
        ("has_loaded_case", requested_case, None),
        ("warm_oe", ("aerosol_optical_depth",), None),
        ("optimal_estimation", measurement, controls),
    ]


def assert_fastmode_oe_runs_single_full_correction() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.input.wavelength_band.optimisation import O2AOptimisation
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

    optimisation = O2AOptimisation.defaults()
    optimisation.fastmode.enabled = True
    optimisation.fastmode.oe.fast_stage_sampling.enabled = False
    reference_case = SimpleNamespace(scene_id="reference", optimisation=optimisation)
    full_case = SimpleNamespace(scene_id="full")
    correction_case = SimpleNamespace(scene_id="correction")
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

        def has_loaded_case(self, case) -> bool:

            assert case is reference_case

            return False

        def load(self, case, *, copy_case: bool = True) -> None:

            loads.append((case, copy_case))

        def warm(self) -> None:

            pass

    class CorrectionCache:
        _handle = Cache.Handle()

        def load(self, case, *, copy_case: bool = True) -> None:

            correction_loads.append((case, copy_case))

        def __enter__(self):

            return self

        def __exit__(self, *_exc: object) -> None:

            return None

    with (
        patch.object(o2a_oe, "run_native_retrieval", side_effect=fake_native_retrieval),
        patch.object(o2a_oe, "full_physics_case", return_value=full_case) as full_physics_case,
        patch.object(o2a_oe, "case_for_state", return_value=correction_case) as case_for_state,
        patch.object(
            o2a_oe,
            "full_correction_measurement",
            return_value=correction_measurement,
        ) as correction_measurement_builder,
        patch.object(
            o2a_oe,
            "full_correction_case",
            return_value=correction_case,
        ) as correction_case_builder,
        patch.object(o2a_oe, "_result_from_native", return_value=full_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
        patch.object(o2a_oe.rtm, "SessionCache", side_effect=CorrectionCache) as session_cache,
    ):
        result = o2a_oe.retrieve(
            case=cast(O2AInput, reference_case),
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert calls[0]["case"] is reference_case
    assert calls[0]["controls"] is controls
    assert calls[0]["load_case"] is False
    assert len(calls) == 1
    full_physics_case.assert_called_once_with(reference_case)
    case_for_state.assert_called_once_with(full_case, fast_result.state, state_vector)
    correction_measurement_builder.assert_called_once_with(
        measurement,
        wavelengths_nm=(765.2, 766.0, 768.0),
        uncertainty_scale=None,
    )
    correction_case_builder.assert_called_once_with(correction_case, correction_measurement)
    session_cache.assert_called_once_with()
    assert loads == [(reference_case, False)]
    assert correction_loads == [(correction_case, False)]
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


def assert_fastmode_oe_uses_sparse_fast_stage_sampling() -> None:

    from zdisamar.input.instrument import SpectralGrid
    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.input.wavelength_band.optimisation import (
        FastModeWavelengthWindow,
        O2AOptimisation,
    )
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import (
        Measurement,
        Result,
        RetrievalControls,
    )
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector
    from zdisamar.rtm.session_cache import SessionCache

    optimisation = O2AOptimisation.defaults()
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
    reference_case = SimpleNamespace(
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

        def has_loaded_case(self, case) -> bool:

            del case

            return False

        def load(self, case, *, copy_case: bool = True) -> None:

            loads.append((case, copy_case))

        def warm(self) -> None:

            pass

    with patch.object(o2a_oe, "run_native_retrieval", side_effect=fake_native_retrieval):
        result = o2a_oe.retrieve(
            case=cast(O2AInput, reference_case),
            measurement=measurement,
            state_vector=state_vector,
            cache=cast(SessionCache, Cache()),
        )

    assert result is not None
    assert len(calls) == 1
    fast_case = cast(O2AInput, calls[0]["case"])
    fast_measurement = cast(Measurement, calls[0]["measurement"])
    expected_wavelengths = optimisation.fastmode.oe.fast_stage_sampling.resolved_wavelengths(
        measurement.wavelength_nm
    )
    assert tuple(fast_measurement.wavelength_nm) == expected_wavelengths
    assert len(fast_measurement.wavelength_nm) < len(measurement.wavelength_nm)
    assert fast_case is loads[0][0]
    assert fast_case is not reference_case
    assert fast_case.spectral_grid.sample_count == len(fast_measurement.wavelength_nm)
    assert tuple(fast_case.instrument_response.measured_wavelengths_nm) == expected_wavelengths
    assert calls[0]["load_case"] is False
    active_controls = cast(RetrievalControls, calls[0]["controls"])
    assert active_controls.max_iterations == 3
    assert loads == [(fast_case, False)]

    optimisation.fastmode.oe.fast_stage_sampling.windows = (
        FastModeWavelengthWindow((755.0, 755.2), 1),
    )

    try:
        optimisation.fastmode.oe.fast_stage_sampling.resolved_wavelengths(measurement.wavelength_nm)
    except ValueError as error:
        assert "wavelength count must be at least two" in str(error)
    else:
        raise AssertionError("single-sample fast-stage window count was accepted")


def assert_fastmode_batch_uses_native_fused_correction() -> None:

    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.input.wavelength_band.optimisation import O2AOptimisation
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

    optimisation = O2AOptimisation.defaults()
    optimisation.fastmode.enabled = True
    reference_case = SimpleNamespace(scene_id="reference", optimisation=optimisation)
    reference_o2a_case = cast(O2AInput, reference_case)
    full_case = SimpleNamespace(scene_id="full")
    correction_case = SimpleNamespace(scene_id="correction")
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

        def load(self, case, *, copy_case: bool = True) -> None:

            correction_loads.append((case, copy_case))

        def __enter__(self):

            return self

        def __exit__(self, *_exc: object) -> None:

            return None

    with (
        patch.object(o2a_oe, "full_physics_case", return_value=full_case) as full_physics_case,
        patch.object(
            o2a_oe,
            "full_correction_measurement",
            return_value=correction_measurement,
        ) as correction_measurement_builder,
        patch.object(
            o2a_oe,
            "full_correction_case",
            return_value=correction_case,
        ) as correction_case_builder,
        patch.object(o2a_oe.rtm, "SessionCache", side_effect=CorrectionCache) as session_cache,
        patch.object(
            o2a_oe,
            "resolved_state_vector_for_loaded_case",
            return_value=state_vectors[0],
        ) as resolved_template,
    ):
        result = o2a_oe.run_native_fastmode_retrieval_batch(
            case=reference_o2a_case,
            measurement=measurement,
            fast_measurement=fast_measurement,
            state_vector=state_vectors[0],
            resolved_template=state_vectors[0],
            controls=controls,
            cache=cast(o2a_oe.rtm.SessionCache, FastCache()),
            start_rows=tuple(vector.initial_state() for vector in state_vectors),
            batch_workers=3,
        )

    full_physics_case.assert_called_once_with(reference_case)
    correction_measurement_builder.assert_called_once_with(
        measurement,
        wavelengths_nm=(765.2, 766.0, 768.0),
        uncertainty_scale=None,
    )
    correction_case_builder.assert_called_once_with(full_case, correction_measurement)
    session_cache.assert_called_once_with()
    assert correction_loads == [(correction_case, False)]
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


def assert_fastmode_pressure_profile_uses_loaded_sparse_cache() -> None:

    from zdisamar.input.instrument import SpectralGrid
    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.input.wavelength_band.optimisation import O2AOptimisation
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

        def resolve_for_case(self, case, pressure_altitude_profile) -> ResolvedParameter:

            del case
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

    optimisation = O2AOptimisation.defaults()
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
    reference_case = SimpleNamespace(
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

        def has_loaded_case(self, case) -> bool:

            match_checks.append(case)

            return bool(loads and loads[-1][0] is case)

        def load(self, case, *, copy_case: bool = True) -> None:

            loads.append((case, copy_case))

        def warm(self) -> None:

            pass

    def fake_pressure_profile(case, cache):

        profile_calls.append((case, cache))

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
            case=cast(O2AInput, reference_case),
            measurement=measurement,
            state_vector=state_vector,
            cache=cast(SessionCache, cache),
        )

    assert result.converged
    assert len(loads) == 1
    fast_case = cast(O2AInput, loads[0][0])
    assert fast_case is not reference_case
    assert fast_case.spectral_grid.sample_count < reference_case.spectral_grid.sample_count
    assert match_checks == [fast_case]
    assert profile_calls == [(fast_case, cache)]
    assert len(retrieval_calls) == 1
    active_controls = cast(RetrievalControls, retrieval_calls[0]["controls"])
    assert active_controls.max_iterations == 4
    resolved_state_vector = cast(StateVector, retrieval_calls[0]["state_vector"])
    assert isinstance(resolved_state_vector.parameters[0], ResolvedParameter)


def assert_native_oe_marshaling_bounds() -> None:

    from zdisamar.bindings.handles import RtmHandle
    from zdisamar.inverse_method import optimal_estimation

    handle = object.__new__(RtmHandle)
    measurement = optimal_estimation.Measurement(
        wavelength_nm=[760.0],
        reflectance=[0.2],
        signal_to_noise=100.0,
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
            )
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


def assert_native_oe_runs_after_default_prepare() -> None:

    from zdisamar.bindings.handles import RtmHandle
    from zdisamar.inverse_method import optimal_estimation

    handle = RtmHandle()

    try:
        case = handle.default_o2a_case()
        measurement = optimal_estimation.simulate_measurement(
            case,
            signal_to_noise=100.0,
        )
        state_vector = optimal_estimation.StateVector(
            (
                optimal_estimation.AerosolOpticalDepth(
                    initial=0.3,
                    prior=0.3,
                    prior_uncertainty=math.sqrt(0.8),
                ),
            )
        )
        handle._check(handle._lib.zds_prepare_default_o2a(handle._ctx))  # noqa: SLF001
        result = handle.optimal_estimation(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=1),
        )
        assert result["iteration_count"] == 1
        assert result["state_count"] == 1
        correction = handle.optimal_estimation_correction(
            measurement=measurement,
            state_vector=state_vector,
            controls=optimal_estimation.RetrievalControls(max_iterations=10),
        )
        assert correction["iteration_count"] == 1
        assert correction["state_count"] == 1
    finally:
        handle.close()


def assert_reference_data_and_rtm_tables() -> None:

    import numpy as np
    from zdisamar import rtm
    from zdisamar.output.tables import PandasConversionError
    from zdisamar.wavelength_bands import o2a

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = Path.cwd()

        try:
            os.chdir(tmpdir)
            case = o2a.reference_case()
            assert "vendor/disamar-fortran" not in case.o2_lines.line_list_asset.path
            thresholds = case.radiative_transfer.performance_thresholds
            assert thresholds.aerosol_tangent_order_cap is None
            assert not thresholds.qzero_rd_product_suppression
            assert not thresholds.qzero_tu_product_suppression
            assert not thresholds.qzero_td_product_suppression
            assert math.isclose(thresholds.fourier_tail_reflectance_epsilon, 3.0e-14)
            fast_thresholds = o2a.RadiativeTransferPerformanceThresholds.fast()
            assert fast_thresholds.fourier_order_cap == 5
            assert fast_thresholds.aerosol_tangent_order_cap == 11
            assert math.isclose(fast_thresholds.fourier_tail_reflectance_epsilon, 1.0e-11)
            assert math.isclose(fast_thresholds.threshold_doubl, 3.0e-5)
            assert math.isclose(fast_thresholds.threshold_mul, thresholds.threshold_mul)
            assert not fast_thresholds.qzero_rd_product_suppression
            assert not fast_thresholds.qzero_tu_product_suppression
            assert not fast_thresholds.qzero_td_product_suppression
            validation_thresholds = copy.deepcopy(thresholds)
            validation_thresholds.phase_function_truncation_threshold = 1.0e-6
            validation_fast_thresholds = validation_thresholds.with_fast_mode()
            assert validation_fast_thresholds.fourier_order_cap == fast_thresholds.fourier_order_cap
            assert (
                validation_fast_thresholds.aerosol_tangent_order_cap
                == fast_thresholds.aerosol_tangent_order_cap
            )
            assert math.isclose(
                validation_fast_thresholds.fourier_tail_reflectance_epsilon,
                fast_thresholds.fourier_tail_reflectance_epsilon,
            )
            assert math.isclose(
                validation_fast_thresholds.threshold_doubl,
                fast_thresholds.threshold_doubl,
            )
            assert math.isclose(
                validation_fast_thresholds.phase_function_truncation_threshold,
                validation_thresholds.phase_function_truncation_threshold,
            )
            assert not validation_fast_thresholds.qzero_rd_product_suppression
            assert not validation_fast_thresholds.qzero_tu_product_suppression
            assert not validation_fast_thresholds.qzero_td_product_suppression
            fast_case = copy.deepcopy(case)
            fast_case.optimisation.fastmode.enabled = True
            assert fast_case is not case
            assert fast_case.optimisation.fastmode.enabled
            assert not case.optimisation.fastmode.enabled
            resolved_fastmode = fast_case.optimisation.fastmode.resolved_dict(
                fast_case.measurement_wavelengths_nm
            )
            fastmode_radiative_transfer = cast(
                dict[str, object],
                resolved_fastmode["radiative_transfer"],
            )
            assert fastmode_radiative_transfer["fourier_order_cap"] == 5
            fastmode_oe = cast(dict[str, object], resolved_fastmode["oe"])
            fast_controls = cast(dict[str, object], fastmode_oe["controls"])
            assert fast_controls["state_vector_convergence_threshold"] == 1.0
            fast_sampling = cast(dict[str, object], fastmode_oe["fast_stage_sampling"])
            fast_sampling_wavelengths = cast(list[float], fast_sampling["wavelengths_nm"])
            fast_sampling_count = cast(int, fast_sampling["sample_count"])
            assert fast_sampling["enabled"]
            assert fast_sampling_count == len(fast_sampling_wavelengths)
            assert fast_sampling_count < len(fast_case.measurement_wavelengths_nm)
            assert fast_sampling["windows"] == [
                {"wavelength_window_nm": [758.0, 758.08], "wavelength_count": 2},
                {"wavelength_window_nm": [758.2, 758.28], "wavelength_count": 2},
                {"wavelength_window_nm": [758.36, 758.48], "wavelength_count": 2},
                {"wavelength_window_nm": [765.2, 765.32], "wavelength_count": 2},
                {"wavelength_window_nm": [765.44, 765.68], "wavelength_count": 2},
                {"wavelength_window_nm": [766.24, 766.84], "wavelength_count": 2},
            ]
            assert fast_sampling_count == 12
            final_correction = cast(dict[str, object], fastmode_oe["final_correction"])
            final_correction_wavelengths = cast(list[float], final_correction["wavelengths_nm"])
            assert final_correction["wavelength_count"] == 4
            assert len(final_correction_wavelengths) == 4
            fast_case.optimisation.fastmode.oe.fast_stage_sampling.enabled = False
            disabled_fastmode = fast_case.optimisation.fastmode.resolved_dict(
                fast_case.measurement_wavelengths_nm
            )
            disabled_fastmode_oe = cast(dict[str, object], disabled_fastmode["oe"])
            disabled_fast_sampling = cast(
                dict[str, object],
                disabled_fastmode_oe["fast_stage_sampling"],
            )
            disabled_sampling_wavelengths = cast(
                list[float],
                disabled_fast_sampling["wavelengths_nm"],
            )
            disabled_sampling_count = cast(int, disabled_fast_sampling["sample_count"])
            assert not disabled_fast_sampling["enabled"]
            assert disabled_sampling_count == len(fast_case.measurement_wavelengths_nm)
            assert disabled_sampling_count == len(disabled_sampling_wavelengths)
            fast_case.optimisation.fastmode.oe.fast_stage_sampling.enabled = True
            fast_case.optimisation.fastmode.oe.fast_stage_sampling.windows = (
                o2a.FastModeWavelengthWindow((759.7, 762.5), 10),
                o2a.FastModeWavelengthWindow((765.2, 768.0), 10),
            )
            fast_case.optimisation.fastmode.oe.final_correction.wavelengths_nm = (
                765.2,
                766.0,
                768.0,
            )
            fast_roundtrip = o2a.O2ACase.from_json(fast_case.to_json_bytes())
            assert fast_roundtrip.optimisation.fastmode.enabled
            assert fast_roundtrip.optimisation.fastmode.oe.fast_stage_sampling.windows == (
                o2a.FastModeWavelengthWindow((759.7, 762.5), 10),
                o2a.FastModeWavelengthWindow((765.2, 768.0), 10),
            )
            assert fast_roundtrip.optimisation.fastmode.oe.final_correction.wavelengths_nm == (
                765.2,
                766.0,
                768.0,
            )
            assert b'"optimisation"' in fast_case.to_json_bytes()
            assert b'"optimisation"' not in fast_case.to_native_json_bytes()
            invalid_optimisation_case = copy.deepcopy(fast_case.to_dict())
            invalid_optimisation = cast(
                dict[str, object],
                invalid_optimisation_case["optimisation"],
            )
            invalid_fastmode = cast(dict[str, object], invalid_optimisation["fastmode"])
            invalid_fastmode["ignored"] = True

            try:
                o2a.O2ACase.from_dict(invalid_optimisation_case)
            except ValueError as exc:
                assert "unsupported fastmode fields" in str(exc)
            else:
                raise AssertionError("unsupported fastmode optimisation control was accepted")

            invalid_sampling_case = copy.deepcopy(fast_case.to_dict())
            invalid_sampling_optimisation = cast(
                dict[str, object],
                invalid_sampling_case["optimisation"],
            )
            invalid_sampling_fastmode = cast(
                dict[str, object],
                invalid_sampling_optimisation["fastmode"],
            )
            invalid_sampling_oe = cast(dict[str, object], invalid_sampling_fastmode["oe"])
            invalid_sampling = cast(dict[str, object], invalid_sampling_oe["fast_stage_sampling"])
            invalid_sampling["ignored"] = True

            try:
                o2a.O2ACase.from_dict(invalid_sampling_case)
            except ValueError as exc:
                assert "unsupported fastmode fast-stage sampling fields" in str(exc)
            else:
                raise AssertionError("unsupported fast-stage sampling control was accepted")

            assert fast_case.radiative_transfer.performance_thresholds.fourier_order_cap is None
            fast_rtm_case = fast_case.with_rtm_optimisation_applied()
            assert fast_rtm_case.optimisation.fastmode.enabled is False
            assert fast_rtm_case.radiative_transfer.performance_thresholds.fourier_order_cap == 5
            assert (
                fast_rtm_case.radiative_transfer.performance_thresholds.aerosol_tangent_order_cap
                == 11
            )
            assert math.isclose(
                fast_rtm_case.radiative_transfer.performance_thresholds.threshold_doubl,
                3.0e-5,
            )
            fast_thresholds = fast_rtm_case.radiative_transfer.performance_thresholds
            assert not fast_thresholds.qzero_rd_product_suppression
            assert not fast_thresholds.qzero_tu_product_suppression
            assert not fast_thresholds.qzero_td_product_suppression
            fast_grid = fast_rtm_case.instrument_response.adaptive_reference_grid
            assert fast_grid["points_per_fwhm"] == 28
            assert fast_grid["strong_line_min_divisions"] == 6
            assert fast_grid["strong_line_max_divisions"] == 22
            assert (
                case.instrument_response.adaptive_reference_grid["strong_line_max_divisions"] != 22
            )
            nominal_wavelengths = rtm.nominal_wavelengths(case)
            assert nominal_wavelengths[0] == case.spectral_grid.start_nm
            assert nominal_wavelengths[-1] == case.spectral_grid.end_nm
            invalid_grid_case = copy.deepcopy(case)
            invalid_grid_case.spectral_grid.sample_count = -1

            try:
                rtm.nominal_wavelengths(invalid_grid_case)
            except ValueError as error:
                assert "sample_count" in str(error)
            else:
                raise AssertionError("negative nominal spectral sample count was accepted")

            mutable_case = copy.deepcopy(case)

            with rtm.SessionCache() as cache:
                cache.load(mutable_case)
                mutable_case.geometry.solar_zenith_deg = 0.0
                spectrum = cache.spectrum(include_case=True)
                assert spectrum.case is not None
                assert spectrum.case.geometry.solar_zenith_deg == case.geometry.solar_zenith_deg

            budget = rtm.atmospheric_budget(case, np.array([760.76], dtype=np.float64))
            assert budget.row_count > 0
            assert len(budget.column("wavelength_nm")) == budget.row_count
            first_table = budget.table
            first_wavelength = float(first_table[0]["wavelength_nm"])
            first_table[0]["wavelength_nm"] = -1.0
            assert float(budget.column("wavelength_nm")[0]) == first_wavelength
            rows = budget.to_rows()
            assert len(rows) == budget.row_count
            assert "support_row_kind_label" in rows[0]

            with patch.dict(sys.modules, {"pandas": None}):
                try:
                    budget.to_pandas()
                except PandasConversionError as error:
                    assert "to_rows" in str(error)
                else:
                    raise AssertionError("to_pandas succeeded without pandas installed")

            spectrum = rtm.spectrum(case)
            output = Path(tmpdir) / "reflectance"
            chart = spectrum.plot.reflectance(save=output)
            assert chart is not None
            reflectance_spec = chart.to_dict()
            reflectance_panels = cast(list[dict[str, object]], reflectance_spec["panels"])
            reflectance_series = cast(list[dict[str, object]], reflectance_panels[0]["series"])
            assert any(
                series["kind"] == "points" and series["name"] == "Minimum reflectance"
                for series in reflectance_series
            )
            assert output.with_suffix(".svg").exists()
        finally:
            os.chdir(old_cwd)


def main() -> int:

    assert_import_laziness()
    assert_plot_package_boundary()
    assert_rtm_conversions()
    assert_session_cache_warms_optimal_estimation_route_once()
    assert_plot_jacobian_uses_rtm_conversion()
    assert_optimal_estimation_grid_mismatch_rejected()
    assert_optimal_estimation_result_dataclass()
    assert_optimal_estimation_diagnosis_display()
    assert_optimal_estimation_diagnosis_auto_workers()
    assert_optimal_estimation_diagnosis_adaptive_grid()
    assert_final_evaluation_reuses_last_rtm_evaluation()
    assert_lazy_final_evaluator_snapshots_case()
    assert_state_vector_uncertainty_rejected()
    assert_measurement_accepts_scientific_numeric_scalars()
    assert_o2a_case_aerosol_state_properties()
    assert_deprecated_python_input_fields_rejected()
    assert_native_oe_loads_requested_case_into_supplied_cache()
    assert_native_oe_reuses_matching_supplied_cache()
    assert_fastmode_oe_runs_single_full_correction()
    assert_fastmode_oe_uses_sparse_fast_stage_sampling()
    assert_fastmode_batch_uses_native_fused_correction()
    assert_fastmode_pressure_profile_uses_loaded_sparse_cache()
    assert_native_oe_marshaling_bounds()
    assert_native_oe_runs_after_default_prepare()
    assert_reference_data_and_rtm_tables()
    print("python_package_refactor=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
