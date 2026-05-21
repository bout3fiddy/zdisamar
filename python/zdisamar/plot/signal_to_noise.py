"""Signal-to-noise plots."""

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
        show_legend=False,
    )

    return SvgFigure(title="Signal-to-noise ratio", panels=(panel,))


def noise_envelope(spectrum, noise_table):

    data = snr_frame(spectrum, noise_table)
    x = column_values(data, fields.WAVELENGTH_NM)
    signal = column_values(data, fields.SUN_NORMALIZED_RADIANCE)
    snr_values = column_values(data, fields.SNR)
    sigma = [value / snr for value, snr in zip(signal, snr_values, strict=True)]
    title = "Sun-normalized radiance noise envelope"
    y_title = fields.QUANTITY_LABELS[fields.SUN_NORMALIZED_RADIANCE]
    panel = SvgPanel(
        title=title,
        x_title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        y_title=y_title,
        series=(
            SvgSeries.band(
                "noise envelope",
                x,
                [value - spread for value, spread in zip(signal, sigma, strict=True)],
                [value + spread for value, spread in zip(signal, sigma, strict=True)],
            ),
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

    if len(wavelengths) != len(snr_values):
        raise ValueError("noise_table wavelengths and SNR values must have the same length")

    if not wavelengths:
        raise ValueError("noise_table must not be empty")

    if any(value <= 0.0 for value in snr_values):
        raise ValueError("noise_table SNR values must be positive")

    interpolated = [
        _interpolate(float(wavelength), wavelengths, snr_values)
        for wavelength in column_values(data, fields.WAVELENGTH_NM)
    ]

    return [
        {**row, fields.SNR: float(value)} for row, value in zip(data, interpolated, strict=True)
    ]


def noise_arrays(noise_table):

    if isinstance(noise_table, tuple) and len(noise_table) == 2:
        return (
            tuple(float(value) for value in noise_table[0]),
            tuple(float(value) for value in noise_table[1]),
        )

    return (
        tuple(float(value) for value in getattr(noise_table, "snr_wavelengths_nm")),  # noqa: B009
        tuple(float(value) for value in getattr(noise_table, "snr_values")),  # noqa: B009
    )


def _interpolate(x_value: float, x: tuple[float, ...], y: tuple[float, ...]) -> float:

    if x_value <= x[0]:
        return y[0]

    if x_value >= x[-1]:
        return y[-1]

    for index in range(1, len(x)):
        if x_value <= x[index]:
            lower_x = x[index - 1]
            upper_x = x[index]
            fraction = (x_value - lower_x) / (upper_x - lower_x)

            return y[index - 1] + fraction * (y[index] - y[index - 1])

    return y[-1]
