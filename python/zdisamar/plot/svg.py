"""Small SVG renderer for zdisamar scientific plots."""

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from html import escape
from math import isfinite
from pathlib import Path
from typing import Self

from .axes import axis_exponent, finite_padded_domain, marker_values
from .properties import PLOT

FIGURE_TITLE_Y = 34
FIGURE_TO_PANEL_TEXT_GAP = 20
INTER_ROW_TEXT_GAP = 20
X_TICK_LABEL_Y_OFFSET = 36
X_AXIS_TITLE_Y_OFFSET = 86
Y_TICK_LABEL_X = -28
Y_AXIS_TITLE_X = -126
PANEL_TITLE_Y = -54
LEGEND_Y_WITH_PANEL_TITLE = -20
LEGEND_Y_WITHOUT_PANEL_TITLE = -24
SUBTITLE_Y_OFFSET = 30


@dataclass(frozen=True)
class SvgSeries:
    """One plotted SVG series."""

    name: str
    kind: str
    x: tuple[float, ...]
    y: tuple[float, ...]
    color: str
    stroke_width: float = field(default_factory=lambda: PLOT.line_width)
    opacity: float = 1.0
    dash: tuple[float, ...] = ()
    y2: tuple[float, ...] = ()
    point_size: float = field(default_factory=lambda: PLOT.default_point_size)
    value_labels: bool = False
    value_label_format: str = ".3g"
    stroke_color: str | None = None
    bar_stroke_width: float = 0.0
    show_legend: bool = True

    @classmethod
    def line(
        cls,
        name: str,
        x: Iterable[float],
        y: Iterable[float],
        *,
        color: str | None = None,
        stroke_width: float | None = None,
        opacity: float = 1.0,
        dash: tuple[float, ...] = (),
        show_legend: bool = True,
    ) -> Self:

        return cls(
            name=name,
            kind="line",
            x=tuple(float(value) for value in x),
            y=tuple(float(value) for value in y),
            color=color or PLOT.colors["blue"],
            stroke_width=stroke_width or PLOT.line_width,
            opacity=opacity,
            dash=dash,
            show_legend=show_legend,
        )

    @classmethod
    def points(
        cls,
        name: str,
        x: Iterable[float],
        y: Iterable[float],
        *,
        color: str | None = None,
        point_size: float | None = None,
        opacity: float = 1.0,
        show_legend: bool = True,
    ) -> Self:

        return cls(
            name=name,
            kind="points",
            x=tuple(float(value) for value in x),
            y=tuple(float(value) for value in y),
            color=color or PLOT.colors["blue"],
            opacity=opacity,
            point_size=point_size or PLOT.default_point_size,
            show_legend=show_legend,
        )

    @classmethod
    def band(
        cls,
        name: str,
        x: Iterable[float],
        y_low: Iterable[float],
        y_high: Iterable[float],
        *,
        color: str | None = None,
        opacity: float | None = None,
        show_legend: bool = True,
    ) -> Self:

        return cls(
            name=name,
            kind="band",
            x=tuple(float(value) for value in x),
            y=tuple(float(value) for value in y_low),
            y2=tuple(float(value) for value in y_high),
            color=color or PLOT.colors["band"],
            opacity=PLOT.noise_band_opacity if opacity is None else opacity,
            show_legend=show_legend,
        )

    @classmethod
    def horizontal_bars(
        cls,
        name: str,
        x: Iterable[float],
        y_low: Iterable[float],
        y_high: Iterable[float],
        *,
        color: str | None = None,
        opacity: float = 1.0,
        stroke_color: str | None = None,
        stroke_width: float = 0.0,
        value_labels: bool = False,
        value_label_format: str = ".3g",
        show_legend: bool = True,
    ) -> Self:

        return cls(
            name=name,
            kind="horizontal_bars",
            x=tuple(float(value) for value in x),
            y=tuple(float(value) for value in y_low),
            y2=tuple(float(value) for value in y_high),
            color=color or PLOT.colors["blue"],
            opacity=opacity,
            stroke_color=stroke_color,
            bar_stroke_width=stroke_width,
            value_labels=value_labels,
            value_label_format=value_label_format,
            show_legend=show_legend,
        )


