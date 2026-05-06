"""Spectrum plots."""

from __future__ import annotations

from collections.abc import Sequence

import altair as alt

from . import fields
from .data import filter_window, marker_frame, spectrum_frame
from .theme import MATPLOTLIB_BLUE

DEFAULT_WIDTH = 1311
DEFAULT_HEIGHT = 465
CONTEXT_HEIGHT = 420
COMPACT_PANEL_HEIGHT = 360
RESIDUAL_HEIGHT = 420


def reflectance(
    spectrum,
    *,
    window_nm: tuple[float, float] | None = None,
    markers_nm: Sequence[float] = (),
    show_minimum: bool = True,
    title: str | None = None,
    width: int | None = None,
    height: int | None = None,
):
    return _quantity_chart(
        spectrum,
        fields.REFLECTANCE,
        window_nm=window_nm,
        markers_nm=markers_nm,
        show_minimum=show_minimum,
        title=title or "Reflectance",
        width=width,
        height=height,
    )


def radiance(
    spectrum,
    *,
    window_nm: tuple[float, float] | None = None,
    markers_nm: Sequence[float] = (),
    title: str | None = None,
    width: int | None = None,
    height: int | None = None,
):
    return _quantity_chart(
        spectrum,
        fields.RADIANCE,
        window_nm=window_nm,
        markers_nm=markers_nm,
        show_minimum=False,
        title=title or "Radiance",
        width=width,
        height=height,
    )


def irradiance(
    spectrum,
    *,
    window_nm: tuple[float, float] | None = None,
    markers_nm: Sequence[float] = (),
    title: str | None = None,
    width: int | None = None,
    height: int | None = None,
):
    return _quantity_chart(
        spectrum,
        fields.IRRADIANCE,
        window_nm=window_nm,
        markers_nm=markers_nm,
        show_minimum=False,
        title=title or "Irradiance",
        width=width,
        height=height,
    )


def triplet(
    spectrum,
    *,
    window_nm: tuple[float, float] | None = None,
    markers_nm: Sequence[float] = (),
):
    return alt.vconcat(
        reflectance(
            spectrum,
            window_nm=window_nm,
            markers_nm=markers_nm,
            height=COMPACT_PANEL_HEIGHT,
        ),
        radiance(
            spectrum,
            window_nm=window_nm,
            markers_nm=markers_nm,
            height=COMPACT_PANEL_HEIGHT,
        ),
        irradiance(
            spectrum,
            window_nm=window_nm,
            markers_nm=markers_nm,
            height=COMPACT_PANEL_HEIGHT,
        ),
    ).resolve_scale(x="shared")


def full_sample_context(
    spectrum,
    *,
    quantity: str = fields.REFLECTANCE,
    markers_nm: Sequence[float] = (),
    title: str = "Full sampled spectrum",
    width: int = DEFAULT_WIDTH,
    height: int = CONTEXT_HEIGHT,
):
    frame = spectrum_frame(spectrum, None)
    frame, y_field, y_axis = _plot_frame(frame, quantity)
    line = (
        alt.Chart(frame)
        .mark_line(color=MATPLOTLIB_BLUE, strokeWidth=1.4)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(
                f"{y_field}:Q",
                title=fields.QUANTITY_LABELS.get(quantity, quantity),
                axis=y_axis,
            ),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(
                    f"{quantity}:Q",
                    title=fields.QUANTITY_LABELS.get(quantity, quantity),
                    format=".8g",
                ),
            ],
        )
        .properties(width=width, height=height, title=title)
    )
    layers = [line]
    if markers_nm:
        layers.append(_marker_rules(markers_nm, None))
    return alt.layer(*layers)


def with_full_sample_spectrum(
    chart,
    spectrum,
    *,
    quantity: str = fields.REFLECTANCE,
    markers_nm: Sequence[float] = (),
):
    return alt.vconcat(
        full_sample_context(spectrum, quantity=quantity, markers_nm=markers_nm),
        chart,
    ).resolve_scale(x="independent")


