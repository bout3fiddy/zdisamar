"""Multi-start optimal-estimation diagnosis objects."""

import math
import os
import statistics
import time
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

from ... import rtm
from ...display import NotebookDisplay, PrettyMapping
from ...input.wavelength_band.o2a import Scene
from .retrieval import Measurement, RetrievalControls
from .state_vector import (
    AEROSOL_LAYER_MID_PRESSURE_HPA,
    AEROSOL_OPTICAL_DEPTH,
    StateName,
    StateVector,
)

DIAGNOSIS_AOD_LOWER = 0.02
DIAGNOSIS_AOD_PSEUDO_LOG_SCALE = 0.08
DIAGNOSIS_DEFAULT_START_CAP = 30
ADAPTIVE_MIN_STARTS = 16
ADAPTIVE_COARSE_FRACTION = 0.7
ADAPTIVE_ENDPOINT_SPLIT_DISTANCE = 0.12
BOUNDARY_BISECTION_INITIAL_SIDE = 3
BOUNDARY_BISECTION_BATCH_SIZE = 10
BOUNDARY_BISECTION_NEIGHBORS = 2
BOUNDARY_BISECTION_ENDPOINT_DISTANCE = 0.10
BOUNDARY_BISECTION_SCORE_THRESHOLD = 4.0
BOUNDARY_BISECTION_FRACTIONS = (0.5, 0.25, 0.125, 0.75, 0.0625, 0.875, 0.9375)
RETRIEVAL_BASIN_CLUSTER_RADIUS = 0.055


@dataclass(frozen=True)
class DiagnosisBatchSummary:
    """Combined native batch output for one diagnosis schedule."""

    state: tuple[tuple[float, ...], ...]
    iterations: tuple[int, ...]
    converged: tuple[bool, ...]
    status: tuple[str, ...]
    history_state: tuple[tuple[tuple[float, ...], ...], ...]
    fast_stage_iterations: tuple[int, ...] | None
    fast_stage_converged: tuple[bool, ...] | None
    full_correction_iterations: tuple[int, ...] | None
    full_correction_converged: tuple[bool, ...] | None


@dataclass(frozen=True)
class RetrievalBasin:
    """Converged endpoint group from a multi-start retrieval."""

    state_names: tuple[StateName, ...]
    indices: tuple[int, ...]
    starts: tuple[tuple[float, ...], ...]
    points: tuple[tuple[float, ...], ...]
    centroid: tuple[float, ...]
    iterations: tuple[int, ...]

    @property
    def run_count(self) -> int:
        """Return the number of starts that reached this basin."""

        return len(self.indices)

    @property
    def start_indices(self) -> tuple[int, ...]:
        """Return one-based start row indices in this basin."""

        return tuple(index + 1 for index in self.indices)

    def value(self, name: StateName) -> float:
        """Return one centroid coordinate by state name."""

        return float(self.centroid[self.state_names.index(name)])

    def to_dict(self) -> dict[str, object]:
        """Return a notebook-friendly basin summary."""

        return {
            "runs": self.run_count,
            "start_indices": list(self.start_indices),
            "retrieved": {
                name: float(self.centroid[index]) for index, name in enumerate(self.state_names)
            },
            "retrieved_spread": {
                name: numeric_stats(tuple(point[index] for point in self.points))
                for index, name in enumerate(self.state_names)
            },
            "start_range": {
                name: {
                    "min": min(start[index] for start in self.starts),
                    "max": max(start[index] for start in self.starts),
                }
                for index, name in enumerate(self.state_names)
            },
            "iterations": numeric_stats(self.iterations),
        }

    def __repr__(self) -> str:

        retrieved = ", ".join(
            f"{name}={self.centroid[index]:.4g}" for index, name in enumerate(self.state_names)
        )

        return f"RetrievalBasin(runs={self.run_count}, {retrieved})"


@dataclass(frozen=True)
class BoundaryBisectionStrategy:
    """Seed starts inside brackets whose endpoints retrieve to different outcomes."""

    initial_side: int = BOUNDARY_BISECTION_INITIAL_SIDE
    refinement_batch_size: int = BOUNDARY_BISECTION_BATCH_SIZE
    neighbor_count: int = BOUNDARY_BISECTION_NEIGHBORS
    endpoint_distance: float = BOUNDARY_BISECTION_ENDPOINT_DISTANCE
    score_threshold: float = BOUNDARY_BISECTION_SCORE_THRESHOLD
    bracket_fractions: tuple[float, ...] = BOUNDARY_BISECTION_FRACTIONS

    def initial_rows(
        self,
        axes: tuple[tuple[float, float], ...],
    ) -> tuple[tuple[float, ...], ...]:
        """Return the opening space-filling starts."""

        return square_start_grid(axes, self.initial_side)

    def refinement_rows(
        self,
        *,
        axes: tuple[tuple[float, float], ...],
        start_rows: tuple[tuple[float, ...], ...],
        batch: DiagnosisBatchSummary,
        count: int,
    ) -> tuple[tuple[float, ...], ...]:
        """Return behavior-aware starts for the next batch."""

        return boundary_bisection_refinement_rows(
            strategy=self,
            axes=axes,
            start_rows=start_rows,
            batch=batch,
            count=count,
        )


