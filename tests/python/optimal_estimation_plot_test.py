import json
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import cast

import numpy as np
from zdisamar.inverse_method.optimal_estimation.retrieval import Iteration, Measurement, Result
from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation
from zdisamar.plot.fields import TOTAL_OPTICAL_DEPTH, WAVELENGTH_NM
from zdisamar.plot.optimal_estimation import (
    JACOBIAN_PANEL_SPACING,
    JACOBIAN_PANEL_WIDTH,
    MEASUREMENT_FIT_HEIGHT,
    MEASUREMENT_RESIDUAL_HEIGHT,
)
from zdisamar.plot.profiles import interval_profile_rows
from zdisamar.plot.properties import PLOT
from zdisamar.plot.svg import (
    Y_AXIS_TITLE_X,
    SvgFigure,
    SvgPanel,
    SvgSeries,
)


def build_result() -> Result:

    return Result(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        state=(0.3, 900.0),
        initial_state=(0.12, 875.0),
        iterations=2,
        converged=True,
        history=(
            Iteration(
                index=1,
                state=(0.21, 888.0),
                chi2=10.0,
                chi2_reflectance=9.5,
                chi2_state_vector=0.5,
                state_vector_convergence=100.0,
                snr_normal=True,
            ),
            Iteration(
                index=2,
                state=(0.3, 900.0),
                chi2=1.0,
                chi2_reflectance=0.9,
                chi2_state_vector=0.1,
                state_vector_convergence=0.5,
                snr_normal=True,
            ),
        ),
        posterior_covariance=((1.0, 0.0), (0.0, 1.0)),
        averaging_kernel=((1.0, 0.0), (0.0, 1.0)),
        measurement=Measurement(
            wavelength_nm=(755.0, 756.0, 757.0),
            reflectance=(0.1, 0.2, 0.3),
            signal_to_noise=(100.0, 100.0, 100.0),
        ),
        final_evaluation=RtmEvaluation(
            wavelength_nm=(755.0, 756.0, 757.0),
            reflectance=(0.11, 0.19, 0.29),
            reflectance_jacobian=(
                (0.1, -1.0e-5),
                (0.2, -2.0e-5),
                (0.3, -3.0e-5),
            ),
        ),
    )


