"""SVG retrieval-path plots for multi-start diagnosis."""

import math
from collections.abc import Sequence
from dataclasses import dataclass
from html import escape
from pathlib import Path

from ..inverse_method.optimal_estimation.diagnosis import RetrievalDiagnosis
from .optimal_estimation import STATE_AXIS_TITLES
from .properties import PLOT
from .svg import format_tick

FIGURE_WIDTH = 1180
FIGURE_HEIGHT = 840
PANEL_X = 150
PANEL_Y = 88
PANEL_WIDTH = 890
PANEL_HEIGHT = 650
AOD_PSEUDO_LOG_SCALE = 0.08
PATH_DENSITY_BANDWIDTH = 0.055
ENDPOINT_CLUSTER_RADIUS = 0.055


@dataclass(frozen=True)
class EndpointCluster:
    """Converged endpoint group shown as one basin marker."""

    indices: tuple[int, ...]
    points: tuple[tuple[float, ...], ...]
    centroid: tuple[float, ...]


@dataclass(frozen=True)
class RetrievalDiagnosisFigure:
    """Single-panel SVG showing actual solver paths from diagnosis starts."""

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

        clusters = endpoint_clusters(self.diagnosis, plot_domains(self.diagnosis))

        return {
            "type": "zdisamar-svg",
            "title": {"text": "Retrieval Paths"},
            "width": self.width,
            "height": self.height,
            "runs": len(self.diagnosis.start_state),
            "non_converged": len(non_converged_paths(self.diagnosis)),
            "endpoint_clusters": len(clusters),
            "truth": None
            if self.diagnosis.truth_state is None
            else list(self.diagnosis.truth_state),
            "state_names": list(self.diagnosis.state_names),
            "x_scale": "pseudo-log",
        }

    def _repr_svg_(self) -> str:
        """Return notebook-display SVG."""

        x_domain, y_domain = plot_domains(self.diagnosis)
        clusters = endpoint_clusters(self.diagnosis, (x_domain, y_domain))
        plot_paths = trimmed_plot_paths(self.diagnosis, clusters, (x_domain, y_domain))
        path_segments = segments(plot_paths)
        densities = segment_densities(path_segments, (x_domain, y_domain))
        elements = [
            (
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.width}" '
                f'height="{self.height}" viewBox="0 0 {self.width} {self.height}">'
            ),
            "<title>Retrieval Paths</title>",
            self.svg_css(),
            (
                f'<defs><clipPath id="diagnosis-plot-clip"><rect x="0" y="0" '
                f'width="{PANEL_WIDTH}" height="{PANEL_HEIGHT}"/></clipPath></defs>'
            ),
            f'<rect class="figure-bg" x="0" y="0" width="{self.width}" height="{self.height}" />',
            (
                f'<text class="plot-title" x="{self.width / 2:.3f}" y="36" '
                f'text-anchor="middle">Retrieval Paths</text>'
            ),
            f'<g class="panel" transform="translate({PANEL_X},{PANEL_Y})">',
            f'<rect class="plot-bg" x="0" y="0" width="{PANEL_WIDTH}" height="{PANEL_HEIGHT}" />',
        ]
        elements.extend(axis_svg(self.diagnosis, x_domain, y_domain))
        elements.append('<g clip-path="url(#diagnosis-plot-clip)">')
        elements.extend(path_svg(path_segments, densities, x_domain, y_domain))
        elements.extend(start_marker_svg(self.diagnosis, x_domain, y_domain))
        elements.extend(non_converged_svg(self.diagnosis, plot_paths, x_domain, y_domain))
        elements.extend(cluster_marker_svg(clusters, x_domain, y_domain))
        elements.append("</g>")
        elements.extend(cluster_label_svg(clusters, x_domain, y_domain))

        if self.diagnosis.truth_state is not None:
            elements.extend(truth_svg(self.diagnosis.truth_state, x_domain, y_domain))

        elements.append("</g>")
        elements.append("</svg>")

        return "\n".join(elements)

    def svg_css(self) -> str:
        """Return embedded plot CSS."""

        return (
            "<style>"
            f"text {{ font-family: {PLOT.font}; fill: black; }}"
            f".plot-title {{ font-size: {PLOT.title_font_size}px; font-weight: 700; }}"
            f".axis-title {{ font-size: {PLOT.axis_title_font_size}px; font-weight: 700; }}"
            f".tick-label,.marker-label {{ font-size: {PLOT.axis_label_font_size}px; }}"
            ".figure-bg { fill: white; }"
            ".plot-bg { fill: #fbfbfb; stroke: #222; stroke-width: 1; }"
            ".axis { stroke: black; stroke-width: 1; }"
            f".grid {{ stroke: {PLOT.colors['grid']}; stroke-opacity: {PLOT.grid_opacity}; }}"
            ".minor-grid { stroke: #d0d0d0; stroke-opacity: 0.22; stroke-width: 0.7; }"
            ".diagnosis-start { fill: white; stroke: #111111; stroke-width: 1.6; opacity: 0.92; }"
            ".diagnosis-non-converged { stroke: #b00020; stroke-width: 2.2; opacity: 0.9; }"
            ".diagnosis-truth { fill: none; stroke: #111111; stroke-width: 2.4; }"
            ".cluster-marker { fill: white; stroke: #1261a6; stroke-width: 2.4; opacity: 0.95; }"
            ".cluster-label { fill: #1261a6; font-size: 15px; font-weight: 700; }"
            ".marker-label { fill: #111111; font-weight: 700; }"
            "</style>"
        )


