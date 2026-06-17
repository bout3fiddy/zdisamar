import copy
import math
import os
import tempfile
from pathlib import Path
from typing import cast

import pytest
from rtm_scene import narrow

pytestmark = [pytest.mark.integration, pytest.mark.native]


def test_reference_data_and_rtm_tables() -> None:

    import numpy as np
    from zdisamar import rtm
    from zdisamar.wavelength_bands import o2a

    with tempfile.TemporaryDirectory() as tmpdir:
        old_cwd = Path.cwd()

        try:
            os.chdir(tmpdir)
            scene = o2a.reference_scene()
            assert "vendor/disamar-fortran" not in scene.o2_lines.line_list_asset.path
            thresholds = scene.radiative_transfer.performance_thresholds
            assert thresholds.aerosol_tangent_order_cap is None
            assert math.isclose(thresholds.fourier_tail_reflectance_epsilon, 3.0e-14)
            fast_thresholds = o2a.RadiativeTransferPerformanceThresholds.fast()
            assert fast_thresholds.fourier_order_cap == 5
            assert fast_thresholds.aerosol_tangent_order_cap == 11
            assert math.isclose(fast_thresholds.fourier_tail_reflectance_epsilon, 1.0e-11)
            assert math.isclose(fast_thresholds.threshold_doubl, 3.0e-5)
            assert math.isclose(fast_thresholds.threshold_mul, thresholds.threshold_mul)
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
            fast_scene = copy.deepcopy(scene)
            fast_scene.optimisation.fastmode.enabled = True
            assert fast_scene is not scene
            assert fast_scene.optimisation.fastmode.enabled
            assert not scene.optimisation.fastmode.enabled
            resolved_fastmode = fast_scene.optimisation.fastmode.resolved_dict(
                fast_scene.measurement_wavelengths_nm
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
            assert fast_sampling_count < len(fast_scene.measurement_wavelengths_nm)
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
            fast_scene.optimisation.fastmode.oe.fast_stage_sampling.enabled = False
            disabled_fastmode = fast_scene.optimisation.fastmode.resolved_dict(
                fast_scene.measurement_wavelengths_nm
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
            assert disabled_sampling_count == len(fast_scene.measurement_wavelengths_nm)
            assert disabled_sampling_count == len(disabled_sampling_wavelengths)
            fast_scene.optimisation.fastmode.oe.fast_stage_sampling.enabled = True
            fast_scene.optimisation.fastmode.oe.fast_stage_sampling.windows = (
                o2a.FastModeWavelengthWindow((759.7, 762.5), 10),
                o2a.FastModeWavelengthWindow((765.2, 768.0), 10),
            )
            fast_scene.optimisation.fastmode.oe.final_correction.wavelengths_nm = (
                765.2,
                766.0,
                768.0,
            )
            fast_roundtrip = o2a.Scene.from_json(fast_scene.to_json_bytes())
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
            assert b'"optimisation"' in fast_scene.to_json_bytes()
            assert b'"optimisation"' not in fast_scene.to_native_json_bytes()
            invalid_optimisation_scene = copy.deepcopy(fast_scene.to_dict())
            invalid_optimisation = cast(
                dict[str, object],
                invalid_optimisation_scene["optimisation"],
            )
            invalid_fastmode = cast(dict[str, object], invalid_optimisation["fastmode"])
            invalid_fastmode["ignored"] = True

            try:
                o2a.Scene.from_dict(invalid_optimisation_scene)
            except ValueError as exc:
                assert "unsupported fastmode fields" in str(exc)
            else:
                raise AssertionError("unsupported fastmode optimisation control was accepted")

            invalid_sampling_scene = copy.deepcopy(fast_scene.to_dict())
            invalid_sampling_optimisation = cast(
                dict[str, object],
                invalid_sampling_scene["optimisation"],
            )
            invalid_sampling_fastmode = cast(
                dict[str, object],
                invalid_sampling_optimisation["fastmode"],
            )
            invalid_sampling_oe = cast(dict[str, object], invalid_sampling_fastmode["oe"])
            invalid_sampling = cast(dict[str, object], invalid_sampling_oe["fast_stage_sampling"])
            invalid_sampling["ignored"] = True

            try:
                o2a.Scene.from_dict(invalid_sampling_scene)
            except ValueError as exc:
                assert "unsupported fastmode fast-stage sampling fields" in str(exc)
            else:
                raise AssertionError("unsupported fast-stage sampling control was accepted")

            assert fast_scene.radiative_transfer.performance_thresholds.fourier_order_cap is None
            fast_rtm_scene = fast_scene.with_rtm_optimisation_applied()
            assert fast_rtm_scene.optimisation.fastmode.enabled is False
            assert fast_rtm_scene.radiative_transfer.performance_thresholds.fourier_order_cap == 5
            assert (
                fast_rtm_scene.radiative_transfer.performance_thresholds.aerosol_tangent_order_cap
                == 11
            )
            assert math.isclose(
                fast_rtm_scene.radiative_transfer.performance_thresholds.threshold_doubl,
                3.0e-5,
            )
            fast_thresholds = fast_rtm_scene.radiative_transfer.performance_thresholds
            fast_grid = fast_rtm_scene.instrument_response.adaptive_reference_grid
            assert fast_grid["points_per_fwhm"] == 28
            assert fast_grid["strong_line_min_divisions"] == 6
            assert fast_grid["strong_line_max_divisions"] == 22
            assert (
                scene.instrument_response.adaptive_reference_grid["strong_line_max_divisions"] != 22
            )
            nominal_wavelengths = rtm.nominal_wavelengths(scene)
            assert nominal_wavelengths[0] == scene.spectral_grid.start_nm
            assert nominal_wavelengths[-1] == scene.spectral_grid.end_nm
            invalid_grid_scene = copy.deepcopy(scene)
            invalid_grid_scene.spectral_grid.sample_count = -1

            try:
                rtm.nominal_wavelengths(invalid_grid_scene)
            except ValueError as error:
                assert "sample_count" in str(error)
            else:
                raise AssertionError("negative nominal spectral sample count was accepted")

            # The config assertions above need the full band (fastmode windows reference
            # specific wavelengths). The forward/budget/plot calls below only check structure
            # and route behavior, so they run on a narrow representative copy for speed.
            forward_scene = narrow(copy.deepcopy(scene))

            mutable_scene = copy.deepcopy(forward_scene)

            with rtm.SessionCache() as cache:
                cache.load(mutable_scene)
                mutable_scene.geometry.solar_zenith_deg = 0.0
                spectrum = cache.spectrum(include_scene=True)
                assert spectrum.scene is not None
                assert spectrum.scene.geometry.solar_zenith_deg == scene.geometry.solar_zenith_deg

            budget = rtm.atmospheric_budget(forward_scene, np.array([760.76], dtype=np.float64))
            assert budget.row_count > 0
            assert len(budget.column("wavelength_nm")) == budget.row_count
            first_table = budget.table
            first_wavelength = float(first_table[0]["wavelength_nm"])
            first_table[0]["wavelength_nm"] = -1.0
            assert float(budget.column("wavelength_nm")[0]) == first_wavelength
            rows = budget.to_rows()
            assert len(rows) == budget.row_count
            assert "support_row_kind_label" in rows[0]

            spectrum = rtm.spectrum(forward_scene)
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
