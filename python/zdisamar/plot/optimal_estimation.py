"""Optimal-estimation result plot accessor."""

from pathlib import Path

from . import fields
from .data import as_float
from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, SvgPanel, SvgSeries, axis_multiplier, line_panel

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

STATE_DERIVATIVE_TITLES = {
    "surface_albedo": "dR/dA",
    "aerosol_optical_depth": "dR/dτ",
    "aerosol_layer_mid_pressure_hpa": "dR/dp (hPa⁻¹)",
}

JACOBIAN_PANEL_HEIGHT = 320
JACOBIAN_PANEL_WIDTH = 520
STATE_TRACE_PANEL_HEIGHT = 300
STATE_TRACE_COLUMNS = 2
MEASUREMENT_FIT_HEIGHT = 315
MEASUREMENT_RESIDUAL_HEIGHT = 170
STATE_TRACE_Y_TITLE = None


class OptimalEstimationPlot(PlotAccessor):
    """Plots that show why an OE retrieval state was accepted."""

    def __init__(self, result):

        super().__init__(result)

    def convergence(self, save: str | Path | None = None):

        return self.finish_plot(convergence_figure(self.target), save=save)

    def measurement_fit(self, save: str | Path | None = None):

        return self.finish_plot(measurement_fit_figure(self.target), save=save)

    def residual(self, save: str | Path | None = None):

        return self.finish_plot(residual_figure(self.target), save=save)

    def jacobian(self, save: str | Path | None = None, *, columns: int = 2):

        return self.finish_plot(jacobian_figure(self.target, columns=columns), save=save)


def state_history_rows(result) -> list[dict[str, object]]:
    """Put each retrieved coordinate into a long table with physical labels."""

    rows: list[dict[str, object]] = []

    if result.initial_state is not None:
        for index, state_name in enumerate(result.state_names):
            rows.append(
                {
                    "iteration": 0,
                    "state_name": state_name,
                    "state_order": index,
                    "state": state_label(state_name),
                    "unit": state_unit(state_name),
                    "state_panel": state_panel_title(state_name),
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
                    "state": state_label(state_name),
                    "unit": state_unit(state_name),
                    "state_panel": state_panel_title(state_name),
                    "value": float(iteration.state[index]),
                    "state_vector_convergence": iteration.state_vector_convergence,
                    "chi2_reflectance": iteration.chi2_reflectance,
                    "chi2_state_vector": iteration.chi2_state_vector,
                }
            )

    return rows


def fit_rows(result) -> list[dict[str, float]]:

    from ..inverse_method.optimal_estimation.measurement import require_matching_wavelength_grid

    measurement = require_measurement(result)
    evaluation = require_final_evaluation(result)
    wavelength_nm = measurement.wavelength_nm
    require_matching_wavelength_grid(
        wavelength_nm,
        evaluation.wavelength_nm,
        expected_name="measurement",
        actual_name="final evaluation",
    )

    return [
        {
            "wavelength_nm": float(wavelength),
            "measurement": float(measured),
            "retrieved_model": float(retrieved),
            "residual": float(measured - retrieved),
        }
        for wavelength, measured, retrieved in zip(
            wavelength_nm,
            measurement.reflectance,
            evaluation.reflectance,
            strict=True,
        )
    ]


def jacobian_frame(result) -> list[dict[str, object]]:
    """Put final reflectance Jacobians into one table for all states."""

    from ..inverse_method.optimal_estimation.measurement import require_matching_wavelength_grid

    measurement = require_measurement(result)
    evaluation = require_final_evaluation(result)
    wavelength_nm = measurement.wavelength_nm
    require_matching_wavelength_grid(
        wavelength_nm,
        evaluation.wavelength_nm,
        expected_name="measurement",
        actual_name="final evaluation",
    )
    rows: list[dict[str, object]] = []

    for index, state_name in enumerate(result.state_names):
        values = [row[index] for row in evaluation.reflectance_jacobian]

        for wavelength, value in zip(wavelength_nm, values, strict=True):
            rows.append(
                {
                    "wavelength_nm": float(wavelength),
                    "state": state_label(state_name),
                    "state_name": state_name,
                    "state_order": index,
                    "unit": state_unit(state_name),
                    "state_panel": state_panel_title(state_name),
                    "reflectance_jacobian": float(value),
                }
            )

    return rows


def convergence_figure(result) -> SvgFigure:

    rows = state_history_rows(result)
    columns = state_columns(result)
    panels = []

    for index, state_name in enumerate(result.state_names):
        panel_rows = [row for row in rows if row["state_name"] == state_name]
        x_values = [as_float(row["iteration"]) for row in panel_rows]
        values = [as_float(row["value"]) for row in panel_rows]
        color = state_color_at(index)
        panel = SvgPanel(
            title=state_panel_title(state_name),
            x_title="Iteration",
            y_title=STATE_TRACE_Y_TITLE,
            series=(
                SvgSeries.line(state_label(state_name), x_values, values, color=color),
                SvgSeries.points(state_label(state_name), x_values, values, color=color),
            ),
            width=panel_width(columns),
            height=STATE_TRACE_PANEL_HEIGHT,
            x_domain=iteration_domain(x_values),
            x_ticks=tuple(sorted(set(x_values))),
            marker_x=(),
        )
        panels.append(panel)

    return SvgFigure(
        title="Retrieved state trajectory",
        panels=tuple(panels),
        columns=columns,
        panel_spacing=112,
        y_independent=True,
    )