@dataclass(frozen=True)
class RetrievalDiagnosis(NotebookDisplay):
    """Final states from many starts of the same inverse problem."""

    state_names: tuple[StateName, ...]
    start_state: tuple[tuple[float, ...], ...]
    retrieved_state: tuple[tuple[float, ...], ...]
    iterations: tuple[int, ...]
    converged: tuple[bool, ...]
    retrieval_paths: tuple[tuple[tuple[float, ...], ...], ...]
    start_bounds: tuple[tuple[float, float], ...]
    batch_workers: int
    truth_state: tuple[float, ...] | None = None
    start_status: tuple[str, ...] = ()
    fast_stage_iterations: tuple[int, ...] | None = None
    fast_stage_converged: tuple[bool, ...] | None = None
    full_correction_iterations: tuple[int, ...] | None = None
    full_correction_converged: tuple[bool, ...] | None = None
    native_worker_limit: int | None = None
    elapsed_s: float = 0.0

    def value(self, name: StateName) -> tuple[float, ...]:
        """Return one retrieved state column by name."""

        index = self.state_names.index(name)

        return tuple(row[index] for row in self.retrieved_state)

    def start_value(self, name: StateName) -> tuple[float, ...]:
        """Return one start-state column by name."""

        index = self.state_names.index(name)

        return tuple(row[index] for row in self.start_state)

    def resolved_start_status(self) -> tuple[str, ...]:
        """Return one status label per start row."""

        if self.start_status:
            return self.start_status

        return ("ok",) * len(self.start_state)

    def basins(self) -> tuple[RetrievalBasin, ...]:
        """Return converged endpoint groups shown as basin markers in the plot."""

        return retrieval_basins(self)

    def to_dict(self) -> dict[str, object]:
        """Return a compact diagnosis summary."""

        state_payload = {}

        for index, name in enumerate(self.state_names):
            retrieved = [row[index] for row in self.retrieved_state]
            starts = [row[index] for row in self.start_state]
            state_payload[name] = {
                "start": {
                    "min": min(starts),
                    "max": max(starts),
                    "bounds": list(self.start_bounds[index]),
                },
                "retrieved": numeric_stats(retrieved),
                "truth": None if self.truth_state is None else self.truth_state[index],
            }

        non_converged = sum(
            1
            for status, converged in zip(
                self.resolved_start_status(),
                self.converged,
                strict=True,
            )
            if status != "ok" or not converged
        )
        basins = self.basins()

        return {
            "runs": len(self.start_state),
            "converged": sum(1 for value in self.converged if value),
            "non_converged": non_converged,
            "basin_count": len(basins),
            "basins": [basin.to_dict() for basin in basins],
            "batch_workers": self.batch_workers,
            "native_worker_limit": self.native_worker_limit,
            "elapsed_s": self.elapsed_s,
            "retrievals_per_s": (
                len(self.start_state) / self.elapsed_s if self.elapsed_s > 0.0 else math.nan
            ),
            "iterations": numeric_stats(self.iterations),
            "state": state_payload,
        }

    def summary(self) -> PrettyMapping:
        """Return a notebook-friendly diagnosis summary."""

        return PrettyMapping("RetrievalDiagnosis", self.to_dict())

    def plot(
        self,
        save: str | Path | None = None,
    ):
        """Render the retrieval path plot as SVG."""

        from ...plot.properties import PLOT
        from ...plot.retrieval_diagnosis import retrieval_diagnosis_figure

        return PLOT.finish(retrieval_diagnosis_figure(self), save=save)

    def __repr__(self) -> str:

        return repr(self.summary())


def diagnose_retrieval(
    *,
    scene: Scene,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    n: int | None = None,
    batch_workers: int | None = None,
    cache: rtm.SessionCache | None = None,
    start_rows: Sequence[Sequence[float]] | None = None,
    seeding_strategy: BoundaryBisectionStrategy | None = None,
) -> RetrievalDiagnosis:
    """Run a same-scene multi-start sweep using the native batch path."""

    if n is not None and n <= 0:
        raise ValueError("n must be positive")

    explicit_start_rows = (
        None
        if start_rows is None
        else tuple(tuple(float(value) for value in row) for row in start_rows)
    )

    if explicit_start_rows is not None and not explicit_start_rows:
        raise ValueError("start_rows must not be empty")

    if explicit_start_rows is None and n is not None and n > DIAGNOSIS_DEFAULT_START_CAP:
        raise ValueError(f"n must be at most {DIAGNOSIS_DEFAULT_START_CAP}")

    axes = diagnosis_bounds(scene, state_vector)
    active_start_count = (
        len(explicit_start_rows)
        if explicit_start_rows is not None
        else DIAGNOSIS_DEFAULT_START_CAP
        if n is None
        else n
    )
    native_worker_limit = native_worker_ceiling()
    active_batch_workers = (
        diagnosis_batch_worker_count_for_limit(active_start_count, native_worker_limit)
        if batch_workers is None
        else batch_workers
    )

    if active_batch_workers <= 0:
        raise ValueError("batch_workers must be positive")

    from . import o2a as o2a_oe

    start_s = time.perf_counter()
    active_start_rows, batch = run_diagnosis_schedule(
        o2a_oe,
        scene=scene,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        batch_workers=active_batch_workers,
        axes=axes,
        start_count=active_start_count,
        dynamic=n is None and explicit_start_rows is None,
        explicit_start_rows=explicit_start_rows,
        seeding_strategy=seeding_strategy,
    )
    elapsed_s = time.perf_counter() - start_s

    return RetrievalDiagnosis(
        state_names=state_vector.names,
        start_state=active_start_rows,
        retrieved_state=batch.state,
        iterations=batch.iterations,
        converged=batch.converged,
        retrieval_paths=batch.history_state,
        start_bounds=axes,
        batch_workers=active_batch_workers,
        start_status=(batch.status if batch.status else ("ok",) * len(active_start_rows)),
        fast_stage_iterations=batch.fast_stage_iterations,
        fast_stage_converged=batch.fast_stage_converged,
        full_correction_iterations=batch.full_correction_iterations,
        full_correction_converged=batch.full_correction_converged,
        native_worker_limit=native_worker_limit,
        elapsed_s=elapsed_s,
    )


