"""Signal-to-noise plots."""

import numpy as np

from . import fields
from .data import column_values, spectrum_frame
from .properties import PLOT
from .svg import SvgFigure, SvgPanel, SvgSeries, line_panel


def snr(spectrum, noise_table):

    data = snr_frame(spectrum, noise_table)
    title = fields.QUANTITY_LABELS[fields.SNR]
    panel = line_panel(
        title=title,
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title=title,
        x=column_values(data, fields.WAVELENGTH_NM),
        y=column_values(data, fields.SNR),
        name=title,
    )

    return SvgFigure(title="Signal-to-noise ratio", panels=(panel,))


def noise_envelope(spectrum, noise_table):

    data = snr_frame(spectrum, noise_table)
    x = column_values(data, fields.WAVELENGTH_NM)
    signal = np.asarray(column_values(data, fields.SUN_NORMALIZED_RADIANCE), dtype=float)
    snr_values = np.asarray(column_values(data, fields.SNR), dtype=float)
    sigma = signal / snr_values
    title = "Sun-normalized radiance noise envelope"
    y_title = fields.QUANTITY_LABELS[fields.SUN_NORMALIZED_RADIANCE]
    panel = SvgPanel(
        title=title,
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title=y_title,
        series=(
            SvgSeries.band("noise envelope", x, signal - sigma, signal + sigma),
            SvgSeries.line(
                y_title,
                x,
                signal,
                color=PLOT.colors["sun_normalized_radiance"],
            ),
        ),
        marker_x=tuple(value for value in PLOT.markers_nm if min(x) <= value <= max(x)),
    )

    return SvgFigure(title=title, panels=(panel,))


def snr_frame(spectrum, noise_table):

    data = spectrum_frame(spectrum)
    wavelengths, snr_values = noise_arrays(noise_table)

    if wavelengths.size != snr_values.size:
        raise ValueError("noise_table wavelengths and SNR values must have the same length")

    if wavelengths.size == 0:
        raise ValueError("noise_table must not be empty")

    if np.any(snr_values <= 0.0):
        raise ValueError("noise_table SNR values must be positive")

    interpolated = np.interp(column_values(data, fields.WAVELENGTH_NM), wavelengths, snr_values)

    return [
        {**row, fields.SNR: float(value)} for row, value in zip(data, interpolated, strict=True)
    ]


def noise_arrays(noise_table):

    if isinstance(noise_table, tuple) and len(noise_table) == 2:
        return (
            np.asarray(noise_table[0], dtype=float),
            np.asarray(noise_table[1], dtype=float),
        )

    return (
        np.asarray(getattr(noise_table, "snr_wavelengths_nm"), dtype=float),  # noqa: B009
        np.asarray(getattr(noise_table, "snr_values"), dtype=float),  # noqa: B009
    )
