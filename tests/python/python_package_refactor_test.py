import copy
import importlib.util
import math
import os
import sys
import tempfile
from dataclasses import replace
from pathlib import Path
from typing import Any, cast


def assert_import_laziness() -> None:

    import zdisamar as zd

    assert "numpy" not in sys.modules
    assert "pandas" not in sys.modules
    assert "altair" not in sys.modules
    assert "inverse_method" not in zd.__all__
    assert "DiagnosticTable" not in zd.__all__
    assert "O2LineDiagnostics" not in zd.__all__
    assert "PerturbationDiagnostics" not in zd.__all__
    assert "RadiativeTransferDiagnosticTable" not in zd.__all__

    import zdisamar.api as api

    assert "O2LineContributions" not in api.__all__
    assert "O2LineDiagnostics" not in api.__all__
    assert "RadiativeTransferDiagnosticTable" not in api.__all__


def assert_plot_package_boundary() -> None:

    assert importlib.util.find_spec("zdisamar.plot") is not None
    assert "zdisamar.plot" not in sys.modules

    from zdisamar.plot.properties import PLOT

    assert PLOT.width == 1311
    assert PLOT.height == 465
    assert PLOT.markers_nm == (755.0, 760.76, 776.0)
    assert "blue" in PLOT.colors


def assert_quantity_conversions() -> None:

    import numpy as np
    from zdisamar.quantities import (
        reflectance_from_radiance,
        reflectance_jacobian_from_radiance_jacobian,
        reflectance_noise_from_sun_normalized_radiance_noise,
        solar_mu0_from_zenith_deg,
        sun_normalized_radiance,
    )

    mu0 = solar_mu0_from_zenith_deg(60.0)
    radiance = np.array([2.0, 3.0], dtype=np.float64)
    irradiance = np.array([10.0, 12.0], dtype=np.float64)
    assert np.allclose(sun_normalized_radiance(radiance, irradiance), radiance / irradiance)
    assert np.allclose(
        reflectance_from_radiance(radiance, irradiance, mu0),
        radiance * math.pi / (mu0 * irradiance),
    )

    radiance_jacobian = np.array([[0.2, 0.4], [0.3, 0.6]], dtype=np.float64)
    expected = radiance_jacobian / ((mu0 * irradiance / math.pi)[:, None])
    assert np.allclose(
        reflectance_jacobian_from_radiance_jacobian(radiance_jacobian, irradiance, mu0),
        expected,
    )
    assert np.allclose(
        reflectance_noise_from_sun_normalized_radiance_noise(np.array([1.0]), mu0),
        np.array([math.pi / mu0]),
    )


