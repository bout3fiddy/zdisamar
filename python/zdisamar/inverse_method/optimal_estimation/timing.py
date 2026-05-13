"""Timing helpers for optimal-estimation instrumentation."""

import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import TypeVar

from .retrieval import IterationTiming

T = TypeVar("T")


@dataclass
class IterationTimer:
    """Collect optional wall-clock timing for one retrieval iteration."""

    index: int
    enabled: bool
    iteration_start: float = field(default_factory=time.perf_counter)
    rtm_seconds: float = 0.0
    solver_start: float = 0.0
    solver_seconds: float = 0.0

    def rtm(self, call: Callable[[], T]) -> T:
        """Measure spectrum-and-Jacobian time separately from OE algebra."""

        if not self.enabled:
            return call()

        start = time.perf_counter()
        value = call()
        self.rtm_seconds = time.perf_counter() - start

        return value

    def start_solver(self) -> None:

        if self.enabled:
            self.solver_start = time.perf_counter()

    def stop_solver(self) -> None:

        if self.enabled:
            self.solver_seconds = time.perf_counter() - self.solver_start

    def finish(self) -> IterationTiming:
        """Return the timing fields stored on the retrieval result."""

        if not self.enabled:
            return IterationTiming(
                index=self.index,
                rtm_and_jacobian_s=0.0,
                solver_update_s=0.0,
                total_iteration_s=0.0,
            )

        return IterationTiming(
            index=self.index,
            rtm_and_jacobian_s=self.rtm_seconds,
            solver_update_s=self.solver_seconds,
            total_iteration_s=time.perf_counter() - self.iteration_start,
        )
