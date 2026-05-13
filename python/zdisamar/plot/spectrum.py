"""Spectrum plot accessors."""

from pathlib import Path
from typing import Any

import altair as alt

from . import fields
from .axes import marker_rules, scaled_y
from .charts import wavelength_line_chart
from .data import spectrum_frame
from .properties import PLOT, PlotAccessor


class SpectrumPlot(PlotAccessor):
    def __init__(self, spectrum: Any):
        super().__init__(spectrum)

    def reflectance(self, save: str | Path | None = None):
        return self._finish(
            _quantity_chart(self._target, fields.REFLECTANCE, show_minimum=True),
            save=save,
        )

    def radiance(self, save: str | Path | None = None):
        return self._finish(
            _quantity_chart(self._target, fields.RADIANCE, show_minimum=False),
            save=save,
        )

    def irradiance(self, save: str | Path | None = None):
        return self._finish(
            _quantity_chart(self._target, fields.IRRADIANCE, show_minimum=False),
            save=save,
        )

    def sun_normalized_radiance(self, save: str | Path | None = None):
        return self._finish(
            _quantity_chart(
                self._target,
                fields.SUN_NORMALIZED_RADIANCE,
                show_minimum=False,
            ),
            save=save,
        )

    def jacobian(self, state: str, save: str | Path | None = None):
        from .jacobian import reflectance_jacobian

        return self._finish(reflectance_jacobian(self._target, state), save=save)

    def snr(self, noise_table, save: str | Path | None = None):
        from .signal_to_noise import snr

        return self._finish(snr(self._target, noise_table), save=save)

    def noise_envelope(self, noise_table, save: str | Path | None = None):
        from .signal_to_noise import noise_envelope

        return self._finish(noise_envelope(self._target, noise_table), save=save)


def _quantity_chart(
    spectrum: Any,
    quantity: str,
    *,
    show_minimum: bool,
):
    data = spectrum_frame(spectrum)
    title = fields.QUANTITY_LABELS[quantity]
    data, y_field, y = scaled_y(data, quantity, title, axis=_quantity_axis(quantity))
    line = wavelength_line_chart(
        data,
        y,
        [
            alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
            alt.Tooltip(f"{quantity}:Q", title=title, format=".8g"),
        ],
    )
    layers = [line, marker_rules(data)]
    if show_minimum and not data.empty:
        minimum = data.loc[[data[quantity].idxmin()]]
        layers.append(
            alt.Chart(minimum)
            .mark_point(
                filled=True,
                color=PLOT.colors["black"],
                size=PLOT.minimum_point_size,
            )
            .encode(
                x=f"{fields.WAVELENGTH_NM}:Q",
                y=f"{y_field}:Q",
                tooltip=[
                    alt.Tooltip(
                        f"{fields.WAVELENGTH_NM}:Q",
                        title="Minimum wavelength (nm)",
                        format=".4f",
                    ),
                    alt.Tooltip(f"{quantity}:Q", title="Minimum", format=".8g"),
                ],
            )
        )
    return alt.layer(*layers).properties(**PLOT.chart(title))


def _quantity_axis(quantity: str):
    if quantity in {fields.RADIANCE, fields.IRRADIANCE}:
        return alt.Axis(format=".4g", tickCount=6)
    if quantity == fields.SUN_NORMALIZED_RADIANCE:
        return alt.Axis(format=".3g")
    return alt.Axis()