def assert_plot_jacobian_uses_shared_conversion() -> None:

    import numpy as np
    from zdisamar.plot.jacobian import jacobian_frame
    from zdisamar.quantities import reflectance_jacobian_from_radiance_jacobian

    class Spectrum:
        jacobian_state_names = ("aerosol_optical_depth",)
        wavelength_nm = np.array([755.0, 760.0], dtype=np.float64)
        irradiance = np.array([10.0, 12.0], dtype=np.float64)
        radiance_jacobian = np.array([[0.2], [0.3]], dtype=np.float64)

        def reflectance_jacobian(self, state: str):

            assert state == "aerosol_optical_depth"

            return reflectance_jacobian_from_radiance_jacobian(
                self.radiance_jacobian[:, 0],
                self.irradiance,
                0.5,
            )

    frame, field, _title = jacobian_frame(Spectrum(), "aerosol_optical_depth")
    assert field == "reflectance_jacobian"
    assert np.allclose(
        frame[field].to_numpy(dtype=float),
        reflectance_jacobian_from_radiance_jacobian(
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


def assert_lazy_final_evaluation_preserves_session_library_path() -> None:

    import numpy as np
    from zdisamar.forward_model.prepared import O2AForwardSession
    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_module
    from zdisamar.inverse_method.optimal_estimation.forward_evaluation import ForwardEvaluation
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector

    custom_library_path = Path("/tmp/custom/libzdisamar.dylib")
    sentinel = cast(ForwardEvaluation, object())
    calls: list[object] = []

    class SuppliedSession:
        @property
        def library_path(self) -> Path:

            return custom_library_path

    class FreshSession:
        @property
        def library_path(self) -> Path:

            return custom_library_path

        def __enter__(self):

            return self

        def __exit__(self, *_exc: object) -> None:

            return None

    def fake_o2a_forward_session(_template: object, library_path: object = None) -> FreshSession:

        calls.append(library_path)

        return FreshSession()

    def fake_evaluate(
        self: Any,
        state: np.ndarray,
        state_vector: StateVector,
    ) -> ForwardEvaluation:

        _ = (state, state_vector)
        assert self._library_path == custom_library_path
        assert self._forward_session is not None

        return sentinel

    original_session = o2a_module.o2a_forward_session
    original_evaluate = o2a_module.O2AInverseForwardModel.evaluate

    try:
        cast(Any, o2a_module).o2a_forward_session = fake_o2a_forward_session
        cast(Any, o2a_module.O2AInverseForwardModel).evaluate = fake_evaluate
        model = o2a_module.O2AInverseForwardModel(
            template=cast(O2AInput, {}),
            forward_session=cast(O2AForwardSession, SuppliedSession()),
        )
        evaluator = o2a_module._lazy_final_evaluator(model, cast(StateVector, object()))
        assert evaluator(np.array([1.0])) is sentinel
        assert calls == [custom_library_path]
    finally:
        cast(Any, o2a_module).o2a_forward_session = original_session
        cast(Any, o2a_module.O2AInverseForwardModel).evaluate = original_evaluate


def assert_optimal_estimation_result_compatibility() -> None:

    from dataclasses import fields

    import numpy as np
    from zdisamar.inverse_method.optimal_estimation.forward_evaluation import ForwardEvaluation
    from zdisamar.inverse_method.optimal_estimation.retrieval import Result

    first = cast(ForwardEvaluation, object())
    second = cast(ForwardEvaluation, object())
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

    positional = Result(
        (),
        np.array([], dtype=np.float64),
        0,
        True,
        (),
        np.empty((0, 0), dtype=np.float64),
        np.empty((0, 0), dtype=np.float64),
        (),
        None,
        first,
    )
    assert positional.final_evaluation is first


def assert_session_library_path_mismatch_rejected() -> None:

    from zdisamar.forward_model.prepared import O2AForwardSession
    from zdisamar.input.wavelength_band.o2a import O2AInput
    from zdisamar.inverse_method.optimal_estimation import O2AInverseForwardModel

    class SuppliedSession:
        @property
        def library_path(self) -> Path:

            return Path("/tmp/custom/libzdisamar-a.dylib")

    class DefaultLibrarySession:
        @property
        def library_path(self) -> None:

            return None

    try:
        O2AInverseForwardModel(
            template=cast(O2AInput, {}),
            library_path=Path("/tmp/custom/libzdisamar-b.dylib"),
            forward_session=cast(O2AForwardSession, SuppliedSession()),
        )
    except ValueError:
        pass
    else:
        raise AssertionError("mismatched forward_session and library_path were accepted")

    try:
        O2AInverseForwardModel(
            template=cast(O2AInput, {}),
            library_path=Path("/tmp/custom/libzdisamar-b.dylib"),
            forward_session=cast(O2AForwardSession, DefaultLibrarySession()),
        )
    except ValueError:
        return

    raise AssertionError("explicit library_path with default-library session was accepted")


def assert_subclass_final_evaluation_is_preserved_eagerly() -> None:

    import numpy as np
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_module
    from zdisamar.inverse_method.optimal_estimation.forward_evaluation import ForwardEvaluation
    from zdisamar.inverse_method.optimal_estimation.retrieval import Result
    from zdisamar.inverse_method.optimal_estimation.state_vector import StateVector

    sentinel = cast(ForwardEvaluation, object())
    calls = 0

    class CustomModel:
        def evaluate(self, state: np.ndarray, state_vector: StateVector) -> ForwardEvaluation:

            nonlocal calls
            _ = (state, state_vector)
            calls += 1

            return sentinel

    def fake_retrieve(*_args: object, **_kwargs: object) -> Result:

        return Result(
            state_names=(),
            state=np.array([1.0], dtype=np.float64),
            iterations=0,
            converged=True,
            history=(),
            posterior_covariance=np.empty((0, 0), dtype=np.float64),
            averaging_kernel=np.empty((0, 0), dtype=np.float64),
        )

    original_retrieve = o2a_module.retrieve

    try:
        cast(Any, o2a_module).retrieve = fake_retrieve
        result = o2a_module._disamar_oe(
            inverse_model=cast(o2a_module.O2AInverseForwardModel, CustomModel()),
            measurement=cast(Any, object()),
            state_vector=cast(StateVector, object()),
        )
        assert result.final_evaluation is sentinel
        assert calls == 1
    finally:
        cast(Any, o2a_module).retrieve = original_retrieve


def assert_reference_data_and_native_table() -> None:

    import numpy as np
    import zdisamar as zd

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = Path.cwd()

        try:
            os.chdir(tmpdir)
            case = zd.o2a_disamar_reference_input()
            assert "vendor/disamar-fortran" not in case.o2_lines.line_list_asset.path
            thresholds = case.radiative_transfer.performance_thresholds
            assert math.isclose(thresholds.fourier_tail_reflectance_epsilon, 3.0e-14)
            fast_thresholds = zd.RadiativeTransferPerformanceThresholds.fast()
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

            with zd.o2a_forward_session() as session:
                session.prepare(mutable_case)
                mutable_case.geometry.solar_zenith_deg = 0.0

                with session.forward_model() as spectrum:
                    assert spectrum.input is not None
                    assert (
                        spectrum.input.geometry.solar_zenith_deg == case.geometry.solar_zenith_deg
                    )

            with (
                zd.prepare(case) as prepared,
                prepared.atmosphere.budget(np.array([760.76], dtype=np.float64)) as budget,
            ):
                assert not hasattr(prepared, "o2_lines")
                assert not hasattr(prepared, "radiative_transfer")
                assert not hasattr(prepared, "perturbations")
                assert budget.row_count > 0
                assert budget.column("wavelength_nm").size == budget.row_count
                first_table = budget.table
                first_wavelength = float(first_table["wavelength_nm"][0])
                first_table["wavelength_nm"][0] = -1.0
                assert float(budget.column("wavelength_nm")[0]) == first_wavelength
                rows = budget.to_rows()
                assert len(rows) == budget.row_count
                assert "support_row_kind_label" in rows[0]

                with prepared.forward_model() as spectrum:
                    output = Path(tmpdir) / "reflectance"
                    chart = spectrum.plot.reflectance(save=output)
                    assert chart is not None
                    assert output.with_suffix(".png").exists()
        finally:
            os.chdir(old_cwd)


def main() -> int:

    assert_import_laziness()
    assert_plot_package_boundary()
    assert_quantity_conversions()
    assert_plot_jacobian_uses_shared_conversion()
    assert_optimal_estimation_grid_mismatch_rejected()
    assert_lazy_final_evaluation_preserves_session_library_path()
    assert_optimal_estimation_result_compatibility()
    assert_session_library_path_mismatch_rejected()
    assert_subclass_final_evaluation_is_preserved_eagerly()
    assert_reference_data_and_native_table()
    print("python_package_refactor=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
