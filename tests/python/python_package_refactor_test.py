import copy
import importlib.util
import math
import os
import sys
import tempfile
from dataclasses import fields, replace
from pathlib import Path
from typing import cast


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
        frame[field].to_numpy(dtype=float),
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

    import numpy as np
    from zdisamar.inverse_method.optimal_estimation.retrieval import Result
    from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation

    first = cast(RtmEvaluation, object())
    second = cast(RtmEvaluation, object())
    result = Result(
        state_names=(),
        state=np.array([], dtype=np.float64),
        iterations=0,
        converged=True,
        history=(),
        posterior_covariance=np.empty((0, 0), dtype=np.float64),
        averaging_kernel=np.empty((0, 0), dtype=np.float64),
        final_evaluation=first,
    )
    assert result.final_evaluation is first
    assert replace(result, final_evaluation=second).final_evaluation is second
    assert replace(result, final_evaluation=None).final_evaluation is None
    assert "final_evaluation" in {field.name for field in fields(result)}


def assert_final_evaluation_reuses_last_rtm_evaluation() -> None:

    import numpy as np
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.retrieval import Result
    from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation

    sentinel = cast(RtmEvaluation, object())
    calls = 0
    result = Result(
        state_names=("aerosol_optical_depth",),
        state=np.array([1.0], dtype=np.float64),
        iterations=1,
        converged=True,
        history=(),
        posterior_covariance=np.eye(1, dtype=np.float64),
        averaging_kernel=np.eye(1, dtype=np.float64),
        last_evaluated_state=np.array([1.0], dtype=np.float64),
        last_evaluation=sentinel,
    )

    def evaluate_state(_state):

        nonlocal calls
        calls += 1

        return cast(RtmEvaluation, object())

    attached = o2a_oe.attach_final_evaluation(result, evaluate_state)
    assert attached.final_evaluation is sentinel
    assert calls == 0


def assert_reference_data_and_rtm_tables() -> None:

    import numpy as np
    from zdisamar import rtm
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
            mutable_case = copy.deepcopy(case)

            with rtm.SessionCache() as cache:
                cache.load(mutable_case)
                mutable_case.geometry.solar_zenith_deg = 0.0
                spectrum = cache.spectrum()
                assert spectrum.case is not None
                assert spectrum.case.geometry.solar_zenith_deg == case.geometry.solar_zenith_deg

            budget = rtm.atmospheric_budget(case, np.array([760.76], dtype=np.float64))
            assert budget.row_count > 0
            assert budget.column("wavelength_nm").size == budget.row_count
            first_table = budget.table
            first_wavelength = float(first_table["wavelength_nm"][0])
            first_table["wavelength_nm"][0] = -1.0
            assert float(budget.column("wavelength_nm")[0]) == first_wavelength
            rows = budget.to_rows()
            assert len(rows) == budget.row_count
            assert "support_row_kind_label" in rows[0]

            spectrum = rtm.spectrum(case)
            output = Path(tmpdir) / "reflectance"
            chart = spectrum.plot.reflectance(save=output)
            assert chart is not None
            assert output.with_suffix(".png").exists()
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
    assert_reference_data_and_rtm_tables()
    print("python_package_refactor=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
