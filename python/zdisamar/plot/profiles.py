"""Shared profile-table transforms for vertical diagnostic plots."""

from typing import Any, cast

from . import fields
from .data import require_columns, to_dataframe


def nearest_wavelength_value(obj: Any, wavelength_nm: float) -> float:

    result = cast(Any, to_dataframe(obj))
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
    result = cast(Any, to_dataframe(obj))
    require_columns(result, required)
    result = result.copy()

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

    result = cast(
        Any,
        active_profile_rows(
            obj, value=value, vertical_axis=vertical_axis, wavelength_nm=wavelength_nm
        ),
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