def run_diagnosis_schedule(
    o2a_oe,
    *,
    scene: Scene,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache | None,
    batch_workers: int,
    axes: tuple[tuple[float, float], ...],
    start_count: int,
    dynamic: bool,
    explicit_start_rows: tuple[tuple[float, ...], ...] | None,
    seeding_strategy: BoundaryBisectionStrategy | None,
) -> tuple[tuple[tuple[float, ...], ...], DiagnosisBatchSummary]:
    """Run either the exact supplied starts or the adaptive default schedule."""

    if explicit_start_rows is not None:
        if not explicit_start_rows:
            raise ValueError("start_rows must not be empty")

        batch = run_diagnosis_batch(
            o2a_oe,
            scene=scene,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=cache,
            batch_workers=batch_workers,
            start_rows=explicit_start_rows,
        )

        return explicit_start_rows, batch

    if dynamic:
        return run_dynamic_diagnosis_schedule(
            o2a_oe,
            scene=scene,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=cache,
            batch_workers=batch_workers,
            axes=axes,
            start_cap=start_count,
            seeding_strategy=seeding_strategy or BoundaryBisectionStrategy(),
        )

    if start_count < ADAPTIVE_MIN_STARTS:
        start_rows = diagnosis_start_grid(axes, start_count)
        batch = run_diagnosis_batch(
            o2a_oe,
            scene=scene,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=cache,
            batch_workers=batch_workers,
            start_rows=start_rows,
        )

        return start_rows, batch

    coarse_side = adaptive_coarse_side(start_count)
    coarse_rows = square_start_grid(axes, coarse_side)
    coarse_batch = run_diagnosis_batch(
        o2a_oe,
        scene=scene,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        batch_workers=batch_workers,
        start_rows=coarse_rows,
    )
    remaining_count = start_count - len(coarse_rows)
    refinement_rows = adaptive_refinement_rows(
        axes=axes,
        side=coarse_side,
        coarse_rows=coarse_rows,
        coarse_batch=coarse_batch,
        count=remaining_count,
    )

    if not refinement_rows:
        return coarse_rows, coarse_batch

    refinement_batch = run_diagnosis_batch(
        o2a_oe,
        scene=scene,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        batch_workers=batch_workers,
        start_rows=refinement_rows,
    )

    return coarse_rows + refinement_rows, combine_batch_summaries(coarse_batch, refinement_batch)


def run_diagnosis_batch(
    o2a_oe,
    *,
    scene: Scene,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache | None,
    batch_workers: int,
    start_rows: tuple[tuple[float, ...], ...],
) -> DiagnosisBatchSummary:
    """Run one native diagnosis batch and copy the relevant summary fields."""

    batch = o2a_oe.diagnosis_batch(
        scene=scene,
        measurement=measurement,
        state_vector=state_vector,
        start_rows=start_rows,
        controls=controls,
        cache=cache,
        batch_workers=batch_workers,
    )

    return DiagnosisBatchSummary(
        state=batch.state,
        iterations=batch.iterations,
        converged=batch.converged,
        status=batch.status if batch.status else ("ok",) * len(start_rows),
        history_state=batch.history_state,
        fast_stage_iterations=batch.fast_stage_iterations,
        fast_stage_converged=batch.fast_stage_converged,
        full_correction_iterations=batch.full_correction_iterations,
        full_correction_converged=batch.full_correction_converged,
    )


def run_dynamic_diagnosis_schedule(
    o2a_oe,
    *,
    scene: Scene,
    measurement: Measurement,
    state_vector: StateVector,
    controls: RetrievalControls | None,
    cache: rtm.SessionCache | None,
    batch_workers: int,
    axes: tuple[tuple[float, float], ...],
    start_cap: int,
    seeding_strategy: BoundaryBisectionStrategy,
) -> tuple[tuple[tuple[float, ...], ...], DiagnosisBatchSummary]:
    """Run the default bounded zoning schedule without requiring a point count."""

    active_rows = seeding_strategy.initial_rows(axes)
    active_batch = run_diagnosis_batch(
        o2a_oe,
        scene=scene,
        measurement=measurement,
        state_vector=state_vector,
        controls=controls,
        cache=cache,
        batch_workers=batch_workers,
        start_rows=active_rows,
    )

    while len(active_rows) < start_cap:
        remaining_count = start_cap - len(active_rows)
        refinement_rows = seeding_strategy.refinement_rows(
            axes=axes,
            start_rows=active_rows,
            batch=active_batch,
            count=min(remaining_count, seeding_strategy.refinement_batch_size),
        )

        if not refinement_rows:
            break

        refinement_batch = run_diagnosis_batch(
            o2a_oe,
            scene=scene,
            measurement=measurement,
            state_vector=state_vector,
            controls=controls,
            cache=cache,
            batch_workers=batch_workers,
            start_rows=refinement_rows,
        )
        active_rows += refinement_rows
        active_batch = combine_batch_summaries(active_batch, refinement_batch)

    return active_rows, active_batch


def combine_batch_summaries(
    first: DiagnosisBatchSummary,
    second: DiagnosisBatchSummary,
) -> DiagnosisBatchSummary:
    """Concatenate two diagnosis batch summaries from the same scene."""

    return DiagnosisBatchSummary(
        state=first.state + second.state,
        iterations=first.iterations + second.iterations,
        converged=first.converged + second.converged,
        status=first.status + second.status,
        history_state=first.history_state + second.history_state,
        fast_stage_iterations=combine_optional_ints(
            first.fast_stage_iterations,
            second.fast_stage_iterations,
        ),
        fast_stage_converged=combine_optional_bools(
            first.fast_stage_converged,
            second.fast_stage_converged,
        ),
        full_correction_iterations=combine_optional_ints(
            first.full_correction_iterations,
            second.full_correction_iterations,
        ),
        full_correction_converged=combine_optional_bools(
            first.full_correction_converged,
            second.full_correction_converged,
        ),
    )


