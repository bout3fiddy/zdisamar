"""Validation and parity plots."""

from __future__ import annotations

from collections.abc import Sequence

import altair as alt

from . import fields
from .data import comparison_frame, metric_frame
from .spectrum import DEFAULT_HEIGHT, DEFAULT_WIDTH, RESIDUAL_HEIGHT
from .theme import MATPLOTLIB_BLUE, MATPLOTLIB_ORANGE, MATPLOTLIB_RED


def overlay(
    current,
    reference,
    *,
    quantity: str = fields.REFLECTANCE,
    reference_label: str = "Reference implementation",
    current_label: str = "Zig implementation",
    window_nm: tuple[float, float] | None = None,
):
    comparison = comparison_frame(current, reference, quantity, window_nm=window_nm)
    current_frame, reference_frame, y_field, y_axis = _overlay_frames(
        comparison,
        quantity,
        reference_label=reference_label,
        current_label=current_label,
    )
    color = alt.Color(
        f"{fields.SOURCE}:N",
        title=None,
        scale=alt.Scale(
            domain=[current_label, reference_label],
            range=[MATPLOTLIB_ORANGE, MATPLOTLIB_BLUE],
        ),
        legend=alt.Legend(orient="bottom-left", labelLimit=360),
    )
    current_line = (
        alt.Chart(current_frame)
        .mark_line(strokeWidth=1.4)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(
                f"{y_field}:Q",
                title=fields.QUANTITY_LABELS.get(quantity, quantity),
                axis=y_axis,
            ),
            color=color,
            tooltip=_overlay_tooltip(quantity),
        )
    )
    reference_line = (
        alt.Chart(reference_frame)
        .mark_line(strokeDash=[7, 4], strokeWidth=2.0)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(
                f"{y_field}:Q",
                title=fields.QUANTITY_LABELS.get(quantity, quantity),
                axis=y_axis,
            ),
            color=color,
            tooltip=_overlay_tooltip(quantity),
        )
    )
    return alt.layer(current_line, reference_line).properties(
        width=DEFAULT_WIDTH,
        height=DEFAULT_HEIGHT,
        title=f"{fields.QUANTITY_LABELS.get(quantity, quantity)} against reference implementation",
    )


def _overlay_frames(comparison, quantity: str, *, reference_label: str, current_label: str):
    reference = comparison[[fields.WAVELENGTH_NM, "reference"]].rename(
        columns={"reference": fields.VALUE}
    )
    reference[fields.SOURCE] = reference_label
    reference[quantity] = comparison["reference"]
    current = comparison[[fields.WAVELENGTH_NM, "current"]].rename(
        columns={"current": fields.VALUE}
    )
    current[fields.SOURCE] = current_label
    current[quantity] = comparison["current"]
    if quantity == fields.RADIANCE:
        return current, reference, fields.VALUE, alt.Axis(format=".2e", tickCount=6)
    return current, reference, fields.VALUE, alt.Axis()


def _overlay_tooltip(quantity: str):
    return [
        alt.Tooltip(f"{fields.SOURCE}:N", title="Source"),
        alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
        alt.Tooltip(f"{quantity}:Q", title=quantity, format=".8g"),
    ]


def _residual_title(quantity: str, relative: bool) -> str:
    if relative:
        return "Relative residual"
    return f"{fields.QUANTITY_LABELS.get(quantity, quantity)} residual"


def _scaled_residual_frame(frame, value_field: str, title: str):
    import math

    import numpy as np

    values = frame[value_field].to_numpy(dtype=float)
    finite_values = values[np.isfinite(values)]
    max_abs = float(np.max(np.abs(finite_values))) if finite_values.size else 0.0
    exponent = int(math.floor(math.log10(max_abs))) if max_abs > 0.0 else 0
    scale = 10.0**exponent

    scaled = frame.copy()
    scaled["_scaled_residual"] = scaled[value_field] / scale
    if exponent == 0:
        return scaled, "_scaled_residual", title, scale
    return scaled, "_scaled_residual", f"{title} (x 10^{exponent})", scale


