"""Instrument-response plot accessor."""

from pathlib import Path

import numpy as np

from . import fields
from .data import as_float, with_channel_labels
from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, SvgPanel, line_panel


class InstrumentResponsePlot(PlotAccessor):
    """Plots for instrument response support weights."""

    def __init__(self, response):

        super().__init__(response)

    def curve(self, save: str | Path | None = None):

        return self._finish(_curve(self._target), save=save)


def _curve(response):

    data = with_channel_labels(response)
    required = [
        "nominal_wavelength_nm",
        "channel_label",
        "offset_nm",
        "support_wavelength_nm",
        "weight",
        "instrument_fwhm_nm",
    ]
    present = set[str]()

    for row in data:
        present.update(row)

    missing = [column for column in required if column not in present]

    if missing:
        raise ValueError(f"missing required plotting columns: {', '.join(missing)}")

    data = [row for row in data if row["channel_label"] == "radiance"]

    if not data:
        raise ValueError("no radiance instrument response rows")

    nominal_wavelengths = np.asarray([row["nominal_wavelength_nm"] for row in data], dtype=float)
    nearest = int(np.argmin(np.abs(nominal_wavelengths - 760.76)))
    selected = float(nominal_wavelengths[nearest])
    data = [row for row in data if as_float(row["nominal_wavelength_nm"]) == selected]
    data = sorted(data, key=lambda row: as_float(row["offset_nm"]))
    max_weight = float(np.max(np.asarray([row["weight"] for row in data], dtype=float)))

    if max_weight <= 0.0:
        raise ValueError("instrument response weights are not positive")

    data = [{**row, "normalized_response": as_float(row["weight"]) / max_weight} for row in data]
    plot_data = [row for row in data if as_float(row["weight"]) >= max_weight * 1.0e-4]

    if not plot_data:
        plot_data = data

    offsets = np.asarray([row["offset_nm"] for row in plot_data], dtype=float)
    x_min = float(np.min(offsets))
    x_max = float(np.max(offsets))
    x_pad = max((x_max - x_min) * 0.04, 0.01)
    title = f"Instrument spectral response function (ISRF), {selected:.5f} nm"

    panel = line_panel(
        title=title,
        x_title=fields.QUANTITY_LABELS["offset_nm"],
        y_title="Normalized ISRF",
        x=[as_float(row["offset_nm"]) for row in plot_data],
        y=[as_float(row["normalized_response"]) for row in plot_data],
        name=title,
        color=PLOT.colors["black"],
        marker_x=False,
    )

    panel = SvgPanel(
        title=panel.title,
        x_title=panel.x_title,
        y_title=panel.y_title,
        series=panel.series,
        width=panel.width,
        height=panel.height,
        x_domain=(x_min - x_pad, x_max + x_pad),
        y_domain=(0.0, 1.05),
    )

    return SvgFigure(
        title=title,
        panels=(panel,),
    )
