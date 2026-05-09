"""Atmospheric-budget plot accessor."""

from pathlib import Path
from typing import Any

import altair as alt

from . import fields
from .axes import label, scaled_x
from .profiles import interval_profile_rows, nearest_wavelength_value
from .properties import PLOT, PlotAccessor

DEFAULT_PROFILE_WAVELENGTH_NM = 760.76


class BudgetPlot(PlotAccessor):
    def __init__(self, budget: Any):
        super().__init__(budget)

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
    budget: Any,
    *,
    wavelength_nm: float | None,
):
    quantity = fields.TOTAL_OPTICAL_DEPTH
    selected_wavelength_nm = _profile_wavelength(budget, wavelength_nm)
    data = interval_profile_rows(
        budget,
        value=quantity,
        vertical_axis="altitude_km",
        wavelength_nm=selected_wavelength_nm,
    )
    title = f"{label(quantity)} profile"
    if selected_wavelength_nm is not None and not data.empty:
        nearest_nm = nearest_wavelength_value(data, selected_wavelength_nm)
        title = f"{label(quantity)} profile, {nearest_nm:.2f} nm"
    data, _, x = scaled_x(data, quantity, label(quantity))
    return (
        alt.Chart(data)
        .mark_point(
            filled=True,
            color=PLOT.colors[quantity],
            size=PLOT.profile_point_size,
            opacity=PLOT.profile_point_opacity,
        )
        .encode(
            x=x,
            y=alt.Y("altitude_km:Q", title=label("altitude_km")),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip("altitude_km:Q", title=label("altitude_km"), format=".4g"),
                alt.Tooltip(f"{quantity}:Q", title=label(quantity), format=".4e"),
            ],
        )
        .properties(**PLOT.chart(title))
    )


def _profile_wavelength(budget: Any, wavelength_nm: float | None) -> float | None:
    if wavelength_nm is not None:
        return wavelength_nm
    import numpy as np

    values = np.unique(budget.column(fields.WAVELENGTH_NM))
    if values.size <= 1:
        return None
    return float(values[int(np.argmin(np.abs(values - DEFAULT_PROFILE_WAVELENGTH_NM)))])
