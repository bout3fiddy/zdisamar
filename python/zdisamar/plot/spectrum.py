"""Spectrum plot accessors."""

from pathlib import Path

from . import fields
from .data import column_values, spectrum_frame
from .properties import PLOT, PlotAccessor
from .svg import SvgFigure, line_panel


class SpectrumPlot(PlotAccessor):
    """Plots for the spectral quantities returned by one O2 A run."""

    def __init__(self, spectrum):

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
        """Plot reflectance Jacobians because OE works in reflectance space."""

        from .jacobian import reflectance_jacobian

        return self._finish(reflectance_jacobian(self._target, state), save=save)

    def snr(self, noise_table, save: str | Path | None = None):

        from .signal_to_noise import snr

        return self._finish(snr(self._target, noise_table), save=save)

    def noise_envelope(self, noise_table, save: str | Path | None = None):

        from .signal_to_noise import noise_envelope

        return self._finish(noise_envelope(self._target, noise_table), save=save)


def _quantity_chart(
    spectrum,
    quantity: str,
    *,
    show_minimum: bool,
):

    data = spectrum_frame(spectrum)
    title = fields.QUANTITY_LABELS[quantity]
    x = column_values(data, fields.WAVELENGTH_NM)
    y = column_values(data, quantity)
    panel = line_panel(
        title=title,
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title=title,
        x=x,
        y=y,
        name=title,
        color=PLOT.colors.get(quantity, PLOT.colors["blue"]),
    )

    _ = show_minimum

    return SvgFigure(title=title, panels=(panel,))