def combine_optional_ints(
    first: tuple[int, ...] | None,
    second: tuple[int, ...] | None,
) -> tuple[int, ...] | None:
    """Concatenate optional integer arrays when both stages returned them."""

    if first is None or second is None:
        return None

    return first + second


def combine_optional_bools(
    first: tuple[bool, ...] | None,
    second: tuple[bool, ...] | None,
) -> tuple[bool, ...] | None:
    """Concatenate optional boolean arrays when both stages returned them."""

    if first is None or second is None:
        return None

    return first + second


def diagnosis_paths(diagnosis: RetrievalDiagnosis) -> tuple[tuple[tuple[float, ...], ...], ...]:
    """Return retrieval paths, falling back to start-to-result lines when needed."""

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


def diagnosis_plot_domains(
    diagnosis: RetrievalDiagnosis,
) -> tuple[tuple[float, float], tuple[float, float]]:
    """Return the first two diagnosis domains used for path plots."""

    if not diagnosis_plot_axes_available(diagnosis):
        return (0.0, 1.0), (0.0, 1.0)

    x_values = list(diagnosis.start_bounds[0])
    y_values = list(diagnosis.start_bounds[1])

    for path in diagnosis_paths(diagnosis):
        for point in path:
            if finite_plot_point(point):
                x_values.append(float(point[0]))
                y_values.append(float(point[1]))

    if diagnosis.truth_state is not None:
        x_values.append(float(diagnosis.truth_state[0]))
        y_values.append(float(diagnosis.truth_state[1]))

    x_lower_floor = 0.0 if diagnosis.state_names[0] == AEROSOL_OPTICAL_DEPTH else None
    x_upper_floor = 2.25 if diagnosis.state_names[0] == AEROSOL_OPTICAL_DEPTH else None
    y_lower_floor = 0.0 if diagnosis.state_names[1] == AEROSOL_LAYER_MID_PRESSURE_HPA else None
    y_upper_floor = 1000.0 if diagnosis.state_names[1] == AEROSOL_LAYER_MID_PRESSURE_HPA else None

    return (
        axis_domain(
            diagnosis.start_bounds[0],
            x_values,
            lower_floor=x_lower_floor,
            upper_floor=x_upper_floor,
            padding_fraction=0.12,
        ),
        axis_domain(
            diagnosis.start_bounds[1],
            y_values,
            lower_floor=y_lower_floor,
            upper_floor=y_upper_floor,
            padding_fraction=0.02,
        ),
    )


def retrieval_basin_domains(
    diagnosis: RetrievalDiagnosis,
) -> tuple[tuple[float, float], tuple[float, float]]:
    """Return axis domains for two-state basin clustering."""

    if not retrieval_basin_axes_available(diagnosis):
        return (0.0, 1.0), (0.0, 1.0)

    x_values = list(diagnosis.start_bounds[0])
    y_values = list(diagnosis.start_bounds[1])

    for path, status, converged in zip(
        diagnosis_paths(diagnosis),
        diagnosis.resolved_start_status(),
        diagnosis.converged,
        strict=True,
    ):
        if status == "ok" and converged and path and finite_plot_point(path[-1]):
            x_values.append(float(path[-1][0]))
            y_values.append(float(path[-1][1]))

    return (
        axis_domain(diagnosis.start_bounds[0], x_values),
        axis_domain(diagnosis.start_bounds[1], y_values),
    )


def retrieval_basins(
    diagnosis: RetrievalDiagnosis,
    *,
    domains: tuple[tuple[float, float], tuple[float, float]] | None = None,
    radius: float = RETRIEVAL_BASIN_CLUSTER_RADIUS,
) -> tuple[RetrievalBasin, ...]:
    """Cluster converged finite endpoints in normalized plotted coordinates."""

    if not retrieval_basin_axes_available(diagnosis):
        return ()

    active_domains = retrieval_basin_domains(diagnosis) if domains is None else domains
    basins: list[RetrievalBasin] = []
    paths = diagnosis_paths(diagnosis)

    for index, (path, status, converged) in enumerate(
        zip(paths, diagnosis.resolved_start_status(), diagnosis.converged, strict=True)
    ):
        if status != "ok" or not converged or not path or not finite_plot_point(path[-1]):
            continue

        endpoint = tuple(float(value) for value in path[-1])
        start = tuple(float(value) for value in diagnosis.start_state[index])
        iterations = (int(diagnosis.iterations[index]),)

        for basin_index, basin in enumerate(basins):
            if plot_distance(endpoint, basin.centroid, active_domains) <= radius:
                points = (*basin.points, endpoint)
                basins[basin_index] = RetrievalBasin(
                    state_names=diagnosis.state_names,
                    indices=(*basin.indices, index),
                    starts=(*basin.starts, start),
                    points=points,
                    centroid=centroid_of(points),
                    iterations=basin.iterations + iterations,
                )
                break
        else:
            basins.append(
                RetrievalBasin(
                    state_names=diagnosis.state_names,
                    indices=(index,),
                    starts=(start,),
                    points=(endpoint,),
                    centroid=endpoint,
                    iterations=iterations,
                )
            )

    return tuple(sorted(basins, key=lambda basin: (basin.centroid[0], basin.centroid[1])))


def retrieval_basin_axes_available(diagnosis: RetrievalDiagnosis) -> bool:
    """Return whether basin summaries can represent every active state axis."""

    return len(diagnosis.state_names) == 2 and len(diagnosis.start_bounds) == 2


def diagnosis_plot_axes_available(diagnosis: RetrievalDiagnosis) -> bool:
    """Return whether the diagnosis has two axes available for path plots."""

    return len(diagnosis.state_names) >= 2 and len(diagnosis.start_bounds) >= 2


def finite_plot_point(point: Sequence[float]) -> bool:
    """Return whether a point contains finite first-two plot coordinates."""

    return len(point) >= 2 and all(math.isfinite(float(value)) for value in point[:2])


