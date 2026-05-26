"""Smoke coverage for multi-layer aerosol-profile spectra."""

import math
from copy import deepcopy
from unittest.mock import patch

from zdisamar import rtm
from zdisamar.bindings.handles import RtmHandle
from zdisamar.inverse_method import optimal_estimation


def main() -> None:

    case = rtm.o2a_reference_case()
    assert len(case.aerosol.profile) == 1
    assert b'"profile"' not in case.to_json_bytes()

    one_layer = rtm.AerosolProfileLayer(
        top_pressure_hpa=430.0,
        bottom_pressure_hpa=510.0,
        optical_depth=0.2,
        single_scatter_albedo=0.96,
        asymmetry_factor=0.72,
        angstrom_exponent=0.4,
    )
    one_layer_case = deepcopy(case)
    one_layer_case.set_aerosol_profile((one_layer,))
    layer_view_case = deepcopy(case)
    layer_view_case.aerosol_optical_depth_550_nm = one_layer.optical_depth
    layer_view_case.aerosol.single_scatter_albedo = one_layer.single_scatter_albedo
    layer_view_case.aerosol.asymmetry_factor = one_layer.asymmetry_factor
    layer_view_case.aerosol.angstrom_exponent = one_layer.angstrom_exponent
    layer_view_case.aerosol_layer.thickness_hpa = (
        one_layer.bottom_pressure_hpa - one_layer.top_pressure_hpa
    )
    layer_view_case.aerosol_layer.mid_pressure_hpa = 0.5 * (
        one_layer.top_pressure_hpa + one_layer.bottom_pressure_hpa
    )
    assert b'"profile"' not in one_layer_case.to_json_bytes()
    assert one_layer_case.to_json_bytes() == layer_view_case.to_json_bytes()

    profile = (
        rtm.AerosolProfileLayer(
            top_pressure_hpa=430.0,
            bottom_pressure_hpa=510.0,
            optical_depth=0.18,
            single_scatter_albedo=0.96,
            asymmetry_factor=0.72,
            angstrom_exponent=0.4,
        ),
        rtm.AerosolProfileLayer(
            top_pressure_hpa=760.0,
            bottom_pressure_hpa=900.0,
            optical_depth=0.24,
            single_scatter_albedo=0.88,
            asymmetry_factor=0.55,
            angstrom_exponent=1.5,
        ),
    )

    profile_case = deepcopy(case)
    profile_case.set_aerosol_profile(profile)
    assert b'"profile"' in profile_case.to_json_bytes()

    partially_off_grid_case = deepcopy(case)
    partially_off_grid_case.set_aerosol_profile(
        (
            rtm.AerosolProfileLayer(
                top_pressure_hpa=1000.0,
                bottom_pressure_hpa=1100.0,
                optical_depth=0.05,
            ),
            rtm.AerosolProfileLayer(
                top_pressure_hpa=760.0,
                bottom_pressure_hpa=900.0,
                optical_depth=0.05,
            ),
        )
    )
    expect_spectrum_rejected(partially_off_grid_case)

    spectral_merge_case = deepcopy(case)
    spectral_merge_case.set_aerosol_profile(
        (
            rtm.AerosolProfileLayer(
                top_pressure_hpa=430.0,
                bottom_pressure_hpa=460.0,
                optical_depth=0.05,
                angstrom_exponent=0.4,
            ),
            rtm.AerosolProfileLayer(
                top_pressure_hpa=440.0,
                bottom_pressure_hpa=470.0,
                optical_depth=0.05,
                angstrom_exponent=1.5,
            ),
        )
    )
    expect_spectrum_rejected(spectral_merge_case)

    baseline = rtm.spectrum(case)
    one_layer_spectrum = rtm.spectrum(one_layer_case)
    layer_view_spectrum = rtm.spectrum(layer_view_case)
    one_layer_delta = max(
        abs(a - b)
        for a, b in zip(
            one_layer_spectrum.reflectance,
            layer_view_spectrum.reflectance,
            strict=True,
        )
    )
    assert one_layer_delta < 1.0e-12

    with rtm.SessionCache(profile_case) as cache:
        profiled = cache.spectrum()
        expect_profile_jacobian_rejected(cache)

        with patch.object(cache, "load", wraps=cache.load) as load_mock:
            cached_profiled = cache.spectrum(profile_case)

    assert len(profiled.wavelength_nm) == len(baseline.wavelength_nm)
    assert len(profiled.reflectance) == len(baseline.reflectance)
    assert len(cached_profiled.reflectance) == len(profiled.reflectance)
    assert load_mock.call_count == 0
    assert all(math.isfinite(value) for value in profiled.reflectance)
    expect_profile_oe_correction_rejected(profile_case, profiled)
    assert not hasattr(cache, "aerosol_profile_spectrum")
    assert not hasattr(rtm, "aerosol_profile_spectrum")
    max_delta = max(
        abs(a - b) for a, b in zip(profiled.reflectance, baseline.reflectance, strict=True)
    )
    assert max_delta > 1.0e-8

    try:
        optimal_estimation.retrieve(
            case=profile_case,
            measurement=optimal_estimation.Measurement((760.0,), (0.2,), signal_to_noise=100.0),
            state_vector=optimal_estimation.StateVector(
                [
                    optimal_estimation.AerosolOpticalDepth(
                        initial=0.3,
                        prior=0.3,
                        prior_uncertainty=math.sqrt(0.8),
                    )
                ]
            ),
        )
    except ValueError as error:
        assert "forward-simulation only" in str(error)
    else:
        raise AssertionError("multi-layer aerosol profile was accepted by retrieval")

    print("aerosol_profile_spectrum=ok")


def expect_spectrum_rejected(case) -> None:

    try:
        rtm.spectrum(case)
    except RuntimeError as error:
        assert "InvalidRequest" in str(error)
    else:
        raise AssertionError("invalid aerosol profile was accepted")


def expect_profile_jacobian_rejected(cache: rtm.SessionCache) -> None:

    try:
        cache.spectrum(jacobian=True, jacobian_state_names=("aerosol_optical_depth",))
    except ValueError as error:
        assert "profile Jacobians" in str(error)
    else:
        raise AssertionError("multi-layer aerosol profile Jacobian was accepted")


def expect_profile_oe_correction_rejected(case, spectrum) -> None:

    measurement = optimal_estimation.Measurement(
        spectrum.wavelength_nm[:2],
        spectrum.reflectance[:2],
        signal_to_noise=(100.0, 100.0),
    )

    with RtmHandle() as handle:
        handle.load_o2a_case(case)

        try:
            handle.optimal_estimation_correction(
                measurement=measurement,
                state_vector=optimal_estimation.StateVector(
                    [
                        optimal_estimation.AerosolOpticalDepth(
                            initial=0.3,
                            prior=0.3,
                            prior_uncertainty=math.sqrt(0.8),
                        )
                    ]
                ),
                controls=optimal_estimation.RetrievalControls(max_iterations=1),
            )
        except RuntimeError as error:
            assert "forward-simulation only" in str(error)
        else:
            raise AssertionError("multi-layer aerosol profile correction was accepted")


if __name__ == "__main__":
    main()
