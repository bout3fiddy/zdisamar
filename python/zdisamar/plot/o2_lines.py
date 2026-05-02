"""O2 line-contribution plots."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

import altair as alt

from . import fields, spectrum as spectrum_plots
from ._common import frame, label
from .data import filter_window, to_dataframe
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH
from .theme import SEMANTIC_COLORS


def window(
    spectrum,
    lines,
    *,
    center_nm: float | None = None,
    window_nm: tuple[float, float] | None = None,
    top_n: int = 40,
    contribution: str = "abs_total_sigma_cm2_per_molecule",
):
    line_frame = _with_labels(lines)
    if window_nm is None:
        center = center_nm if center_nm is not None else float(line_frame[fields.WAVELENGTH_NM].median())
        window_nm = (center - 0.5, center + 0.5)
    top = spectrum_plots.reflectance(
        spectrum,
        window_nm=window_nm,
        show_minimum=False,
        title="Reflectance line window",
        height=260,
    )
    filtered_lines = filter_window(line_frame, window_nm)
    stems = contribution_stems(
        filtered_lines,
        contribution=contribution,
        top_n=top_n,
        facet_by_wavelength=False,
        log_y=True,
    )
    partition = partition_bar(filtered_lines)
    status = status_counts(filtered_lines)
    return alt.vconcat(top, stems, alt.hconcat(partition, status)).resolve_scale(x="independent")


def contribution_stems(
    lines,
    *,
    contribution: str = "abs_total_sigma_cm2_per_molecule",
    top_n: int = 60,
    facet_by_wavelength: bool = True,
    log_y: bool = True,
):
    data = _top_contributions(_with_labels(lines), contribution, top_n)
    y_scale = alt.Scale(type="log") if log_y else alt.Scale()
    bars = (
        alt.Chart(data)
        .mark_bar(width=2, color=SEMANTIC_COLORS["o2_strong_lines"])
        .encode(
            x=alt.X("center_wavelength_nm:Q", title="Line center (nm)"),
            y=alt.Y(f"{contribution}:Q", title=label(contribution), scale=y_scale),
            color=alt.Color("row_kind_label:N", title="Line kind"),
            tooltip=[
                alt.Tooltip("center_wavelength_nm:Q", title="Line center (nm)", format=".5f"),
                alt.Tooltip(f"{contribution}:Q", title=label(contribution), format=".3e"),
                alt.Tooltip("status_label:N", title="Status"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="O2 line contribution stems")
    )
    if facet_by_wavelength and data[fields.WAVELENGTH_NM].nunique() > 1:
        return bars.facet(column=alt.Column(f"{fields.WAVELENGTH_NM}:N", title="Sample wavelength (nm)"))
    return bars


def partition_bar(
    lines,
    *,
    components: Sequence[str] = (
        "weak_line_sigma_cm2_per_molecule",
        "strong_line_sigma_cm2_per_molecule",
        "line_mixing_sigma_cm2_per_molecule",
    ),
    absolute: bool = True,
):
    data = to_dataframe(lines)
    rows = []
    for component in components:
        if component not in data.columns:
            continue
        values = data[component].abs() if absolute else data[component]
        rows.append({"component": component, fields.VALUE: float(values.sum())})
    import pandas as pd

    plot_frame = pd.DataFrame.from_records(rows)
    return (
        alt.Chart(plot_frame)
        .mark_bar()
        .encode(
            x=alt.X("component:N", title="Component"),
            y=alt.Y(f"{fields.VALUE}:Q", title="Sum absolute sigma" if absolute else "Sum sigma"),
            color=alt.Color("component:N", title="Component"),
            tooltip=[alt.Tooltip("component:N"), alt.Tooltip(f"{fields.VALUE}:Q", format=".3e")],
        )
        .properties(width=420, height=300, title="O2 line partition")
    )


def status_counts(lines):
    data = _with_labels(lines)
    return (
        alt.Chart(data)
        .mark_bar(color=SEMANTIC_COLORS["o2_weak_lines"])
        .encode(
            x=alt.X("status_label:N", title="Status"),
            y=alt.Y("count():Q", title="Rows"),
            color=alt.Color("row_kind_label:N", title="Line kind"),
            tooltip=[alt.Tooltip("status_label:N"), alt.Tooltip("count():Q", title="Rows")],
        )
        .properties(width=420, height=300, title="O2 line status counts")
    )


def isotope_bar(
    lines,
    *,
    value: str = "abs_total_sigma_cm2_per_molecule",
    aggregate: Literal["sum", "max"] = "sum",
):
    data = frame(lines, ["isotope_number", value])
    grouped = data.groupby("isotope_number", as_index=False)[value].agg(aggregate)
    return (
        alt.Chart(grouped)
        .mark_bar(color=SEMANTIC_COLORS["o2_strong_lines"])
        .encode(
            x=alt.X("isotope_number:N", title="Isotope"),
            y=alt.Y(f"{value}:Q", title=f"{aggregate} {label(value)}"),
            tooltip=[alt.Tooltip("isotope_number:N"), alt.Tooltip(f"{value}:Q", format=".3e")],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="O2 isotope contribution")
    )


def cross_section_profile(
    lines,
    *,
    value: str = "abs_total_sigma_cm2_per_molecule",
    vertical_axis: Literal["altitude_km", "pressure_hpa"] = "altitude_km",
    top_n: int = 8,
):
    data = _top_contributions(_with_labels(lines), value, top_n)
    return (
        alt.Chart(data)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{value}:Q", title=label(value), scale=alt.Scale(type="log")),
            y=_vertical_y(vertical_axis),
            color=alt.Color("center_wavelength_nm:N", title="Line center (nm)"),
            tooltip=[
                alt.Tooltip("center_wavelength_nm:Q", title="Line center (nm)", format=".5f"),
                alt.Tooltip(f"{vertical_axis}:Q", title=label(vertical_axis), format=".4g"),
                alt.Tooltip(f"{value}:Q", title=label(value), format=".3e"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="O2 cross-section profile")
    )


def _with_labels(lines):
    data = to_dataframe(lines)
    if "row_kind_label" not in data.columns and "row_kind" in data.columns:
        data["row_kind_label"] = data["row_kind"].map({0: "weak_line", 1: "strong_line"}).fillna("unknown")
    if "status_label" not in data.columns and "status" in data.columns:
        data["status_label"] = data["status"].map(
            {
                0: "weak_included",
                1: "weak_excluded_by_strong_line",
                2: "strong_sidecar",
                3: "weak_zero_after_cutoff",
            }
        ).fillna("unknown")
    return data


def _top_contributions(data, contribution: str, top_n: int):
    require = [fields.WAVELENGTH_NM, "center_wavelength_nm", contribution]
    for column in require:
        if column not in data.columns:
            raise ValueError(f"missing required plotting column: {column}")
    data = data[data[contribution] > 0.0].copy()
    return data.nlargest(top_n, contribution) if top_n else data


def _vertical_y(vertical_axis: str):
    if vertical_axis == "pressure_hpa":
        return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis), scale=alt.Scale(reverse=True))
    return alt.Y(f"{vertical_axis}:Q", title=label(vertical_axis))