def marker_strip(
    markers_nm: Sequence[float],
    *,
    window_nm: tuple[float, float] | None = None,
    width: int = DEFAULT_WIDTH,
    height: int = 34,
):
    frame = filter_window(marker_frame(markers_nm), window_nm)
    if frame.empty:
        return alt.Chart(frame).mark_tick().properties(width=width, height=height)
    return (
        alt.Chart(frame)
        .mark_tick(color="#111111", thickness=1.2, size=18)
        .encode(
            x=alt.X(
                f"{fields.WAVELENGTH_NM}:Q",
                title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
            ),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".3f")
            ],
        )
        .properties(width=width, height=height, title="Selected wavelengths")
    )


def micro_window_marker_spectrum(
    spectrum,
    *,
    windows: dict[str, tuple[float, float]] | None = None,
    markers_nm: Sequence[float] = (),
    window_nm: tuple[float, float] | None = (755.0, 776.0),
):
    import pandas as pd

    windows = windows or {"O2 A band": (755.0, 776.0)}
    chart = reflectance(
        spectrum,
        window_nm=window_nm,
        markers_nm=markers_nm,
        show_minimum=False,
        title="Micro-window reflectance",
    )
    rows = [
        {"window": name, "start_nm": float(bounds[0]), "end_nm": float(bounds[1])}
        for name, bounds in windows.items()
    ]
    bands = (
        alt.Chart(pd.DataFrame.from_records(rows))
        .mark_rect(color="#D9D9D9", opacity=0.35)
        .encode(
            x="start_nm:Q",
            x2="end_nm:Q",
            tooltip=[
                alt.Tooltip("window:N", title="Window"),
                alt.Tooltip("start_nm:Q", title="Start (nm)", format=".3f"),
                alt.Tooltip("end_nm:Q", title="End (nm)", format=".3f"),
            ],
        )
    )
    return alt.layer(bands, chart).resolve_scale(y="independent")


def _quantity_chart(
    spectrum,
    quantity: str,
    *,
    window_nm: tuple[float, float] | None,
    markers_nm: Sequence[float],
    show_minimum: bool,
    title: str,
    width: int | None,
    height: int | None,
):
    frame = spectrum_frame(spectrum, window_nm)
    frame, y_field, y_axis = _plot_frame(frame, quantity)
    line = (
        alt.Chart(frame)
        .mark_line(color=MATPLOTLIB_BLUE, strokeWidth=1.4)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(
                f"{y_field}:Q",
                title=fields.QUANTITY_LABELS.get(quantity, quantity),
                axis=y_axis,
            ),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(
                    f"{quantity}:Q",
                    title=fields.QUANTITY_LABELS.get(quantity, quantity),
                    format=".8g",
                ),
            ],
        )
        .properties(width=width or DEFAULT_WIDTH, height=height or DEFAULT_HEIGHT, title=title)
    )
    layers = [line]
    if markers_nm:
        layers.append(_marker_rules(markers_nm, window_nm))
    if show_minimum and not frame.empty:
        minimum = frame.loc[[frame[quantity].idxmin()]]
        layers.append(
            alt.Chart(minimum)
            .mark_point(filled=True, color="#111111", size=35)
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
    return alt.layer(*layers)


def _marker_rules(markers_nm: Sequence[float], window_nm: tuple[float, float] | None):
    return (
        alt.Chart(filter_window(marker_frame(markers_nm), window_nm))
        .mark_rule(color="#737373", strokeDash=[4, 3], strokeWidth=0.8)
        .encode(x=f"{fields.WAVELENGTH_NM}:Q")
    )


def _wavelength_x():
    return alt.X(
        f"{fields.WAVELENGTH_NM}:Q",
        title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        axis=alt.Axis(tickMinStep=5),
    )


def _plot_frame(frame, quantity: str):
    if quantity == fields.RADIANCE:
        return frame, quantity, alt.Axis(format=".2e", tickCount=6)
    return frame, quantity, alt.Axis()
