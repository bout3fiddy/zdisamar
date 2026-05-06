"""Shared plotting data transforms."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import pandas as pd

from . import fields
from .data import require_columns, to_dataframe


def frame(obj: Any, required: Sequence[str]):
    result = to_dataframe(obj)
    require_columns(result, required)
    return result


def label(name: str) -> str:
    return fields.QUANTITY_LABELS.get(name, name.replace("_", " "))


def nearest_wavelength_rows(obj: Any, wavelengths_nm: Sequence[float] | None):
    result = to_dataframe(obj)
    require_columns(result, [fields.WAVELENGTH_NM])
    if wavelengths_nm is None:
        return result
    selected = []
    unique_wavelengths = result[fields.WAVELENGTH_NM].drop_duplicates()
    for wavelength in wavelengths_nm:
        index = (unique_wavelengths - float(wavelength)).abs().idxmin()
        selected.append(float(unique_wavelengths.loc[index]))
    return result[result[fields.WAVELENGTH_NM].isin(selected)].copy()


def nearest_wavelength_value(obj: Any, wavelength_nm: float) -> float:
    result = to_dataframe(obj)
    require_columns(result, [fields.WAVELENGTH_NM])
    unique_wavelengths = result[fields.WAVELENGTH_NM].drop_duplicates()
    index = (unique_wavelengths - float(wavelength_nm)).abs().idxmin()
    return float(unique_wavelengths.loc[index])


def active_profile_rows(
    obj: Any,
    *,
    value: str,
    vertical_axis: str,
    wavelength_nm: float | None = None,
):
    import numpy as np

    required = [fields.WAVELENGTH_NM, vertical_axis, value]
    result = frame(obj, required).copy()
    if wavelength_nm is not None:
        selected = nearest_wavelength_value(result, wavelength_nm)
        result = result[result[fields.WAVELENGTH_NM] == selected].copy()

    finite = np.isfinite(result[vertical_axis].to_numpy(dtype=float)) & np.isfinite(
        result[value].to_numpy(dtype=float)
    )
    result = result.loc[finite].copy()

    if "support_row_kind_label" in result.columns:
        active = result[result["support_row_kind_label"] == "parity_active"].copy()
        if not active.empty:
            result = active
    elif "path_length_cm" in result.columns:
        active = result[result["path_length_cm"] > 0.0].copy()
        if not active.empty:
            result = active

    if vertical_axis == "pressure_hpa":
        return result.sort_values(vertical_axis, ascending=False)
    return result.sort_values(vertical_axis)


def interval_profile_rows(
    obj: Any,
    *,
    value: str,
    vertical_axis: str,
    wavelength_nm: float | None = None,
    mode: str = "sum",
    numerator: str | None = None,
    denominator: str | None = None,
):
    import numpy as np

    required = [fields.WAVELENGTH_NM, vertical_axis, value]
    if numerator is not None:
        required.append(numerator)
    if denominator is not None:
        required.append(denominator)
    result = active_profile_rows(
        obj, value=value, vertical_axis=vertical_axis, wavelength_nm=wavelength_nm
    )
    require_columns(result, required)

    top_column = "top_pressure_hpa" if vertical_axis == "pressure_hpa" else "top_altitude_km"
    bottom_column = (
        "bottom_pressure_hpa" if vertical_axis == "pressure_hpa" else "bottom_altitude_km"
    )
    if top_column not in result.columns or bottom_column not in result.columns:
        return result

    group_columns = [fields.WAVELENGTH_NM, top_column, bottom_column]
    grouped = result.groupby(group_columns, as_index=False)
    if numerator is not None and denominator is not None:
        summed = grouped[[numerator, denominator]].sum()
        summed[value] = np.divide(
            summed[numerator],
            summed[denominator],
            out=np.zeros(len(summed), dtype=float),
            where=summed[denominator].to_numpy(dtype=float) > 0.0,
        )
    elif mode == "mean":
        summed = grouped[[value]].mean()
    else:
        summed = grouped[[value]].sum()

    summed[vertical_axis] = 0.5 * (
        summed[top_column].to_numpy(dtype=float) + summed[bottom_column].to_numpy(dtype=float)
    )
    if vertical_axis == "pressure_hpa":
        return summed.sort_values(vertical_axis, ascending=False)
    return summed.sort_values(vertical_axis)


def with_channel_labels(obj: Any):
    result = to_dataframe(obj)
    if "channel_label" in result.columns or "channel" not in result.columns:
        return result
    labels = {0: "radiance", 1: "irradiance", "0": "radiance", "1": "irradiance"}
    result = result.copy()
    result["channel_label"] = result["channel"].map(labels).fillna(result["channel"].astype(str))
    return result


def melt_components(obj: Any, components: Sequence[str], *, id_vars: Sequence[str]):
    result = to_dataframe(obj)
    available = [component for component in components if component in result.columns]
    require_columns(result, [*id_vars, *available])
    if not available:
        return pd.DataFrame(columns=[*id_vars, "component", "component_label", fields.VALUE])
    melted = result.melt(
        id_vars=list(id_vars),
        value_vars=available,
        var_name="component",
        value_name=fields.VALUE,
    )
    melted["component_label"] = melted["component"].map(label)
    return melted


def component_sums(
    obj: Any,
    components: Sequence[str],
    *,
    group_by: Sequence[str] = (fields.WAVELENGTH_NM,),
):
    melted = melt_components(obj, components, id_vars=group_by)
    if melted.empty:
        return melted
    return melted.groupby([*group_by, "component", "component_label"], as_index=False)[
        fields.VALUE
    ].sum()


def numeric_cell_bounds(
    obj: Any,
    x: str,
    *,
    y: str | None = None,
    x_start: str = "_x_start",
    x_end: str = "_x_end",
    y_start: str = "_y_start",
    y_end: str = "_y_end",
):
    result = to_dataframe(obj).copy()
    _add_axis_bounds(result, x, x_start, x_end)
    if y is not None:
        _add_axis_bounds(result, y, y_start, y_end)
    return result


def _add_axis_bounds(data, column: str, start: str, end: str) -> None:
    import numpy as np

    values = np.array(sorted(data[column].dropna().unique()), dtype=float)
    if values.size == 0:
        data[start] = pd.NA
        data[end] = pd.NA
        return
    if values.size == 1:
        half_step = 0.5
        edges = np.array([values[0] - half_step, values[0] + half_step], dtype=float)
    else:
        midpoints = (values[:-1] + values[1:]) / 2.0
        first = values[0] - (midpoints[0] - values[0])
        last = values[-1] + (values[-1] - midpoints[-1])
        edges = np.concatenate([[first], midpoints, [last]])
    starts = dict(zip(values, edges[:-1], strict=True))
    ends = dict(zip(values, edges[1:], strict=True))
    numeric = data[column].astype(float)
    data[start] = numeric.map(starts)
    data[end] = numeric.map(ends)
