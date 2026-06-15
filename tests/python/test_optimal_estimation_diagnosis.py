import math
import os
from dataclasses import replace
from types import SimpleNamespace
from typing import cast
from unittest.mock import patch


def test_optimal_estimation_diagnosis_display() -> None:

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
        start_state=((0.1, 225.0), (0.11, 255.0), (0.8, 700.0), (0.9, 900.0)),
        retrieved_state=((0.1, 240.0), (0.105, 243.0), (0.6, 720.0), (0.7, 900.0)),
        iterations=(3, 4, 5, 6),
        converged=(True, True, True, True),
        retrieval_paths=(
            ((0.1, 240.0),),
            ((0.105, 243.0),),
            ((0.6, 720.0),),
            ((0.7,),),
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

    one_axis_sweep = RetrievalDiagnosis(
        state_names=("aerosol_optical_depth",),
        start_state=((0.1,), (0.2,)),
        retrieved_state=((0.12,), (0.22,)),
        iterations=(3, 4),
        converged=(True, True),
        retrieval_paths=(((0.12,),), ((0.22,),)),
        start_bounds=((0.02, 2.0),),
        batch_workers=1,
    )
    assert one_axis_sweep.basins() == ()
    assert one_axis_sweep.to_dict()["basin_count"] == 0

    two_axis_sweep = RetrievalDiagnosis(
        state_names=(
            "aerosol_optical_depth",
            "aerosol_layer_mid_pressure_hpa",
        ),
        start_state=((0.1, 300.0), (0.1, 900.0)),
        retrieved_state=((0.1, 300.0), (0.1, 900.0)),
        iterations=(3, 3),
        converged=(True, True),
        retrieval_paths=(((0.1, 300.0),), ((0.1, 900.0),)),
        start_bounds=((0.02, 2.0), (0.0, 1000.0)),
        batch_workers=1,
    )
    assert len(two_axis_sweep.basins()) == 2
    assert two_axis_sweep.to_dict()["basin_count"] == 2
    assert two_axis_sweep.plot().to_dict()["endpoint_clusters"] == 2

    pressure_basin_sweep = RetrievalDiagnosis(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        start_state=((0.1, 300.0), (0.1, 900.0)),
        retrieved_state=((0.1, 300.0), (0.1, 900.0)),
        iterations=(3, 3),
        converged=(True, True),
        retrieval_paths=(((0.1, 300.0),), ((0.1, 900.0),)),
        start_bounds=((0.02, 2.0), (0.0, 1000.0)),
        batch_workers=1,
    )
    assert len(pressure_basin_sweep.basins()) == 2
    assert pressure_basin_sweep.plot().to_dict()["endpoint_clusters"] == 2

    failed_outlier_sweep = RetrievalDiagnosis(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        start_state=((0.1, 300.0), (0.1, 360.0), (0.1, 900.0)),
        retrieved_state=((0.1, 300.0), (0.1, 360.0), (0.1, 2000.0)),
        iterations=(3, 3, 0),
        converged=(True, True, False),
        retrieval_paths=(((0.1, 300.0),), ((0.1, 360.0),), ((0.1, 2000.0),)),
        start_bounds=((0.02, 2.0), (0.0, 1000.0)),
        batch_workers=1,
        start_status=("ok", "ok", "failed"),
    )
    assert len(failed_outlier_sweep.basins()) == 2
    assert failed_outlier_sweep.plot().to_dict()["endpoint_clusters"] == 2

    no_truth = replace(sweep, truth_state=None)
    no_truth_figure = no_truth.plot()
    assert no_truth_figure.to_dict()["truth"] is None
    no_truth_svg = no_truth_figure._repr_svg_()
    assert ">truth" not in no_truth_svg
    assert 'class="diagnosis-truth"' not in no_truth_svg


def test_optimal_estimation_diagnosis_auto_workers() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=len(explicit_rows),
            batch_workers=2,
            start_rows=explicit_rows,
        )

    assert len(explicit_large.start_state) == 100
    assert calls[0]["start_rows"] == explicit_rows


def test_optimal_estimation_diagnosis_adaptive_grid() -> None:

    from zdisamar.input.wavelength_band.o2a import Scene
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
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
            scene=cast(Scene, SimpleNamespace(surface=SimpleNamespace(pressure_hpa=900.0))),
            measurement=measurement,
            state_vector=state_vector,
            controls=RetrievalControls(),
            n=31,
        )
    except ValueError as error:
        assert "at most 30" in str(error)
    else:
        raise AssertionError("diagnosis accepted more than 30 starts")
