"""Private reflectance-jacobian plots."""

from typing import Any

import altair as alt

from . import fields
from .axes import marker_rules, scaled_y, wavelength_x
from .properties import PLOT


def reflectance_jacobian(spectrum: Any, state: str):
    data, y_field, y_title = _jacobian_frame(spectrum, state)
    data, _, y = scaled_y(data, y_field, y_title)
    line = (
        alt.Chart(data)
        .mark_line(color=PLOT.colors["blue"], strokeWidth=PLOT.line_width)
        .encode(
            x=wavelength_x(),
            y=y,
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{y_field}:Q", title=y_title, format=".8g"),
            ],
        )
    )
    return alt.layer(line, marker_rules(data)).properties(
        **PLOT.chart(f"{y_title}: {state}")
    )


def _jacobian_frame(spectrum: Any, state: str):
    import pandas as pd

    names = spectrum.jacobian_state_names
    if state not in names:
        raise ValueError(f"unknown Jacobian state: {state}")
    index = names.index(state)
    wavelength_nm = spectrum.wavelength_nm.copy()
    try:
        reflectance_jacobian = spectrum.reflectance_jacobian(state).copy()
    except RuntimeError:
        radiance_jacobian = spectrum.radiance_jacobian[:, index].copy()
        return (
            pd.DataFrame(
                {
                    fields.WAVELENGTH_NM: wavelength_nm,
                    fields.RADIANCE_JACOBIAN: radiance_jacobian,
                }
            ),
            fields.RADIANCE_JACOBIAN,
            "dL / dx",
        )
    return (
        pd.DataFrame(
            {
                fields.WAVELENGTH_NM: wavelength_nm,
                fields.REFLECTANCE_JACOBIAN: reflectance_jacobian,
            }
        ),
        fields.REFLECTANCE_JACOBIAN,
        fields.QUANTITY_LABELS[fields.REFLECTANCE_JACOBIAN],
    )
