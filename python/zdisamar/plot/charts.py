"""Shared Altair chart grammar."""

import altair as alt

from .axes import wavelength_x
from .properties import PLOT


def wavelength_line_chart(
    data,
    y: alt.Y,
    tooltip,
    *,
    color: str | None = None,
) -> alt.Chart:

    return (
        alt.Chart(data)
        .mark_line(color=color or PLOT.colors["blue"], strokeWidth=PLOT.line_width)
        .encode(
            x=wavelength_x(),
            y=y,
            tooltip=tooltip,
        )
    )