def axis_domain(
    bounds: tuple[float, float],
    values: Sequence[float],
    *,
    lower_floor: float | None = None,
    upper_floor: float | None = None,
    padding_fraction: float = 0.0,
) -> tuple[float, float]:
    """Return a finite domain from explicit bounds and optional plot padding."""

    finite = [float(value) for value in values if math.isfinite(float(value))]
    lower = min((float(bounds[0]), *finite))
    upper = max((float(bounds[1]), *finite))

    if lower_floor is not None:
        lower = min(lower, float(lower_floor))

    if upper_floor is not None:
        upper = max(upper, float(upper_floor))

    if not upper > lower:
        padding = max(abs(lower) * 0.05, 1.0e-12)

        return lower - padding, upper + padding

    if padding_fraction > 0.0:
        upper += (upper - lower) * padding_fraction

    return lower, upper


def plot_distance(
    first: Sequence[float],
    second: Sequence[float],
    domains: tuple[tuple[float, float], tuple[float, float]],
) -> float:
    """Return plotted-coordinate distance between two state-space points."""

    first_point = tuple(first[index] for index in range(2))
    second_point = tuple(second[index] for index in range(2))

    return point_distance(
        plot_normalized_point(first_point, domains),
        plot_normalized_point(second_point, domains),
    )


def centroid_of(points: Sequence[tuple[float, ...]]) -> tuple[float, ...]:
    """Return the coordinate centroid for a non-empty endpoint group."""

    return tuple(
        statistics.fmean(point[index] for point in points) for index in range(len(points[0]))
    )


def adaptive_coarse_side(start_count: int) -> int:
    """Choose the square coarse grid side for the first adaptive pass."""

    maximum_side = max(3, math.isqrt(start_count))
    side = max(3, int(math.floor(math.sqrt(start_count * ADAPTIVE_COARSE_FRACTION))))

    if side >= maximum_side and maximum_side * maximum_side >= start_count:
        side = maximum_side - 1

    return max(3, side)


def boundary_bisection_refinement_rows(
    *,
    strategy: BoundaryBisectionStrategy,
    axes: tuple[tuple[float, float], ...],
    start_rows: tuple[tuple[float, ...], ...],
    batch: DiagnosisBatchSummary,
    count: int,
) -> tuple[tuple[float, ...], ...]:
    """Choose starts along observed behavior boundaries in plotted coordinates."""

    if count <= 0:
        return ()

    outcomes = boundary_bisection_outcomes(axes, batch, strategy)
    contention_edges = []
    other_edges = []

    for first_index, second_index in boundary_bisection_neighbor_pairs(axes, start_rows, strategy):
        score = boundary_bisection_edge_score(
            axes,
            start_rows,
            batch,
            outcomes,
            first_index,
            second_index,
        )

        if score < strategy.score_threshold:
            continue

        edge = (score, first_index, second_index)

        if boundary_bisection_edge_is_contentious(outcomes, first_index, second_index):
            contention_edges.append(edge)
        else:
            other_edges.append(edge)

    contention_edges.sort(key=lambda item: item[0], reverse=True)
    other_edges.sort(key=lambda item: item[0], reverse=True)
    candidates = [
        boundary_bisection_interpolated_point(
            axes,
            start_rows[first_index],
            start_rows[second_index],
            fraction=fraction,
        )
        for fraction in strategy.bracket_fractions
        for _, first_index, second_index in contention_edges
    ]
    candidates.extend(
        boundary_bisection_interpolated_point(
            axes,
            start_rows[first_index],
            start_rows[second_index],
            fraction=0.5,
        )
        for _, first_index, second_index in other_edges
    )

    return unique_candidate_rows(
        axes,
        existing=start_rows,
        candidates=candidates,
        count=count,
    )


def boundary_bisection_outcomes(
    axes: tuple[tuple[float, float], ...],
    batch: DiagnosisBatchSummary,
    strategy: BoundaryBisectionStrategy,
) -> tuple[int | None, ...]:
    """Cluster converged endpoints; use None for non-converged or invalid starts."""

    centers: list[tuple[float, ...]] = []
    counts: list[int] = []
    labels = []

    for state, status, converged in zip(batch.state, batch.status, batch.converged, strict=True):
        if status != "ok" or not converged or not finite_values(state):
            labels.append(None)
            continue

        point = plot_normalized_point(state, axes)

        for center_index, center in enumerate(centers):
            if point_distance(point, center) <= strategy.endpoint_distance:
                count = counts[center_index] + 1
                centers[center_index] = tuple(
                    (center[axis_index] * counts[center_index] + point[axis_index]) / count
                    for axis_index in range(len(point))
                )
                counts[center_index] = count
                labels.append(center_index)
                break
        else:
            centers.append(point)
            counts.append(1)
            labels.append(len(centers) - 1)

    return tuple(labels)


def boundary_bisection_neighbor_pairs(
    axes: tuple[tuple[float, float], ...],
    start_rows: tuple[tuple[float, ...], ...],
    strategy: BoundaryBisectionStrategy,
) -> tuple[tuple[int, int], ...]:
    """Return nearest-neighbor start pairs in the same coordinates used by the plot."""

    points = [plot_normalized_point(row, axes) for row in start_rows]
    pairs: set[tuple[int, int]] = set()

    for first_index, point in enumerate(points):
        distances = sorted(
            (
                point_distance(point, other),
                second_index,
            )
            for second_index, other in enumerate(points)
            if second_index != first_index
        )

        for _, second_index in distances[: strategy.neighbor_count]:
            lower_index = min(first_index, second_index)
            upper_index = max(first_index, second_index)
            pairs.add((lower_index, upper_index))

    return tuple(
        pair
        for _, pair in sorted(
            (
                point_distance(points[first_index], points[second_index]),
                (first_index, second_index),
            )
            for first_index, second_index in pairs
        )
    )


