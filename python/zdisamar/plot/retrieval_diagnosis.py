"""SVG basin-density plots for multi-start retrieval diagnosis."""

import math
from collections.abc import Sequence
from dataclasses import dataclass
from html import escape
from pathlib import Path

from ..inverse_method.optimal_estimation.diagnosis import RetrievalDiagnosis
from .optimal_estimation import STATE_AXIS_TITLES
from .properties import PLOT
from .svg import dash_values, format_tick, scale_value, ticks

FIGURE_WIDTH = 1180
FIGURE_HEIGHT = 840
PANEL_X = 150
PANEL_Y = 88
PANEL_WIDTH = 870
PANEL_HEIGHT = 650
COLORBAR_X = 1060
COLORBAR_Y = 166
COLORBAR_WIDTH = 22
COLORBAR_HEIGHT = 420
TRAJECTORY_FIELD_BANDWIDTH = 0.035


@dataclass(frozen=True)
class RetrievalDiagnosisFigure:
    """Single-panel SVG showing how start states flow into retrieved states."""

    diagnosis: RetrievalDiagnosis
    cells: int

    @property
    def width(self) -> int:

        return FIGURE_WIDTH

    @property
    def height(self) -> int:

        return FIGURE_HEIGHT

    def save(self, path: str | Path) -> None:
        """Save the runtime plot format."""

        output = Path(path)

        if output.suffix == "":
            output = output.with_suffix(".svg")

        if output.suffix.lower() != ".svg":
            raise ValueError("zdisamar runtime plots save as SVG")

        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(self._repr_svg_(), encoding="utf-8")

    def to_dict(self) -> dict[str, object]:
        """Return a compact plot description for tests."""

        return {
            "type": "zdisamar-svg",
            "title": {"text": "Retrieval basin diagnosis"},
            "width": self.width,
            "height": self.height,
            "cells": self.cells,
            "density": "interpolated trajectory field",
            "runs": len(self.diagnosis.start_state),
            "failed_starts": sum(
                1 for status in self.diagnosis.resolved_start_status() if status != "ok"
            ),
            "state_names": list(self.diagnosis.state_names),
        }

    def _repr_svg_(self) -> str:
        """Return notebook-display SVG."""

        x_domain, y_domain = plot_domains(self.diagnosis)
        elements = [
            (
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" '
                f'height="{self.height}" viewBox="0 0 {self.width} {self.height}">'
            ),
            "<title>Retrieval basin diagnosis</title>",
            self.svg_css(),
            f'<rect class="figure-bg" x="0" y="0" width="{self.width}" height="{self.height}" />',
            (
                f'<text class="plot-title" x="{self.width / 2:.3f}" y="36" '
                f'text-anchor="middle">Retrieval basin diagnosis</text>'
            ),
            f'<g class="panel" transform="translate({PANEL_X},{PANEL_Y})">',
            f'<rect class="plot-bg" x="0" y="0" width="{PANEL_WIDTH}" height="{PANEL_HEIGHT}" />',
        ]
        elements.extend(density_svg(self.diagnosis, self.cells, x_domain, y_domain))
        elements.extend(trajectory_marker_svg(self.diagnosis, x_domain, y_domain))
        elements.extend(axis_svg(self.diagnosis, x_domain, y_domain))
        elements.append("</g>")
        elements.extend(colorbar_svg())
        elements.append("</svg>")

        return "\n".join(elements)

    def svg_css(self) -> str:
        """Return embedded plot CSS."""

        return (
            "<style>"
            f"text {{ font-family: {PLOT.font}; fill: black; }}"
            f".plot-title {{ font-size: {PLOT.title_font_size}px; font-weight: 400; }}"
            f".axis-title {{ font-size: {PLOT.axis_title_font_size}px; }}"
            f".tick-label,.legend-label {{ font-size: {PLOT.axis_label_font_size}px; }}"
            ".figure-bg { fill: white; }"
            ".plot-bg { fill: white; stroke: black; stroke-width: 1; }"
            ".axis { stroke: black; stroke-width: 1; }"
            f".grid {{ stroke: {PLOT.colors['grid']}; stroke-opacity: {PLOT.grid_opacity}; }}"
            ".density-cell { shape-rendering: auto; }"
            ".diagnosis-start { fill: white; stroke: #1f77b4; stroke-width: 1; opacity: 0.42; }"
            ".diagnosis-bad-start { stroke: #b00020; stroke-width: 1.6; opacity: 0.78; }"
            ".diagnosis-end { fill: #111111; opacity: 0.58; }"
            ".diagnosis-result { fill: none; stroke: #111111; stroke-width: 2.2; }"
            "</style>"
        )