@dataclass(frozen=True)
class SvgPanel:
    """One Cartesian plot panel."""

    title: str
    x_title: str
    y_title: str | None
    series: tuple[SvgSeries, ...]
    width: int = field(default_factory=lambda: PLOT.width)
    height: int = field(default_factory=lambda: PLOT.height)
    x_domain: tuple[float, float] | None = None
    x_ticks: tuple[float, ...] = ()
    y_domain: tuple[float, float] | None = None
    y_ticks: tuple[float, ...] = ()
    y_tick_labels: tuple[str, ...] = ()
    marker_x: tuple[float, ...] = ()
    rule_y: tuple[float, ...] = ()
    y_axis_multiplier: str | None = None
    show_x_axis: bool = True
    show_x_grid: bool = False
    show_y_grid: bool = True
    show_title: bool = True
    show_legend: bool = True

    def resolved_x_domain(self) -> tuple[float, float]:

        if self.x_domain is not None:
            return self.x_domain

        values = [value for series in self.series for value in series.x if isfinite(value)]

        if not values:
            return (0.0, 1.0)

        low = min(values)
        high = max(values)

        if low == high:
            pad = max(abs(low) * 0.05, 1.0e-12)

            return (low - pad, high + pad)

        return (low, high)

    def resolved_y_domain(self) -> tuple[float, float]:

        if self.y_domain is not None:
            return self.y_domain

        values = []

        for series in self.series:
            values.extend(value for value in series.y if isfinite(value))
            values.extend(value for value in series.y2 if isfinite(value))

        values.extend(value for value in self.rule_y if isfinite(value))

        domain = finite_padded_domain(values)

        return (0.0, 1.0) if domain is None else domain

    def with_default_markers(self) -> "SvgPanel":  # noqa: UP037

        return SvgPanel(
            title=self.title,
            x_title=self.x_title,
            y_title=self.y_title,
            series=self.series,
            width=self.width,
            height=self.height,
            x_domain=self.x_domain,
            x_ticks=self.x_ticks,
            y_domain=self.y_domain,
            y_ticks=self.y_ticks,
            y_tick_labels=self.y_tick_labels,
            marker_x=tuple(marker_values(series_x_values(self.series))),
            rule_y=self.rule_y,
            y_axis_multiplier=self.y_axis_multiplier,
            show_x_axis=self.show_x_axis,
            show_x_grid=self.show_x_grid,
            show_y_grid=self.show_y_grid,
            show_title=self.show_title,
            show_legend=self.show_legend,
        )