def boundary_bisection_edge_is_contentious(
    outcomes: tuple[int | None, ...],
    first_index: int,
    second_index: int,
) -> bool:
    """Return whether a neighbor edge separates different retrieval behavior."""

    return outcomes[first_index] != outcomes[second_index]


def boundary_bisection_edge_score(
    axes: tuple[tuple[float, float], ...],
    start_rows: tuple[tuple[float, ...], ...],
    batch: DiagnosisBatchSummary,
    outcomes: tuple[int | None, ...],
    first_index: int,
    second_index: int,
) -> float:
    """Score a neighbor edge by whether retrieval behavior changes across it."""

    first_outcome = outcomes[first_index]
    second_outcome = outcomes[second_index]
    first_failed = first_outcome is None
    second_failed = second_outcome is None
    score = 0.0

    if first_failed != second_failed:
        score += 12.0
    elif first_failed and second_failed:
        score += 2.0
    elif first_outcome != second_outcome:
        score += 10.0

    endpoint_distance = boundary_bisection_endpoint_distance(axes, batch, first_index, second_index)

    if endpoint_distance is not None:
        score += 4.0 * endpoint_distance

    score += boundary_bisection_path_score(axes, start_rows, batch, first_index, second_index)

    if score <= 0.0:
        return 0.0

    start_distance = point_distance(
        plot_normalized_point(start_rows[first_index], axes),
        plot_normalized_point(start_rows[second_index], axes),
    )

    return score / (0.35 + start_distance)


def boundary_bisection_endpoint_distance(
    axes: tuple[tuple[float, float], ...],
    batch: DiagnosisBatchSummary,
    first_index: int,
    second_index: int,
) -> float | None:
    """Return plotted endpoint distance when both endpoints are finite."""

    first = batch.state[first_index]
    second = batch.state[second_index]

    if not finite_values(first) or not finite_values(second):
        return None

    return point_distance(plot_normalized_point(first, axes), plot_normalized_point(second, axes))


def boundary_bisection_path_score(
    axes: tuple[tuple[float, float], ...],
    start_rows: tuple[tuple[float, ...], ...],
    batch: DiagnosisBatchSummary,
    first_index: int,
    second_index: int,
) -> float:
    """Score long or iteration-heavy paths without making them dominate boundaries."""

    path_lengths = (
        boundary_bisection_path_length(axes, start_rows, batch, first_index),
        boundary_bisection_path_length(axes, start_rows, batch, second_index),
    )
    max_path_length = max(path_lengths)
    max_iterations = max(batch.iterations[first_index], batch.iterations[second_index])
    path_score = max(0.0, max_path_length - 0.35) * 2.0
    iteration_score = min(1.5, max(0, max_iterations - 4) * 0.15)

    return path_score + iteration_score


def boundary_bisection_path_length(
    axes: tuple[tuple[float, float], ...],
    start_rows: tuple[tuple[float, ...], ...],
    batch: DiagnosisBatchSummary,
    index: int,
) -> float:
    """Return one solver path length in plotted coordinates."""

    path = boundary_bisection_path(start_rows, batch, index)

    return sum(
        point_distance(plot_normalized_point(first, axes), plot_normalized_point(second, axes))
        for first, second in zip(path, path[1:], strict=False)
        if finite_values(first) and finite_values(second)
    )


def boundary_bisection_path(
    start_rows: tuple[tuple[float, ...], ...],
    batch: DiagnosisBatchSummary,
    index: int,
) -> tuple[tuple[float, ...], ...]:
    """Return one path from the compact batch history or final-state fallback."""

    if batch.history_state and index < len(batch.history_state):
        history = batch.history_state[index]

        if history:
            return (start_rows[index], *history)

    return (start_rows[index], batch.state[index])


def boundary_bisection_interpolated_point(
    axes: tuple[tuple[float, float], ...],
    first: tuple[float, ...],
    second: tuple[float, ...],
    *,
    fraction: float,
) -> tuple[float, ...]:
    """Return an edge point in plotted coordinates, mapped back to state values."""

    active_fraction = max(0.0, min(float(fraction), 1.0))

    return tuple(
        plot_axis_value(
            (
                plot_axis_unit(first[axis_index], axis, axis_index=axis_index)
                + (
                    plot_axis_unit(second[axis_index], axis, axis_index=axis_index)
                    - plot_axis_unit(first[axis_index], axis, axis_index=axis_index)
                )
                * active_fraction
            ),
            axis,
            axis_index=axis_index,
        )
        for axis_index, axis in enumerate(axes)
    )


def square_start_grid(
    axes: Sequence[tuple[float, float]],
    side: int,
) -> tuple[tuple[float, ...], ...]:
    """Return a square deterministic grid over the two diagnosis axes."""

    if len(axes) != 2:
        raise ValueError("multi-start basin diagnosis currently requires exactly two state axes")

    x_values = axis_grid_values(axes[0], side, axis_index=0)
    y_values = axis_grid_values(axes[1], side, axis_index=1)

    return tuple((x_value, y_value) for y_value in y_values for x_value in x_values)