def retrieval_diagnosis_figure(
    diagnosis: RetrievalDiagnosis,
    *,
    cells: int = 150,
) -> RetrievalDiagnosisFigure:
    """Return the SVG figure for one multi-start diagnosis."""

    return RetrievalDiagnosisFigure(diagnosis=diagnosis, cells=int(cells))


def plot_domains(diagnosis: RetrievalDiagnosis) -> tuple[tuple[float, float], tuple[float, float]]:
    """Return padded axis domains, with pressure increasing downward."""

    x_values = [0.0, diagnosis.start_bounds[0][1]]
    y_values = [0.0, diagnosis.start_bounds[1][1]]

    for path in diagnosis_paths(diagnosis):
        for point in path:
            if finite_point(point):
                x_values.append(float(point[0]))
                y_values.append(float(point[1]))

    if diagnosis.truth_state is not None:
        x_values.append(float(diagnosis.truth_state[0]))
        y_values.append(float(diagnosis.truth_state[1]))

    x_high = max(2.25, max(x_values) * 1.12)
    y_high = max(1000.0, max(y_values) * 1.02)

    return (0.0, x_high), (0.0, y_high)


def diagnosis_paths(diagnosis: RetrievalDiagnosis) -> tuple[tuple[tuple[float, ...], ...], ...]:
    """Return plotted paths, falling back to start-to-result lines when needed."""

    if diagnosis.retrieval_paths:
        return tuple(
            (start, *path) if path else (start,)
            for start, path in zip(
                diagnosis.start_state,
                diagnosis.retrieval_paths,
                strict=True,
            )
        )

    return tuple(
        (start, end)
        for start, end in zip(diagnosis.start_state, diagnosis.retrieved_state, strict=True)
    )