def measurement_fit_figure(result) -> SvgFigure:

    rows = fit_rows(result)
    wavelength = [row["wavelength_nm"] for row in rows]
    measurement = [row["measurement"] for row in rows]
    retrieved = [row["retrieved_model"] for row in rows]
    residual = [row["residual"] for row in rows]
    reflectance_values = [*measurement, *retrieved]
    fit_panel = SvgPanel(
        title="Retrieved model with measurement samples",
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title="Reflectance",
        series=(
            SvgSeries.line(
                "Retrieved model",
                wavelength,
                retrieved,
                color=PLOT.colors["orange"],
                stroke_width=1.7,
            ),
            SvgSeries.points(
                "Measurement",
                wavelength,
                measurement,
                color=PLOT.colors["blue"],
                point_size=PLOT.default_point_size * 0.55,
                opacity=0.75,
            ),
        ),
        width=PLOT.diagnostic_width,
        height=MEASUREMENT_FIT_HEIGHT,
        y_axis_multiplier=axis_multiplier(reflectance_values),
        show_x_axis=False,
    )
    residual_panel = line_panel(
        title="Residual",
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title="Residual",
        x=wavelength,
        y=residual,
        name="Residual",
        color=PLOT.colors["red"],
        width=PLOT.diagnostic_width,
        height=MEASUREMENT_RESIDUAL_HEIGHT,
        marker_x=False,
        rule_y=(0.0,),
    )

    return SvgFigure(
        title="Measurement fit",
        panels=(fit_panel, residual_panel),
        columns=1,
        panel_spacing=44,
    )


def residual_figure(result) -> SvgFigure:

    rows = fit_rows(result)
    residual = [row["residual"] for row in rows]
    panel = line_panel(
        title="Final residual",
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title="Residual",
        x=[row["wavelength_nm"] for row in rows],
        y=residual,
        name="Residual",
        color=PLOT.colors["red"],
        width=PLOT.diagnostic_width,
        height=PLOT.height,
        marker_x=False,
        rule_y=(0.0,),
    )

    return SvgFigure(title="Final residual", panels=(panel,))


def jacobian_figure(result, *, columns: int) -> SvgFigure:

    rows = jacobian_frame(result)
    columns = max(1, columns)
    panels = []

    for index, state_name in enumerate(result.state_names):
        panel_rows = [row for row in rows if row["state_name"] == state_name]
        values = [as_float(row["reflectance_jacobian"]) for row in panel_rows]
        derivative_title = state_derivative_title(state_name)
        panel = line_panel(
            title=state_panel_title(state_name),
            x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
            y_title=derivative_title,
            x=[as_float(row["wavelength_nm"]) for row in panel_rows],
            y=values,
            name=derivative_title,
            color=state_color_at(index),
            width=jacobian_panel_width(columns),
            height=JACOBIAN_PANEL_HEIGHT,
        )
        panels.append(panel)

    return SvgFigure(
        title="Final reflectance Jacobians",
        panels=tuple(panels),
        columns=columns,
        panel_spacing=112,
        y_independent=True,
    )


def require_measurement(result):

    if result.measurement is None:
        raise RuntimeError("optimal-estimation result does not include a measurement")

    return result.measurement


def require_final_evaluation(result):

    # The final spectrum can be expensive. It is evaluated here only for plots
    # that need residuals or Jacobians at the accepted retrieval state.
    evaluation = result.final_evaluation

    if evaluation is None:
        raise RuntimeError("optimal-estimation result does not include a final forward evaluation")

    return evaluation


def state_label(state_name: str) -> str:

    return STATE_LABELS.get(state_name, state_name.replace("_", " "))


def state_unit(state_name: str) -> str:

    return STATE_UNITS.get(state_name, "")


def state_axis_title(state_name: str) -> str:

    return STATE_AXIS_TITLES.get(state_name, state_label(state_name))


def state_panel_title(state_name: str) -> str:

    return STATE_PANEL_TITLES.get(state_name, state_axis_title(state_name))


def state_derivative_title(state_name: str) -> str:

    return STATE_DERIVATIVE_TITLES.get(state_name, "dR/dx")


def state_color_at(index: int) -> str:

    return color_range(index + 1)[index]


def color_range(count: int) -> list[str]:

    palette = [
        PLOT.colors["blue"],
        PLOT.colors["orange"],
        PLOT.colors["red"],
        PLOT.colors["neutral"],
    ]

    return [palette[index % len(palette)] for index in range(count)]


def state_columns(result) -> int:

    return min(STATE_TRACE_COLUMNS, max(1, len(result.state_names)))


def iteration_domain(values: list[float]) -> tuple[float, float]:

    if not values:
        return (0.0, 1.0)

    low = min(values)
    high = max(values)

    if low == high:
        return (low - 0.5, high + 0.5)

    return (low, high)


def panel_width(columns: int) -> int:

    return max(300, int(PLOT.diagnostic_width / max(1, columns)) - 35)


def jacobian_panel_width(columns: int) -> int:

    if columns <= 1:
        return PLOT.diagnostic_width

    return JACOBIAN_PANEL_WIDTH