def adaptive_refinement_rows(
    *,
    axes: tuple[tuple[float, float], ...],
    side: int,
    coarse_rows: tuple[tuple[float, ...], ...],
    coarse_batch: DiagnosisBatchSummary,
    count: int,
) -> tuple[tuple[float, ...], ...]:
    """Choose refinement starts from coarse cells with mixed or uncertain outcomes."""

    if count <= 0:
        return ()

    x_values = axis_grid_values(axes[0], side, axis_index=0)
    y_values = axis_grid_values(axes[1], side, axis_index=1)
    candidates = []

    for y_index in range(side - 1):
        for x_index in range(side - 1):
            corner_indices = (
                y_index * side + x_index,
                y_index * side + x_index + 1,
                (y_index + 1) * side + x_index,
                (y_index + 1) * side + x_index + 1,
            )
            score = adaptive_cell_score(axes, coarse_rows, coarse_batch, corner_indices)

            if score <= 0.0:
                continue

            candidates.extend(
                (
                    score - rank * 1.0e-3,
                    interpolated_cell_point(
                        x_values, y_values, x_index, y_index, x_fraction, y_fraction
                    ),
                )
                for rank, (x_fraction, y_fraction) in enumerate(refinement_fractions())
            )

    candidates.sort(key=lambda item: item[0], reverse=True)
    selected = unique_candidate_rows(
        axes,
        existing=coarse_rows,
        candidates=(row for _, row in candidates),
        count=count,
    )

    if len(selected) < count:
        fill_rows = diagnosis_start_grid(axes, count + len(coarse_rows) + side)
        selected += unique_candidate_rows(
            axes,
            existing=coarse_rows + selected,
            candidates=fill_rows,
            count=count - len(selected),
        )

    return selected


def adaptive_cell_score(
    axes: tuple[tuple[float, float], ...],
    coarse_rows: tuple[tuple[float, ...], ...],
    coarse_batch: DiagnosisBatchSummary,
    corner_indices: tuple[int, int, int, int],
) -> float:
    """Score one coarse cell for refinement."""

    outcomes = [
        (
            coarse_rows[index],
            coarse_batch.state[index],
            coarse_batch.status[index],
            coarse_batch.converged[index],
        )
        for index in corner_indices
    ]
    non_converged_count = sum(
        1
        for _, state, status, converged in outcomes
        if status != "ok" or not converged or not finite_values(state)
    )
    endpoints = [
        normalized_point(state, axes)
        for _, state, status, converged in outcomes
        if status == "ok" and converged and finite_values(state)
    ]
    path_lengths = [
        point_distance(normalized_point(start, axes), normalized_point(state, axes))
        for start, state, status, converged in outcomes
        if status == "ok" and converged and finite_values(state)
    ]
    endpoint_spread = max_pair_distance(endpoints)
    score = 0.0

    if non_converged_count > 0:
        score += 8.0 + non_converged_count

    if endpoint_spread >= ADAPTIVE_ENDPOINT_SPLIT_DISTANCE:
        score += 4.0 + endpoint_spread
    elif endpoints:
        score += 0.1 * (statistics.fmean(path_lengths) if path_lengths else 0.0)

    return score


def refinement_fractions() -> tuple[tuple[float, float], ...]:
    """Return deterministic within-cell refinement positions."""

    return (
        (0.5, 0.5),
        (0.25, 0.5),
        (0.75, 0.5),
        (0.5, 0.25),
        (0.5, 0.75),
        (0.25, 0.25),
        (0.75, 0.75),
    )


def interpolated_cell_point(
    x_values: tuple[float, ...],
    y_values: tuple[float, ...],
    x_index: int,
    y_index: int,
    x_fraction: float,
    y_fraction: float,
) -> tuple[float, float]:
    """Return one point inside a coarse-grid cell."""

    x_low = x_values[x_index]
    x_high = x_values[x_index + 1]
    y_low = y_values[y_index]
    y_high = y_values[y_index + 1]

    return (
        x_low + (x_high - x_low) * x_fraction,
        y_low + (y_high - y_low) * y_fraction,
    )


def unique_candidate_rows(
    axes: tuple[tuple[float, float], ...],
    *,
    existing: tuple[tuple[float, ...], ...],
    candidates: Iterable[tuple[float, ...]],
    count: int,
) -> tuple[tuple[float, ...], ...]:
    """Return unique bounded candidate starts."""

    seen = {start_key(row, axes) for row in existing}
    selected = []

    for candidate in candidates:
        row = tuple(float(value) for value in candidate)

        if not row_in_bounds(row, axes):
            continue

        key = start_key(row, axes)

        if key in seen:
            continue

        seen.add(key)
        selected.append(row)

        if len(selected) == count:
            break

    return tuple(selected)


def row_in_bounds(
    row: tuple[float, ...],
    axes: tuple[tuple[float, float], ...],
) -> bool:
    """Return whether one candidate start lies inside the diagnosis domain."""

    return len(row) == len(axes) and all(
        low <= value <= high for value, (low, high) in zip(row, axes, strict=True)
    )


def start_key(
    row: tuple[float, ...],
    axes: tuple[tuple[float, float], ...],
) -> tuple[int, ...]:
    """Quantize one start row for deterministic de-duplication."""

    return tuple(
        round(normalized_axis(value, axis) * 1.0e9) for value, axis in zip(row, axes, strict=True)
    )


def normalized_point(
    values: Sequence[float],
    axes: tuple[tuple[float, float], ...],
) -> tuple[float, ...]:
    """Scale a state-space point by the diagnosis axes."""

    return tuple(normalized_axis(value, axis) for value, axis in zip(values, axes, strict=True))


def plot_normalized_point(
    values: Sequence[float],
    axes: tuple[tuple[float, float], ...],
) -> tuple[float, ...]:
    """Scale a point by the diagnosis plot axes."""

    return tuple(
        plot_axis_unit(value, axis, axis_index=axis_index)
        for axis_index, (value, axis) in enumerate(zip(values, axes, strict=True))
    )


def normalized_axis(value: float, axis: tuple[float, float]) -> float:
    """Scale one value by one diagnosis axis."""

    low, high = axis

    return (float(value) - low) / (high - low)


