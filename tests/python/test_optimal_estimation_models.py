import copy
import math
from dataclasses import fields, replace
from typing import cast
from unittest.mock import patch


def test_optimal_estimation_grid_mismatch_rejected() -> None:

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


def test_optimal_estimation_result_dataclass() -> None:

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


def test_final_evaluation_reuses_last_rtm_evaluation() -> None:

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


def test_lazy_final_evaluator_snapshots_scene() -> None:

    from zdisamar.inverse_method import optimal_estimation
    from zdisamar.inverse_method.optimal_estimation import o2a as o2a_oe
    from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation
    from zdisamar.wavelength_bands import o2a

    sentinel = cast(RtmEvaluation, object())
    observed_solar_zenith: list[float] = []
    scene = o2a.reference_scene()
    original_solar_zenith = scene.geometry.solar_zenith_deg

    def fake_evaluate_state(template, _state, _state_vector):

        observed_solar_zenith.append(template.geometry.solar_zenith_deg)

        return sentinel

    with patch.object(o2a_oe, "evaluate_state", fake_evaluate_state):
        evaluator = o2a_oe._lazy_final_evaluator(  # noqa: SLF001
            scene,
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
        scene.geometry.solar_zenith_deg = 0.0

        assert evaluator([1.0]) is sentinel

    assert observed_solar_zenith == [original_solar_zenith]


def test_state_vector_uncertainty_rejected() -> None:

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


def test_measurement_accepts_scientific_numeric_scalars() -> None:

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


def test_scene_aerosol_state_properties() -> None:

    from zdisamar.wavelength_bands import o2a

    scene = o2a.reference_scene()
    serialized_aerosol = scene.aerosol.to_dict()
    assert "layer_center_km" not in serialized_aerosol
    assert "layer_width_km" not in serialized_aerosol

    native_scene = copy.deepcopy(scene.to_native_dict())
    native_intervals = cast(list[dict[str, object]], native_scene["intervals"])
    native_intervals[0]["top_altitude_km"] = None
    native_intervals[0]["bottom_altitude_km"] = None
    native_intervals[0]["top_pressure_variance_hpa2"] = None
    native_intervals[0]["bottom_pressure_variance_hpa2"] = None
    native_aerosol = cast(dict[str, object], native_scene["aerosol"])
    native_placement = cast(dict[str, object], native_aerosol["placement"])
    native_placement["top_altitude_km"] = None
    native_placement["bottom_altitude_km"] = None

    null_placeholder_scene = o2a.Scene.from_dict(native_scene)
    assert math.isnan(null_placeholder_scene.atmosphere.intervals[0].top_altitude_km)
    assert math.isnan(null_placeholder_scene.atmosphere.intervals[0].bottom_altitude_km)
    assert null_placeholder_scene.atmosphere.intervals[0].top_pressure_variance_hpa2 == 0.0
    assert null_placeholder_scene.atmosphere.intervals[0].bottom_pressure_variance_hpa2 == 0.0
    assert math.isnan(null_placeholder_scene.aerosol.placement.top_altitude_km)
    assert math.isnan(null_placeholder_scene.aerosol.placement.bottom_altitude_km)

    scene.aerosol_optical_depth_550_nm = 0.31
    scene.aerosol_layer.thickness_hpa = 50.0
    scene.aerosol_layer.mid_pressure_hpa = 900.0

    assert scene.aerosol.optical_depth_550_nm == 0.31
    assert scene.aerosol_layer.thickness_hpa == 50.0
    assert scene.aerosol_layer.mid_pressure_hpa == 900.0
    assert scene.aerosol.placement.top_pressure_hpa == 875.0
    assert scene.aerosol.placement.bottom_pressure_hpa == 925.0
    assert scene.atmosphere.intervals[0].bottom_pressure_hpa == 875.0
    assert scene.atmosphere.intervals[1].top_pressure_hpa == 875.0
    assert scene.atmosphere.intervals[1].bottom_pressure_hpa == 925.0
    assert scene.atmosphere.intervals[2].top_pressure_hpa == 925.0

    legacy = copy.deepcopy(serialized_aerosol)
    legacy["layer_center_km"] = 5.4

    try:
        o2a.Aerosol.from_dict(legacy)
    except ValueError as error:
        assert "unsupported aerosol placement fields" in str(error)
    else:
        raise AssertionError("legacy aerosol placement fields were accepted")

    invalid_scene = copy.deepcopy(scene)
    invalid_scene.aerosol.placement.semantics = "altitude_center_width_approximation"

    try:
        invalid_scene.aerosol_layer.mid_pressure_hpa = 900.0
    except ValueError as error:
        assert "explicit interval bounds" in str(error)
    else:
        raise AssertionError("pressure setter accepted altitude placement semantics")

    invalid_scene = copy.deepcopy(scene)

    try:
        invalid_scene.aerosol_layer.mid_pressure_hpa = math.nan
    except ValueError as error:
        assert "finite" in str(error)
    else:
        raise AssertionError("pressure setter accepted non-finite pressure")

    invalid_scene = copy.deepcopy(scene)
    original_top_pressure_hpa = invalid_scene.aerosol.placement.top_pressure_hpa
    original_bottom_pressure_hpa = invalid_scene.aerosol.placement.bottom_pressure_hpa

    try:
        invalid_scene.aerosol_layer.thickness_hpa = 650.0
    except ValueError as error:
        assert "atmosphere ordering" in str(error)
    else:
        raise AssertionError("pressure setter accepted inverted neighboring intervals")

    assert invalid_scene.aerosol.placement.top_pressure_hpa == original_top_pressure_hpa
    assert invalid_scene.aerosol.placement.bottom_pressure_hpa == original_bottom_pressure_hpa


def test_deprecated_python_input_fields_rejected() -> None:

    from zdisamar.wavelength_bands import o2a

    scene = o2a.reference_scene()

    observation = copy.deepcopy(scene.instrument_response.to_dict())
    observation["noise_model"] = {"enabled": True}

    try:
        o2a.InstrumentResponse.from_dict(observation)
    except ValueError as error:
        assert "unsupported observation fields" in str(error)
    else:
        raise AssertionError("deprecated observation noise_model field was accepted")

    radiative_transfer = copy.deepcopy(scene.radiative_transfer.to_dict())
    radiative_transfer["use_adding"] = True
    radiative_transfer["stokes_dimension"] = 1

    try:
        o2a.RadiativeTransferControls.from_dict(radiative_transfer)
    except ValueError as error:
        assert "unsupported radiative-transfer fields" in str(error)
    else:
        raise AssertionError("deprecated radiative-transfer fields were accepted")
