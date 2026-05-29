"""Shared profile-table transforms for vertical diagnostic plots."""

import math
from collections.abc import Sequence
from typing import Protocol

from . import fields
from .axes import label
from .data import PlotRow, as_float, column_values, require_columns, to_records
from .properties import PLOT
from .svg import SvgFigure, SvgPanel, SvgSeries

DEFAULT_PROFILE_WAVELENGTH_NM = 760.76


class ColumnTable(Protocol):
    def column(self, name: str) -> Sequence[float]: ...


def profile_figure(
    table: ColumnTable,
    *,
    quantity: str,
    title: str,
    color_key: str,
    wavelength_nm: float | None,
) -> SvgFigure:
    """Build a wavelength-selected altitude profile figure."""

    selected_wavelength_nm = profile_wavelength(table, wavelength_nm)
    data = interval_profile_rows(
        table,
        value=quantity,
        vertical_axis="altitude_km",
        wavelength_nm=selected_wavelength_nm,
    )
    resolved_title = title

    if selected_wavelength_nm is not None and data:
        resolved_title = f"{title}, {nearest_wavelength_value(data, selected_wavelength_nm):.2f} nm"

    panel = SvgPanel(
        title=resolved_title,
        x_title=label(quantity),
        y_title=label("altitude_km"),
        series=(
            SvgSeries.points(
                resolved_title,
                column_values(data, quantity),
                column_values(data, "altitude_km"),
                color=PLOT.colors[color_key],
                point_size=PLOT.profile_point_size,
                opacity=PLOT.profile_point_opacity,
            ),
        ),
        show_legend=False,
    )

    return SvgFigure(title=resolved_title, panels=(panel,))


def profile_wavelength(table: ColumnTable, wavelength_nm: float | None) -> float | None:

    if wavelength_nm is not None:
        return wavelength_nm

    values = sorted({float(value) for value in table.column(fields.WAVELENGTH_NM)})

    if len(values) <= 1:
        return None

    return min(values, key=lambda value: abs(value - DEFAULT_PROFILE_WAVELENGTH_NM))


def nearest_wavelength_value(obj: object, wavelength_nm: float) -> float:

    result = to_records(obj)
    require_columns(result, [fields.WAVELENGTH_NM])
    unique_wavelengths = sorted({as_float(row[fields.WAVELENGTH_NM]) for row in result})

    return min(unique_wavelengths, key=lambda value: abs(value - float(wavelength_nm)))


def active_profile_rows(
    obj: object,
    *,
    value: str,
    vertical_axis: str,
    wavelength_nm: float | None = None,
) -> list[PlotRow]:

    required = [fields.WAVELENGTH_NM, vertical_axis, value]
    result = to_records(obj)
    require_columns(result, required)

    if wavelength_nm is not None:
        selected = nearest_wavelength_value(result, wavelength_nm)
        result = [row for row in result if as_float(row[fields.WAVELENGTH_NM]) == selected]

    result = [
        row
        for row in result
        if math.isfinite(as_float(row[vertical_axis])) and math.isfinite(as_float(row[value]))
    ]

    if result and "support_row_kind_label" in result[0]:
        active = [row for row in result if row["support_row_kind_label"] == "parity_active"]

        if active:
            result = active
    elif result and "path_length_cm" in result[0]:
        active = [row for row in result if as_float(row["path_length_cm"]) > 0.0]

        if active:
            result = active

    if vertical_axis == "pressure_hpa":
        return sorted(result, key=lambda row: as_float(row[vertical_axis]), reverse=True)

    return sorted(result, key=lambda row: as_float(row[vertical_axis]))


def interval_profile_rows(
    obj: object,
    *,
    value: str,
    vertical_axis: str,
    wavelength_nm: float | None = None,
    mode: str = "sum",
    numerator: str | None = None,
    denominator: str | None = None,
) -> list[PlotRow]:

    required = [fields.WAVELENGTH_NM, vertical_axis, value]

    if numerator is not None:
        required.append(numerator)

    if denominator is not None:
        required.append(denominator)

    source_rows = to_records(obj)
    require_columns(source_rows, required)
    result = active_profile_rows(
        source_rows,
        value=value,
        vertical_axis=vertical_axis,
        wavelength_nm=wavelength_nm,
    )

    if not result:
        return result

    top_column = "top_pressure_hpa" if vertical_axis == "pressure_hpa" else "top_altitude_km"
    bottom_column = (
        "bottom_pressure_hpa" if vertical_axis == "pressure_hpa" else "bottom_altitude_km"
    )

    if not result or top_column not in result[0] or bottom_column not in result[0]:
        return result

    grouped: dict[tuple[float, float, float], list[PlotRow]] = {}

    for row in result:
        key = (
            as_float(row[fields.WAVELENGTH_NM]),
            as_float(row[top_column]),
            as_float(row[bottom_column]),
        )
        grouped.setdefault(key, []).append(row)

    summed: list[PlotRow] = []

    for (wavelength_nm, top, bottom), rows in grouped.items():
        output: PlotRow = {
            fields.WAVELENGTH_NM: wavelength_nm,
            top_column: top,
            bottom_column: bottom,
            vertical_axis: 0.5 * (top + bottom),
        }

        if numerator is not None and denominator is not None:
            numerator_sum = sum(as_float(row[numerator]) for row in rows)
            denominator_sum = sum(as_float(row[denominator]) for row in rows)
            output[numerator] = numerator_sum
            output[denominator] = denominator_sum
            output[value] = numerator_sum / denominator_sum if denominator_sum > 0.0 else 0.0
        elif mode == "mean":
            output[value] = sum(as_float(row[value]) for row in rows) / len(rows)
        else:
            output[value] = sum(as_float(row[value]) for row in rows)

        summed.append(output)

    if vertical_axis == "pressure_hpa":
        return sorted(summed, key=lambda row: as_float(row[vertical_axis]), reverse=True)

    return sorted(summed, key=lambda row: as_float(row[vertical_axis]))