def _scaled_residual_axis(frame, value_field: str):
    import math

    import numpy as np

    values = frame[value_field].to_numpy(dtype=float)
    finite_values = values[np.isfinite(values)]
    max_abs = float(np.max(np.abs(finite_values))) if finite_values.size else 0.0
    if max_abs <= 0.0:
        return [-1.0, 0.0, 1.0], ".0f"
    if max_abs <= 1.5:
        step = 0.5
        number_format = ".1f"
    else:
        step = float(max(1, math.ceil(max_abs / 3.0)))
        number_format = ".0f"
    bound = step * math.ceil(max_abs / step)
    tick_count = int(round((2.0 * bound) / step)) + 1
    values = [round(-bound + step * index, 10) for index in range(tick_count)]
    return values, number_format


def residual(
    current,
    reference,
    *,
    quantity: str = fields.REFLECTANCE,
    relative: bool = False,
    tolerance: float | None = None,
    window_nm: tuple[float, float] | None = None,
):
    import pandas as pd

    comparison = comparison_frame(
        current, reference, quantity, relative=relative, window_nm=window_nm
    )
    y_field = "plotted_residual"
    y_title = _residual_title(quantity, relative)
    comparison, scaled_y_field, scaled_y_title, residual_scale = _scaled_residual_frame(
        comparison, y_field, y_title
    )
    axis_values, axis_format = _scaled_residual_axis(comparison, scaled_y_field)
    line = (
        alt.Chart(comparison)
        .mark_line(color=MATPLOTLIB_RED, strokeWidth=1.3)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(
                f"{scaled_y_field}:Q",
                title=scaled_y_title,
                axis=alt.Axis(format=axis_format, values=axis_values),
            ),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{y_field}:Q", title=y_title, format=".8g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=RESIDUAL_HEIGHT, title=f"{quantity} residual")
    )
    zero = (
        alt.Chart(pd.DataFrame({scaled_y_field: [0.0]}))
        .mark_rule(color="#111111", strokeWidth=0.8)
        .encode(y=f"{scaled_y_field}:Q")
    )
    layers = []
    if tolerance is not None:
        band = pd.DataFrame(
            {
                fields.WAVELENGTH_NM: [float(comparison[fields.WAVELENGTH_NM].min())],
                "wavelength_end_nm": [float(comparison[fields.WAVELENGTH_NM].max())],
                "lo": [-abs(tolerance) / residual_scale],
                "hi": [abs(tolerance) / residual_scale],
            }
        )
        layers.append(
            alt.Chart(band)
            .mark_area(color="#D9D9D9", opacity=0.35)
            .encode(
                x=f"{fields.WAVELENGTH_NM}:Q",
                x2="wavelength_end_nm:Q",
                y="lo:Q",
                y2="hi:Q",
            )
        )
    layers.extend([line, zero])
    return alt.layer(*layers)


def residual_histogram(
    current,
    reference,
    *,
    quantity: str = fields.REFLECTANCE,
    relative: bool = False,
    bins: int = 60,
):
    frame = comparison_frame(current, reference, quantity, relative=relative)
    y_field = "plotted_residual"
    title = _residual_title(quantity, relative)
    frame, scaled_x_field, scaled_x_title, _ = _scaled_residual_frame(frame, y_field, title)
    axis_values, axis_format = _scaled_residual_axis(frame, scaled_x_field)
    base = alt.Chart(frame)
    histogram = (
        base.mark_bar(color="#737373")
        .encode(
            x=alt.X(
                f"{scaled_x_field}:Q",
                bin=alt.Bin(maxbins=bins),
                title=scaled_x_title,
                axis=alt.Axis(format=axis_format, values=axis_values),
            ),
            y=alt.Y("count():Q", title="Count"),
            tooltip=[
                alt.Tooltip("count():Q", title="Count"),
                alt.Tooltip(f"{y_field}:Q", title=title, format=".2e"),
            ],
        )
        .properties(
            width=DEFAULT_WIDTH,
            height=RESIDUAL_HEIGHT,
            title="Residual against reference implementation",
        )
    )
    mean = base.mark_rule(color="#111111", strokeWidth=1.0).encode(x=f"mean({scaled_x_field}):Q")
    return alt.layer(histogram, mean)


