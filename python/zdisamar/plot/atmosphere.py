"""Atmospheric-budget plot accessor."""

from pathlib import Path

import numpy as np

from . import fields
from .axes import label
from .data import column_values
from .profiles import interval_profile_rows, nearest_wavelength_value
from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, SvgPanel, SvgSeries

DEFAULT_PROFILE_WAVELENGTH_NM = 760.76


class BudgetPlot(PlotAccessor):
    """Plots for atmospheric optical-depth budgets."""

    def __init__(self, budget):

        super().__init__(budget)

    def optical_depth(
        self,
        wavelength_nm: float | None = None,
        save: str | Path | None = None,
    ):

        return self.finish_plot(
            optical_depth_profile(self.target, wavelength_nm=wavelength_nm),
            save=save,
        )


def optical_depth_profile(
    budget,
    *,
    wavelength_nm: float | None,
):

    quantity = fields.TOTAL_OPTICAL_DEPTH
    selected_wavelength_nm = profile_wavelength(budget, wavelength_nm)
    data = interval_profile_rows(
        budget,
        value=quantity,
        vertical_axis="altitude_km",
        wavelength_nm=selected_wavelength_nm,
    )
    title = f"{label(quantity)} profile"

    if selected_wavelength_nm is not None and data:
        nearest_nm = nearest_wavelength_value(data, selected_wavelength_nm)
        title = f"{label(quantity)} profile, {nearest_nm:.2f} nm"

    panel = SvgPanel(
        title=title,
        x_title=label(quantity),
        y_title=label("altitude_km"),
        series=(
            SvgSeries.points(
                title,
                column_values(data, quantity),
                column_values(data, "altitude_km"),
                color=PLOT.colors[quantity],
                point_size=PLOT.profile_point_size,
                opacity=PLOT.profile_point_opacity,
            ),
        ),
    )

    return SvgFigure(title=title, panels=(panel,))


def profile_wavelength(budget, wavelength_nm: float | None) -> float | None:

    if wavelength_nm is not None:
        return wavelength_nm

    values = np.unique(budget.column(fields.WAVELENGTH_NM))

    if values.size <= 1:
        return None

    return float(values[int(np.argmin(np.abs(values - DEFAULT_PROFILE_WAVELENGTH_NM)))])
