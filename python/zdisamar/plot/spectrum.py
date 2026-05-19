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

        return self.finish_plot(
            quantity_chart(self.target, fields.REFLECTANCE),
            save=save,
        )

    def radiance(self, save: str | Path | None = None):

        return self.finish_plot(
            quantity_chart(self.target, fields.RADIANCE),
            save=save,
        )

    def irradiance(self, save: str | Path | None = None):

        return self.finish_plot(
            quantity_chart(self.target, fields.IRRADIANCE),
            save=save,
        )

    def sun_normalized_radiance(self, save: str | Path | None = None):

        return self.finish_plot(
            quantity_chart(
                self.target,
                fields.SUN_NORMALIZED_RADIANCE,
            ),
            save=save,
        )

    def jacobian(self, state: str, save: str | Path | None = None):
        """Plot reflectance Jacobians because OE works in reflectance space."""

        from .jacobian import reflectance_jacobian

        return self.finish_plot(reflectance_jacobian(self.target, state), save=save)

    def snr(self, noise_table, save: str | Path | None = None):

        from .signal_to_noise import snr

        return self.finish_plot(snr(self.target, noise_table), save=save)

    def noise_envelope(self, noise_table, save: str | Path | None = None):

        from .signal_to_noise import noise_envelope

        return self.finish_plot(noise_envelope(self.target, noise_table), save=save)


def quantity_chart(
    spectrum,
    quantity: str,
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

    return SvgFigure(title=title, panels=(panel,))
