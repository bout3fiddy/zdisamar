import json
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
from zdisamar.inverse_method.optimal_estimation.retrieval import Iteration, Measurement, Result
from zdisamar.inverse_method.optimal_estimation.rtm_evaluation import RtmEvaluation
from zdisamar.plot.axes import finite_padded_scale, scaled_y
from zdisamar.plot.optimal_estimation import MEASUREMENT_RESIDUAL_HEIGHT
from zdisamar.plot.properties import PLOT
from zdisamar.plot.svg import SvgFigure, SvgPanel, SvgSeries


def build_result() -> Result:

    return Result(
        state_names=("aerosol_optical_depth", "aerosol_layer_mid_pressure_hpa"),
        state=np.array([0.3, 900.0], dtype=np.float64),
        initial_state=np.array([0.12, 875.0], dtype=np.float64),
        iterations=2,
        converged=True,
        history=(
            Iteration(
                index=1,
                state=np.array([0.21, 888.0], dtype=np.float64),
                chi2=10.0,
                chi2_reflectance=9.5,
                chi2_state_vector=0.5,
                state_vector_convergence=100.0,
                snr_normal=True,
            ),
            Iteration(
                index=2,
                state=np.array([0.3, 900.0], dtype=np.float64),
                chi2=1.0,
                chi2_reflectance=0.9,
                chi2_state_vector=0.1,
                state_vector_convergence=0.5,
                snr_normal=True,
            ),
        ),
        posterior_covariance=np.eye(2, dtype=np.float64),
        averaging_kernel=np.eye(2, dtype=np.float64),
        measurement=Measurement(
            wavelength_nm=np.array([755.0, 756.0, 757.0], dtype=np.float64),
            reflectance=np.array([0.1, 0.2, 0.3], dtype=np.float64),
            variance=np.ones(3, dtype=np.float64),
        ),
        final_evaluation=RtmEvaluation(
            wavelength_nm=np.array([755.0, 756.0, 757.0], dtype=np.float64),
            reflectance=np.array([0.11, 0.19, 0.29], dtype=np.float64),
            reflectance_jacobian=np.array(
                [[0.1, -1.0e-5], [0.2, -2.0e-5], [0.3, -3.0e-5]],
                dtype=np.float64,
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
    assert "x1e2" not in convergence_spec
    assert "9e+2" not in convergence_spec

    fit = result.plot.measurement_fit().to_dict()
    fit_spec = json.dumps(fit)
    assert fit["title"]["text"] == "Measurement fit"
    assert len(fit["panels"]) == 2
    assert '"points"' in fit_spec
    assert "Residual" in fit_spec
    assert "residual_scaled" not in fit_spec
    assert fit["panels"][1]["width"] == PLOT.diagnostic_width
    assert fit["panels"][1]["height"] == MEASUREMENT_RESIDUAL_HEIGHT
    fit_residual_domain = fit["panels"][1]["y_domain"]
    assert fit_residual_domain[0] <= 0.0 <= fit_residual_domain[1]

    residual = result.plot.residual().to_dict()
    residual_spec = json.dumps(residual)
    assert residual["title"]["text"] == "Final residual"
    assert "residual_scaled" not in residual_spec
    residual_domain = residual["panels"][0]["y_domain"]
    assert residual_domain[0] <= 0.0 <= residual_domain[1]

    jacobian = result.plot.jacobian().to_dict()
    jacobian_spec = json.dumps(jacobian)
    assert jacobian["title"]["text"] == "Final reflectance Jacobians"
    assert len(jacobian["panels"]) == 2
    assert jacobian["resolve"]["scale"]["y"] == "independent"
    assert "reflectance_jacobian_scaled" not in jacobian_spec
    assert "Jacobian x" not in jacobian_spec
    assert "x1e-5" in jacobian_spec
    assert "Reflectance jacobian" not in jacobian_spec
    assert "dR/d\\u03c4" in jacobian_spec
    assert "dR/dp (hPa\\u207b\\u00b9)" in jacobian_spec

    _, _, plain_tiny_y = scaled_y({"tiny": [1.0e-5, 2.0e-5]}, "tiny", "Tiny")
    assert "labelExpr" not in json.dumps(plain_tiny_y.to_dict())

    flat_tiny_domain = finite_padded_scale([1.0e-5, 1.0e-5]).to_dict()["domain"]
    assert flat_tiny_domain[0] > 0.0
    assert flat_tiny_domain[1] < 2.0e-5

    with TemporaryDirectory() as directory:
        jacobian_path = Path(directory) / "jacobian.svg"
        result.plot.jacobian().save(jacobian_path)
        jacobian_svg = jacobian_path.read_text()

    assert f".grid {{ stroke: {PLOT.colors['grid']};" in jacobian_svg
    assert f"stroke-opacity: {PLOT.grid_opacity}" in jacobian_svg
    assert f".axis-title {{ font-size: {PLOT.axis_title_font_size}px;" in jacobian_svg

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

    print("optimal_estimation_plot=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
