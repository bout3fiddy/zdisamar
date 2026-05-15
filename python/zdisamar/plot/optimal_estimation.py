"""Optimal-estimation result plot accessor."""

from pathlib import Path

import altair as alt

from .axes import finite_padded_scale, scaled_y, wavelength_x
from .charts import wavelength_line_chart
from .properties import PLOT, PlotAccessor

STATE_LABELS = {
    "surface_albedo": "Surface albedo",
    "aerosol_optical_depth": "Aerosol optical depth",
    "aerosol_layer_mid_pressure_hpa": "Aerosol layer mid-pressure",
}

STATE_UNITS = {
    "surface_albedo": "",
    "aerosol_optical_depth": "optical depth at 550 nm",
    "aerosol_layer_mid_pressure_hpa": "hPa",
}

STATE_AXIS_TITLES = {
    "surface_albedo": "Surface albedo",
    "aerosol_optical_depth": "AOD at 550 nm",
    "aerosol_layer_mid_pressure_hpa": "Mid-pressure (hPa)",
}

STATE_PANEL_TITLES = {
    "surface_albedo": "Surface albedo",
    "aerosol_optical_depth": "Aerosol optical depth",
    "aerosol_layer_mid_pressure_hpa": "Layer mid-pressure (hPa)",
}

JACOBIAN_PANEL_HEIGHT = 320
STATE_TRACE_PANEL_HEIGHT = 300
STATE_TRACE_COLUMNS = 2
MEASUREMENT_FIT_HEIGHT = 315
MEASUREMENT_RESIDUAL_HEIGHT = 170
STATE_TRACE_Y_TITLE = "Value"
JACOBIAN_Y_TITLE = "Jacobian"


class OptimalEstimationPlot(PlotAccessor):
    """Plots that show why an OE retrieval state was accepted."""

    def __init__(self, result):

        super().__init__(result)

    def convergence(self, save: str | Path | None = None):

        return self._finish(_convergence(self._target), save=save)

    def measurement_fit(self, save: str | Path | None = None):

        return self._finish(_measurement_fit(self._target), save=save)

    def residual(self, save: str | Path | None = None):

        return self._finish(_residual(self._target), save=save)

    def jacobian(self, save: str | Path | None = None, *, columns: int = 2):

        return self._finish(_jacobian(self._target, columns=columns), save=save)


def _state_history_frame(result):
    """Put each retrieved coordinate into a long table with physical labels."""

    import pandas as pd

    rows = []

    if result.initial_state is not None:
        for index, state_name in enumerate(result.state_names):
            rows.append(
                {
                    "iteration": 0,
                    "state_name": state_name,
                    "state_order": index,
                    "state": _state_label(state_name),
                    "unit": _state_unit(state_name),
                    "state_panel": _state_panel_title(state_name),
                    "value": float(result.initial_state[index]),
                    "state_vector_convergence": None,
                    "chi2_reflectance": None,
                    "chi2_state_vector": None,
                }
            )

    for iteration in result.history:
        for index, state_name in enumerate(result.state_names):
            rows.append(
                {
                    "iteration": iteration.index,
                    "state_name": state_name,
                    "state_order": index,
                    "state": _state_label(state_name),
                    "unit": _state_unit(state_name),
                    "state_panel": _state_panel_title(state_name),
                    "value": float(iteration.state[index]),
                    "state_vector_convergence": iteration.state_vector_convergence,
                    "chi2_reflectance": iteration.chi2_reflectance,
                    "chi2_state_vector": iteration.chi2_state_vector,
                }
            )

    return pd.DataFrame(rows)


def _fit_frame(result):

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


def jacobian_frame(result):
    """Put final reflectance Jacobians into one table for all states."""

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
                    "state_name": state_name,
                    "state_order": index,
                    "unit": _state_unit(state_name),
                    "state_panel": _state_panel_title(state_name),
                    "reflectance_jacobian": values,
                }
            )
        )

    return pd.concat(columns, ignore_index=True)


