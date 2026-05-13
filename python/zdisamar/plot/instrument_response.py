"""Instrument-response plot accessor."""

from pathlib import Path
from typing import Any, cast

import altair as alt

from .data import with_channel_labels
from .properties import PLOT, PlotAccessor


class InstrumentResponsePlot(PlotAccessor):
    """Plots for instrument response support weights."""

    def __init__(self, response: Any):

        super().__init__(response)

    def curve(self, save: str | Path | None = None):

        return self._finish(_curve(self._target), save=save)


def _curve(response: Any):

    data = cast(Any, with_channel_labels(response))
    required = [
        "nominal_wavelength_nm",
        "channel_label",
        "offset_nm",
        "support_wavelength_nm",
        "weight",
        "instrument_fwhm_nm",
    ]
    missing = [column for column in required if column not in data.columns]

    if missing:
        raise ValueError(f"missing required plotting columns: {', '.join(missing)}")

    data = data[data["channel_label"] == "radiance"].copy()

    if data.empty:
        raise ValueError("no radiance instrument response rows")

    nearest = (data["nominal_wavelength_nm"] - 760.76).abs().idxmin()
    selected = float(data.loc[nearest, "nominal_wavelength_nm"])
    data = data[data["nominal_wavelength_nm"] == selected].sort_values("offset_nm").copy()
    max_weight = float(data["weight"].max())

    if max_weight <= 0.0:
        raise ValueError("instrument response weights are not positive")

    data["normalized_response"] = data["weight"] / max_weight
    plot_data = data[data["weight"] >= max_weight * 1.0e-4].copy()

    if plot_data.empty:
        plot_data = data

    x_min = float(plot_data["offset_nm"].min())
    x_max = float(plot_data["offset_nm"].max())
    x_pad = max((x_max - x_min) * 0.04, 0.01)
    title = f"Instrument spectral response function (ISRF), {selected:.5f} nm"

    return (
        alt.Chart(plot_data)
        .mark_line(color=PLOT.colors["black"], strokeWidth=PLOT.isrf_line_width)
        .encode(
            x=alt.X(
                "offset_nm:Q",
                title="Offset from nominal wavelength (nm)",
                scale=alt.Scale(domain=[x_min - x_pad, x_max + x_pad], zero=False),
            ),
            y=alt.Y(
                "normalized_response:Q",
                title="Normalized ISRF",
                scale=alt.Scale(domain=[0.0, 1.05]),
                axis=alt.Axis(format=".2f"),
            ),
            tooltip=[
                alt.Tooltip(
                    "nominal_wavelength_nm:Q",
                    title="Nominal wavelength (nm)",
                    format=".5f",
                ),
                alt.Tooltip(
                    "support_wavelength_nm:Q",
                    title="Support wavelength (nm)",
                    format=".5f",
                ),
                alt.Tooltip("offset_nm:Q", title="Offset (nm)", format=".6f"),
                alt.Tooltip("normalized_response:Q", title="Normalized ISRF", format=".5f"),
                alt.Tooltip("weight:Q", title="Native weight", format=".5g"),
                alt.Tooltip("instrument_fwhm_nm:Q", title="FWHM (nm)", format=".5f"),
            ],
        )
        .properties(**PLOT.chart(title))
    )
