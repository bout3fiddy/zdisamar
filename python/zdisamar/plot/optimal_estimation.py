"""Optimal-estimation result plot accessor."""

from pathlib import Path
from typing import Any

import altair as alt

from .axes import finite_padded_scale, scaled_y
from .properties import PLOT, PlotAccessor

STATE_LABELS = {
    "surface_albedo": "Surface albedo",
    "aerosol_optical_depth": "Aerosol optical depth",
    "aerosol_layer_mid_pressure_hpa": "Aerosol layer mid-pressure (hPa)",
}


class OptimalEstimationPlot(PlotAccessor):
    def __init__(self, result: Any):
        super().__init__(result)

    def convergence(self, save: str | Path | None = None):
        return self._finish(_convergence(self._target), save=save)

    def measurement_fit(self, save: str | Path | None = None):
        return self._finish(_measurement_fit(self._target), save=save)

    def residual(self, save: str | Path | None = None):
        return self._finish(_residual(self._target), save=save)

    def jacobian(self, save: str | Path | None = None):
        return self._finish(_jacobian(self._target), save=save)


def _history_frame(result: Any):
    import pandas as pd

    return pd.DataFrame(
        {
            "iteration": [iteration.index for iteration in result.history],
            "state_vector_convergence": [
                iteration.state_vector_convergence for iteration in result.history
            ],
            "chi2_reflectance": [iteration.chi2_reflectance for iteration in result.history],
            "chi2_state_vector": [iteration.chi2_state_vector for iteration in result.history],
        }
    )


def _fit_frame(result: Any):
    import pandas as pd

    from ..inverse_method.optimal_estimation.measurement import require_matching_wavelength_grid

    measurement = _require_measurement(result)
    evaluation = _require_final_evaluation(result)
    wavelength_nm = measurement.wavelength_nm
    require_matching_wavelength_grid(
        wavelength_nm,
        evaluation.wavelength_nm,
        expected_name="measurement",
        actual_name="final evaluation",
    )
    return pd.DataFrame(
        {
            "wavelength_nm": wavelength_nm,
            "measurement": measurement.reflectance,
            "retrieved_model": evaluation.reflectance,
            "residual": measurement.reflectance - evaluation.reflectance,
        }
    )


def jacobian_frame(result: Any):
    import pandas as pd

    from ..inverse_method.optimal_estimation.measurement import require_matching_wavelength_grid

    measurement = _require_measurement(result)
    evaluation = _require_final_evaluation(result)
    wavelength_nm = measurement.wavelength_nm
    require_matching_wavelength_grid(
        wavelength_nm,
        evaluation.wavelength_nm,
        expected_name="measurement",
        actual_name="final evaluation",
    )
    columns = []
    for index, state_name in enumerate(result.state_names):
        values = evaluation.reflectance_jacobian[:, index]
        columns.append(
            pd.DataFrame(
                {
                    "wavelength_nm": wavelength_nm,
                    "state": _state_label(state_name),
                    "reflectance_jacobian": values,
                }
            )
        )
    return pd.concat(columns, ignore_index=True)


def _convergence(result: Any):
    data = _history_frame(result)
    data, _, y = scaled_y(
        data,
        "state_vector_convergence",
        "State-vector convergence",
    )
    return (
        alt.Chart(data)
        .mark_line(point=True, color=PLOT.colors["orange"])
        .encode(
            x=alt.X("iteration:O", title="Iteration"),
            y=y,
            tooltip=[
                alt.Tooltip("iteration:O", title="Iteration"),
                alt.Tooltip(
                    "state_vector_convergence:Q",
                    title="State-vector convergence",
                    format=".6g",
                ),
                alt.Tooltip("chi2_reflectance:Q", title="Reflectance chi-square", format=".6g"),
                alt.Tooltip("chi2_state_vector:Q", title="State chi-square", format=".6g"),
            ],
        )
        .properties(**PLOT.chart("Retrieval convergence"))
    )


def _measurement_fit(result: Any):
    data = _fit_frame(result)
    long = data.melt(
        id_vars=["wavelength_nm"],
        value_vars=["measurement", "retrieved_model"],
        var_name="series",
        value_name="reflectance",
    )
    long["series_label"] = long["series"].map(
        lambda value: {
            "measurement": "Measurement",
            "retrieved_model": "Retrieved model",
        }.get(value, str(value))
    )
    return (
        alt.Chart(long)
        .mark_line()
        .encode(
            x=alt.X("wavelength_nm:Q", title="Wavelength (nm)", scale=alt.Scale(zero=False)),
            y=alt.Y(
                "reflectance:Q",
                title="Reflectance",
                scale=finite_padded_scale(long["reflectance"]),
            ),
            color=alt.Color(
                "series_label:N",
                title=None,
                scale=alt.Scale(
                    domain=["Measurement", "Retrieved model"],
                    range=[PLOT.colors["blue"], PLOT.colors["orange"]],
                ),
            ),
            tooltip=["wavelength_nm:Q", "series_label:N", "reflectance:Q"],
        )
        .properties(**PLOT.chart("Measurement fit"))
    )


def _residual(result: Any):
    data = _fit_frame(result)
    data, _, y = scaled_y(data, "residual", "Measurement - retrieved reflectance")
    return (
        alt.Chart(data)
        .mark_line(color=PLOT.colors["red"])
        .encode(
            x=alt.X("wavelength_nm:Q", title="Wavelength (nm)", scale=alt.Scale(zero=False)),
            y=y,
            tooltip=[
                alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("residual:Q", title="Residual", format=".8g"),
            ],
        )
        .properties(**PLOT.chart("Final residual"))
    )


def _jacobian(result: Any):
    data = jacobian_frame(result)
    data, _, y = scaled_y(data, "reflectance_jacobian", "Reflectance jacobian")
    return (
        alt.Chart(data)
        .mark_line()
        .encode(
            x=alt.X("wavelength_nm:Q", title="Wavelength (nm)", scale=alt.Scale(zero=False)),
            y=y,
            color=alt.Color("state:N", title=None),
            tooltip=[
                alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("state:N", title="State"),
                alt.Tooltip(
                    "reflectance_jacobian:Q",
                    title="Reflectance jacobian",
                    format=".8g",
                ),
            ],
        )
        .properties(**PLOT.chart("Final reflectance Jacobians"))
    )


def _require_measurement(result: Any):
    if result.measurement is None:
        raise RuntimeError("optimal-estimation result does not include a measurement")
    return result.measurement


def _require_final_evaluation(result: Any):
    if result.final_evaluation is None:
        raise RuntimeError("optimal-estimation result does not include a final forward evaluation")
    return result.final_evaluation


def _state_label(state_name: str) -> str:
    return STATE_LABELS.get(state_name, state_name.replace("_", " "))