def _convergence(result):

    data = _state_history_frame(result)
    columns = _state_columns(result)
    charts = []

    for index, state_name in enumerate(result.state_names):
        panel_data = data[data["state_name"] == state_name].copy()
        panel_data, _, y = scaled_y(
            panel_data,
            "value",
            STATE_TRACE_Y_TITLE,
            axis=_numeric_axis(format=".6g"),
        )
        charts.append(
            alt.Chart(panel_data)
            .mark_line(point=True, color=_state_color_at(index), strokeWidth=2.0)
            .encode(
                x=alt.X("iteration:O", title="Iteration", axis=alt.Axis(grid=False)),
                y=y,
                tooltip=[
                    alt.Tooltip("iteration:O", title="Iteration"),
                    alt.Tooltip("state:N", title="State"),
                    alt.Tooltip("unit:N", title="State unit"),
                    alt.Tooltip("value:Q", title="Value", format=".6g"),
                    alt.Tooltip(
                        "state_vector_convergence:Q",
                        title="State-vector convergence",
                        format=".6g",
                    ),
                    alt.Tooltip(
                        "chi2_reflectance:Q",
                        title="Reflectance chi-square",
                        format=".6g",
                    ),
                    alt.Tooltip(
                        "chi2_state_vector:Q",
                        title="State chi-square",
                        format=".6g",
                    ),
                ],
            )
            .properties(
                title=_state_panel_title(state_name),
                width=_panel_width(columns),
                height=STATE_TRACE_PANEL_HEIGHT,
            )
        )

    return wrap_panel_charts(
        charts,
        columns=columns,
        title="Retrieved state trajectory",
    )


def _measurement_fit(result):

    data = _fit_frame(result)
    top = _measurement_fit_panel(data)
    residual = _measurement_residual_panel(data)

    return (
        alt.vconcat(top, residual, spacing=20, bounds="flush")
        .resolve_scale(x="shared")
        .properties(title="Measurement fit")
    )


def _measurement_fit_panel(data):

    reflectance_values = data[["measurement", "retrieved_model"]].to_numpy().ravel()
    retrieved = (
        alt.Chart(data)
        .mark_line(color=PLOT.colors["orange"], strokeWidth=1.7)
        .encode(
            x=alt.X(
                "wavelength_nm:Q",
                title=None,
                axis=alt.Axis(grid=False, labels=False, ticks=False),
                scale=alt.Scale(zero=False),
            ),
            y=alt.Y(
                "retrieved_model:Q",
                title="Reflectance",
                axis=_numeric_axis(format=".4g"),
                scale=finite_padded_scale(reflectance_values),
            ),
            tooltip=_measurement_fit_tooltips(),
        )
    )
    measurement = (
        alt.Chart(data)
        .mark_point(
            color=PLOT.colors["blue"],
            filled=True,
            opacity=0.75,
            size=PLOT.default_point_size * 0.55,
        )
        .encode(
            x="wavelength_nm:Q",
            y="measurement:Q",
            tooltip=_measurement_fit_tooltips(),
        )
    )

    return (retrieved + measurement).properties(
        title="Retrieved model with measurement samples",
        width=PLOT.width,
        height=MEASUREMENT_FIT_HEIGHT,
    )


def _measurement_residual_panel(data):

    plot_data, plot_field, y = scaled_y(data, "residual", "Residual")
    zero_data = plot_data.iloc[[0]].copy()
    zero_data[plot_field] = 0.0
    residual = wavelength_line_chart(
        plot_data,
        y,
        [
            alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
            alt.Tooltip("residual:Q", title="Residual", format=".8g"),
        ],
        color=PLOT.colors["red"],
    ).properties(
        width=PLOT.width,
        height=MEASUREMENT_RESIDUAL_HEIGHT,
    )
    zero = (
        alt.Chart(zero_data)
        .mark_rule(
            color=PLOT.colors["neutral"],
            strokeDash=list(PLOT.marker_rule_dash),
            strokeWidth=PLOT.marker_rule_width,
        )
        .encode(y=f"{plot_field}:Q")
    )

    return zero + residual