@dataclass(frozen=True)
class SvgFigure:
    """Renderable SVG figure used by notebook-facing `.plot` accessors."""

    title: str
    panels: tuple[SvgPanel, ...]
    subtitle: str | None = None
    columns: int = 1
    panel_spacing: int = 44
    y_independent: bool = False
    margin_left: int = 178
    margin_right: int = 36
    margin_top: int = 96
    margin_bottom: int = 122
    title_anchor: str = "middle"

    @property
    def width(self) -> int:

        panel_width = max((panel.width for panel in self.panels), default=PLOT.width)
        columns = min(max(self.columns, 1), max(len(self.panels), 1))

        return (
            self.margin_left
            + self.margin_right
            + columns * panel_width
            + (columns - 1) * self.panel_spacing
        )

    @property
    def height(self) -> int:

        rows = max(1, self.row_count())

        return (
            self.effective_margin_top()
            + self.margin_bottom
            + sum(self.row_height(index) for index in range(rows))
            + sum(self.row_spacing_after(index) for index in range(rows - 1))
        )

    def to_dict(self) -> dict[str, object]:
        """Return a stable plot description for tests."""

        return {
            "type": "zdisamar-svg",
            "title": {"text": self.title},
            "subtitle": None if self.subtitle is None else {"text": self.subtitle},
            "width": self.width,
            "height": self.height,
            "columns": self.columns,
            "resolve": {"scale": {"y": "independent" if self.y_independent else "shared"}},
            "panels": [self.panel_dict(index, panel) for index, panel in enumerate(self.panels)],
        }

    def save(self, path: str | Path) -> None:
        """Save the public runtime plot format."""

        output = Path(path)

        if output.suffix == "":
            output = output.with_suffix(".svg")

        if output.suffix.lower() != ".svg":
            raise ValueError("zdisamar runtime plots save as SVG")

        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(self._repr_svg_(), encoding="utf-8")

    @property
    def svg_css(self) -> str:
        """Return the CSS embedded in this SVG figure."""

        return (
            "<style>"
            f"text {{ font-family: {PLOT.font}; fill: black; }}"
            f".plot-title {{ font-size: {PLOT.title_font_size}px; font-weight: 400; }}"
            f".plot-subtitle {{ font-size: {PLOT.subtitle_font_size}px; font-weight: 400; }}"
            f".panel-title {{ font-size: {PLOT.panel_title_font_size}px; font-weight: 400; }}"
            f".axis-title {{ font-size: {PLOT.axis_title_font_size}px; }}"
            f".tick-label,.axis-multiplier {{ font-size: {PLOT.axis_label_font_size}px; }}"
            f".legend-label {{ font-size: {PLOT.legend_font_size}px; }}"
            ".figure-bg { fill: white; }"
            ".plot-bg { fill: white; stroke: black; stroke-width: 1; }"
            ".axis { stroke: black; stroke-width: 1; }"
            f".grid {{ stroke: {PLOT.colors['grid']}; stroke-opacity: {PLOT.grid_opacity}; }}"
            ".series.line { stroke-linejoin: round; stroke-linecap: round; }"
            "</style>"
        )

    def _repr_svg_(self) -> str:
        """Return notebook-display SVG."""

        elements = [
            (
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" '
                f'height="{self.height}" viewBox="0 0 {self.width} {self.height}">'
            ),
            f"<title>{escape(self.title)}</title>",
            self.svg_css,
            f'<rect class="figure-bg" x="0" y="0" width="{self.width}" height="{self.height}" />',
            (
                f'<text class="plot-title" x="{self.title_x():.3f}" y="{FIGURE_TITLE_Y}" '
                f'text-anchor="{escape(self.title_anchor)}">{escape(self.title)}</text>'
            ),
        ]

        if self.subtitle is not None:
            elements.append(
                f'<text class="plot-subtitle" x="{self.title_x():.3f}" '
                f'y="{FIGURE_TITLE_Y + SUBTITLE_Y_OFFSET}" '
                f'text-anchor="{escape(self.title_anchor)}">{escape(self.subtitle)}</text>'
            )

        for index, panel in enumerate(self.panels):
            elements.extend(self.panel_svg(index, panel))

        elements.append("</svg>")

        return "\n".join(elements)

    def panel_dict(self, index: int, panel: SvgPanel) -> dict[str, object]:

        origin_x, origin_y = self.panel_origin(index)
        x_domain = panel.resolved_x_domain()
        y_domain = panel.resolved_y_domain()

        return {
            "title": {"text": panel.title},
            "origin": [origin_x, origin_y],
            "width": panel.width,
            "height": panel.height,
            "x_title": panel.x_title,
            "y_title": panel.y_title,
            "x_domain": [x_domain[0], x_domain[1]],
            "x_ticks": list(panel.x_ticks),
            "y_domain": [y_domain[0], y_domain[1]],
            "y_ticks": list(panel.y_ticks),
            "y_tick_labels": list(panel.y_tick_labels),
            "marker_x": list(panel.marker_x),
            "rule_y": list(panel.rule_y),
            "axis_multiplier": panel.y_axis_multiplier,
            "show_x_axis": panel.show_x_axis,
            "show_x_grid": panel.show_x_grid,
            "show_y_grid": panel.show_y_grid,
            "show_title": panel.show_title,
            "show_legend": panel.show_legend,
            "series": [
                {
                    "name": series.name,
                    "kind": series.kind,
                    "count": len(series.x),
                    "color": series.color,
                    "stroke_width": series.stroke_width,
                    "opacity": series.opacity,
                    "show_legend": series.show_legend,
                }
                for series in panel.series
            ],
        }

    def panel_svg(self, index: int, panel: SvgPanel) -> list[str]:

        origin_x, origin_y = self.panel_origin(index)
        x_domain = panel.resolved_x_domain()
        y_domain = panel.resolved_y_domain()
        elements = [
            f'<g class="panel" transform="translate({origin_x},{origin_y})">',
            f'<rect class="plot-bg" x="0" y="0" width="{panel.width}" height="{panel.height}" />',
        ]

        if self.draw_panel_title(panel):
            elements.append(
                f'<text class="panel-title" x="{panel.width / 2:.3f}" y="{PANEL_TITLE_Y}" '
                f'text-anchor="middle">{escape(panel.title)}</text>'
            )

        elements.extend(axis_svg(panel, x_domain, y_domain))
        elements.extend(legend_svg(panel, self.draw_panel_title(panel)))

        for marker in panel.marker_x:
            x = scale_value(marker, x_domain, 0.0, float(panel.width))
            elements.append(
                f'<line class="marker" x1="{x:.3f}" x2="{x:.3f}" y1="0" '
                f'y2="{panel.height}" stroke="{PLOT.colors["neutral"]}" '
                f'stroke-width="{PLOT.marker_rule_width}" '
                f'stroke-dasharray="{dash_values(PLOT.marker_rule_dash)}" />'
            )

        for rule in panel.rule_y:
            y = scale_value(rule, y_domain, float(panel.height), 0.0)
            elements.append(
                f'<line class="rule-y" x1="0" x2="{panel.width}" y1="{y:.3f}" '
                f'y2="{y:.3f}" stroke="{PLOT.colors["neutral"]}" '
                f'stroke-width="{PLOT.marker_rule_width}" '
                f'stroke-dasharray="{dash_values(PLOT.marker_rule_dash)}" />'
            )

        for series in panel.series:
            elements.extend(series_svg(panel, series, x_domain, y_domain))

        if panel.y_axis_multiplier is not None:
            elements.append(
                f'<text class="axis-multiplier" x="0" y="-8">'
                f"{escape(panel.y_axis_multiplier)}</text>"
            )

        elements.append("</g>")

        return elements

    def panel_origin(self, index: int) -> tuple[int, int]:

        columns = max(self.columns, 1)
        panel_width = max(panel.width for panel in self.panels)
        column = index % columns
        row = index // columns
        previous_row_height = sum(
            self.row_height(row_index) + self.row_spacing_after(row_index)
            for row_index in range(row)
        )

        return (
            self.margin_left + column * (panel_width + self.panel_spacing),
            self.effective_margin_top() + previous_row_height,
        )

    def row_count(self) -> int:

        if not self.panels:
            return 0

        columns = max(self.columns, 1)

        return (len(self.panels) + columns - 1) // columns

    def row_height(self, row: int) -> int:

        columns = max(self.columns, 1)
        start = row * columns
        stop = min(start + columns, len(self.panels))

        return max((panel.height for panel in self.panels[start:stop]), default=PLOT.height)

    def row_spacing_after(self, row: int) -> int:

        bottom_content = max(
            (panel_bottom_content_depth(panel) for panel in self.row_panels(row)),
            default=0,
        )
        top_content = max(
            (
                panel_top_content_height(panel, self.draw_panel_title(panel))
                for panel in self.row_panels(row + 1)
            ),
            default=0,
        )

        return max(self.panel_spacing, bottom_content + top_content + INTER_ROW_TEXT_GAP)

    def row_panels(self, row: int) -> tuple[SvgPanel, ...]:

        columns = max(self.columns, 1)
        start = row * columns
        stop = min(start + columns, len(self.panels))

        return self.panels[start:stop]

    def draw_panel_title(self, panel: SvgPanel) -> bool:

        return panel.show_title and not (len(self.panels) == 1 and panel.title == self.title)

    def effective_margin_top(self) -> int:

        first_row_top_content = max(
            (
                panel_top_content_height(panel, self.draw_panel_title(panel))
                for panel in self.row_panels(0)
            ),
            default=0,
        )
        figure_text_height = PLOT.title_font_size

        if self.subtitle is not None:
            figure_text_height = SUBTITLE_Y_OFFSET + PLOT.subtitle_font_size

        top_for_figure_title = FIGURE_TITLE_Y + figure_text_height + FIGURE_TO_PANEL_TEXT_GAP
        top_for_figure_title += first_row_top_content

        return max(self.margin_top, top_for_figure_title)

    def title_x(self) -> float:

        if self.title_anchor == "start":
            return 8.0

        if self.title_anchor == "end":
            return float(self.width - 8)

        return self.width / 2.0