def retrieval_diagnosis_figure(
    diagnosis: RetrievalDiagnosis,
    *,
    cells: int = 150,
) -> RetrievalDiagnosisFigure:
    """Return the SVG figure for one multi-start diagnosis."""

    if cells < 20:
        raise ValueError("diagnosis plot cells must be at least 20")

    return RetrievalDiagnosisFigure(diagnosis=diagnosis, cells=int(cells))


def plot_domains(diagnosis: RetrievalDiagnosis) -> tuple[tuple[float, float], tuple[float, float]]:
    """Return axis domains, with pressure increasing downward."""

    x_domain = diagnosis.start_bounds[0]
    y_bounds = diagnosis.start_bounds[1]
    y_name = diagnosis.state_names[1]
    y_domain = (y_bounds[1], y_bounds[0]) if "pressure" in y_name else y_bounds

    return x_domain, y_domain


def density_svg(
    diagnosis: RetrievalDiagnosis,
    cells: int,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render the full interpolated trajectory-density field."""

    density = trajectory_density(diagnosis, cells)
    max_density = max((value for row in density for value in row), default=0.0)

    if max_density <= 0.0:
        return []

    x_low, x_high = diagnosis.start_bounds[0]
    y_low, y_high = diagnosis.start_bounds[1]
    dx = (x_high - x_low) / cells
    dy = (y_high - y_low) / cells
    elements = []

    for y_index, row in enumerate(density):
        cell_low_y = y_low + y_index * dy
        cell_high_y = cell_low_y + dy
        y0 = scale_value(cell_low_y, y_domain, float(PANEL_HEIGHT), 0.0)
        y1 = scale_value(cell_high_y, y_domain, float(PANEL_HEIGHT), 0.0)
        y = min(y0, y1)
        height = max(abs(y1 - y0), 0.8)

        for x_index, value in enumerate(row):
            normalized = value / max_density
            cell_low_x = x_low + x_index * dx
            cell_high_x = cell_low_x + dx
            x0 = scale_value(cell_low_x, x_domain, 0.0, float(PANEL_WIDTH))
            x1 = scale_value(cell_high_x, x_domain, 0.0, float(PANEL_WIDTH))
            color, opacity = density_color(normalized)
            elements.append(
                f'<rect class="density-cell" x="{x0:.3f}" y="{y:.3f}" '
                f'width="{max(x1 - x0, 0.8):.3f}" height="{height:.3f}" '
                f'fill="{color}" opacity="{opacity:.3f}" />'
            )

    return elements


def trajectory_density(diagnosis: RetrievalDiagnosis, cells: int) -> list[list[float]]:
    """Interpolate trajectory density over the full state-space panel."""

    grid = [[0.0 for _ in range(cells)] for _ in range(cells)]
    trajectories = normalized_trajectories(diagnosis)
    bandwidth2 = TRAJECTORY_FIELD_BANDWIDTH * TRAJECTORY_FIELD_BANDWIDTH

    if not trajectories:
        return grid

    for y_index, row in enumerate(grid):
        y = (y_index + 0.5) / cells

        for x_index in range(cells):
            x = (x_index + 0.5) / cells
            value = 0.0

            for start_x, start_y, end_x, end_y in trajectories:
                distance2 = distance_to_segment2(x, y, start_x, start_y, end_x, end_y)
                value += math.exp(-0.5 * distance2 / bandwidth2)

            row[x_index] = value

    return grid


def normalized_trajectories(
    diagnosis: RetrievalDiagnosis,
) -> list[tuple[float, float, float, float]]:
    """Return finite successful start-to-retrieved paths in normalized panel units."""

    return [
        (
            normalized_axis_value(start[0], diagnosis.start_bounds[0]),
            normalized_axis_value(start[1], diagnosis.start_bounds[1]),
            normalized_axis_value(end[0], diagnosis.start_bounds[0]),
            normalized_axis_value(end[1], diagnosis.start_bounds[1]),
        )
        for start, end, status in zip(
            diagnosis.start_state,
            diagnosis.retrieved_state,
            diagnosis.resolved_start_status(),
            strict=True,
        )
        if status == "ok" and finite_point(start) and finite_point(end)
    ]


def normalized_axis_value(value: float, bounds: tuple[float, float]) -> float:
    """Scale a state coordinate into the unit interval for distance calculations."""

    low, high = bounds

    return (float(value) - low) / (high - low)


def distance_to_segment2(
    x: float,
    y: float,
    start_x: float,
    start_y: float,
    end_x: float,
    end_y: float,
) -> float:
    """Return squared unit-panel distance from a point to one trajectory segment."""

    dx = end_x - start_x
    dy = end_y - start_y
    length2 = dx * dx + dy * dy

    if length2 <= 0.0:
        projection = 0.0
    else:
        projection = ((x - start_x) * dx + (y - start_y) * dy) / length2
        projection = max(0.0, min(1.0, projection))

    closest_x = start_x + projection * dx
    closest_y = start_y + projection * dy
    distance_x = x - closest_x
    distance_y = y - closest_y

    return distance_x * distance_x + distance_y * distance_y


def density_color(normalized: float) -> tuple[str, float]:
    """Map density to a pale-yellow through red ramp."""

    t = max(0.0, min(1.0, normalized)) ** 0.58
    red = 255
    green = round(216 * (1.0 - t) + 42 * t)
    blue = round(150 * (1.0 - t) + 35 * t)
    opacity = 0.28 + 0.66 * t

    return f"rgb({red},{green},{blue})", opacity


def trajectory_marker_svg(
    diagnosis: RetrievalDiagnosis,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render starts, endpoints, and the accepted result state."""

    elements = []

    for start, status in zip(
        diagnosis.start_state,
        diagnosis.resolved_start_status(),
        strict=True,
    ):
        if status == "ok":
            elements.append(point_svg(start, x_domain, y_domain, "diagnosis-start", 2.0))
        else:
            elements.extend(bad_start_svg(start, x_domain, y_domain))

    for end, status in zip(
        diagnosis.retrieved_state,
        diagnosis.resolved_start_status(),
        strict=True,
    ):
        if status != "ok" or not finite_point(end):
            continue

        elements.append(point_svg(end, x_domain, y_domain, "diagnosis-end", 2.2))

    result = diagnosis.result_state
    x = scale_value(result[0], x_domain, 0.0, float(PANEL_WIDTH))
    y = scale_value(result[1], y_domain, float(PANEL_HEIGHT), 0.0)
    elements.extend(
        [
            f'<line class="diagnosis-result" x1="{x - 8:.3f}" x2="{x + 8:.3f}" '
            f'y1="{y:.3f}" y2="{y:.3f}" />',
            f'<line class="diagnosis-result" x1="{x:.3f}" x2="{x:.3f}" '
            f'y1="{y - 8:.3f}" y2="{y + 8:.3f}" />',
        ]
    )

    return elements


def finite_point(point: Sequence[float]) -> bool:
    """Return whether a plotted state-space point is finite."""

    return all(math.isfinite(float(value)) for value in point)


def bad_start_svg(
    point: Sequence[float],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render one failed start marker."""

    x = scale_value(point[0], x_domain, 0.0, float(PANEL_WIDTH))
    y = scale_value(point[1], y_domain, float(PANEL_HEIGHT), 0.0)

    return [
        f'<line class="diagnosis-bad-start" x1="{x - 4:.3f}" x2="{x + 4:.3f}" '
        f'y1="{y - 4:.3f}" y2="{y + 4:.3f}" />',
        f'<line class="diagnosis-bad-start" x1="{x - 4:.3f}" x2="{x + 4:.3f}" '
        f'y1="{y + 4:.3f}" y2="{y - 4:.3f}" />',
    ]


def point_svg(
    point: Sequence[float],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
    class_name: str,
    radius: float,
) -> str:
    """Render one state-space marker."""

    x = scale_value(point[0], x_domain, 0.0, float(PANEL_WIDTH))
    y = scale_value(point[1], y_domain, float(PANEL_HEIGHT), 0.0)

    return f'<circle class="{class_name}" cx="{x:.3f}" cy="{y:.3f}" r="{radius:.3f}" />'


def axis_svg(
    diagnosis,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render axes, grid, labels, and a compact legend."""

    elements = [
        f'<line class="axis" x1="0" x2="{PANEL_WIDTH}" y1="{PANEL_HEIGHT}" y2="{PANEL_HEIGHT}" />',
        f'<line class="axis" x1="0" x2="0" y1="0" y2="{PANEL_HEIGHT}" />',
    ]

    for value in ticks(x_domain, PLOT.x_axis_tick_count):
        x = scale_value(value, x_domain, 0.0, float(PANEL_WIDTH))
        elements.append(
            f'<line class="grid" x1="{x:.3f}" x2="{x:.3f}" y1="0" y2="{PANEL_HEIGHT}" />'
        )
        elements.append(
            f'<text class="tick-label" x="{x:.3f}" y="{PANEL_HEIGHT + 34}" '
            f'text-anchor="middle">{escape(format_tick(value, None))}</text>'
        )

    for value in ticks(y_domain, PLOT.y_axis_tick_count):
        y = scale_value(value, y_domain, float(PANEL_HEIGHT), 0.0)
        elements.append(
            f'<line class="grid" x1="0" x2="{PANEL_WIDTH}" y1="{y:.3f}" y2="{y:.3f}" />'
        )
        elements.append(
            f'<text class="tick-label" x="-26" y="{y + 4:.3f}" '
            f'text-anchor="end">{escape(format_tick(value, None))}</text>'
        )

    x_title = STATE_AXIS_TITLES.get(diagnosis.state_names[0]) or diagnosis.state_names[0]
    y_title = STATE_AXIS_TITLES.get(diagnosis.state_names[1]) or diagnosis.state_names[1]
    elements.extend(
        [
            (
                f'<text class="axis-title" x="{PANEL_WIDTH / 2:.3f}" y="{PANEL_HEIGHT + 82}" '
                f'text-anchor="middle">{escape(x_title)}</text>'
            ),
            (
                f'<text class="axis-title" '
                f'transform="translate(-112,{PANEL_HEIGHT / 2:.3f}) rotate(-90)" '
                f'text-anchor="middle">{escape(y_title)}</text>'
            ),
            '<g class="legend" transform="translate(8,-24)">',
            '<circle class="diagnosis-start" cx="6" cy="-4" r="3" />',
            '<text class="legend-label" x="18" y="0">start</text>',
            '<circle class="diagnosis-end" cx="76" cy="-4" r="3" />',
            '<text class="legend-label" x="88" y="0">retrieved</text>',
            ('<line class="diagnosis-bad-start" x1="174" x2="182" y1="-8" y2="0" />'),
            ('<line class="diagnosis-bad-start" x1="174" x2="182" y1="0" y2="-8" />'),
            '<text class="legend-label" x="192" y="0">failed start</text>',
            (
                f'<line class="diagnosis-result" x1="306" x2="322" '
                f'y1="-4" y2="-4" stroke-dasharray="{dash_values(())}" />'
            ),
            (
                f'<line class="diagnosis-result" x1="314" x2="314" '
                f'y1="-12" y2="4" stroke-dasharray="{dash_values(())}" />'
            ),
            '<text class="legend-label" x="332" y="0">accepted result</text>',
            "</g>",
        ]
    )

    return elements


def colorbar_svg() -> list[str]:
    """Render the trajectory-density color scale."""

    elements = [f'<g class="colorbar" transform="translate({COLORBAR_X},{COLORBAR_Y})">']
    steps = 36
    step_height = COLORBAR_HEIGHT / steps

    for index in range(steps):
        normalized = (index + 1) / steps
        color, opacity = density_color(normalized)
        y = COLORBAR_HEIGHT - (index + 1) * step_height
        elements.append(
            f'<rect x="0" y="{y:.3f}" width="{COLORBAR_WIDTH}" height="{step_height + 0.5:.3f}" '
            f'fill="{color}" opacity="{opacity:.3f}" />'
        )

    elements.extend(
        [
            (
                f'<rect x="0" y="0" width="{COLORBAR_WIDTH}" '
                f'height="{COLORBAR_HEIGHT}" fill="none" stroke="black" />'
            ),
            f'<text class="legend-label" x="{COLORBAR_WIDTH + 12}" y="4">dense</text>',
            (
                f'<text class="legend-label" x="{COLORBAR_WIDTH + 12}" '
                f'y="{COLORBAR_HEIGHT:.3f}">sparse</text>'
            ),
            (
                f'<text class="axis-title" '
                f'transform="translate({COLORBAR_WIDTH + 64},'
                f'{COLORBAR_HEIGHT / 2:.3f}) rotate(-90)" '
                'text-anchor="middle">trajectory density</text>'
            ),
            "</g>",
        ]
    )

    return elements
