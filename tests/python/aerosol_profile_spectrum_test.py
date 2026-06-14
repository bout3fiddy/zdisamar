"""Smoke coverage for multi-layer aerosol-profile spectra."""

import math
from copy import deepcopy
from unittest.mock import patch

from zdisamar import rtm
from zdisamar.bindings.handles import RtmHandle
from zdisamar.inverse_method import optimal_estimation


def main() -> None:

    scene = rtm.reference_scene()
    assert len(scene.aerosol.profile) == 1
    assert b'"profile"' not in scene.to_json_bytes()

    one_layer = rtm.AerosolProfileLayer(
        top_pressure_hpa=430.0,
        bottom_pressure_hpa=510.0,
        optical_depth=0.2,
        single_scatter_albedo=0.96,
        asymmetry_factor=0.72,
        angstrom_exponent=0.4,
    )
    one_layer_scene = deepcopy(scene)
    one_layer_scene.set_aerosol_profile((one_layer,))
    layer_view_scene = deepcopy(scene)
    layer_view_scene.aerosol_optical_depth_550_nm = one_layer.optical_depth
    layer_view_scene.aerosol.single_scatter_albedo = one_layer.single_scatter_albedo
    layer_view_scene.aerosol.asymmetry_factor = one_layer.asymmetry_factor
    layer_view_scene.aerosol.angstrom_exponent = one_layer.angstrom_exponent
    layer_view_scene.aerosol_layer.thickness_hpa = (
        one_layer.bottom_pressure_hpa - one_layer.top_pressure_hpa
    )
    layer_view_scene.aerosol_layer.mid_pressure_hpa = 0.5 * (
        one_layer.top_pressure_hpa + one_layer.bottom_pressure_hpa
    )
    assert b'"profile"' not in one_layer_scene.to_json_bytes()
    assert one_layer_scene.to_json_bytes() == layer_view_scene.to_json_bytes()

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

    profile_scene = deepcopy(scene)
    profile_scene.set_aerosol_profile(profile)
    assert b'"profile"' in profile_scene.to_json_bytes()

    partially_off_grid_scene = deepcopy(scene)
    partially_off_grid_scene.set_aerosol_profile(
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
    expect_spectrum_rejected(partially_off_grid_scene)

    spectral_merge_scene = deepcopy(scene)
    spectral_merge_scene.set_aerosol_profile(
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
    expect_spectrum_rejected(spectral_merge_scene)

    baseline = rtm.spectrum(scene)
    one_layer_spectrum = rtm.spectrum(one_layer_scene)
    layer_view_spectrum = rtm.spectrum(layer_view_scene)
    one_layer_delta = max(
        abs(a - b)
        for a, b in zip(
            one_layer_spectrum.reflectance,
            layer_view_spectrum.reflectance,
            strict=True,
        )
    )
    assert one_layer_delta < 1.0e-12

    with rtm.SessionCache(profile_scene) as cache:
        profiled = cache.spectrum()
        expect_profile_jacobian_rejected(cache)

        with patch.object(cache, "load", wraps=cache.load) as load_mock:
            cached_profiled = cache.spectrum(profile_scene)

    assert len(profiled.wavelength_nm) == len(baseline.wavelength_nm)
    assert len(profiled.reflectance) == len(baseline.reflectance)
    assert len(cached_profiled.reflectance) == len(profiled.reflectance)
    assert load_mock.call_count == 0
    assert all(math.isfinite(value) for value in profiled.reflectance)
    expect_profile_oe_correction_rejected(profile_scene, profiled)
    assert not hasattr(cache, "aerosol_profile_spectrum")
    assert not hasattr(rtm, "aerosol_profile_spectrum")
    max_delta = max(
        abs(a - b) for a, b in zip(profiled.reflectance, baseline.reflectance, strict=True)
    )
    assert max_delta > 1.0e-8

    try:
        optimal_estimation.retrieve(
            scene=profile_scene,
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


def expect_spectrum_rejected(scene) -> None:

    try:
        rtm.spectrum(scene)
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


def expect_profile_oe_correction_rejected(scene, spectrum) -> None:

    measurement = optimal_estimation.Measurement(
        spectrum.wavelength_nm[:2],
        spectrum.reflectance[:2],
        signal_to_noise=(100.0, 100.0),
    )

    with RtmHandle() as handle:
        handle.load_scene(scene)

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