def line_panel(
    *,
    title: str,
    x_title: str,
    y_title: str | None,
    x: Sequence[float],
    y: Sequence[float],
    name: str,
    color: str | None = None,
    width: int | None = None,
    height: int | None = None,
    marker_x: bool = True,
    rule_y: tuple[float, ...] = (),
    show_title: bool = True,
    show_legend: bool = True,
    series_show_legend: bool = True,
) -> SvgPanel:
    """Build one line panel with zdisamar defaults."""

    y_axis_multiplier = axis_multiplier(y)

    return SvgPanel(
        title=title,
        x_title=x_title,
        y_title=y_title,
        series=(SvgSeries.line(name, x, y, color=color, show_legend=series_show_legend),),
        width=width or PLOT.width,
        height=height or PLOT.height,
        marker_x=tuple(marker_values(x)) if marker_x else (),
        rule_y=rule_y,
        y_axis_multiplier=y_axis_multiplier,
        show_title=show_title,
        show_legend=show_legend,
    )


def legend_svg(panel: SvgPanel, has_panel_title: bool) -> list[str]:
    """Render one compact per-panel legend above the plotting box."""

    items = legend_items(panel)

    if not items:
        return []

    item_widths = [legend_item_width(label) for label, _kind, _color in items]
    total_width = sum(item_widths)
    x = max(0, panel.width - total_width)
    y = LEGEND_Y_WITH_PANEL_TITLE if has_panel_title else LEGEND_Y_WITHOUT_PANEL_TITLE
    elements = [f'<g class="legend" transform="translate({x:.3f},{y:.3f})">']

    cursor = 0

    for width, (label, kind, color) in zip(item_widths, items, strict=True):
        elements.extend(legend_item_svg(cursor, label, kind, color))
        cursor += width

    elements.append("</g>")

    return elements