def residual_histogram_report(
    current,
    reference,
    *,
    quantity: str = fields.REFLECTANCE,
    residual_threshold: float,
    relative: bool = False,
    bins: int = 60,
):
    comparison = comparison_frame(current, reference, quantity, relative=relative)
    spectrum_panel = _residual_highlight_spectrum(comparison, quantity, residual_threshold)
    histogram_panel = residual_histogram(
        current, reference, quantity=quantity, relative=relative, bins=bins
    )
    residual_panel = _residual_line_panel(
        comparison, quantity, residual_threshold, relative=relative
    )
    return alt.vconcat(spectrum_panel, histogram_panel, residual_panel).resolve_scale(
        x="independent"
    )


def residual_highlight_spectrum(
    current,
    reference,
    *,
    quantity: str = fields.REFLECTANCE,
    residual_threshold: float,
    relative: bool = False,
):
    comparison = comparison_frame(current, reference, quantity, relative=relative)
    return _residual_highlight_spectrum(comparison, quantity, residual_threshold)


def residual_by_wavelength(
    current,
    reference,
    *,
    quantity: str = fields.REFLECTANCE,
    residual_threshold: float,
    relative: bool = False,
):
    comparison = comparison_frame(current, reference, quantity, relative=relative)
    return _residual_line_panel(comparison, quantity, residual_threshold, relative=relative)


def metrics_bar(
    current,
    reference,
    *,
    quantities: Sequence[str] = (
        fields.REFLECTANCE,
        fields.RADIANCE,
        fields.IRRADIANCE,
    ),
    metrics: Sequence[str] = ("mae", "rmse", "max_abs", "mean_signed"),
):
    frame = metric_frame(current, reference, quantities, metrics)
    frame = frame.copy()
    frame["metric_quantity"] = frame[fields.QUANTITY] + " " + frame[fields.METRIC]
    return (
        alt.Chart(frame)
        .mark_bar()
        .encode(
            x=alt.X(
                "metric_quantity:N",
                title="Quantity and metric",
                sort=None,
                axis=alt.Axis(labelAngle=-32, labelLimit=220),
            ),
            y=alt.Y(
                f"{fields.VALUE}:Q",
                title="Value",
                axis=alt.Axis(format=".2e", tickCount=6),
            ),
            color=alt.Color(f"{fields.METRIC}:N", title="Metric", legend=None),
            tooltip=[
                alt.Tooltip(f"{fields.QUANTITY}:N", title="Quantity"),
                alt.Tooltip(f"{fields.METRIC}:N", title="Metric"),
                alt.Tooltip(f"{fields.VALUE}:Q", title="Value", format=".8g"),
            ],
        )
        .properties(width=DEFAULT_WIDTH, height=DEFAULT_HEIGHT, title="Validation metrics")
    )


def one_to_one(
    table,
    *,
    reference: str = "reference",
    current: str = "current",
    group: str | None = None,
    fit_line: bool = True,
):
    from .data import require_columns, to_dataframe

    frame = to_dataframe(table)
    require_columns(frame, [reference, current])
    color = alt.Color(f"{group}:N", title=group) if group else alt.value("#111111")
    points = (
        alt.Chart(frame)
        .mark_point(filled=True, opacity=0.7, size=28)
        .encode(
            x=alt.X(f"{reference}:Q", title=reference),
            y=alt.Y(f"{current}:Q", title=current),
            color=color,
        )
        .properties(width=320, height=320, title="Current vs reference")
    )
    rule = (
        alt.Chart(frame)
        .mark_line(color="#111111", strokeDash=[4, 3])
        .encode(x=f"{reference}:Q", y=f"{reference}:Q")
    )
    layers = [points, rule]
    if fit_line:
        layers.append(points.transform_regression(reference, current).mark_line(color="#7F1D1D"))
    return alt.layer(*layers)