def main() -> int:

    result = build_result()

    convergence = result.plot.convergence().to_dict()
    assert convergence["title"]["text"] == "Retrieved state trajectory"
    assert convergence["type"] == "zdisamar-svg"
    assert len(convergence["panels"]) == 2
    assert convergence["resolve"]["scale"]["y"] == "independent"
    assert convergence["panels"][0]["x_ticks"] == [0.0, 1.0, 2.0]
    convergence_spec = json.dumps(convergence)
    assert "Aerosol optical depth" in convergence_spec
    assert "Layer mid-pressure (hPa)" in convergence_spec
    assert '"line"' in convergence_spec
    assert '"points"' in convergence_spec
    assert convergence["panels"][0]["show_legend"] is False
    assert convergence["panels"][1]["show_legend"] is False
    assert "x1e2" not in convergence_spec
    assert "9e+2" not in convergence_spec

    fit_chart = result.plot.measurement_fit()
    fit = fit_chart.to_dict()
    fit_spec = json.dumps(fit)
    assert fit["title"]["text"] == "Measurement fit"
    assert len(fit["panels"]) == 2
    assert fit["panels"][0]["series"][0]["name"] == "Fit"
    assert fit["panels"][0]["series"][0]["show_legend"] is True
    assert "Retrieved model" not in fit_spec
    assert '"points"' in fit_spec
    assert "Residual" in fit_spec
    assert "residual_scaled" not in fit_spec
    assert fit["panels"][1]["width"] == PLOT.diagnostic_width
    assert fit["panels"][1]["height"] == MEASUREMENT_RESIDUAL_HEIGHT
    assert fit["panels"][0]["show_x_axis"] is False
    assert fit["panels"][1]["show_x_axis"] is True
    assert fit["panels"][0]["show_title"] is False
    assert fit["panels"][1]["show_title"] is False
    assert fit["panels"][0]["show_legend"] is True
    assert fit["panels"][1]["show_legend"] is False
    assert fit["height"] < 900
    assert (
        fit["height"]
        == fit["panels"][1]["origin"][1] + MEASUREMENT_RESIDUAL_HEIGHT + fit_chart.margin_bottom
    )
    assert fit["panels"][1]["marker_x"] == []
    fit_residual_domain = fit["panels"][1]["y_domain"]
    assert fit_residual_domain[0] <= 0.0 <= fit_residual_domain[1]
    assert fit["panels"][1]["origin"][1] == (
        fit["panels"][0]["origin"][1] + MEASUREMENT_FIT_HEIGHT + fit_chart.row_spacing_after(0)
    )
    assert fit["panels"][0]["origin"][0] + Y_AXIS_TITLE_X >= 40

    residual = result.plot.residual().to_dict()
    residual_spec = json.dumps(residual)
    assert residual["title"]["text"] == "Final residual"
    assert "residual_scaled" not in residual_spec
    assert residual["panels"][0]["marker_x"] == []
    assert residual["panels"][0]["show_legend"] is False
    residual_domain = residual["panels"][0]["y_domain"]
    assert residual_domain[0] <= 0.0 <= residual_domain[1]

    jacobian = result.plot.jacobian().to_dict()
    jacobian_spec = json.dumps(jacobian)
    assert jacobian["title"]["text"] == "Final reflectance Jacobians"
    assert len(jacobian["panels"]) == 2
    assert jacobian["resolve"]["scale"]["y"] == "independent"
    assert jacobian["panels"][0]["width"] == JACOBIAN_PANEL_WIDTH
    assert jacobian["panels"][1]["width"] == JACOBIAN_PANEL_WIDTH
    assert jacobian["panels"][1]["origin"][0] == (
        jacobian["panels"][0]["origin"][0] + JACOBIAN_PANEL_WIDTH + JACOBIAN_PANEL_SPACING
    )
    assert jacobian["panels"][0]["marker_x"] == []
    assert jacobian["panels"][1]["marker_x"] == []
    assert jacobian["panels"][0]["show_legend"] is False
    assert jacobian["panels"][1]["show_legend"] is False
    assert "reflectance_jacobian_scaled" not in jacobian_spec
    assert "Jacobian x" not in jacobian_spec
    assert "x1e-5" in jacobian_spec
    assert "Reflectance jacobian" not in jacobian_spec
    assert "dR/d\\u03c4" in jacobian_spec
    assert "dR/dp (hPa\\u207b\\u00b9)" in jacobian_spec

    tiny_panel = SvgPanel(
        title="Tiny",
        x_title="x",
        y_title="Tiny",
        series=(SvgSeries.line("tiny", [0.0, 1.0], [1.0e-5, 2.0e-5]),),
    )
    tiny = SvgFigure(title="Tiny", panels=(tiny_panel,))
    tiny_spec = tiny.to_dict()
    tiny_panels = cast(list[dict[str, object]], tiny_spec["panels"])
    assert "labelExpr" not in json.dumps(tiny_spec)
    assert tiny_panels[0]["axis_multiplier"] is None
    assert "x1e-5" not in tiny._repr_svg_()

    flat_tiny = SvgFigure(
        title="Flat tiny",
        panels=(
            SvgPanel(
                title="Flat tiny",
                x_title="x",
                y_title="Tiny",
                series=(SvgSeries.line("tiny", [0.0, 1.0], [1.0e-5, 1.0e-5]),),
            ),
        ),
    )
    flat_tiny_panels = cast(list[dict[str, object]], flat_tiny.to_dict()["panels"])
    flat_tiny_domain = cast(list[float], flat_tiny_panels[0]["y_domain"])
    assert flat_tiny_domain[0] > 0.0
    assert flat_tiny_domain[1] < 2.0e-5

    with TemporaryDirectory() as directory:
        fit_path = Path(directory) / "measurement-fit.svg"
        residual_path = Path(directory) / "residual.svg"
        jacobian_path = Path(directory) / "jacobian.svg"
        result.plot.measurement_fit().save(fit_path)
        result.plot.residual().save(residual_path)
        result.plot.jacobian().save(jacobian_path)
        fit_svg = fit_path.read_text()
        residual_svg = residual_path.read_text()
        jacobian_svg = jacobian_path.read_text()

    assert f".grid {{ stroke: {PLOT.colors['grid']};" in jacobian_svg
    assert f"stroke-opacity: {PLOT.grid_opacity}" in jacobian_svg
    assert f".axis-title {{ font-size: {PLOT.axis_title_font_size}px;" in jacobian_svg
    assert 'class="figure-bg"' in jacobian_svg
    assert fit_svg.count('class="legend"') == 1
    assert "Fit</text>" in fit_svg
    assert "Measurement</text>" in fit_svg
    assert 'class="legend"' not in residual_svg
    assert 'class="legend"' not in jacobian_svg

    missing_samples_plot = SvgFigure(
        title="Missing samples",
        panels=(
            SvgPanel(
                title="Missing samples",
                x_title="x",
                y_title="y",
                series=(
                    SvgSeries.band(
                        "band",
                        [0.0, 1.0, 2.0, 3.0],
                        [-0.1, -0.2, np.nan, -0.3],
                        [0.1, 0.2, np.inf, 0.3],
                    ),
                    SvgSeries.line("line", [0.0, 1.0, 2.0, 3.0], [0.0, np.nan, 1.0, 2.0]),
                    SvgSeries.points("points", [0.0, 1.0, 2.0], [0.0, np.inf, 1.0]),
                ),
            ),
        ),
    )

    with TemporaryDirectory() as directory:
        missing_samples_path = Path(directory) / "missing-samples.svg"
        missing_samples_plot.save(missing_samples_path)
        missing_samples = missing_samples_path.read_text()

    assert "nan" not in missing_samples.lower()
    assert "inf" not in missing_samples.lower()
    assert 'd="M0.000' in missing_samples
    assert " M" in missing_samples

    empty_plot = SvgFigure(title="Empty figure", panels=())
    empty_spec = empty_plot.to_dict()
    assert empty_spec["panels"] == []
    assert empty_plot.width > 0
    assert empty_plot.height > 0

    with TemporaryDirectory() as directory:
        empty_path = Path(directory) / "empty.svg"
        empty_plot.save(empty_path)
        assert "<svg" in empty_path.read_text()

    empty_profile = interval_profile_rows(
        [
            {
                WAVELENGTH_NM: 760.76,
                "altitude_km": np.nan,
                "top_altitude_km": 1.0,
                "bottom_altitude_km": 0.0,
                TOTAL_OPTICAL_DEPTH: 1.0,
            }
        ],
        value=TOTAL_OPTICAL_DEPTH,
        vertical_axis="altitude_km",
    )
    assert empty_profile == []

    print("optimal_estimation_plot=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