def legend_items(panel: SvgPanel) -> list[tuple[str, str, str]]:

    if not panel.show_legend:
        return []

    return unique_legend_items(panel.series)


def unique_legend_items(series: Sequence[SvgSeries]) -> list[tuple[str, str, str]]:

    items: list[tuple[str, str, str]] = []

    for item in series:
        if not item.show_legend:
            continue

        key = (item.name, item.kind, item.color)

        if key not in items:
            items.append(key)

    return items


def legend_item_width(label: str) -> int:

    return 34 + max(24, len(label) * 8)


def legend_item_svg(x: int, label: str, kind: str, color: str) -> list[str]:

    swatch_y = -4
    text_x = x + 25

    if kind == "points":
        swatch = f'<circle cx="{x + 9}" cy="{swatch_y}" r="3.2" fill="{color}" />'
    elif kind in {"band", "horizontal_bars"}:
        swatch = f'<rect x="{x}" y="{swatch_y - 4}" width="18" height="8" fill="{color}" />'
    else:
        swatch = (
            f'<line x1="{x}" x2="{x + 18}" y1="{swatch_y}" y2="{swatch_y}" '
            f'stroke="{color}" stroke-width="{PLOT.line_width}" />'
        )

    return [
        swatch,
        f'<text class="legend-label" x="{text_x}" y="0">{escape(label)}</text>',
    ]


def panel_top_content_height(panel: SvgPanel, has_panel_title: bool) -> int:

    text_height = 0

    if has_panel_title:
        text_height = max(text_height, abs(PANEL_TITLE_Y) + PLOT.panel_title_font_size)

    if legend_items(panel):
        legend_y = LEGEND_Y_WITH_PANEL_TITLE if has_panel_title else LEGEND_Y_WITHOUT_PANEL_TITLE
        text_height = max(text_height, abs(legend_y) + PLOT.legend_font_size)

    if panel.y_axis_multiplier is not None:
        text_height = max(text_height, 8 + PLOT.axis_label_font_size)

    return text_height


def panel_bottom_content_depth(panel: SvgPanel) -> int:

    if not panel.show_x_axis:
        return 0

    return X_AXIS_TITLE_Y_OFFSET + PLOT.axis_title_font_size


def axis_multiplier(values: Iterable[float]) -> str | None:
    """Return compact scientific multiplier text."""

    exponent = axis_exponent(values)

    return None if exponent is None else f"x1e{exponent}"


