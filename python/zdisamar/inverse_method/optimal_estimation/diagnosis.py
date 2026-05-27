"""Multi-start optimal-estimation diagnosis objects."""

import copy
import math
import os
import statistics
import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from ... import rtm
from ...display import NotebookDisplay, PrettyMapping
from ...input.wavelength_band.o2a import O2AInput
from .retrieval import Measurement, RetrievalControls
from .state_vector import StateName, StateVector


@dataclass(frozen=True)
class RetrievalDiagnosis(NotebookDisplay):
    """Final states from many starts of the same inverse problem."""

    state_names: tuple[StateName, ...]
    start_state: tuple[tuple[float, ...], ...]
    retrieved_state: tuple[tuple[float, ...], ...]
    iterations: tuple[int, ...]
    converged: tuple[bool, ...]
    start_bounds: tuple[tuple[float, float], ...]
    result_state: tuple[float, ...]
    result_initial_state: tuple[float, ...] | None
    batch_workers: int
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
                "accepted_result": self.result_state[index],
            }

        return {
            "runs": len(self.start_state),
            "converged": sum(1 for value in self.converged if value),
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
        *,
        cells: int = 150,
    ):
        """Render the basin trajectory-density plot as SVG."""

        from ...plot.properties import PLOT
        from ...plot.retrieval_diagnosis import retrieval_diagnosis_figure

        return PLOT.finish(retrieval_diagnosis_figure(self, cells=cells), save=save)

    def __repr__(self) -> str:

        return repr(self.summary())


def diagnose_retrieval(
    *,
    case: O2AInput,
    measurement: Measurement,
    state_vector: StateVector,
    result_state: Sequence[float],
    result_initial_state: Sequence[float] | None,
    controls: RetrievalControls,
    start_count: int = 100,
    batch_workers: int | None = None,
    bounds: Mapping[StateName, tuple[float, float]] | None = None,
    cache: rtm.SessionCache | None = None,
    start_rows: Sequence[Sequence[float]] | None = None,
) -> RetrievalDiagnosis:
    """Run a same-scene multi-start sweep using the native batch path."""

    if start_count <= 0:
        raise ValueError("start_count must be positive")

    axes = diagnosis_bounds(state_vector, bounds or {})
    active_start_rows = (
        tuple(tuple(float(value) for value in row) for row in start_rows)
        if start_rows is not None
        else diagnosis_start_grid(axes, start_count)
    )

    if not active_start_rows:
        raise ValueError("start_rows must not be empty")

    active_start_count = len(active_start_rows)
    native_worker_limit = native_worker_ceiling()
    active_batch_workers = (
        diagnosis_batch_worker_count_for_limit(active_start_count, native_worker_limit)
        if batch_workers is None
        else batch_workers
    )

    if active_batch_workers <= 0:
        raise ValueError("batch_workers must be positive")

    start_vectors = tuple(state_vector_for_start(state_vector, row) for row in active_start_rows)

    from . import o2a as o2a_oe

    start_s = time.perf_counter()
    batch = o2a_oe.diagnosis_batch(
        case=case,
        measurement=measurement,
        state_vectors=start_vectors,
        controls=controls,
        cache=cache,
        batch_workers=active_batch_workers,
    )
    elapsed_s = time.perf_counter() - start_s

    return RetrievalDiagnosis(
        state_names=state_vector.names,
        start_state=active_start_rows,
        retrieved_state=batch.state,
        iterations=batch.iterations,
        converged=batch.converged,
        start_bounds=axes,
        result_state=tuple(float(value) for value in result_state),
        result_initial_state=(
            None
            if result_initial_state is None
            else tuple(float(value) for value in result_initial_state)
        ),
        batch_workers=active_batch_workers,
        fast_stage_iterations=batch.fast_stage_iterations,
        fast_stage_converged=batch.fast_stage_converged,
        full_correction_iterations=batch.full_correction_iterations,
        full_correction_converged=batch.full_correction_converged,
        native_worker_limit=native_worker_limit,
        elapsed_s=elapsed_s,
    )


def diagnosis_batch_worker_count(start_count: int) -> int:
    """Choose a bounded native start-worker count for a same-scene diagnosis."""

    return diagnosis_batch_worker_count_for_limit(start_count, native_worker_ceiling())


def diagnosis_batch_worker_count_for_limit(start_count: int, native_worker_limit: int) -> int:
    """Choose start-level workers without hiding the native prefetch pool."""

    return min(start_count, max(1, min(3, native_worker_limit)))


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
    state_vector: StateVector,
    supplied: Mapping[StateName, tuple[float, float]],
) -> tuple[tuple[float, float], ...]:
    """Resolve finite start bounds for each state-vector coordinate."""

    axes = []

    for parameter in state_vector.parameters:
        if parameter.name in supplied:
            low, high = supplied[parameter.name]
        else:
            low = parameter.lower
            high = parameter.upper

        if low is None or high is None:
            raise ValueError(
                f"diagnosis start bounds for {parameter.name!r} must be finite; "
                "pass bounds={name: (low, high)} or set parameter lower/upper"
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
    x_values = linspace(axes[0][0], axes[0][1], columns)
    y_values = linspace(axes[1][0], axes[1][1], rows)

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


def state_vector_for_start(
    state_vector: StateVector,
    start: Sequence[float],
) -> StateVector:
    """Use one start row as both initial state and prior for the sweep."""

    if len(start) != len(state_vector.parameters):
        raise ValueError("diagnosis start length does not match state vector")

    parameters = []

    for parameter, value in zip(state_vector.parameters, start, strict=True):
        updated = copy.copy(parameter)
        object.__setattr__(updated, "initial", float(value))
        object.__setattr__(updated, "prior", float(value))
        parameters.append(updated)

    return StateVector(tuple(parameters))


def numeric_stats(values: Sequence[float | int]) -> dict[str, float]:
    """Return small finite stats for display payloads."""

    parsed = [float(value) for value in values]

    if not parsed:
        return {"min": math.nan, "median": math.nan, "mean": math.nan, "max": math.nan}

    return {
        "min": min(parsed),
        "median": statistics.median(parsed),
        "mean": statistics.fmean(parsed),
        "max": max(parsed),
    }