def plot_axis_unit(
    value: float,
    axis: tuple[float, float],
    *,
    axis_index: int,
) -> float:
    """Map one state value to the plotted unit interval."""

    low, high = axis
    clamped = max(low, min(float(value), high))

    if axis_index != 0:
        return (clamped - low) / (high - low)

    high_unit = math.log1p(high / DIAGNOSIS_AOD_PSEUDO_LOG_SCALE)

    if high_unit <= 0.0:
        return normalized_axis(clamped, axis)

    return math.log1p(max(clamped, 0.0) / DIAGNOSIS_AOD_PSEUDO_LOG_SCALE) / high_unit


def plot_axis_value(
    unit: float,
    axis: tuple[float, float],
    *,
    axis_index: int,
) -> float:
    """Map one plotted unit coordinate back to the state domain."""

    low, high = axis
    clamped_unit = max(0.0, min(float(unit), 1.0))

    if axis_index != 0:
        return low + clamped_unit * (high - low)

    high_unit = math.log1p(high / DIAGNOSIS_AOD_PSEUDO_LOG_SCALE)

    if high_unit <= 0.0:
        return low + clamped_unit * (high - low)

    value = DIAGNOSIS_AOD_PSEUDO_LOG_SCALE * math.expm1(clamped_unit * high_unit)

    return max(low, min(value, high))


def finite_values(values: Sequence[float]) -> bool:
    """Return whether every value is finite."""

    return all(math.isfinite(float(value)) for value in values)


def max_pair_distance(points: Sequence[tuple[float, ...]]) -> float:
    """Return the largest pairwise normalized distance."""

    if len(points) < 2:
        return 0.0

    return max(
        point_distance(first, second)
        for first_index, first in enumerate(points)
        for second in points[first_index + 1 :]
    )


def point_distance(first: Sequence[float], second: Sequence[float]) -> float:
    """Return Euclidean distance between two normalized points."""

    return math.sqrt(
        sum((left - right) * (left - right) for left, right in zip(first, second, strict=True))
    )


def diagnosis_batch_worker_count_for_limit(start_count: int, native_worker_limit: int) -> int:
    """Choose start-level workers without hiding the native prefetch pool."""

    return min(start_count, max(1, min(2, native_worker_limit)))


def native_worker_ceiling() -> int:
    """Return the configured native worker ceiling used by RTM prefetch loops."""

    configured = os.environ.get("ZDISAMAR_WORKER_LIMIT")

    if configured is not None:
        try:
            value = int(configured)
        except ValueError as exc:
            raise ValueError("ZDISAMAR_WORKER_LIMIT must be a positive integer") from exc

        if value <= 0:
            raise ValueError("ZDISAMAR_WORKER_LIMIT must be a positive integer")

        return value

    return os.cpu_count() or 1


def diagnosis_bounds(
    scene: Scene,
    state_vector: StateVector,
) -> tuple[tuple[float, float], ...]:
    """Resolve the diagnosis domain for each state-vector coordinate."""

    axes = []

    for parameter in state_vector.parameters:
        low: float | None
        high: float | None

        if parameter.name == AEROSOL_OPTICAL_DEPTH:
            low, high = DIAGNOSIS_AOD_LOWER, 2.0
        elif parameter.name == AEROSOL_LAYER_MID_PRESSURE_HPA:
            low, high = 50.0, float(scene.surface.pressure_hpa)
        else:
            low = parameter.lower
            high = parameter.upper

        if low is None or high is None:
            raise ValueError(
                f"diagnosis start bounds for {parameter.name!r} must be finite; "
                "set parameter lower/upper"
            )

        low = float(low)
        high = float(high)

        if not all(math.isfinite(value) for value in (low, high)) or not high > low:
            raise ValueError(f"invalid diagnosis bounds for {parameter.name!r}")

        axes.append((low, high))

    return tuple(axes)


def diagnosis_start_grid(
    axes: Sequence[tuple[float, float]],
    start_count: int,
) -> tuple[tuple[float, ...], ...]:
    """Build deterministic start rows over the first two state axes."""

    if len(axes) != 2:
        raise ValueError("multi-start basin diagnosis currently requires exactly two state axes")

    columns = max(1, math.ceil(math.sqrt(start_count)))
    rows = max(1, math.ceil(start_count / columns))
    x_values = axis_grid_values(axes[0], columns, axis_index=0)
    y_values = axis_grid_values(axes[1], rows, axis_index=1)

    starts = []

    for y_value in y_values:
        for x_value in x_values:
            starts.append((x_value, y_value))

            if len(starts) == start_count:
                return tuple(starts)

    return tuple(starts)


def linspace(low: float, high: float, count: int) -> tuple[float, ...]:
    """Return count evenly spaced values including both endpoints."""

    if count <= 1:
        return (0.5 * (low + high),)

    step = (high - low) / (count - 1)

    return tuple(low + index * step for index in range(count))


def axis_grid_values(
    axis: tuple[float, float],
    count: int,
    *,
    axis_index: int,
) -> tuple[float, ...]:
    """Return deterministic starts, expanding the low-AOD part of the first axis."""

    low, high = axis

    if axis_index != 0 or count <= 1:
        return linspace(low, high, count)

    scale = DIAGNOSIS_AOD_PSEUDO_LOG_SCALE
    low_unit = math.log1p(max(low, 0.0) / scale)
    high_unit = math.log1p(max(high, 0.0) / scale)

    if not high_unit > low_unit:
        return linspace(low, high, count)

    return tuple(
        scale * math.expm1(low_unit + index * (high_unit - low_unit) / (count - 1))
        for index in range(count)
    )


def numeric_stats(values: Sequence[float | int]) -> dict[str, float]:
    """Return small finite stats for display payloads."""

    parsed = [float(value) for value in values if math.isfinite(float(value))]

    if not parsed:
        return {"min": math.nan, "median": math.nan, "mean": math.nan, "max": math.nan}

    return {
        "min": min(parsed),
        "median": statistics.median(parsed),
        "mean": statistics.fmean(parsed),
        "max": max(parsed),
    }