def endpoint_clusters(
    diagnosis: RetrievalDiagnosis,
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> tuple[EndpointCluster, ...]:
    """Cluster converged finite endpoints in normalized panel coordinates."""

    clusters: list[EndpointCluster] = []
    paths = diagnosis_paths(diagnosis)

    for index, (path, status, converged) in enumerate(
        zip(paths, diagnosis.resolved_start_status(), diagnosis.converged, strict=True)
    ):
        if status != "ok" or not converged or not path or not finite_point(path[-1]):
            continue

        endpoint = tuple(float(value) for value in path[-1])

        for cluster_index, cluster in enumerate(clusters):
            if normalized_distance(endpoint, cluster.centroid, domains) <= ENDPOINT_CLUSTER_RADIUS:
                points = (*cluster.points, endpoint)
                clusters[cluster_index] = EndpointCluster(
                    indices=(*cluster.indices, index),
                    points=points,
                    centroid=centroid_of(points),
                )
                break
        else:
            clusters.append(
                EndpointCluster(indices=(index,), points=(endpoint,), centroid=endpoint)
            )

    return tuple(clusters)


def trimmed_plot_paths(
    diagnosis: RetrievalDiagnosis,
    clusters: Sequence[EndpointCluster],
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> tuple[tuple[tuple[float, ...], ...], ...]:
    """Stop paths at the endpoint-cluster boundary to avoid dense arrow knots."""

    trimmed = []

    for index, path in enumerate(diagnosis_paths(diagnosis)):
        cluster = cluster_for_path(index, clusters)

        if cluster is None:
            trimmed.append(path)
            continue

        centroid = cluster.centroid

        active_path = [path[0]]

        for point in path[1:]:
            if normalized_distance(point, centroid, domains) <= ENDPOINT_CLUSTER_RADIUS:
                active_path.append(centroid)
                break

            active_path.append(point)
        else:
            active_path.append(centroid)

        trimmed.append(tuple(active_path))

    return tuple(trimmed)


def cluster_for_path(index: int, clusters: Sequence[EndpointCluster]) -> EndpointCluster | None:
    """Return the endpoint cluster containing one path index."""

    for cluster in clusters:
        if index in cluster.indices:
            return cluster

    return None


def centroid_of(points: Sequence[tuple[float, ...]]) -> tuple[float, ...]:
    """Return the coordinate centroid for endpoint labels."""

    return tuple(
        sum(point[index] for point in points) / len(points) for index in range(len(points[0]))
    )


def segments(
    paths: Sequence[Sequence[Sequence[float]]],
) -> tuple[tuple[Sequence[float], Sequence[float]], ...]:
    """Return finite path segments."""

    return tuple(
        (first, second)
        for path in paths
        for first, second in zip(path, path[1:], strict=False)
        if finite_point(first) and finite_point(second)
    )


def segment_densities(
    path_segments: Sequence[tuple[Sequence[float], Sequence[float]]],
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> tuple[float, ...]:
    """Return local overlap density for each actual path segment."""

    midpoints = [segment_midpoint(first, second) for first, second in path_segments]

    return tuple(
        sum(
            math.exp(
                -0.5
                * normalized_distance2(midpoint, other, domains)
                / (PATH_DENSITY_BANDWIDTH * PATH_DENSITY_BANDWIDTH)
            )
            for other in midpoints
        )
        for midpoint in midpoints
    )


def segment_midpoint(first: Sequence[float], second: Sequence[float]) -> tuple[float, float]:
    """Return one segment midpoint in state coordinates."""

    return ((float(first[0]) + float(second[0])) * 0.5, (float(first[1]) + float(second[1])) * 0.5)


def path_svg(
    path_segments: Sequence[tuple[Sequence[float], Sequence[float]]],
    densities: Sequence[float],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render density-colored path segments and sparse arrowheads."""

    if not path_segments:
        return []

    low = min(densities)
    high = max(densities)
    elements = []

    for (first, second), density in zip(path_segments, densities, strict=True):
        normalized = 0.35 if high <= low else math.log1p(density - low) / math.log1p(high - low)
        color = density_color(normalized)
        stroke_width = 1.15 + 2.35 * normalized
        opacity = 0.35 + 0.46 * normalized
        x1 = x_value(first[0], x_domain)
        y1 = y_value(first[1], y_domain)
        x2 = x_value(second[0], x_domain)
        y2 = y_value(second[1], y_domain)
        elements.append(
            f'<line x1="{x1:.3f}" y1="{y1:.3f}" x2="{x2:.3f}" y2="{y2:.3f}" '
            f'stroke="{color}" stroke-width="{stroke_width:.3f}" '
            f'stroke-linecap="round" opacity="{opacity:.3f}" />'
        )
        elements.extend(arrowhead_svg(x1, y1, x2, y2, color, max(1.15, stroke_width * 0.64)))

    return elements


def arrowhead_svg(
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    color: str,
    stroke_width: float,
) -> list[str]:
    """Render one compact arrowhead unless the segment is too short."""

    if math.hypot(x2 - x1, y2 - y1) < 18.0:
        return []

    angle = math.atan2(y2 - y1, x2 - x1)
    length = 8.0
    spread = math.radians(28.0)
    left = (x2 - math.cos(angle - spread) * length, y2 - math.sin(angle - spread) * length)
    right = (x2 - math.cos(angle + spread) * length, y2 - math.sin(angle + spread) * length)
    attrs = (
        f'stroke="{color}" stroke-width="{stroke_width:.3f}" stroke-linecap="round" opacity="0.84"'
    )

    return [
        f'<line x1="{left[0]:.3f}" y1="{left[1]:.3f}" x2="{x2:.3f}" y2="{y2:.3f}" {attrs} />',
        f'<line x1="{right[0]:.3f}" y1="{right[1]:.3f}" x2="{x2:.3f}" y2="{y2:.3f}" {attrs} />',
    ]


def density_color(normalized: float) -> str:
    """Map path density to a blue-yellow-red ramp without rendering a colorbar."""

    value = max(0.0, min(1.0, normalized))

    if value < 0.5:
        amount = value / 0.5
        red = mix(73, 236, amount)
        green = mix(116, 185, amount)
        blue = mix(165, 91, amount)
    else:
        amount = (value - 0.5) / 0.5
        red = mix(236, 171, amount)
        green = mix(185, 28, amount)
        blue = mix(91, 47, amount)

    return f"#{red:02x}{green:02x}{blue:02x}"


def mix(left: int, right: int, amount: float) -> int:
    """Interpolate one RGB channel."""

    return round(left + (right - left) * amount)


def start_marker_svg(
    diagnosis: RetrievalDiagnosis,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render start-state circles."""

    return [
        f'<circle class="diagnosis-start" cx="{x_value(start[0], x_domain):.3f}" '
        f'cy="{y_value(start[1], y_domain):.3f}" r="5.1" />'
        for start in diagnosis.start_state
        if finite_point(start)
    ]


def non_converged_svg(
    diagnosis: RetrievalDiagnosis,
    paths: Sequence[Sequence[Sequence[float]]],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render terminal crosses for failed or non-converged starts."""

    elements = []

    for path, status, converged in zip(
        paths,
        diagnosis.resolved_start_status(),
        diagnosis.converged,
        strict=True,
    ):
        if status == "ok" and converged:
            continue

        point = path[-1] if path else ()

        if finite_point(point):
            elements.extend(cross_svg(point, x_domain, y_domain))

    return elements


def cluster_marker_svg(
    clusters: Sequence[EndpointCluster],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render endpoint cluster markers."""

    elements = []

    for cluster in clusters:
        centroid = cluster.centroid
        radius = 8.0 + 2.2 * math.sqrt(len(cluster.indices))
        elements.append(
            f'<circle class="cluster-marker" cx="{x_value(centroid[0], x_domain):.3f}" '
            f'cy="{y_value(centroid[1], y_domain):.3f}" r="{radius:.3f}" />'
        )

    return elements


def cluster_label_svg(
    clusters: Sequence[EndpointCluster],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render blue endpoint centroid labels."""

    elements = []

    for index, cluster in enumerate(sorted(clusters, key=lambda item: item.centroid[0])):
        centroid = cluster.centroid

        label = f"{centroid[0]:.3g}, {centroid[1]:.0f} hPa"
        dx = 18.0
        dy = 24.0 if index == 0 else 23.0
        elements.append(
            f'<text class="cluster-label" x="{x_value(centroid[0], x_domain) + dx:.3f}" '
            f'y="{y_value(centroid[1], y_domain) + dy:.3f}">{escape(label)}</text>'
        )

    return elements


def truth_svg(
    point: Sequence[float],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render a labelled truth marker only when truth is known."""

    x = x_value(point[0], x_domain)
    y = y_value(point[1], y_domain)
    label = f"truth ({float(point[0]):.3g}, {float(point[1]):.0f} hPa)"

    return [
        f'<line class="diagnosis-truth" x1="{x - 9:.3f}" x2="{x + 9:.3f}" '
        f'y1="{y:.3f}" y2="{y:.3f}" />',
        f'<line class="diagnosis-truth" x1="{x:.3f}" x2="{x:.3f}" '
        f'y1="{y - 9:.3f}" y2="{y + 9:.3f}" />',
        f'<text class="marker-label" x="{x + 12:.3f}" y="{y - 40:.3f}">{escape(label)}</text>',
    ]


def cross_svg(
    point: Sequence[float],
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render one non-convergence/failure marker."""

    x = x_value(point[0], x_domain)
    y = y_value(point[1], y_domain)

    return [
        f'<line class="diagnosis-non-converged" x1="{x - 7:.3f}" x2="{x + 7:.3f}" '
        f'y1="{y - 7:.3f}" y2="{y + 7:.3f}" />',
        f'<line class="diagnosis-non-converged" x1="{x - 7:.3f}" x2="{x + 7:.3f}" '
        f'y1="{y + 7:.3f}" y2="{y - 7:.3f}" />',
    ]


def non_converged_paths(diagnosis: RetrievalDiagnosis) -> list[tuple[tuple[float, ...], ...]]:
    """Return paths that failed or returned without convergence."""

    return [
        path
        for path, status, converged in zip(
            diagnosis_paths(diagnosis),
            diagnosis.resolved_start_status(),
            diagnosis.converged,
            strict=True,
        )
        if status != "ok" or not converged
    ]


def finite_point(point: Sequence[float]) -> bool:
    """Return whether a plotted state-space point is finite."""

    return len(point) >= 2 and all(math.isfinite(float(value)) for value in point[:2])


def axis_svg(
    diagnosis: RetrievalDiagnosis,
    x_domain: tuple[float, float],
    y_domain: tuple[float, float],
) -> list[str]:
    """Render axes, pseudo-log x ticks, grid, and labels."""

    elements = [
        f'<line class="axis" x1="0" x2="{PANEL_WIDTH}" y1="{PANEL_HEIGHT}" y2="{PANEL_HEIGHT}" />',
        f'<line class="axis" x1="0" x2="0" y1="0" y2="{PANEL_HEIGHT}" />',
    ]

    for value in minor_x_ticks(x_domain):
        x = x_value(value, x_domain)
        elements.append(
            f'<line class="minor-grid" x1="{x:.3f}" x2="{x:.3f}" y1="0" y2="{PANEL_HEIGHT}" />'
        )
        elements.append(
            f'<line class="axis" x1="{x:.3f}" x2="{x:.3f}" '
            f'y1="{PANEL_HEIGHT}" y2="{PANEL_HEIGHT + 7}" opacity="0.55" />'
        )

    for value in major_x_ticks(x_domain):
        x = x_value(value, x_domain)
        label = "0" if value == 0.0 else format_tick(value, None)
        elements.append(
            f'<line class="grid" x1="{x:.3f}" x2="{x:.3f}" y1="0" y2="{PANEL_HEIGHT}" />'
        )
        elements.append(
            f'<line class="axis" x1="{x:.3f}" x2="{x:.3f}" '
            f'y1="{PANEL_HEIGHT}" y2="{PANEL_HEIGHT + 12}" />'
        )

        if not math.isclose(value, 0.01):
            elements.append(
                f'<text class="tick-label" x="{x:.3f}" y="{PANEL_HEIGHT + 31}" '
                f'text-anchor="middle">{escape(label)}</text>'
            )

    for value in y_ticks(y_domain):
        y = y_value(value, y_domain)
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
        ]
    )

    return elements


def major_x_ticks(x_domain: tuple[float, float]) -> tuple[float, ...]:
    """Return conventional pseudo-log AOD tick labels."""

    return tuple(
        value for value in (0.0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0) if value <= x_domain[1]
    )


def minor_x_ticks(x_domain: tuple[float, float]) -> tuple[float, ...]:
    """Return pseudo-log minor ticks between labelled AOD ticks."""

    return tuple(
        value
        for value in (0.03, 0.04, 0.06, 0.07, 0.08, 0.09, 0.3, 0.4, 0.6, 0.7, 0.8, 0.9, 1.5)
        if value <= x_domain[1]
    )


def y_ticks(y_domain: tuple[float, float]) -> tuple[float, ...]:
    """Return pressure ticks with zero and surface-side padding."""

    return tuple(
        value
        for value in (0.0, 100.0, 225.0, 350.0, 500.0, 650.0, 800.0, 950.0, 1000.0)
        if value <= y_domain[1]
    )


def x_value(value: float, x_domain: tuple[float, float]) -> float:
    """Map AOD to the pseudo-log plot coordinate."""

    low, high = x_domain
    clamped = max(low, min(float(value), high))
    unit = math.log1p(clamped / AOD_PSEUDO_LOG_SCALE) / math.log1p(high / AOD_PSEUDO_LOG_SCALE)

    return unit * PANEL_WIDTH


def y_value(value: float, y_domain: tuple[float, float]) -> float:
    """Map pressure to the plot coordinate, increasing downward."""

    low, high = y_domain
    clamped = max(low, min(float(value), high))

    return (clamped - low) / (high - low) * PANEL_HEIGHT


def normalized_point(
    point: Sequence[float],
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> tuple[float, float]:
    """Return a point in normalized plotted coordinates."""

    x_domain, y_domain = domains

    return (
        x_value(point[0], x_domain) / PANEL_WIDTH,
        y_value(point[1], y_domain) / PANEL_HEIGHT,
    )


def normalized_distance(
    first: Sequence[float],
    second: Sequence[float],
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> float:
    """Return normalized plotted distance between two points."""

    return math.sqrt(normalized_distance2(first, second, domains))


def normalized_distance2(
    first: Sequence[float],
    second: Sequence[float],
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> float:
    """Return squared normalized plotted distance between two points."""

    first_x, first_y = normalized_point(first, domains)
    second_x, second_y = normalized_point(second, domains)

    return (first_x - second_x) * (first_x - second_x) + (first_y - second_y) * (first_y - second_y)
