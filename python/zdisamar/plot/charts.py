"""Shared chart grammar for SVG plots."""

from .axes import wavelength_x
from .properties import PLOT
from .svg import SvgPanel, SvgSeries


def wavelength_line_chart(
    data,
    y,
    tooltip,
    *,
    color: str | None = None,
):

    _ = tooltip
    x_encoding = wavelength_x()

    return SvgPanel(
        title="",
        x_title=str(x_encoding.title),
        y_title=str(y.title),
        series=(
            SvgSeries.line(
                str(y.field),
                (float(row[x_encoding.field]) for row in data),
                (float(row[y.field]) for row in data),
                color=color or PLOT.colors["blue"],
                show_legend=False,
            ),
        ),
        show_legend=False,
    )
