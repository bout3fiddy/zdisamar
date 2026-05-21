import copy
import importlib.util
import math
import os
import sys
import tempfile
from dataclasses import fields, replace
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

    from zdisamar.inverse_method.optimal_estimation.retrieval import Result
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
                        variance=0.8,
                    )
                ]
            ),
        )
        case.geometry.solar_zenith_deg = 0.0

        assert evaluator([1.0]) is sentinel

    assert observed_solar_zenith == [original_solar_zenith]


def assert_o2a_case_aerosol_state_properties() -> None:

    from zdisamar.wavelength_bands import o2a

    case = o2a.reference_case()
    case.aerosol_optical_depth_550_nm = 0.31
    case.aerosol_layer_pressure_thickness_hpa = 50.0
    case.aerosol_layer_mid_pressure_hpa = 900.0

    assert case.aerosol.optical_depth_550_nm == 0.31
    assert case.aerosol_layer_pressure_thickness_hpa == 50.0
    assert case.aerosol_layer_mid_pressure_hpa == 900.0
    assert case.aerosol.placement.top_pressure_hpa == 875.0
    assert case.aerosol.placement.bottom_pressure_hpa == 925.0
    assert case.atmosphere.intervals[0].bottom_pressure_hpa == 875.0
    assert case.atmosphere.intervals[1].top_pressure_hpa == 875.0
    assert case.atmosphere.intervals[1].bottom_pressure_hpa == 925.0
    assert case.atmosphere.intervals[2].top_pressure_hpa == 925.0


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
    measurement = Measurement((), (), ())
    state_vector = SimpleNamespace(parameters=())
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

    with (
        patch.object(o2a_oe, "_result_from_native", return_value=native_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
    ):
        result = o2a_oe._disamar_oe(  # noqa: SLF001
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
    measurement = Measurement((), (), ())
    state_vector = SimpleNamespace(parameters=())
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

    with (
        patch.object(o2a_oe, "_result_from_native", return_value=native_result),
        patch.object(o2a_oe, "attach_final_evaluation", side_effect=lambda result, _eval: result),
    ):
        result = o2a_oe._disamar_oe(  # noqa: SLF001
            case=cast(O2AInput, requested_case),
            measurement=measurement,
            state_vector=cast(StateVector, state_vector),
            controls=controls,
            cache=cast(SessionCache, Cache()),
        )

    assert result is native_result
    assert events == [
        ("has_loaded_case", requested_case, None),
        ("optimal_estimation", measurement, controls),
    ]


def assert_native_oe_marshaling_bounds() -> None:

    from zdisamar.bindings.handles import RtmHandle
    from zdisamar.inverse_method import optimal_estimation

    handle = object.__new__(RtmHandle)
    measurement = optimal_estimation.Measurement(
        wavelength_nm=[760.0],
        reflectance=[0.2],
        variance=[1.0e-6],
    )
    state_vector = SimpleNamespace(
        parameters=[
            SimpleNamespace(
                name="aerosol_optical_depth",
                initial=0.3,
                prior=0.3,
                variance=0.8,
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
    state_vector.parameters[0].jacobian_scale = lambda _value: 2.0

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
        measurement = optimal_estimation.measurement_from_case(case, reflectance_variance=1.0e-6)
        state_vector = optimal_estimation.StateVector(
            (
                optimal_estimation.AerosolOpticalDepth(
                    initial=0.3,
                    prior=0.3,
                    variance=0.8,
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
            assert math.isclose(thresholds.fourier_tail_reflectance_epsilon, 3.0e-14)
            fast_thresholds = o2a.RadiativeTransferPerformanceThresholds.fast()
            assert fast_thresholds.fourier_order_cap == 5
            assert math.isclose(fast_thresholds.fourier_tail_reflectance_epsilon, 1.0e-11)
            assert math.isclose(fast_thresholds.threshold_doubl, 3.0e-5)
            assert math.isclose(fast_thresholds.threshold_mul, thresholds.threshold_mul)
            validation_thresholds = copy.deepcopy(thresholds)
            validation_thresholds.phase_function_truncation_threshold = 1.0e-6
            validation_fast_thresholds = validation_thresholds.with_fast_mode()
            assert validation_fast_thresholds.fourier_order_cap == fast_thresholds.fourier_order_cap
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
            fast_case = case.with_fast_mode()
            assert fast_case is not case
            assert fast_case.radiative_transfer.performance_thresholds.fourier_order_cap == 5
            assert math.isclose(
                fast_case.radiative_transfer.performance_thresholds.threshold_doubl,
                3.0e-5,
            )
            assert fast_case.instrument_response.adaptive_reference_grid["points_per_fwhm"] == 28
            assert (
                fast_case.instrument_response.adaptive_reference_grid["strong_line_min_divisions"]
                == 6
            )
            assert (
                fast_case.instrument_response.adaptive_reference_grid["strong_line_max_divisions"]
                == 22
            )
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
    assert_plot_jacobian_uses_rtm_conversion()
    assert_optimal_estimation_grid_mismatch_rejected()
    assert_optimal_estimation_result_dataclass()
    assert_final_evaluation_reuses_last_rtm_evaluation()
    assert_lazy_final_evaluator_snapshots_case()
    assert_o2a_case_aerosol_state_properties()
    assert_native_oe_loads_requested_case_into_supplied_cache()
    assert_native_oe_reuses_matching_supplied_cache()
    assert_native_oe_marshaling_bounds()
    assert_native_oe_runs_after_default_prepare()
    assert_reference_data_and_rtm_tables()
    print("python_package_refactor=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
