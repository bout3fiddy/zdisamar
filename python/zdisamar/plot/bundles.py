"""Multi-panel plot bundles."""

from __future__ import annotations

from collections.abc import Sequence

import altair as alt

from . import fields
from . import spectrum as spectrum_plots
from . import validation


def o2a_forward_summary(
    spectrum,
    *,
    case=None,
    markers_nm: Sequence[float] = (755.0, 760.76, 776.0),
    window_nm: tuple[float, float] | None = None,
):
    _ = case
    panels = [
        spectrum_plots.reflectance(
            spectrum,
            window_nm=window_nm,
            markers_nm=markers_nm,
            height=spectrum_plots.COMPACT_PANEL_HEIGHT,
        ),
        spectrum_plots.radiance(
            spectrum,
            window_nm=window_nm,
            markers_nm=markers_nm,
            height=spectrum_plots.COMPACT_PANEL_HEIGHT,
        ),
        spectrum_plots.irradiance(
            spectrum,
            window_nm=window_nm,
            markers_nm=markers_nm,
            height=spectrum_plots.COMPACT_PANEL_HEIGHT,
        ),
    ]
    if markers_nm:
        panels.append(spectrum_plots.marker_strip(markers_nm, window_nm=window_nm))
    return alt.vconcat(*panels).resolve_scale(x="shared")


def validation_against_reference(
    current,
    reference,
    *,
    quantities: Sequence[str] = (fields.REFLECTANCE, fields.RADIANCE, fields.IRRADIANCE),
    window_nm: tuple[float, float] | None = None,
):
    panels = []
    for quantity in quantities:
        panels.append(validation.overlay(current, reference, quantity=quantity, window_nm=window_nm))
        panels.append(validation.residual(current, reference, quantity=quantity, window_nm=window_nm))
    if quantities:
        panels.append(validation.residual_histogram(current, reference, quantity=quantities[0]))
    panels.append(validation.metrics_bar(current, reference, quantities=quantities))
    return alt.vconcat(*panels).resolve_scale(color="independent")
