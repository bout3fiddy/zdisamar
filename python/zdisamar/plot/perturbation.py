"""Perturbation and sensitivity plots."""

from __future__ import annotations

from typing import Literal

import altair as alt

from . import fields
from .common import label, numeric_cell_bounds
from .data import filter_window, require_columns, to_dataframe
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH
from .theme import MATPLOTLIB_RED


def delta_reflectance(
    result_or_results,
    *,
    signed: bool = True,
    window_nm: tuple[float, float] | None = None,
    show_max: bool = True,
):
    field = fields.DELTA_REFLECTANCE if signed else fields.ABS_DELTA_REFLECTANCE
    data = _results_frame(result_or_results)
    data = filter_window(data, window_nm)
    require_columns(data, [fields.WAVELENGTH_NM, field, "label"])
    line = (
        alt.Chart(data)
        .mark_line()
        .encode(
            x=alt.X(f"{fields.WAVELENGTH_NM}:Q", title=label(fields.WAVELENGTH_NM)),
            y=alt.Y(f"{field}:Q", title=label(field)),
            color=alt.Color("label:N", title="Perturbation"),
            tooltip=[
                alt.Tooltip("label:N", title="Perturbation"),
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{field}:Q", title=label(field), format=".3e"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title=label(field))
    )
    if not show_max:
        return line
    max_rows = data.loc[data.groupby("label")[fields.ABS_DELTA_REFLECTANCE].idxmax()]
    points = (
        alt.Chart(max_rows)
        .mark_point(filled=True, color=MATPLOTLIB_RED, size=45)
        .encode(x=f"{fields.WAVELENGTH_NM}:Q", y=f"{field}:Q", tooltip=[alt.Tooltip("label:N")])
    )
    return alt.layer(line, points)


def abs_delta_reflectance(
    result_or_results,
    *,
    window_nm: tuple[float, float] | None = None,
):
    return delta_reflectance(result_or_results, signed=False, window_nm=window_nm, show_max=True)


def delta_heatmap(
    results,
    *,
    interpolate: bool = True,
    signed: bool = True,
):
    _ = interpolate
    field = fields.DELTA_REFLECTANCE if signed else fields.ABS_DELTA_REFLECTANCE
    data = _results_frame(results)
    require_columns(data, [fields.WAVELENGTH_NM, field, "label"])
    data = numeric_cell_bounds(data, fields.WAVELENGTH_NM)
    scale = alt.Scale(scheme="redblue", domainMid=0) if signed else alt.Scale(scheme="greys")
    return (
        alt.Chart(data)
        .mark_rect()
        .encode(
            x=alt.X(
                "_x_start:Q",
                title=label(fields.WAVELENGTH_NM),
                scale=alt.Scale(zero=False),
                axis=alt.Axis(tickMinStep=5),
            ),
            x2="_x_end:Q",
            y=alt.Y("label:N", title="Perturbation"),
            color=alt.Color(f"{field}:Q", title=label(field), scale=scale),
            tooltip=[
                alt.Tooltip("label:N", title="Perturbation"),
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{field}:Q", title=label(field), format=".3e"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Perturbation delta heatmap")
    )


def summary_bar(
    results,
    *,
    metric: Literal["max_abs_delta_reflectance", "mean_abs_delta_reflectance"] = "max_abs_delta_reflectance",
):
    data = _summary_frame(results)
    require_columns(data, ["label", metric])
    return (
        alt.Chart(data)
        .mark_bar(color=MATPLOTLIB_RED)
        .encode(
            x=alt.X("label:N", title="Perturbation", axis=alt.Axis(labelAngle=0, labelLimit=360)),
            y=alt.Y(f"{metric}:Q", title=label(metric)),
            tooltip=[alt.Tooltip("label:N"), alt.Tooltip(f"{metric}:Q", format=".3e")],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Perturbation summary")
    )


def _results_frame(result_or_results):
    import pandas as pd

    results = result_or_results if isinstance(result_or_results, list | tuple) else [result_or_results]
    frames = []
    for index, result in enumerate(results):
        frame = to_dataframe(result)
        summary = getattr(result, "summary", None)
        frame = frame.copy()
        frame["label"] = getattr(summary, "label", f"perturbation {index + 1}")
        frames.append(frame)
    return pd.concat(frames, ignore_index=True)


def _summary_frame(results):
    import pandas as pd

    items = results if isinstance(results, list | tuple) else [results]
    rows = []
    for index, result in enumerate(items):
        summary = getattr(result, "summary", None)
        if summary is None:
            rows.append({"label": f"perturbation {index + 1}", **to_dataframe(result).iloc[0].to_dict()})
        else:
            rows.append(
                {
                    "label": summary.label,
                    "parameter_path": summary.parameter_path,
                    "max_abs_delta_reflectance": summary.max_abs_delta_reflectance,
                    "max_abs_delta_wavelength_nm": summary.max_abs_delta_wavelength_nm,
                    "mean_abs_delta_reflectance": summary.mean_abs_delta_reflectance,
                }
            )
    return pd.DataFrame.from_records(rows)
