"""Signal-to-noise plots."""

from typing import Any, cast

import altair as alt

from . import fields
from .axes import finite_padded_scale, marker_rules, scaled_y, wavelength_x
from .charts import wavelength_line_chart
from .data import spectrum_frame
from .properties import PLOT


def snr(spectrum: Any, noise_table):

    data = _snr_frame(spectrum, noise_table)
    data, _, y = scaled_y(data, fields.SNR, fields.QUANTITY_LABELS[fields.SNR])
    line = wavelength_line_chart(
        data,
        y,
        [
            alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
            alt.Tooltip(f"{fields.SNR}:Q", title="SNR", format=".4g"),
        ],
    )

    return alt.layer(line, marker_rules(data)).properties(**PLOT.chart("Signal-to-noise ratio"))


def noise_envelope(spectrum: Any, noise_table):

    data = _snr_frame(spectrum, noise_table)
    signal = data[fields.SUN_NORMALIZED_RADIANCE].to_numpy(dtype=float)
    sigma = signal / data[fields.SNR].to_numpy(dtype=float)
    data = data.assign(noise_lo=signal - sigma, noise_hi=signal + sigma)
    y_scale = finite_padded_scale(data["noise_lo"].tolist() + data["noise_hi"].tolist())
    band = (
        alt.Chart(data)
        .mark_area(color=PLOT.colors["band"], opacity=PLOT.noise_band_opacity)
        .encode(
            x=wavelength_x(),
            y=alt.Y(
                "noise_lo:Q",
                title=fields.QUANTITY_LABELS[fields.SUN_NORMALIZED_RADIANCE],
                scale=y_scale,
            ),
            y2="noise_hi:Q",
        )
    )
    line = wavelength_line_chart(
        data,
        alt.Y(
            f"{fields.SUN_NORMALIZED_RADIANCE}:Q",
            title=fields.QUANTITY_LABELS[fields.SUN_NORMALIZED_RADIANCE],
            scale=y_scale,
        ),
        [
            alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
            alt.Tooltip(
                f"{fields.SUN_NORMALIZED_RADIANCE}:Q",
                title="Sun-normalized radiance",
                format=".8g",
            ),
            alt.Tooltip(f"{fields.SNR}:Q", title="SNR", format=".4g"),
        ],
    )

    return alt.layer(band, line, marker_rules(data)).properties(
        **PLOT.chart("Sun-normalized radiance noise envelope")
    )


def _snr_frame(spectrum: Any, noise_table):

    import numpy as np

    data = spectrum_frame(spectrum)
    wavelengths, snr_values = _noise_arrays(noise_table)

    if wavelengths.size != snr_values.size:
        raise ValueError("noise_table wavelengths and SNR values must have the same length")

    if wavelengths.size == 0:
        raise ValueError("noise_table must not be empty")

    if np.any(snr_values <= 0.0):
        raise ValueError("noise_table SNR values must be positive")

    data[fields.SNR] = np.interp(
        data[fields.WAVELENGTH_NM].to_numpy(dtype=float),
        wavelengths,
        snr_values,
    )

    return data


def _noise_arrays(noise_table):

    import numpy as np

    if isinstance(noise_table, tuple) and len(noise_table) == 2:
        return (
            np.asarray(noise_table[0], dtype=float),
            np.asarray(noise_table[1], dtype=float),
        )

    table = cast(Any, noise_table)

    return (
        np.asarray(table.snr_wavelengths_nm, dtype=float),
        np.asarray(table.snr_values, dtype=float),
    )
