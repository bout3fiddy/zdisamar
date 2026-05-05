"""O2 line-contribution plots."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Literal

import altair as alt

from . import fields, spectrum as spectrum_plots
from .common import frame, label
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
    ranked = contribution_rank(
        filtered_lines,
        contribution=contribution,
        top_n=top_n,
    )
    partition = partition_bar(filtered_lines)
    status = status_counts(filtered_lines)
    return alt.vconcat(top, ranked, alt.hconcat(partition, status)).resolve_scale(x="independent", color="independent")


def contribution_rank(
    lines,
    *,
    contribution: str = "abs_total_sigma_cm2_per_molecule",
    top_n: int = 40,
):
    data = _top_contributions(_with_labels(lines), contribution, top_n).copy()
    data = data.sort_values(contribution, ascending=True).reset_index(drop=True)
    data["rank"] = range(len(data), 0, -1)
    data["line_label"] = data["rank"].map(lambda value: f"#{value}")
    data, scaled_field, scaled_title = _scaled_scientific_frame(data, contribution, label(contribution))
    return (
        alt.Chart(data)
        .mark_bar()
        .encode(
            x=alt.X(f"{scaled_field}:Q", title=scaled_title, axis=alt.Axis(format=".3g")),
            y=alt.Y("line_label:N", title="Top line rank", sort="-x"),
            color=alt.Color("row_kind_display:N", title="Line kind", legend=alt.Legend(orient="right")),
            tooltip=[
                alt.Tooltip("line_label:N", title="Rank"),
                alt.Tooltip("center_wavelength_nm:Q", title="Line center (nm)", format=".8f"),
                alt.Tooltip(f"{contribution}:Q", title=label(contribution), format=".3e"),
                alt.Tooltip("altitude_km:Q", title="Altitude (km)", format=".3f"),
                alt.Tooltip("status_display:N", title="Status"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=440, title="Top O2 line contributors")
    )


def contribution_stems(
    lines,
    *,
    contribution: str = "abs_total_sigma_cm2_per_molecule",
    top_n: int = 60,
    facet_by_wavelength: bool = True,
    log_y: bool = True,
):
    data = _top_contributions(_with_labels(lines), contribution, top_n)
    data, scaled_field, scaled_title = _scaled_scientific_frame(data, contribution, label(contribution))
    if log_y:
        positive = data[data[scaled_field] > 0.0][scaled_field]
        stem_base = float(positive.min()) * 0.7 if not positive.empty else 1.0
        y_scale = alt.Scale(type="log", domain=[stem_base, float(positive.max()) * 1.2]) if not positive.empty else alt.Scale()
        y_axis = alt.Axis(format=".2g")
    else:
        stem_base = 0.0
        y_scale = alt.Scale()
        y_axis = alt.Axis(format=".2g")
    data = data.copy()
    data["_stem_base"] = stem_base
    base = alt.Chart(data).encode(
        x=alt.X("center_wavelength_nm:Q", title="Line center (nm)", scale=alt.Scale(zero=False)),
        color=alt.Color("row_kind_display:N", title="Line kind", legend=alt.Legend(orient="right")),
        tooltip=[
            alt.Tooltip("center_wavelength_nm:Q", title="Line center (nm)", format=".5f"),
            alt.Tooltip(f"{contribution}:Q", title=label(contribution), format=".3e"),
            alt.Tooltip("status_display:N", title="Status"),
        ],
    )
    stems = base.mark_rule(strokeWidth=1.0).encode(
        y=alt.Y("_stem_base:Q", title=scaled_title, scale=y_scale, axis=y_axis),
        y2=f"{scaled_field}:Q",
    )
    points = base.mark_point(filled=True, size=42).encode(
        y=alt.Y(f"{scaled_field}:Q", title=scaled_title, scale=y_scale, axis=y_axis)
    )
    chart = (
        alt.layer(stems, points)
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="O2 line contribution stems")
    )
    if facet_by_wavelength and data[fields.WAVELENGTH_NM].nunique() > 1:
        return chart.facet(column=alt.Column(f"{fields.WAVELENGTH_NM}:N", title="Sample wavelength (nm)"))
    return chart


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
        rows.append(
            {
                "component": component,
                "component_label": _LINE_COMPONENT_DISPLAY.get(component, label(component)),
                fields.VALUE: float(values.sum()),
            }
        )
    import pandas as pd

    plot_frame = pd.DataFrame.from_records(rows)
    plot_frame, scaled_field, scaled_title = _scaled_scientific_frame(
        plot_frame,
        fields.VALUE,
        "Sum absolute sigma" if absolute else "Sum sigma",
    )
    return (
        alt.Chart(plot_frame)
        .mark_bar()
        .encode(
            x=alt.X("component_label:N", title="Component", axis=alt.Axis(labelAngle=0, labelLimit=240)),
            y=alt.Y(f"{scaled_field}:Q", title=scaled_title, axis=alt.Axis(format=".3g")),
            color=alt.Color("component_label:N", title="Component", legend=None),
            tooltip=[alt.Tooltip("component_label:N"), alt.Tooltip(f"{fields.VALUE}:Q", format=".3e")],
        )
        .properties(width=420, height=300, title="O2 line partition")
    )


def status_counts(lines):
    data = _with_labels(lines)
    return (
        alt.Chart(data)
        .mark_bar(color=SEMANTIC_COLORS["o2_weak_lines"])
        .encode(
            x=alt.X("status_display:N", title="Status", axis=alt.Axis(labelAngle=0, labelLimit=180)),
            y=alt.Y("count():Q", title="Rows"),
            color=alt.Color("row_kind_display:N", title="Line kind", legend=alt.Legend(orient="right")),
            tooltip=[alt.Tooltip("status_display:N", title="Status"), alt.Tooltip("count():Q", title="Rows")],
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
    data = to_dataframe(lines).copy()
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
    import pandas as pd

    row_kind = data["row_kind_label"].astype(str) if "row_kind_label" in data.columns else pd.Series("unknown", index=data.index)
    status = data["status_label"].astype(str) if "status_label" in data.columns else pd.Series("unknown", index=data.index)
    data["row_kind_display"] = row_kind.map(_ROW_KIND_DISPLAY).fillna(row_kind.str.replace("_", " "))
    data["status_display"] = status.map(_STATUS_DISPLAY).fillna(status.str.replace("_", " "))
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


def _scaled_scientific_frame(data, value_field: str, title: str):
    import math
    import numpy as np

    result = data.copy()
    if result.empty or value_field not in result.columns:
        result["_scaled_value"] = []
        return result, "_scaled_value", title
    values = result[value_field].to_numpy(dtype=float)
    finite = values[np.isfinite(values) & (values != 0.0)]
    if finite.size == 0:
        result["_scaled_value"] = result[value_field]
        return result, "_scaled_value", title
    exponent = int(math.floor(math.log10(float(np.max(np.abs(finite))))))
    scale = 10.0**exponent
    result["_scaled_value"] = result[value_field] / scale
    if exponent == 0:
        return result, "_scaled_value", title
    return result, "_scaled_value", f"{title} (x 10^{exponent})"


_ROW_KIND_DISPLAY = {
    "weak_line": "Weak line",
    "strong_line": "Strong line",
}

_STATUS_DISPLAY = {
    "weak_included": "Included",
    "weak_excluded_by_strong_line": "Excluded",
    "strong_sidecar": "Sidecar",
    "weak_zero_after_cutoff": "Cutoff",
}

_LINE_COMPONENT_DISPLAY = {
    "weak_line_sigma_cm2_per_molecule": "Weak",
    "strong_line_sigma_cm2_per_molecule": "Strong",
    "line_mixing_sigma_cm2_per_molecule": "Line mixing",
}