def _measurement_fit_tooltips():

    return [
        alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
        alt.Tooltip("measurement:Q", title="Measurement", format=".8g"),
        alt.Tooltip("retrieved_model:Q", title="Retrieved model", format=".8g"),
        alt.Tooltip("residual:Q", title="Residual", format=".8g"),
    ]


def _residual(result):

    data = _fit_frame(result)
    data, _, y = scaled_y(data, "residual", "Measurement - retrieved reflectance")

    return wavelength_line_chart(
        data,
        y,
        [
            alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
            alt.Tooltip("residual:Q", title="Residual", format=".8g"),
        ],
        color=PLOT.colors["red"],
    ).properties(**PLOT.chart("Final residual"))


def _jacobian(result, *, columns: int):

    data = jacobian_frame(result)
    columns = max(1, columns)
    charts = []

    for index, state_name in enumerate(result.state_names):
        panel_data = data[data["state_name"] == state_name].copy()
        panel_data, _, y = scaled_y(
            panel_data,
            "reflectance_jacobian",
            JACOBIAN_Y_TITLE,
            axis=_numeric_axis(format=".4g"),
        )
        charts.append(
            alt.Chart(panel_data)
            .mark_line(color=_state_color_at(index), strokeWidth=1.7)
            .encode(
                x=wavelength_x(),
                y=y,
                tooltip=[
                    alt.Tooltip("wavelength_nm:Q", title="Wavelength (nm)", format=".4f"),
                    alt.Tooltip("state:N", title="State"),
                    alt.Tooltip("unit:N", title="State unit"),
                    alt.Tooltip(
                        "reflectance_jacobian:Q",
                        title="Reflectance jacobian",
                        format=".8g",
                    ),
                ],
            )
            .properties(
                title=_state_panel_title(state_name),
                width=_panel_width(columns),
                height=JACOBIAN_PANEL_HEIGHT,
            )
        )

    return wrap_panel_charts(
        charts,
        columns=columns,
        title="Final reflectance Jacobians",
    )


def _require_measurement(result):

    if result.measurement is None:
        raise RuntimeError("optimal-estimation result does not include a measurement")

    return result.measurement


def _require_final_evaluation(result):

    # The final spectrum can be expensive. It is evaluated here only for plots
    # that need residuals or Jacobians at the accepted retrieval state.
    evaluation = result.final_evaluation

    if evaluation is None:
        raise RuntimeError("optimal-estimation result does not include a final forward evaluation")

    return evaluation


def _state_label(state_name: str) -> str:

    return STATE_LABELS.get(state_name, state_name.replace("_", " "))


def _state_unit(state_name: str) -> str:

    return STATE_UNITS.get(state_name, "")


def _state_axis_title(state_name: str) -> str:

    return STATE_AXIS_TITLES.get(state_name, _state_label(state_name))


def _state_panel_title(state_name: str) -> str:

    return STATE_PANEL_TITLES.get(state_name, _state_axis_title(state_name))


def _state_color_at(index: int) -> str:

    return _color_range(index + 1)[index]


def _color_range(count: int) -> list[str]:

    palette = [
        PLOT.colors["blue"],
        PLOT.colors["orange"],
        PLOT.colors["red"],
        PLOT.colors["neutral"],
    ]

    return [palette[index % len(palette)] for index in range(count)]


def _state_columns(result) -> int:

    return min(STATE_TRACE_COLUMNS, max(1, len(result.state_names)))


def _panel_width(columns: int) -> int:

    return max(320, int(PLOT.width / max(1, columns)) - 45)


def wrap_panel_charts(charts, *, columns: int, title: str):

    rows = [
        alt.hconcat(*charts[start : start + columns], spacing=52, bounds="flush")
        for start in range(0, len(charts), columns)
    ]
    chart = rows[0] if len(rows) == 1 else alt.vconcat(*rows, spacing=32, bounds="flush")

    return chart.resolve_scale(y="independent").properties(title=title)


def _numeric_axis(*, format: str):

    return alt.Axis(format=format, tickCount=PLOT.y_axis_tick_count)
