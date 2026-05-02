"""Shared plotting data transforms."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

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


def with_channel_labels(obj: Any):
    result = to_dataframe(obj)
    if "channel_label" in result.columns or "channel" not in result.columns:
        return result
    labels = {0: "radiance", 1: "irradiance", "0": "radiance", "1": "irradiance"}
    result = result.copy()
    result["channel_label"] = result["channel"].map(labels).fillna(result["channel"].astype(str))
    return result


def melt_components(obj: Any, components: Sequence[str], *, id_vars: Sequence[str]):
    import pandas as pd

    result = to_dataframe(obj)
    available = [component for component in components if component in result.columns]
    require_columns(result, [*id_vars, *available])
    if not available:
        return pd.DataFrame(columns=[*id_vars, "component", fields.VALUE])
    return result.melt(
        id_vars=list(id_vars),
        value_vars=available,
        var_name="component",
        value_name=fields.VALUE,
    )


def component_sums(obj: Any, components: Sequence[str], *, group_by: Sequence[str] = (fields.WAVELENGTH_NM,)):
    melted = melt_components(obj, components, id_vars=group_by)
    if melted.empty:
        return melted
    return melted.groupby([*group_by, "component"], as_index=False)[fields.VALUE].sum()
