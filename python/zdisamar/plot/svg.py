"""Small SVG renderer for zdisamar scientific plots."""

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from html import escape
from math import isfinite
from pathlib import Path
from typing import Self

from .axes import axis_exponent, finite_padded_domain, marker_values
from .properties import PLOT

X_TICK_LABEL_Y_OFFSET = 30
X_AXIS_TITLE_Y_OFFSET = 70
Y_TICK_LABEL_X = -14
Y_AXIS_TITLE_X = -104
PANEL_TITLE_Y = -24


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
    ) -> Self:

        return cls(
            name=name,
            kind="points",
            x=tuple(float(value) for value in x),
            y=tuple(float(value) for value in y),
            color=color or PLOT.colors["blue"],
            opacity=opacity,
            point_size=point_size or PLOT.default_point_size,
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
    ) -> Self:

        return cls(
            name=name,
            kind="band",
            x=tuple(float(value) for value in x),
            y=tuple(float(value) for value in y_low),
            y2=tuple(float(value) for value in y_high),
            color=color or PLOT.colors["band"],
            opacity=PLOT.noise_band_opacity if opacity is None else opacity,
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
    marker_x: tuple[float, ...] = ()
    rule_y: tuple[float, ...] = ()
    y_axis_multiplier: str | None = None

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
            marker_x=tuple(marker_values(series_x_values(self.series))),
            rule_y=self.rule_y,
            y_axis_multiplier=self.y_axis_multiplier,
        )


@dataclass(frozen=True)
class SvgFigure:
    """Renderable SVG figure used by notebook-facing `.plot` accessors."""

    title: str
    panels: tuple[SvgPanel, ...]
    columns: int = 1
    panel_spacing: int = 44
    y_independent: bool = False
    margin_left: int = 138
    margin_right: int = 28
    margin_top: int = 68
    margin_bottom: int = 94

    @property
    def width(self) -> int:

        panel_width = max(panel.width for panel in self.panels)
        columns = min(max(self.columns, 1), len(self.panels))

        return (
            self.margin_left
            + self.margin_right
            + columns * panel_width
            + (columns - 1) * self.panel_spacing
        )

    @property
    def height(self) -> int:

        panel_height = max(panel.height for panel in self.panels)
        rows = (len(self.panels) + max(self.columns, 1) - 1) // max(self.columns, 1)

        return (
            self.effective_margin_top()
            + self.margin_bottom
            + rows * panel_height
            + (rows - 1) * self.panel_spacing
        )

    def to_dict(self) -> dict[str, object]:
        """Return a stable plot description for tests."""

        return {
            "type": "zdisamar-svg",
            "title": {"text": self.title},
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
            f".panel-title {{ font-size: {PLOT.panel_title_font_size}px; font-weight: 400; }}"
            f".axis-title {{ font-size: {PLOT.axis_title_font_size}px; }}"
            f".tick-label,.axis-multiplier {{ font-size: {PLOT.axis_label_font_size}px; }}"
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
            (
                f'<text class="plot-title" x="{self.width / 2:.3f}" y="34" '
                f'text-anchor="middle">{escape(self.title)}</text>'
            ),
        ]

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
            "marker_x": list(panel.marker_x),
            "rule_y": list(panel.rule_y),
            "axis_multiplier": panel.y_axis_multiplier,
            "series": [
                {
                    "name": series.name,
                    "kind": series.kind,
                    "count": len(series.x),
                    "color": series.color,
                    "stroke_width": series.stroke_width,
                    "opacity": series.opacity,
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
        panel_height = max(panel.height for panel in self.panels)
        column = index % columns
        row = index // columns

        return (
            self.margin_left + column * (panel_width + self.panel_spacing),
            self.effective_margin_top() + row * (panel_height + self.panel_spacing),
        )

    def draw_panel_title(self, panel: SvgPanel) -> bool:

        return not (len(self.panels) == 1 and panel.title == self.title)

    def effective_margin_top(self) -> int:

        if any(self.draw_panel_title(panel) for panel in self.panels):
            return 104

        return self.margin_top


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
) -> SvgPanel:
    """Build one line panel with zdisamar defaults."""

    y_axis_multiplier = axis_multiplier(y)

    return SvgPanel(
        title=title,
        x_title=x_title,
        y_title=y_title,
        series=(SvgSeries.line(name, x, y, color=color),),
        width=width or PLOT.width,
        height=height or PLOT.height,
        marker_x=tuple(marker_values(x)) if marker_x else (),
        rule_y=rule_y,
        y_axis_multiplier=y_axis_multiplier,
    )


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

    for value in ticks(y_domain, PLOT.y_axis_tick_count):
        y = scale_value(value, y_domain, float(panel.height), 0.0)
        elements.append(
            f'<line class="grid" x1="0" x2="{panel.width}" y1="{y:.3f}" y2="{y:.3f}" />'
        )
        elements.append(
            f'<text class="tick-label" x="{Y_TICK_LABEL_X}" y="{y + 4:.3f}" text-anchor="end">'
            f"{escape(format_tick(value, panel.y_axis_multiplier))}</text>"
        )

    x_tick_values = panel.x_ticks if panel.x_ticks else ticks(x_domain, PLOT.x_axis_tick_count)

    for value in x_tick_values:
        x = scale_value(value, x_domain, 0.0, float(panel.width))
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

    if series.kind == "band":
        upper = [
            (
                scale_value(x, x_domain, 0.0, float(panel.width)),
                scale_value(y, y_domain, float(panel.height), 0.0),
            )
            for x, y in zip(series.x, series.y2, strict=True)
        ]
        lower = [
            (
                scale_value(x, x_domain, 0.0, float(panel.width)),
                scale_value(y, y_domain, float(panel.height), 0.0),
            )
            for x, y in zip(reversed(series.x), reversed(series.y), strict=True)
        ]
        points = " ".join(f"{x:.3f},{y:.3f}" for x, y in [*upper, *lower])

        return [
            (
                f'<polygon class="series band" points="{points}" fill="{series.color}" '
                f'opacity="{series.opacity:.3f}" />'
            )
        ]

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
        ]

    path = [
        path_data(
            scale_value(x, x_domain, 0.0, float(panel.width)),
            scale_value(y, y_domain, float(panel.height), 0.0),
            index,
        )
        for index, (x, y) in enumerate(zip(series.x, series.y, strict=True))
    ]

    return [
        (
            f'<path class="series line" d="{" ".join(path)}" fill="none" stroke="{series.color}" '
            f'stroke-width="{series.stroke_width}" opacity="{series.opacity:.3f}" '
            f'stroke-dasharray="{dash_values(series.dash)}"><title>{escape(series.name)}</title></path>'
        )
    ]


def series_x_values(series: Sequence[SvgSeries]) -> list[float]:

    return [value for item in series for value in item.x]


def path_data(x: float, y: float, index: int) -> str:

    command = "M" if index == 0 else "L"

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
