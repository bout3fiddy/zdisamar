import json
import math
from pathlib import Path
from tempfile import TemporaryDirectory

from zdisamar.inverse_method.optimal_estimation.profile import (
    build_profile_result,
    pressure_bins,
)


def main() -> int:

    bins = pressure_bins([225.0, 300.0, 375.0, 450.0])
    raw = (
        {
            "converged": True,
            "iteration_count": 3,
            "retrieved_aod_550_nm": 0.16,
            "posterior_variance": 0.02,
            "averaging_kernel": 0.8,
            "spectral_chi2_ref": 15.0,
            "prior_chi2": 0.2,
            "total_cost_ref": 15.2,
            "residual_rms": 0.01,
            "residual_max_abs": 0.02,
        },
        {
            "converged": True,
            "iteration_count": 3,
            "retrieved_aod_550_nm": 0.12,
            "posterior_variance": 0.02,
            "averaging_kernel": 0.7,
            "spectral_chi2_ref": 10.0,
            "prior_chi2": 0.1,
            "total_cost_ref": 10.1,
            "residual_rms": 0.005,
            "residual_max_abs": 0.01,
        },
        {
            "converged": True,
            "iteration_count": 2,
            "retrieved_aod_550_nm": 0.09,
            "posterior_variance": 0.03,
            "averaging_kernel": 0.5,
            "spectral_chi2_ref": 12.0,
            "prior_chi2": 0.05,
            "total_cost_ref": 12.05,
            "residual_rms": 0.008,
            "residual_max_abs": 0.015,
        },
    )
    result = build_profile_result(
        bins=bins,
        raw_candidates=raw,
        beta=1.0,
        layer_thickness_hpa=50.0,
    )

    assert result.best_bin_id == "p_300_375"
    assert math.isclose(sum(result.probability_by_bin.values()), 1.0)
    assert result.pressure_p50_hpa == 337.5
    assert (
        result.expected_aod_profile[1].expected_aod_550_nm
        > result.expected_aod_profile[0].expected_aod_550_nm
    )

    summary = result.plot.summary()
    spec = summary.to_dict()
    spec_text = json.dumps(spec)
    assert spec["type"] == "zdisamar-svg"
    assert spec["title"]["text"] == "Discrete aerosol-layer profile"
    assert len(spec["panels"]) == 2
    assert spec["panels"][0]["x_title"] == "Probability"
    assert spec["panels"][0]["y_title"] == "Pressure bin (hPa)"
    assert spec["panels"][0]["y_domain"] == [450.0, 225.0]
    assert spec["panels"][0]["y_tick_labels"] == ["225-300", "300-375", "375-450"]
    assert spec["panels"][0]["series"][0]["kind"] == "horizontal_bars"
    assert "Expected AOD at 550 nm" in spec_text

    with TemporaryDirectory() as directory:
        path = Path(directory) / "profile-summary.svg"
        result.plot.summary(
            truth_layers=(
                {
                    "top_pressure_hpa": 300.0,
                    "bottom_pressure_hpa": 375.0,
                    "optical_depth": 0.12,
                },
            )
        ).save(path)
        svg = path.read_text()

    assert "<svg" in svg
    assert "Layer-location probability" in svg
    assert "Model-averaged AOD distribution" in svg
    assert "Truth AOD fraction" in svg
    print("profile_retrieval_plot=ok")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
