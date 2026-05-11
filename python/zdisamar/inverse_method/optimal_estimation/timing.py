"""Timing helpers for optimal-estimation instrumentation."""

import time
from collections.abc import Callable
from typing import TypeVar

from .retrieval import IterationTiming

T = TypeVar("T")


class IterationTimer:
    """Collect wall-clock timing for one retrieval iteration."""

    def __init__(self, index: int):
        self._index = index
        self._iteration_start = time.perf_counter()
        self._forward_seconds = 0.0
        self._solver_start = 0.0
        self._solver_seconds = 0.0

    def forward(self, call: Callable[[], T]) -> T:
        start = time.perf_counter()
        value = call()
        self._forward_seconds = time.perf_counter() - start
        return value

    def start_solver(self) -> None:
        self._solver_start = time.perf_counter()

    def stop_solver(self) -> None:
        self._solver_seconds = time.perf_counter() - self._solver_start

    def finish(self) -> IterationTiming:
        return IterationTiming(
            index=self._index,
            forward_model_and_jacobian_s=self._forward_seconds,
            solver_update_s=self._solver_seconds,
            total_iteration_s=time.perf_counter() - self._iteration_start,
        )


class NoopIterationTimer:
    """Avoid wall-clock probes on production retrieval calls."""

    def __init__(self, index: int):
        self._index = index

    def forward(self, call: Callable[[], T]) -> T:
        return call()

    def start_solver(self) -> None:
        pass

    def stop_solver(self) -> None:
        pass

    def finish(self) -> IterationTiming:
        return IterationTiming(
            index=self._index,
            forward_model_and_jacobian_s=0.0,
            solver_update_s=0.0,
            total_iteration_s=0.0,
        )
