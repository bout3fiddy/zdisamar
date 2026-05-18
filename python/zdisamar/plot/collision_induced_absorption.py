"""O2-O2 collision-induced absorption plot accessor."""

from pathlib import Path

import numpy as np

from . import fields
from .axes import label
from .data import column_values
from .profiles import interval_profile_rows, nearest_wavelength_value
from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, SvgPanel, SvgSeries

DEFAULT_PROFILE_WAVELENGTH_NM = 760.76


class CollisionInducedAbsorptionPlot(PlotAccessor):
    """Plots for O2-O2 collision-induced absorption by layer."""

    def __init__(self, table):

        super().__init__(table)

    def optical_depth(
        self,
        wavelength_nm: float | None = None,
        save: str | Path | None = None,
    ):

        return self._finish(
            _optical_depth_profile(self._target, wavelength_nm=wavelength_nm),
            save=save,
        )


def _optical_depth_profile(
    table,
    *,
    wavelength_nm: float | None,
):

    quantity = fields.COLLISION_INDUCED_ABSORPTION_OPTICAL_DEPTH
    selected_wavelength_nm = _profile_wavelength(table, wavelength_nm)
    data = interval_profile_rows(
        table,
        value=quantity,
        vertical_axis="altitude_km",
        wavelength_nm=selected_wavelength_nm,
    )
    title = "O2-O2 collision-induced absorption optical depth profile"

    if selected_wavelength_nm is not None and data:
        title = f"{title}, {nearest_wavelength_value(data, selected_wavelength_nm):.2f} nm"

    panel = SvgPanel(
        title=title,
        x_title=label(quantity),
        y_title=label("altitude_km"),
        series=(
            SvgSeries.points(
                title,
                column_values(data, quantity),
                column_values(data, "altitude_km"),
                color=PLOT.colors["collision_induced_absorption"],
                point_size=PLOT.profile_point_size,
                opacity=PLOT.profile_point_opacity,
            ),
        ),
    )

    return SvgFigure(title=title, panels=(panel,))


def _profile_wavelength(table, wavelength_nm: float | None) -> float | None:

    if wavelength_nm is not None:
        return wavelength_nm

    values = np.unique(table.column(fields.WAVELENGTH_NM))

    if values.size <= 1:
        return None

    return float(values[int(np.argmin(np.abs(values - DEFAULT_PROFILE_WAVELENGTH_NM)))])