def _residual_highlight_spectrum(comparison, quantity: str, residual_threshold: float):
    import numpy as np
    import pandas as pd

    frame = comparison[[fields.WAVELENGTH_NM, "current", fields.RESIDUAL]].rename(
        columns={"current": quantity}
    )
    frame["abs_residual"] = np.abs(frame[fields.RESIDUAL].to_numpy(dtype=float))
    frame["above_threshold"] = frame["abs_residual"] > abs(residual_threshold)

    highlight_rows: list[dict[str, object]] = []
    group = 0
    previous_highlighted = False
    for row in frame.itertuples(index=False):
        highlighted = bool(row.above_threshold)
        if highlighted and not previous_highlighted:
            group += 1
        previous_highlighted = highlighted
        if highlighted:
            highlight_rows.append(
                {
                    fields.WAVELENGTH_NM: getattr(row, fields.WAVELENGTH_NM),
                    quantity: getattr(row, quantity),
                    "highlight_group": group,
                    "abs_residual": row.abs_residual,
                }
            )
    highlight_frame = pd.DataFrame.from_records(highlight_rows)

    base = (
        alt.Chart(frame)
        .mark_line(color=MATPLOTLIB_BLUE, strokeWidth=1.4)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(f"{quantity}:Q", title=fields.QUANTITY_LABELS.get(quantity, quantity)),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(
                    f"{quantity}:Q",
                    title=fields.QUANTITY_LABELS.get(quantity, quantity),
                    format=".8g",
                ),
                alt.Tooltip("abs_residual:Q", title="Absolute residual", format=".2e"),
            ],
        )
        .properties(
            width=DEFAULT_WIDTH,
            height=DEFAULT_HEIGHT,
            title="Full sampled reflectance spectrum",
        )
    )
    layers = [base]
    if not highlight_frame.empty:
        layers.append(
            alt.Chart(highlight_frame)
            .mark_line(color=MATPLOTLIB_RED, strokeWidth=2.4)
            .encode(
                x=_wavelength_x(),
                y=f"{quantity}:Q",
                detail="highlight_group:N",
                tooltip=[
                    alt.Tooltip(
                        f"{fields.WAVELENGTH_NM}:Q",
                        title="Wavelength (nm)",
                        format=".4f",
                    ),
                    alt.Tooltip(
                        f"{quantity}:Q",
                        title=fields.QUANTITY_LABELS.get(quantity, quantity),
                        format=".8g",
                    ),
                    alt.Tooltip("abs_residual:Q", title="Absolute residual", format=".2e"),
                ],
            )
        )
        layers.append(
            alt.Chart(highlight_frame)
            .mark_point(color=MATPLOTLIB_RED, filled=True, size=22)
            .encode(
                x=_wavelength_x(),
                y=f"{quantity}:Q",
                tooltip=[alt.Tooltip("abs_residual:Q", format=".2e")],
            )
        )
    return alt.layer(*layers)


def _residual_line_panel(comparison, quantity: str, residual_threshold: float, *, relative: bool):
    import pandas as pd

    y_field = "plotted_residual"
    y_title = _residual_title(quantity, relative)
    frame, scaled_y_field, scaled_y_title, residual_scale = _scaled_residual_frame(
        comparison, y_field, y_title
    )
    axis_values, axis_format = _scaled_residual_axis(frame, scaled_y_field)
    line = (
        alt.Chart(frame)
        .mark_line(color=MATPLOTLIB_RED, strokeWidth=1.3)
        .encode(
            x=_wavelength_x(),
            y=alt.Y(
                f"{scaled_y_field}:Q",
                title=scaled_y_title,
                axis=alt.Axis(format=axis_format, values=axis_values),
            ),
            tooltip=[
                alt.Tooltip(f"{fields.WAVELENGTH_NM}:Q", title="Wavelength (nm)", format=".4f"),
                alt.Tooltip(f"{y_field}:Q", title=y_title, format=".2e"),
            ],
        )
    )
    zero = (
        alt.Chart(pd.DataFrame({scaled_y_field: [0.0]}))
        .mark_rule(color="#111111", strokeWidth=0.8)
        .encode(y=f"{scaled_y_field}:Q")
    )
    threshold = pd.DataFrame(
        {
            scaled_y_field: [
                -abs(residual_threshold) / residual_scale,
                abs(residual_threshold) / residual_scale,
            ]
        }
    )
    threshold_rules = (
        alt.Chart(threshold)
        .mark_rule(color="#737373", strokeDash=[5, 3], strokeWidth=0.8)
        .encode(y=f"{scaled_y_field}:Q")
    )
    return alt.layer(line, zero, threshold_rules).properties(
        width=DEFAULT_WIDTH,
        height=RESIDUAL_HEIGHT,
        title=f"{fields.QUANTITY_LABELS.get(quantity, quantity)} residuals by wavelength",
    )


def _wavelength_x():
    return alt.X(
        f"{fields.WAVELENGTH_NM}:Q",
        title=fields.QUANTITY_LABELS[fields.WAVELENGTH_NM],
        axis=alt.Axis(tickMinStep=5),
    )
