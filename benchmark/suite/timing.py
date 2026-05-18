"""Timing helpers."""

import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class TimingSample:
    wall_s: float
    process_cpu_s: float

    @property
    def average_active_cores(self) -> float:

        if self.wall_s <= 0.0:
            return 0.0

        return self.process_cpu_s / self.wall_s


def timing_start() -> tuple[float, float]:

    return time.perf_counter(), time.process_time()


def elapsed_since(start: tuple[float, float]) -> TimingSample:

    wall_start, cpu_start = start

    return TimingSample(
        wall_s=time.perf_counter() - wall_start,
        process_cpu_s=time.process_time() - cpu_start,
    )


def combine(samples: list[TimingSample]) -> TimingSample:

    return TimingSample(
        wall_s=sum(sample.wall_s for sample in samples),
        process_cpu_s=sum(sample.process_cpu_s for sample in samples),
    )


def timed(callback: Callable[[], Any]) -> tuple[TimingSample, Any]:

    start = timing_start()
    value = callback()

    return elapsed_since(start), value
