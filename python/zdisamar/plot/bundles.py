"""Multi-panel plot bundles."""

from __future__ import annotations

from collections.abc import Sequence

import altair as alt

from . import atmosphere, cia, fields, o2_lines, perturbation
from . import instrument_response as instrument_response_plots
from . import radiative_transfer as radiative_transfer_plots
from . import spectrum as spectrum_plots
from . import validation
from ._common import nearest_wavelength_rows


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


def o2_line_window(
    spectrum,
    lines,
    *,
    center_nm: float = 760.76,
    window_nm: tuple[float, float] | None = None,
    top_n: int = 25,
):
    return o2_lines.window(spectrum, lines, center_nm=center_nm, window_nm=window_nm, top_n=top_n)


def atmospheric_budget(budget, *, markers_nm=(755.0, 760.76, 776.0)):
    selected = tuple(markers_nm)
    return alt.vconcat(
        atmosphere.optical_depth_heatmap(budget, markers_nm=selected),
        atmosphere.component_stack(budget),
        alt.hconcat(
            atmosphere.optical_depth_profile(budget, wavelengths_nm=selected),
            atmosphere.single_scatter_albedo_profile(budget, wavelengths_nm=selected),
        ),
    ).resolve_scale(color="independent")


def cia_budget(cia_table, *, wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0)):
    selected = nearest_wavelength_rows(cia_table, wavelengths_nm)
    return alt.vconcat(
        alt.hconcat(cia.share_spectrum(cia_table), cia.share_profile(selected)),
        alt.hconcat(
            atmosphere.optical_depth_profile(selected, quantity=fields.CIA_OPTICAL_DEPTH, wavelengths_nm=wavelengths_nm),
            cia.cross_section_temperature(selected),
        ),
    ).resolve_scale(color="independent")


def instrument_response_bundle(response, *, nominal_wavelength_nm: float = 760.76):
    return instrument_response_plots.isrf(response, nominal_wavelength_nm=nominal_wavelength_nm)


def instrument_response(response, *, nominal_wavelength_nm: float = 760.76):
    return instrument_response_bundle(response, nominal_wavelength_nm=nominal_wavelength_nm)


def radiative_transfer_budget(rt, *, wavelengths_nm: Sequence[float] = (755.0, 760.76, 776.0)):
    selected = nearest_wavelength_rows(rt, wavelengths_nm)
    return alt.hconcat(
        radiative_transfer_plots.cumulative_transmission(selected),
        radiative_transfer_plots.source_profile(selected),
    ).resolve_scale(color="independent")


def perturbation_sensitivity(results):
    return alt.vconcat(
        perturbation.delta_reflectance(results),
        perturbation.abs_delta_reflectance(results),
        perturbation.delta_heatmap(results),
        perturbation.summary_bar(results),
    ).resolve_scale(color="independent")