def axis_svg(
    panel: SvgPanel,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:

    elements = [
        f'<line class="axis" x1="0" x2="{panel.width}" y1="{panel.height}" y2="{panel.height}" />',
        f'<line class="axis" x1="0" x2="0" y1="0" y2="{panel.height}" />',
    ]

    y_tick_values = (
        panel.y_ticks if panel.y_ticks else tuple(ticks(y_domain, PLOT.y_axis_tick_count))
    )

    for index, value in enumerate(y_tick_values):
        y = scale_value(value, y_domain, float(panel.height), 0.0)

        if panel.show_y_grid:
            elements.append(
                f'<line class="grid" x1="0" x2="{panel.width}" y1="{y:.3f}" y2="{y:.3f}" />'
            )

        label = (
            panel.y_tick_labels[index]
            if len(panel.y_tick_labels) == len(y_tick_values)
            else format_tick(value, panel.y_axis_multiplier)
        )
        elements.append(
            f'<text class="tick-label" x="{Y_TICK_LABEL_X}" y="{y + 4:.3f}" text-anchor="end">'
            f"{escape(label)}</text>"
        )

    if panel.show_x_axis:
        x_tick_values = panel.x_ticks if panel.x_ticks else ticks(x_domain, PLOT.x_axis_tick_count)

        for value in x_tick_values:
            x = scale_value(value, x_domain, 0.0, float(panel.width))

            if panel.show_x_grid:
                elements.append(
                    f'<line class="grid" x1="{x:.3f}" x2="{x:.3f}" y1="0" y2="{panel.height}" />'
                )

            elements.append(
                f'<text class="tick-label" x="{x:.3f}" y="{panel.height + X_TICK_LABEL_Y_OFFSET}" '
                f'text-anchor="middle">{escape(format_tick(value, None))}</text>'
            )

        elements.append(
            f'<text class="axis-title" x="{panel.width / 2:.3f}" '
            f'y="{panel.height + X_AXIS_TITLE_Y_OFFSET}" '
            f'text-anchor="middle">{escape(panel.x_title)}</text>'
        )

    if panel.y_title is not None:
        transform = f"translate({Y_AXIS_TITLE_X},{panel.height / 2:.3f}) rotate(-90)"
        elements.append(
            f'<text class="axis-title" transform="{transform}" '
            f'text-anchor="middle">{escape(panel.y_title)}</text>'
        )

    return elements


def series_svg(
    panel: SvgPanel,
    series: SvgSeries,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:

    if series.kind == "horizontal_bars":
        return horizontal_bars_svg(panel, series, x_domain, y_domain)

    if series.kind == "band":
        elements = []
        upper: list[tuple[float, float]] = []
        lower: list[tuple[float, float]] = []

        for x, y_low, y_high in zip(series.x, series.y, series.y2, strict=True):
            if not all(isfinite(value) for value in (x, y_low, y_high)):
                elements.extend(band_polygon_svg(series, upper, lower))
                upper = []
                lower = []
                continue

            upper.append(
                (
                    scale_value(x, x_domain, 0.0, float(panel.width)),
                    scale_value(y_high, y_domain, float(panel.height), 0.0),
                )
            )
            lower.append(
                (
                    scale_value(x, x_domain, 0.0, float(panel.width)),
                    scale_value(y_low, y_domain, float(panel.height), 0.0),
                )
            )

        elements.extend(band_polygon_svg(series, upper, lower))

        return elements

    if series.kind == "points":
        radius = max(series.point_size, 1.0) ** 0.5 / 2.0

        return [
            (
                f'<circle class="series point" '
                f'cx="{scale_value(x, x_domain, 0.0, float(panel.width)):.3f}" '
                f'cy="{scale_value(y, y_domain, float(panel.height), 0.0):.3f}" '
                f'r="{radius:.3f}" '
                f'fill="{series.color}" opacity="{series.opacity:.3f}">'
                f"<title>{escape(series.name)}</title></circle>"
            )
            for x, y in zip(series.x, series.y, strict=True)
            if isfinite(x) and isfinite(y)
        ]

    path = []
    move_next = True

    for x, y in zip(series.x, series.y, strict=True):
        if not (isfinite(x) and isfinite(y)):
            move_next = True
            continue

        path.append(
            path_data(
                scale_value(x, x_domain, 0.0, float(panel.width)),
                scale_value(y, y_domain, float(panel.height), 0.0),
                move_next,
            )
        )
        move_next = False

    return [
        (
            f'<path class="series line" d="{" ".join(path)}" fill="none" stroke="{series.color}" '
            f'stroke-width="{series.stroke_width}" opacity="{series.opacity:.3f}" '
            f'stroke-dasharray="{dash_values(series.dash)}"><title>{escape(series.name)}</title></path>'
        )
    ]


def horizontal_bars_svg(
    panel: SvgPanel,
    series: SvgSeries,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:

    elements: list[str] = []
    zero_x = scale_value(0.0, x_domain, 0.0, float(panel.width))

    for x, y_low, y_high in zip(series.x, series.y, series.y2, strict=True):
        if not all(isfinite(value) for value in (x, y_low, y_high)):
            continue

        value_x = scale_value(x, x_domain, 0.0, float(panel.width))
        top_y = scale_value(y_low, y_domain, float(panel.height), 0.0)
        bottom_y = scale_value(y_high, y_domain, float(panel.height), 0.0)
        center_y = 0.5 * (top_y + bottom_y)
        height = abs(bottom_y - top_y) * 0.90
        x_min = min(zero_x, value_x)
        width = abs(value_x - zero_x)
        stroke = (
            f' stroke="{series.stroke_color}" stroke-width="{series.bar_stroke_width:g}"'
            if series.stroke_color is not None and series.bar_stroke_width > 0.0
            else ""
        )

        elements.append(
            f'<rect class="series horizontal-bar" x="{x_min:.3f}" '
            f'y="{center_y - 0.5 * height:.3f}" width="{width:.3f}" '
            f'height="{height:.3f}" fill="{series.color}" opacity="{series.opacity:.3f}"'
            f"{stroke}><title>{escape(series.name)}</title></rect>"
        )

        if series.value_labels and abs(x) > 0.0:
            elements.append(horizontal_bar_label_svg(panel, series, x, value_x, center_y))

    return elements


def horizontal_bar_label_svg(
    panel: SvgPanel,
    series: SvgSeries,
    value: float,
    value_x: float,
    center_y: float,
) -> str:

    label = format(value, series.value_label_format)
    outside_x = value_x + 8.0

    if outside_x + 44.0 <= panel.width:
        return (
            f'<text class="tick-label" x="{outside_x:.3f}" y="{center_y + 4.0:.3f}" '
            f'text-anchor="start">{escape(label)}</text>'
        )

    return (
        f'<text class="tick-label" x="{max(value_x - 8.0, 8.0):.3f}" '
        f'y="{center_y + 4.0:.3f}" text-anchor="end">{escape(label)}</text>'
    )


def series_x_values(series: Sequence[SvgSeries]) -> list[float]:

    return [value for item in series for value in item.x]


def band_polygon_svg(
    series: SvgSeries,
    upper: Sequence[tuple[float, float]],
    lower: Sequence[tuple[float, float]],
) -> list[str]:

    if len(upper) < 2 or len(lower) < 2:
        return []

    points = " ".join(f"{x:.3f},{y:.3f}" for x, y in [*upper, *reversed(lower)])

    return [
        (
            f'<polygon class="series band" points="{points}" fill="{series.color}" '
            f'opacity="{series.opacity:.3f}" />'
        )
    ]


def path_data(x: float, y: float, move: bool) -> str:

    command = "M" if move else "L"

    return f"{command}{x:.3f},{y:.3f}"


def ticks(domain: tuple[float, float], count: int) -> list[float]:

    low, high = domain

    if count <= 1 or low == high:
        return [low]

    step = (high - low) / (count - 1)

    return [low + index * step for index in range(count)]


def format_tick(value: float, multiplier: str | None) -> str:

    if multiplier is not None:
        exponent = int(multiplier.removeprefix("x1e"))
        value = value / (10.0**exponent)

    return f"{value:.4g}"


def scale_value(
    value: float,
    domain: tuple[float, float],
    pixel_min: float,
    pixel_max: float,
) -> float:

    low, high = domain

    if high == low:
        return 0.5 * (pixel_min + pixel_max)

    return pixel_min + (value - low) * (pixel_max - pixel_min) / (high - low)


def dash_values(values: Sequence[float]) -> str:

    return "none" if not values else " ".join(f"{value:g}" for value in values)
